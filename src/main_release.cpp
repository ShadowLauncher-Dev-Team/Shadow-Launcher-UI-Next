// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
// Shadow Launcher — C++ Entry Point
// Phase 4: Unified backend + QML UI port

#include <QApplication>
#include <QWidget>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QIcon>
#include <QDir>
#include <QStandardPaths>
#include <QFileInfo>
#include <QJsonDocument>

// 3D geometry
#include <QJsonObject>
#include <QProcess>
#include <QProgressDialog>
#include <QWindow>
#include <QQuickWindow>
#include <QQuickItem>
#include <QMouseEvent>
#include <QDebug>
#include <QAbstractNativeEventFilter>
#include <QTimer>
#include <QScreen>
#include <QPixmap>
#include <QWindow>
#include <QSurfaceFormat>
#include <QTranslator>
#include <QSettings>
#include <memory>

namespace {

// 点空白处释放文本焦点。
//
// 为什么放在窗口层：QML 里试过两次都不成——版本设置页每个 pane 里是 anchors.fill 的
// Flickable，它会把 press 吃掉，所以挂在下层的 MouseArea / TapHandler 根本收不到；
// 而 SField.blur() 那种"逐处调用"只要漏一处就一直保持聚焦（下载页能正常工作正是因为
// 它把该调的地方都调到了，且它没有全屏 Flickable 挡着）。
// 在窗口层拦 MouseButtonPress：当前焦点在文本输入上、且按下的点不在它的矩形内，就释放焦点。
// 对所有页面一视同仁，不依赖各页面自己挂监听，也没有 TapHandler 的手势判定延迟（点快也准）。
class FocusClearFilter : public QObject
{
public:
    explicit FocusClearFilter(QQuickWindow* w) : QObject(w), m_win(w) {}

protected:
    bool eventFilter(QObject* obj, QEvent* ev) override
    {
        if (ev->type() == QEvent::MouseButtonPress && m_win) {
            QQuickItem* fi = m_win->activeFocusItem();
            if (fi && isTextInput(fi)) {
                auto* me = static_cast<QMouseEvent*>(ev);
                const QPointF local = fi->mapFromScene(me->position());
                const bool outside = !fi->contains(local);
                qInfo() << "[focus] press" << me->position() << "focusItem=" << fi->metaObject()->className()
                        << "local=" << local << "inside=" << !outside;
                if (outside) {
                    // 两件事都做：显式清焦点（对 TextInput 直接有效），再把焦点交给根。
                    // 只做后者时，若根不可聚焦就会静默失败、输入框仍持有 activeFocus（蓝边不消失）。
                    fi->setFocus(false);
                    if (m_win->contentItem())
                        m_win->contentItem()->forceActiveFocus();
                    qInfo() << "[focus] 已释放文本焦点";
                }
            }
        }
        return QObject::eventFilter(obj, ev);
    }

private:
    static bool isTextInput(QQuickItem* it)
    {
        // TextInput / TextEdit 及其控件封装（TextArea、TextField 等最终都派生自这两类）
        return it->inherits("QQuickTextInput") || it->inherits("QQuickTextEdit")
            || it->inherits("QQuickTextArea") || it->inherits("QQuickTextField");
    }

    QQuickWindow* m_win = nullptr;
};

} // namespace

#ifdef Q_OS_WIN
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  include <windows.h>
#  include <shellapi.h>
#  include <dwmapi.h>
#  pragma comment(lib, "dwmapi.lib")
#endif

#include "utils/logger.h"
#include "version.h"   // 2026-08-15：SHADOW_DISPLAY_VERSION（原 CMake 宏，现头文件）
#include "backend/shadow_backend.h"
#include "backend/settings_backend.h"
#include "backend/launch_backend.h"  // detachAllGames（退出时分离游戏进程）
#include "ui_next/appearance_controller.h"
#include "core/http_client.h"

#include "core/screenshot_server.h"
#include "core/modpack/zip_archive.h"
#include <QFile>
#include <functional>

// ── Remove CEF references ──

using namespace ShadowLauncher;

// ── Native event filter: handle taskbar minimize/restore for frameless window ──
class TaskbarMinimizeFilter : public QAbstractNativeEventFilter {
public:
    QWindow* targetWindow = nullptr;

    bool nativeEventFilter(const QByteArray& eventType, void* message, qintptr* /*result*/) override {
#ifdef Q_OS_WIN
        if (eventType == "windows_generic_MSG" || eventType == "windows_dispatcher_MSG") {
            MSG* msg = static_cast<MSG*>(message);

            // ── Minimize: click title bar minimize button or custom window menu ──
            if (msg->message == WM_SYSCOMMAND && (msg->wParam & 0xFFF0) == SC_MINIMIZE) {
                ShowWindow(msg->hwnd, SW_MINIMIZE);
                return true;
            }

            // ── Also handle system restore (taskbar thumbnail preview context menu) ──
            if (msg->message == WM_SYSCOMMAND && (msg->wParam & 0xFFF0) == SC_RESTORE) {
                if (targetWindow) {
                    targetWindow->showNormal();
                    targetWindow->raise();
                    targetWindow->requestActivate();
                    return true;
                }
            }
        }
#endif
        Q_UNUSED(eventType)
        return false;
    }
};

// Global for screenshot mode
static QWindow* screenshotWindow = nullptr;
// ── 全量更新准备（2026-08-15 方案A重构）──
// 旧实现 applyFullUpdate 在当前进程（PreInit）内删除并复制自身 DLL——
// 进程存活期间 DLL 被 loader 锁定，删除/复制必然失败 → 全量更新静默失败。
// 现在这里只做"解压 + 完整性校验"（只写新文件，不触碰已加载文件，安全），
// 真正的"删旧 + 复制 + 换 exe"移入 SLUpdater（旧进程退出后、无锁时执行）。
// 成功返回 true 并设置 outNewExeW（新 exe 路径）与 outExtractDirW（解压目录）；
// 失败返回 false（跳过更新，继续用当前版本）。
static bool prepareFullUpdate(const std::wstring& appDirW,
                              const std::wstring& zipPathW,
                              std::wstring& outNewExeW,
                              std::wstring& outExtractDirW)
{
    const QString appDir = QString::fromWCharArray(appDirW.c_str());
    const QString updateDir = appDir + QStringLiteral("/_update");
    const QString extractDir = updateDir + QStringLiteral("/extracted");
    const QString zipPath = QString::fromWCharArray(zipPathW.c_str());

    // 1) 清理旧解压残留 + 解压新包到 extracted（先解压验证完整性，再动旧目录）
    QDir(extractDir).removeRecursively();
    QDir().mkpath(extractDir);

    ShadowLauncher::ZipArchive zip;
    if (!zip.open(zipPath)) {
        OutputDebugStringA("[PreInit] 全量更新：无法打开更新包\n");
        return false;
    }
    const int n = zip.extractPrefixTo(QString(), extractDir);
    zip.close();
    if (n <= 0) {
        OutputDebugStringA("[PreInit] 全量更新：解压失败\n");
        return false;
    }

    // 2) 包内必须有新主程序（否则更新后无 exe 可运行）
    const QString newExe = extractDir + QStringLiteral("/ShadowLauncher.exe");
    if (!QFileInfo::exists(newExe)) {
        OutputDebugStringA("[PreInit] 全量更新：包内缺少 ShadowLauncher.exe\n");
        return false;
    }
    outNewExeW = newExe.toStdWString();
    outExtractDirW = extractDir.toStdWString();

    // 3) 删除 zip 释放空间（extracted 保留给 SLUpdater 复制 + 换 exe）
    QFile::remove(zipPath);
    OutputDebugStringA("[PreInit] 全量更新：解压+校验完成，准备由 SLUpdater 执行替换\n");
    return true;
}


int main(int argc, char *argv[])
{
    // 2026-08-11：强制 QtQuick.Controls 使用 Basic 风格。
    // Qt 6.7+ 在 Windows 上默认按 native 风格解析（QtQuick.Controls.Windows，且内部依赖
    // Fusion 等模块）——发布包 4g 只保留 Basic 风格，若不显式指定会报
    // "module QtQuick.Controls.Windows/Fusion is not installed" 界面无法出现。
    // 项目全部组件显式 import QtQuick.Controls.Basic，强制 Basic 无功能损失。
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");

    QElapsedTimer startupTimer;
    startupTimer.start();
    // ── Pending update from previous session? ──
    // MUST run before QApplication — no QML window should flash.
    {
        OutputDebugStringA("[PreInit] 检查待安装更新...\n");
        wchar_t exePathW[MAX_PATH];
        GetModuleFileNameW(nullptr, exePathW, MAX_PATH);
        std::wstring exePath(exePathW);
        std::wstring appDirW = exePath.substr(0, exePath.find_last_of(L"\\/"));

        std::wstring lockPath = appDirW + L"\\_update\\.install_lock";
        std::wstring statePath = appDirW + L"\\_update\\state.json";

        bool lockExists = GetFileAttributesW(lockPath.c_str()) != INVALID_FILE_ATTRIBUTES;
        bool stateExists = GetFileAttributesW(statePath.c_str()) != INVALID_FILE_ATTRIBUTES;

        // 全量更新残留清理：安装完成/中止后 _update/extracted 不再需要（2026-08-11）
        // （applyFullUpdate 进行中时 extracted 尚不存在，无冲突；重启后的新进程执行此处清理）
        QDir(QString::fromWCharArray((appDirW + L"\\_update\\extracted").c_str())).removeRecursively();

        // If lock exists but no state.json → SLUpdater completed, cleanup
        if (lockExists && !stateExists) {
            OutputDebugStringA("[PreInit] 安装锁存在但无待安装更新，清理锁\n");
            // ── 2026-08-25：更新完成后的首次启动，写一次性标记（exe 目录 .just_updated），
            //    供 QML 区分"新装/更新用户"——蓝色更新内容 toast 仅更新用户弹出。──
            {
                std::wstring markerPath = appDirW + L"\\.just_updated";
                HANDLE hMark = CreateFileW(markerPath.c_str(), GENERIC_WRITE, 0, nullptr,
                                           CREATE_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr);
                if (hMark != INVALID_HANDLE_VALUE) {
                    const char ack[] = "updated";
                    DWORD written = 0;
                    WriteFile(hMark, ack, (DWORD)(sizeof(ack) - 1), &written, nullptr);
                    CloseHandle(hMark);
                }
            }
            DeleteFileW(lockPath.c_str());
            // 全量更新残留的 extracted 目录一并清理（SLUpdater 只删 state/lock）
            QDir(QString::fromWCharArray((appDirW + L"\\_update\\extracted").c_str())).removeRecursively();
            lockExists = false;
        }
        // If lock exists with state → SLUpdater crashed mid-install, retry
        if (lockExists) {
            OutputDebugStringA("[PreInit] 安装锁存在，上次安装可能中断，重试\n");
            DeleteFileW(lockPath.c_str());
            lockExists = false;
        }
        HANDLE hFile = CreateFileW(statePath.c_str(), GENERIC_READ,
                                   FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                   FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hFile == INVALID_HANDLE_VALUE) {
            OutputDebugStringA("[PreInit] 无待安装更新\n");
        } else {
            DWORD size = GetFileSize(hFile, nullptr);
            if (size > 0 && size < 1048576) {   // 1MB 上限（release_notes 可能很大，原 4096 会吞掉整个更新）
                std::string json(size, '\0');
                DWORD read = 0;
                ReadFile(hFile, &json[0], size, &read, nullptr);
                CloseHandle(hFile);

                // Quick JSON parse: find "state":N
                auto findInt = [&](const char* key) -> int {
                    std::string k = std::string("\"") + key + "\":";
                    auto pos = json.find(k);
                    if (pos == std::string::npos) return -1;
                    pos += k.size();
                    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
                    return atoi(&json[pos]);
                };

                // state.json 是 UTF-8；逐字节拷贝宽字符会把中文路径（C:\Users\<用户名>\...）变成乱码
                // → GetFileAttributesW 失败 → 更新静默跳过。必须按 UTF-8 正确转宽字符。
                auto utf8ToWide = [](const std::string& s) -> std::wstring {
                    if (s.empty()) return std::wstring();
                    int len = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
                    std::wstring out(len, L'\0');
                    if (len > 0)
                        MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &out[0], len);
                    return out;
                };

                int stateVal = findInt("state");

                // If already running the target version, clean up stale state
                bool alreadyCurrent = false;
                if (stateVal == 5) {
                    auto pos = json.find("\"download_version\":\"");
                    if (pos != std::string::npos) {
                        pos += 20;   // 2026-08-15 修复：'"download_version":"' 实际 20 字符（原 21 off-by-one）
                        auto end = json.find('"', pos);
                        std::string dlVer = json.substr(pos, end - pos);
                        if (dlVer == SHADOW_DISPLAY_VERSION) {
                            OutputDebugStringA("[PreInit] 已是目标版本，清除过期状态\n");
                            DeleteFileW(statePath.c_str());
                            DeleteFileW(lockPath.c_str());
                            std::wstring wildcard = appDirW + L"\\_update\\*";
                            WIN32_FIND_DATAW fd;
                            HANDLE hFind = FindFirstFileW(wildcard.c_str(), &fd);
                            if (hFind != INVALID_HANDLE_VALUE) {
                                do {
                                    if (wcscmp(fd.cFileName, L"state.json") != 0) {
                                        DeleteFileW((appDirW + L"\\_update\\" + fd.cFileName).c_str());
                                    }
                                } while (FindNextFileW(hFind, &fd));
                                FindClose(hFind);
                            }
                            alreadyCurrent = true;
                        }
                    }
                }

                if (alreadyCurrent) {
                    // skip — already on this version
                } else if (stateVal == -1) {
                    // Corrupted — clean up
                    OutputDebugStringA("[PreInit] state.json 损坏，清除\n");
                    DeleteFileW(statePath.c_str());
                    // Also delete any download files
                    std::wstring wildcard = appDirW + L"\\_update\\*";
                    WIN32_FIND_DATAW fd;
                    HANDLE hFind = FindFirstFileW(wildcard.c_str(), &fd);
                    if (hFind != INVALID_HANDLE_VALUE) {
                        do {
                            if (wcscmp(fd.cFileName, L"state.json") != 0) {
                                std::wstring fp = appDirW + L"\\_update\\" + fd.cFileName;
                                DeleteFileW(fp.c_str());
                            }
                        } while (FindNextFileW(hFind, &fd));
                        FindClose(hFind);
                    }
                } else if (stateVal == 5) { // Ready
                    // 解析新版本号（changelog 用；2026-08-15 修复：此前公告写的是当前版本）
                    std::string dlVer;
                    {
                        auto dvPos = json.find("\"download_version\":\"");
                        if (dvPos != std::string::npos) {
                            dvPos += 20;   // '"download_version":"' = 20 字符
                            auto dvEnd = json.find('"', dvPos);
                            dlVer = json.substr(dvPos, dvEnd - dvPos);
                        }
                    }
                    auto pos = json.find("\"download_path\":\"");
                    if (pos != std::string::npos) {
                        pos += 17;   // 2026-08-11 off-by-one 修复："download_path":" 为 17 字符
                        auto end = json.find('"', pos);
                        std::string newFile = json.substr(pos, end - pos);
                        std::wstring newFileW = utf8ToWide(newFile);

                        // Extract release notes BEFORE SLUpdater deletes state.json
                        auto rnPos = json.find("\"release_notes\":\"");
                        if (rnPos != std::string::npos) {
                            rnPos += 17;
                            std::string notes;
                            while (rnPos < json.size()) {
                                if (json[rnPos] == '\\' && rnPos + 1 < json.size()) {
                                    char c = json[rnPos + 1];
                                    if (c == 'n') { notes += '\n'; rnPos += 2; continue; }
                                    if (c == 'r') { rnPos += 2; continue; }
                                    if (c == '"') { notes += '"'; rnPos += 2; continue; }
                                    if (c == '\\') { notes += '\\'; rnPos += 2; continue; }
                                }
                                if (json[rnPos] == '"') break;
                                notes += json[rnPos];
                                rnPos++;
                            }
                            if (!notes.empty()) {
                                // Escape notes for JSON (must be done after unescaping from state.json)
                                auto jsonEscape = [](const std::string& s) -> std::string {
                                    std::string out;
                                    out.reserve(s.size() + 32);
                                    for (char c : s) {
                                        switch (c) {
                                            case '"':  out += "\\\""; break;
                                            case '\\': out += "\\\\"; break;
                                            case '\n': out += "\\n";  break;
                                            case '\r': out += "\\r";  break;
                                            case '\t': out += "\\t";  break;
                                            default:   out += c;
                                        }
                                    }
                                    return out;
                                };
                                // Write to changelog_to_show.json
                                std::wstring clPath = appDirW + L"\\_update\\changelog_to_show.json";
                                HANDLE hCl = CreateFileW(clPath.c_str(), GENERIC_WRITE, 0, nullptr,
                                                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
                                if (hCl != INVALID_HANDLE_VALUE) {
                                    // 2026-08-15：version 用新版本号（此前误写当前版本 SHADOW_DISPLAY_VERSION）
                                    std::string wrapped = "{\"version\":\"" + dlVer
                                                         + "\",\"notes\":\"" + jsonEscape(notes) + "\"}";
                                    DWORD written;
                                    WriteFile(hCl, wrapped.data(), (DWORD)wrapped.size(), &written, nullptr);
                                    CloseHandle(hCl);
                                    OutputDebugStringA("[PreInit] 已保存发布公告\n");
                                }
                            }
                        }

                        // ── 2026-08-11/15：全量更新（.zip 包）──
                        // 解压+校验由 prepareFullUpdate 完成（当前进程存活，不能动自身 DLL）；
                        // 删除旧文件/复制新文件/换 exe 全部移交 SLUpdater（旧进程退出后无锁执行）
                        const bool isZip = newFile.size() >= 4
                            && newFile.compare(newFile.size() - 4, 4, ".zip") == 0;
                        std::wstring installNewExeW, extractDirW;
                        if (isZip && !prepareFullUpdate(appDirW, newFileW, installNewExeW, extractDirW)) {
                            OutputDebugStringA("[PreInit] 全量更新失败，继续使用当前版本\n");
                            DeleteFileW(statePath.c_str());
                            DeleteFileW(lockPath.c_str());
                            newFileW.clear();   // 不执行更新
                        } else if (isZip) {
                            newFileW = installNewExeW;   // SLUpdater 替换 extracted 里的新 exe
                        }
                        // .exe 增量包走原逻辑（newFileW 不变）

                        std::wstring updaterPath = appDirW + L"\\SLUpdater.exe";
                        if (GetFileAttributesW(updaterPath.c_str()) != INVALID_FILE_ATTRIBUTES &&
                            GetFileAttributesW(newFileW.c_str()) != INVALID_FILE_ATTRIBUTES) {
                            // Create lock file to prevent concurrent installs
                            CreateDirectoryW((appDirW + L"\\_update").c_str(), nullptr);
                            HANDLE hLock = CreateFileW(lockPath.c_str(), GENERIC_WRITE, 0, nullptr,
                                                       CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
                            if (hLock != INVALID_HANDLE_VALUE) CloseHandle(hLock);

                            OutputDebugStringA("[PreInit] 发现待安装更新，启动 SLUpdater\n");
                            DWORD pid = GetCurrentProcessId();
                            // 全量：第 4 参数 = extracted 目录（SLUpdater 执行删旧+复制+换 exe）；
                            // 增量：仅 3 参数（SLUpdater 只换 exe）
                            wchar_t cmdLine[4096];
                            if (isZip) {
                                swprintf_s(cmdLine, L"\"%s\" %lu \"%s\" \"%s\" \"%s\"",
                                           updaterPath.c_str(), pid, exePathW, newFileW.c_str(),
                                           extractDirW.c_str());
                            } else {
                                swprintf_s(cmdLine, L"\"%s\" %lu \"%s\" \"%s\"",
                                           updaterPath.c_str(), pid, exePathW, newFileW.c_str());
                            }

                            STARTUPINFOW si = { sizeof(si) };
                            PROCESS_INFORMATION pi = {};
                            si.dwFlags = STARTF_USESHOWWINDOW;
                            si.wShowWindow = SW_SHOW;   // 2026-08-15：SLUpdater 带进度窗口，不再隐藏
                            const BOOL started = CreateProcessW(nullptr, cmdLine, nullptr, nullptr,
                                           FALSE, 0, nullptr, nullptr, &si, &pi);
                            if (started) {
                                CloseHandle(pi.hProcess);
                                CloseHandle(pi.hThread);
                                return 0; // Updated, exit immediately
                            }
                            // ── 2026-11-13：SLUpdater 起不来时**不能退出** ──
                            // 原实现在 CreateProcessW 失败（杀软拦截/文件被占用/路径含特殊字符）
                            // 后仍然 CloseHandle(NULL) 并 return 0：启动器直接消失、更新没装上、
                            // 用户以为「更新的把启动器删了」。改为清锁、保留 state.json（下次再试）、
                            // 继续以当前版本启动。
                            {
                                const DWORD err = GetLastError();
                                char buf[256];
                                wsprintfA(buf, "[PreInit] SLUpdater 启动失败 err=%lu，继续用当前版本\n",
                                          static_cast<unsigned long>(err));
                                OutputDebugStringA(buf);
                            }
                            DeleteFileW(lockPath.c_str());
                        } else {
                            OutputDebugStringA("[PreInit] 缺少 SLUpdater 或更新文件，跳过\n");
                        }
                    }
                }
            } else {
                CloseHandle(hFile);
            }
        }
    }

    auto checkpoint = [&](const QString& stage) { qCInfo(logApp) << stage; };

    // Qt attribute setup
    checkpoint(QStringLiteral("Setting Qt attributes..."));
    QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);

    // ── Transparent frameless window: require alpha channel ──
    // Without this, Window { color: "transparent" } may flash white corners
    // on certain GPU/driver combos (Intel, some NVidia).
    {
        QSurfaceFormat fmt;
        fmt.setAlphaBufferSize(8);
        QSurfaceFormat::setDefaultFormat(fmt);
    }

    QApplication app(argc, argv);
    checkpoint(QStringLiteral("QApplication constructed"));

    app.setApplicationName("Shadow Launcher");
    app.setApplicationVersion(SHADOW_DISPLAY_VERSION);
    app.setOrganizationName("ShadowTeam");
    app.setOrganizationDomain("shadowteam.dev");

    // ── Load saved language ──
    QSettings settings;
    // 0=简体 1=繁体(港澳) 2=繁体(台湾) 3=English   顺序必须与设置页下拉一致
    static const char* kLangCodes[] = { "zh_CN", "zh_HK", "zh_TW", "en" };
    const int langIdx = qBound(0, settings.value("general/languageIndex", 0).toInt(), 3);
    QString lang = QString::fromLatin1(kLangCodes[langIdx]);
    auto* translator = new QTranslator(&app);
    if (lang != QStringLiteral("zh_CN") && translator->load(QStringLiteral(":/i18n/shadow_%1").arg(lang))) {
        app.installTranslator(translator);
        qCInfo(logApp) << QStringLiteral("语言已加载 lang=%1").arg(lang);
    } else {
        qCInfo(logApp) << QStringLiteral("使用默认语言");
    }

    // ── Initialise structured logging ──
    initLogger(QCoreApplication::applicationDirPath());
    checkpoint(QStringLiteral("Logger initialized"));
    qCInfo(logApp) << QStringLiteral("=== Shadow Launcher v%1 启动 ===").arg(app.applicationVersion())
                   << "PID:" << QCoreApplication::applicationPid();

    // Data directory
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    checkpoint(QStringLiteral("Data directory created"));



    // Modrinth API: uniquely-identifying User-Agent header (mandatory)
    HttpClient::instance().setUserAgent(
        QStringLiteral("YOUR_APP/1.0.0"
                       " (https://github.com/xiaole1173/shadow-launcher)"));

    ShadowBackend* backend = new ShadowBackend(&app);
    checkpoint(QStringLiteral("ShadowBackend constructed"));

    // ── 设置自检（--ui-selftest-settings）────────────────────────────────────
    // 一次性跑设置项的边界 / 拒绝断言，结果打进日志。
    // 与 --ui-pane / --ui-reenter 同类的测试基础设施。
    // 注意：会改写 QSettings（内存 / 限速 / GC / 语言等），调用方跑前必须自行备份。
    if (app.arguments().contains(QStringLiteral("--ui-selftest-settings"))) {
        SettingsBackend* st = backend->settings();
        auto report = [](const QString& name, const QString& expected, const QString& actual) {
            qInfo().noquote() << QStringLiteral("[SELFTEST] %1  期望=%2  实际=%3  %4")
                                 .arg(name, expected, actual,
                                      expected == actual ? QStringLiteral("PASS") : QStringLiteral("FAIL"));
        };

        // T1：内存 setter 路径（对照，证明 setter 本身是对的）
        st->setMaxMemory(999999);
        report(QStringLiteral("T1 setMaxMemory(999999)"), QStringLiteral("32768"), QString::number(st->maxMemoryMB()));
        st->setMinMemory(-5);
        report(QStringLiteral("T1 setMinMemory(-5)"), QStringLiteral("256"), QString::number(st->minMemoryMB()));

        // F5：限速 0 应表示不限速(-1)，而不是被夹成 0.1MB/s
        st->setDownloadSpeedLimitMB(0);
        report(QStringLiteral("F5 setDownloadSpeedLimitMB(0)"), QStringLiteral("-1"), QString::number(st->downloadSpeedLimitMB()));
        st->setDownloadSpeedLimitMB(30);
        report(QStringLiteral("F5 setDownloadSpeedLimitMB(30)"), QStringLiteral("20"), QString::number(st->downloadSpeedLimitMB()));

        // F6：透明度 clamp
        st->setSidebarOpacity(5.0);
        report(QStringLiteral("F6 setSidebarOpacity(5.0)"), QStringLiteral("1"), QString::number(st->sidebarOpacity()));
        st->setContentOpacity(-1.0);
        report(QStringLiteral("F6 setContentOpacity(-1)"), QStringLiteral("0"), QString::number(st->contentOpacity()));

        // F7：枚举范围
        st->setGcMode(99);
        report(QStringLiteral("F7 setGcMode(99)"), QStringLiteral("3"), QString::number(st->gcMode()));
        st->setGcMode(0);
        st->setProcessPriority(99);
        report(QStringLiteral("F7 setProcessPriority(99)"), QStringLiteral("2"), QString::number(st->processPriority()));
        st->setProcessPriority(1);
        st->setFileDownloadSource(9);
        report(QStringLiteral("F7 setFileDownloadSource(9)"), QStringLiteral("2"), QString::number(st->fileDownloadSource()));
        st->setFileDownloadSource(1);
        st->setListDownloadSource(-3);
        report(QStringLiteral("F7 setListDownloadSource(-3)"), QStringLiteral("0"), QString::number(st->listDownloadSource()));
        st->setListDownloadSource(1);

        // F8：自动进服地址只接受 host[:port]
        st->setAutoJoinServer(QStringLiteral("mc.example.com:25565"));
        report(QStringLiteral("F8 合法地址应保留"), QStringLiteral("mc.example.com:25565"), st->autoJoinServer());
        st->setAutoJoinServer(QStringLiteral("srv --username someone"));
        report(QStringLiteral("F8 非法地址应被拒绝"), QStringLiteral("mc.example.com:25565"), st->autoJoinServer());
        st->setAutoJoinServer(QString());

        // 资源迁移校验：mod_zh.json 从 qml/ 迁到 assets/data/ 后必须仍能解析出映射。
        // 条目取自 mod_zh.json 第 3 条（"24Hourclock" -> "24小时制"）。
        {
            const QString zh = backend->resolveModZh(QStringLiteral("24Hourclock"));
            report(QStringLiteral("mod_zh.json 可读（汉化映射）"),
                   QStringLiteral("24小时制"),
                   zh.isEmpty() ? QStringLiteral("(空)") : zh);
        }

        // 资源迁移校验：协议 HTML 从 qml/ 迁到 assets/ 后，qrc 路径必须仍然可读。
        // 路径拼错时 readQrcFile 返回空串（不报错），只有断言长度才能发现。
        {
            const QString html = backend->betaAgreementHtml();
            report(QStringLiteral("协议 HTML 可读（qrc 路径）"),
                   QStringLiteral("长度>1000"),
                   html.length() > 1000 ? QStringLiteral("长度>1000")
                                        : (QStringLiteral("长度=") + QString::number(html.length())));
        }

        // 最小内存必须真的进 JVM 参数（-Xms）：导出启动脚本复用 buildArgs，
        // 可以在不启动游戏的前提下验证参数组装。
        {
            // 自检跑在版本列表异步刷新之前，installedVersions() 还是空的。
            // 直接从游戏目录扫一个真实存在的版本（有 <id>/<id>.json 才算）。
            QStringList vers = backend->installedVersions();
            if (vers.isEmpty()) {
                const QDir vroot(st->gameDir() + QStringLiteral("/versions"));
                const QFileInfoList dirs = vroot.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
                for (const QFileInfo& d : dirs) {
                    const QString id = d.fileName();
                    if (QFileInfo::exists(d.absoluteFilePath() + QLatin1Char('/') + id + QStringLiteral(".json"))) {
                        vers << id;
                        break;
                    }
                }
            }
            st->setMaxMemory(2048);
            st->setMinMemory(1536);
            if (!vers.isEmpty()) {
                const QString bat = backend->exportLaunchScript(vers.first(), st->javaPath(), 2048);
                report(QStringLiteral("最小内存写入 -Xms（导出脚本）"),
                       QStringLiteral("含 -Xms1536M"),
                       bat.contains(QStringLiteral("-Xms1536M"))
                           ? QStringLiteral("含 -Xms1536M")
                           : (QStringLiteral("不含，实际=") + bat.section(QStringLiteral("-Xms"), 1, 1).left(8)));
                // 夹取：Xms 不得大于 Xmx，否则 JVM 拒绝启动
                st->setMaxMemory(1024);
                st->setMinMemory(1024);
                const QString bat2 = backend->exportLaunchScript(vers.first(), st->javaPath(), 512);
                report(QStringLiteral("Xms 不超过 Xmx（max=512）"),
                       QStringLiteral("含 -Xms512M"),
                       bat2.contains(QStringLiteral("-Xms512M")) ? QStringLiteral("含 -Xms512M")
                                                                  : QStringLiteral("不含"));
            } else {
                report(QStringLiteral("最小内存写入 -Xms（导出脚本）"),
                       QStringLiteral("至少装 1 个版本"), QStringLiteral("无已装版本，跳过"));
            }
        }

        // 进程优先级版本级：mode=0 跟随全局、mode=1 用版本值
        {
            const QString vid = QStringLiteral("__selftest__");
            st->setProcessPriority(1);
            st->setVersionProcessPriorityMode(vid, 0);
            report(QStringLiteral("优先级 mode=0 应为跟随全局"),
                   QStringLiteral("0"), QString::number(st->versionProcessPriorityMode(vid)));
            st->setVersionProcessPriorityMode(vid, 1);
            st->setVersionProcessPriority(vid, 2);
            report(QStringLiteral("优先级 mode=1 覆盖值"),
                   QStringLiteral("2"), QString::number(st->versionProcessPriority(vid)));
            report(QStringLiteral("优先级 mode 越界应夹到 0..1"),
                   QStringLiteral("1"), [&]{ st->setVersionProcessPriorityMode(vid, 9); return QString::number(st->versionProcessPriorityMode(vid)); }());
        }

        // F10：versionId 含路径分隔符时应拒绝写键
        st->setVersionMemoryMode(QStringLiteral("../evil"), 2);
        report(QStringLiteral("F10 setVersionMemoryMode(../evil)"), QStringLiteral("0"),
               QString::number(st->versionMemoryMode(QStringLiteral("../evil"))));

        // T8：语言切换后是否置"需要重启"标志
        {
            const int langBefore = st->languageIndex();
            st->setLanguageIndex(langBefore == 1 ? 0 : 1);
            report(QStringLiteral("T8 切语言后 languageChanged"),
                   QStringLiteral("true"), st->isLanguageChanged() ? QStringLiteral("true") : QStringLiteral("false"));
            st->setLanguageIndex(langBefore);
        }

        qInfo().noquote() << QStringLiteral("[SELFTEST] 结束（本次运行已改写设置，跑完请恢复备份）");
    }

    auto argumentValue = [&app](const QString& name) {
        const int index = app.arguments().indexOf(name);
        return index >= 0 && index + 1 < app.arguments().size() ? app.arguments().at(index + 1) : QString();
    };
    const QString uiNextMode = argumentValue(QStringLiteral("--ui-next-mode"));
    const QString uiNextDensity = argumentValue(QStringLiteral("--ui-next-density"));
    const QStringList uiNextSize = argumentValue(QStringLiteral("--ui-next-size")).split(QLatin1Char('x'));
    // QML engine
    QQmlApplicationEngine engine;

    // Appearance 单例：外观页（待做）会用，当前只是承接 --ui-next-mode/--ui-next-density。
    AppearanceController* appearance = engine.singletonInstance<AppearanceController*>("ShadowLauncher.Next", "Appearance");
    if (appearance)
        appearance->setPersistenceEnabled(!app.arguments().contains(QStringLiteral("--screenshot")));

    // Clear QML disk cache to avoid stale compiled QML from older builds
    engine.clearComponentCache();

    // Add exe dir to import path so module can find qmldir
    engine.addImportPath(QCoreApplication::applicationDirPath());
    checkpoint(QStringLiteral("QML engine created"));

    // 注册自定义 3D 几何体

    // Expose backend and data directory to QML
    engine.rootContext()->setContextProperty("backend", backend);
    engine.rootContext()->setContextProperty("dataDir", dataDir);
    engine.addImportPath(QStringLiteral("qrc:/qt/qml"));

    // Pass engine reference for language hot-switch
    backend->setEngine(&engine);

    // ── Screenshot Server (Debug/Dev only; NDEBUG stubs it out) ──
    ScreenshotServer* ssServer = new ScreenshotServer(&engine, &app);

    // ── Taskbar minimize: install native event filter ──
    TaskbarMinimizeFilter* taskbarFilter = new TaskbarMinimizeFilter();
    app.installNativeEventFilter(taskbarFilter);

    // Set target window + measure first frame render
    QElapsedTimer* pStartupTimer = &startupTimer;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [taskbarFilter, pStartupTimer, ssServer](QObject* obj, const QUrl&) {
            QQuickWindow* win = qobject_cast<QQuickWindow*>(obj);
            if (!win) return;

            // ── 窗口底色：深色实底（曾经设成 transparent 来躲角落白边）──
            // 透明实底在「起页回退动画」的那一两帧会从边缘缝里透出桌面 → 一圈白边。
            // 深色实底 + DWM 圆角裁剪 = 缝里露的是自己的底色，看不出来。
            win->setColor(QColor(8, 9, 13));

#ifdef Q_OS_WIN
            // ── Windows 11 窗口圆角 ──
            // 由 DWM 直接裁出圆角（不再整窗加离屏遮罩，避免 hover 重绘时控件消失）。
            {
                HWND hwndDwm = reinterpret_cast<HWND>(win->winId());
                if (hwndDwm) {
                    DWM_WINDOW_CORNER_PREFERENCE pref = DWMWCP_ROUND;
                    DwmSetWindowAttribute(hwndDwm, DWMWA_WINDOW_CORNER_PREFERENCE,
                                          &pref, sizeof(pref));
                    // 去掉 DWM 自己在窗沿画的那圈 1px 边框（跟随系统强调色，浅色下是白线）。
                    // 页面切换那种「瞬间一帧」里，圆角重绘会把这条边框露出来 —— 就是用户报的
                    // 「白边组成的框」。DWMWA_BORDER_COLOR(34) + DWMWA_COLOR_NONE 直接不要它。
                    const DWORD borderNone = 0xFFFFFFFE; // DWMWA_COLOR_NONE
                    DwmSetWindowAttribute(hwndDwm, 34 /*DWMWA_BORDER_COLOR*/,
                                          &borderNone, sizeof(borderNone));
                }
            }
#endif

            // 点空白释放文本焦点（窗口层，见 FocusClearFilter 注释）
            win->installEventFilter(new FocusClearFilter(win));

            taskbarFilter->targetWindow = win;
            screenshotWindow = win;
            if (ssServer) ssServer->setWindow(win);

            // ── Frameless window taskbar fix: add WS_SYSMENU|WS_MINIMIZEBOX ──
            // Without these, Windows Shell ignores taskbar minimize requests
            HWND hwnd = (HWND)win->winId();
            SetWindowLongPtrW(hwnd, GWL_STYLE,
                GetWindowLongPtrW(hwnd, GWL_STYLE) | WS_SYSMENU | WS_MINIMIZEBOX);
            // Measure first frame render
            QObject::connect(win, &QQuickWindow::frameSwapped,
                win, [pStartupTimer]() {
                    qCInfo(logApp) << QStringLiteral("首帧渲染完成");
                }, Qt::SingleShotConnection);
        }, Qt::QueuedConnection);

    // Release mode: always load from precompiled qrc
    // Add root qml/ import path for Qt built-in QML modules (deployed by windeployqt)
    engine.addImportPath(QCoreApplication::applicationDirPath() + QStringLiteral("/qml"));

    QUrl url;
    checkpoint(QStringLiteral("Loading QML (precompiled qrc)..."));
    // 旧 UI（qml/）已于 2026-11-10 整体移除，只剩新 UI
    url = QUrl(QStringLiteral("qrc:/qt/qml/ShadowLauncher/Next/Main.qml"));

    // ── Beta key gate（内测闸门）──
    // 公测版（默认）不定义 SHADOW_ENABLE_BETA_GATE → 直接加载主界面。
    // 内测版：CMake -DSHADOW_ENABLE_BETA_GATE=ON 重新配置编译，启用下方密钥验证闸门。
    bool loadedBetaDialog = false;
#ifdef SHADOW_ENABLE_BETA_GATE
    checkpoint(QStringLiteral("Checking beta key..."));
    QString savedKey = ShadowBackend::loadBetaKey();

    // 已保存密钥（本地解密成功）即放行：不再每次启动重新联网验证——
    // 旧逻辑 validateBetaKey 为同步网络请求（5s 超时），网络波动/服务器偶发
    // 失败会把已保存的密钥误判为无效 → 频繁重弹内测验证窗口。
    // 密钥有效性在首次输入时已由 submitBetaKey 联网验证并加密落盘。
    // 新 UI 暂无独立的内测密钥弹窗（旧 BetaKeyDialog.qml 随 qml/ 一并移除）。
    // 若仍用 -DSHADOW_ENABLE_BETA_GATE=ON 构建，这里只做"有密钥就放行"，
    // 无密钥时直接进主界面（不再有输入窗口）—— 需要内测闸门时必须先补新 UI 的密钥页。
    if (!savedKey.isEmpty()) {
        qCInfo(logApp) << QStringLiteral("[Beta] 已保存密钥 直接放行");
    } else {
        qCWarning(logApp) << QStringLiteral("[Beta] 内测闸门已启用但新 UI 无密钥输入页，直接放行");
    }
#endif // SHADOW_ENABLE_BETA_GATE

    if (!loadedBetaDialog) {
        // Log QML engine warnings for debugging
        QObject::connect(&engine, &QQmlEngine::warnings,
                         &app, [](const QList<QQmlError>& errs) {
            for (const auto& e : errs)
                qCWarning(logApp) << QStringLiteral("[QML] %1:%2: %3")
                    .arg(e.url().toString()).arg(e.line()).arg(e.description());
        });

        engine.load(url);
    }
    checkpoint(QStringLiteral("QML engine.load() completed"));

    // 校验根对象是否加载成功
    if (!loadedBetaDialog) {
        if (engine.rootObjects().isEmpty()) {
            qCCritical(logApp) << QStringLiteral("无法加载任何QML根对象 退出");
            return -1;
        }
        checkpoint(QStringLiteral("Root objects verified"));
    }

    if (!loadedBetaDialog) {
        QObject* rootObject = engine.rootObjects().first();
        if (appearance) {
            if (!uiNextMode.isEmpty()) appearance->setMode(uiNextMode);
            if (!uiNextDensity.isEmpty()) appearance->setDensity(uiNextDensity);
        }
        if (uiNextSize.size() == 2) {
            rootObject->setProperty("width", uiNextSize.at(0).toInt());
            rootObject->setProperty("height", uiNextSize.at(1).toInt());
        }
    }

    // 接管上次退出时 detach 后仍存活的游戏进程（恢复右下角"强制关闭"按钮与结束能力）。
    // QML 已加载完成，emit runningCountChanged 会同步刷新运行列表。
    if (backend->launchBackend()) {
        backend->launchBackend()->adoptDetachedGames();
    }

    qCInfo(logApp) << QStringLiteral("事件循环已启动")
                   << "— total startup:" << startupTimer.elapsed() << "ms";

    // ── Start screenshot server ──
    {
        quint16 ssPort = static_cast<quint16>(qEnvironmentVariableIntValue("SHADOW_SS_PORT"));
        if (ssPort == 0) ssPort = 9999;
        ssServer->start(ssPort);
    }

    // ── Verify / repair test mode（校验后端实测）──
    // 用法: --verify-test <versionId> / --repair-test <versionId>
    // 结果写 <exe目录>/verify_test_result.txt，随后自动退出。
    {
        const QStringList vargs = app.arguments();
        const int verifyTestIdx = vargs.indexOf(QStringLiteral("--verify-test"));
        const int repairTestIdx = vargs.indexOf(QStringLiteral("--repair-test"));
        if (verifyTestIdx >= 0 || repairTestIdx >= 0) {
            const bool doRepair = (repairTestIdx >= 0);
            const int argIdx = doRepair ? repairTestIdx : verifyTestIdx;
            if (argIdx + 1 < vargs.size()) {
                const QString vid = vargs.at(argIdx + 1);
                const QString outPath = QCoreApplication::applicationDirPath()
                                        + QStringLiteral("/verify_test_result.txt");
                QFile::remove(outPath);
                auto writeLine = [outPath](const QString& line) {
                    QFile f(outPath);
                    if (f.open(QIODevice::Append)) {
                        f.write((line + QStringLiteral("\n")).toUtf8());
                        f.close();
                    }
                };

                QObject::connect(backend, &ShadowBackend::logMessage, backend,
                                 [writeLine](const QString& m) { writeLine(QStringLiteral("[LOG] ") + m); });
                QObject::connect(backend, &ShadowBackend::verifyFailedFiles, backend,
                                 [writeLine](const QStringList& files) {
                    for (const QString& f : files) writeLine(QStringLiteral("[FAILED] ") + f);
                });
                auto stage = std::make_shared<int>(0);   // 0=已校验, 1=已修复
                QObject::connect(backend, &ShadowBackend::verifyFinished, backend,
                                 [writeLine, backend, vid, doRepair, stage](bool ok) {
                    if (doRepair && *stage == 0) {
                        *stage = 1;
                        writeLine(QStringLiteral("[STAGE] verify ok=")
                                  + (ok ? QStringLiteral("1") : QStringLiteral("0"))
                                  + QStringLiteral(" → 开始修复"));
                        QTimer::singleShot(300, backend, [writeLine, backend, vid]() {
                            writeLine(QStringLiteral("[STAGE] repair start"));
                            backend->repairVersion(vid);
                        });
                        return;
                    }
                    writeLine(QStringLiteral("[RESULT] verifyFinished ok=")
                              + (ok ? QStringLiteral("1") : QStringLiteral("0")));
                    QTimer::singleShot(400, qApp, &QCoreApplication::quit);
                });

                QTimer::singleShot(2500, backend, [backend, vid, writeLine]() {
                    writeLine(QStringLiteral("[START] verify ") + vid);
                    backend->verifyVersion(vid);
                });
            }
        }
    }

    // ── Auto-launch test mode ──
    QStringList args = app.arguments();
    int autoIdx = args.indexOf(QStringLiteral("--auto-launch"));
    if (autoIdx >= 0 && autoIdx + 1 < args.size()) {
        QString autoVersion = args[autoIdx + 1];
        qCInfo(logApp) << QStringLiteral("[自动测试] 自动启动模式 版本=%1").arg(autoVersion);
        QTimer::singleShot(2000, backend, [backend, autoVersion]() {
            qCInfo(logApp) << QStringLiteral("[自动测试] 触发启动 版本=%1").arg(autoVersion);
            backend->launch(autoVersion, true);
        });
    }

    // ── Auto-install test mode (trigger download click programmatically) ──
    int autoInstallIdx = args.indexOf(QStringLiteral("--auto-install"));
    if (autoInstallIdx >= 0 && autoInstallIdx + 1 < args.size()) {
        QString autoVersion = args[autoInstallIdx + 1];
        qCInfo(logApp) << QStringLiteral("[自动测试] 自动安装模式 版本=%1").arg(autoVersion);
        QTimer::singleShot(1500, backend, [backend, autoVersion]() {
            qCInfo(logApp) << QStringLiteral("[自动测试] 触发安装 版本=%1").arg(autoVersion);
            backend->installVersion(autoVersion);
        });
    }

    // ── Test download mode: navigate to download page + auto-install ──
    int testDownloadIdx = args.indexOf(QStringLiteral("--test-download"));
    if (testDownloadIdx >= 0 && testDownloadIdx + 1 < args.size()) {
        QString testVersion = args[testDownloadIdx + 1];
        qCInfo(logApp) << QStringLiteral("[自动测试] 下载测试模式 版本=%1").arg(testVersion);
        // Navigate to download page after QML is ready
        QTimer::singleShot(2500, backend, [&engine, backend, testVersion]() {
            qCInfo(logApp) << QStringLiteral("[自动测试] 跳转到下载页面");
            if (!engine.rootObjects().isEmpty()) {
                engine.rootObjects().first()->setProperty("navListIndex", 1);
            }
            // Trigger install 800ms after navigation (allow page to render)
            QTimer::singleShot(800, backend, [backend, testVersion]() {
                qCInfo(logApp) << QStringLiteral("[自动测试] 触发下载安装 版本=%1").arg(testVersion);
                backend->installVersion(testVersion);
            });
        });
    }

    // ── Navigate + Screenshot test mode ──
    // Smart timing: wait for content-ready signal, not fixed delay
    // Usage: --screenshot <name> [--navigate <page>:<tab>]
    int ssIdx = args.indexOf(QStringLiteral("--screenshot"));
    if (ssIdx >= 0 && ssIdx + 1 < args.size()) {
        QString ssName = args[ssIdx + 1];
        QString ssPath = QCoreApplication::applicationDirPath() + "/" + ssName + ".png";
        qCInfo(logApp) << QStringLiteral("[截图] 截图模式 保存路径=%1").arg(ssPath);

        // Parse --navigate argument
        int navIdx = args.indexOf(QStringLiteral("--navigate"));
        int targetPage = -1, targetTab = -1;
        if (navIdx >= 0 && navIdx + 1 < args.size()) {
            QString navArg = args[navIdx + 1];
            QStringList parts = navArg.split(':');
            QString pageStr;
            if (parts.size() >= 1) {
                pageStr = parts[0].toLower();
                // 统计 / 实用网站两个页面已移除（2026-11-10），nav model 只剩 6 项
                if (pageStr == "launch" || pageStr == "0") targetPage = 0;
                else if (pageStr == "download" || pageStr == "1") targetPage = 1;
                else if (pageStr == "multiplayer" || pageStr == "2") targetPage = 2;
                else if (pageStr == "settings" || pageStr == "3") targetPage = 3;
            }
            if (parts.size() >= 2) {
                QString tabStr = parts[1].toLower();
                if (pageStr == "settings" || pageStr == "3") {
                    if (tabStr == "general" || tabStr == "0") targetTab = 0;
                    else if (tabStr == "java" || tabStr == "1") targetTab = 1;
                    else if (tabStr == "memory" || tabStr == "2") targetTab = 2;
                    else if (tabStr == "experimental" || tabStr == "3") targetTab = 3;
                    else if (tabStr == "about" || tabStr == "4") targetTab = 4;
                } else {
                    if (tabStr == "mc" || tabStr == "0") targetTab = 0;
                    else if (tabStr == "mod" || tabStr == "1") targetTab = 1;
                    else if (tabStr == "shader" || tabStr == "2") targetTab = 2;
                    else if (tabStr == "rp" || tabStr == "3") targetTab = 3;
                    else if (tabStr == "pack" || tabStr == "4") targetTab = 4;
                    else if (tabStr == "datapack" || tabStr == "dp" || tabStr == "5") targetTab = 5;
                }
            }
        }

        // Parse --detail argument (force-open RP detail page)
        int detailIdx = args.indexOf(QStringLiteral("--detail"));
        QString detailSlug;
        if (detailIdx >= 0 && detailIdx + 1 < args.size()) {
            detailSlug = args[detailIdx + 1];
            targetPage = 1;  // force download page
            if (targetTab < 0) targetTab = 3;  // default to RP tab
        }

        // Parse --detail-expand <major> (expand a group in detail page)
        int expandIdx = args.indexOf(QStringLiteral("--detail-expand"));
        QString expandMajor;
        if (expandIdx >= 0 && expandIdx + 1 < args.size()) {
            expandMajor = args[expandIdx + 1];
        }

        // Parse --toggle-pre-release <on|off>
        int toggleIdx = args.indexOf(QStringLiteral("--toggle-pre-release"));
        bool togglePreRelease = false, hasToggle = false;
        if (toggleIdx >= 0 && toggleIdx + 1 < args.size()) {
            togglePreRelease = (args[toggleIdx + 1].toLower() == QStringLiteral("on"));
            hasToggle = true;
            targetPage = 1; if (targetTab < 0) targetTab = 3;
        }

        // Parse --open-version-menu
        bool openVersionMenu = args.contains(QStringLiteral("--open-version-menu"));
        // Parse --open-version-settings <section>（版本设置浮层，-1=概览 1=启动配置）
        int vsSection = -2;
        int vsIdx = args.indexOf(QStringLiteral("--open-version-settings"));
        if (vsIdx >= 0 && vsIdx + 1 < args.size()) {
            vsSection = args[vsIdx + 1].toInt();
        }
        if (openVersionMenu) {
            targetPage = 1; if (targetTab < 0) targetTab = 3;
        }

        // Shared ready flag (heap-allocated so lambdas share ownership)
        auto ready = std::make_shared<bool>(false);
        auto doScreenshot = [ssPath, &app]() {
            // Use QQuickWindow::grabWindow() — renders window content off-screen
            // (QScreen::grabWindow captures screen compositor + overlapping windows on Windows)
            auto* qw = qobject_cast<QQuickWindow*>(screenshotWindow);
            if (qw && qw->isVisible()) {
                QImage img = qw->grabWindow();
                QPixmap pix = QPixmap::fromImage(img);
                if (pix.save(ssPath, "PNG")) {
                    qCInfo(logApp) << QStringLiteral("[截图] 截图已保存 路径=%1").arg(ssPath)
                                   << "size:" << pix.width() << "x" << pix.height();
                } else {
                    qCCritical(logApp) << QStringLiteral("[截图] 截图保存失败 路径=%1").arg(ssPath);
                }
            } else {
                qCCritical(logApp) << QStringLiteral("[截图] 窗口未就绪");
            }
            // Give async icon downloads 10s to finish before quitting
            qCInfo(logApp) << QStringLiteral("[截图] 等待10秒图标下载后退出");
            QTimer::singleShot(10000, qApp, &QCoreApplication::quit);
        };

        if (targetPage >= 0) {
            qCInfo(logApp) << QStringLiteral("[截图] 导航到页面=%1").arg(targetPage)
                           << "tab" << targetTab;

            // Navigate after QML is ready
            QTimer::singleShot(1500, backend, [backend, targetPage, targetTab, 
                    detailSlug, expandMajor, togglePreRelease, hasToggle, openVersionMenu, vsSection]() {
                emit backend->navigateToRequested(targetPage, targetTab);
                
                // --open-version-settings: 打开版本设置浮层到指定分区
                if (vsSection >= -1) {
                    QTimer::singleShot(800, backend, [backend, vsSection]() {
                        qCInfo(logApp) << QStringLiteral("[截图] 打开版本设置浮层 section=%1").arg(vsSection);
                        emit backend->navigateToRequested(99, vsSection);
                    });
                }

                // --toggle-pre-release <on|off>
                if (hasToggle) {
                    QTimer::singleShot(500, backend, [backend, togglePreRelease]() {
                        qCInfo(logApp) << QStringLiteral("[截图] 切换预发布开关=%1").arg(togglePreRelease);
                        emit backend->setRpShowPreReleases(togglePreRelease);
                    });
                }
                
                // --open-version-menu
                if (openVersionMenu) {
                    QTimer::singleShot(1000, backend, [backend]() {
                        qCInfo(logApp) << QStringLiteral("[截图] 打开版本下拉菜单");
                        emit backend->openRpVersionMenu();
                    });
                }
                
                // Open detail page if --detail flag was set
                if (!detailSlug.isEmpty()) {
                    QTimer::singleShot(2000, backend, [backend, detailSlug, expandMajor, targetTab]() {
                        qCInfo(logApp) << QStringLiteral("[截图] 打开详情页 slug=%1 tab=%2").arg(detailSlug, targetTab);
                        if (targetTab == 1)
                            emit backend->openModDetailRequested(detailSlug);
                        else if (targetTab == 2)
                            emit backend->openShaderDetailRequested(detailSlug);
                        else
                            emit backend->openRpDetailRequested(detailSlug);
                        // --detail-expand <major>
                        if (!expandMajor.isEmpty()) {
                            QTimer::singleShot(3500, backend, [backend, expandMajor]() {
                                qCInfo(logApp) << QStringLiteral("[截图] 展开详情分组 version=%1").arg(expandMajor);
                                emit backend->expandRpDetailGroup(expandMajor);
                            });
                        }
                    });
                }
            });

            // Connect to content-ready signals based on target
            if (!detailSlug.isEmpty()) {
                // --detail mode: wait for detail page + expand to complete
                // QML engine init takes ~10s, total chain: navigate(1.5)+detail(2)+expand(3.5)+QML timer(0.5) ≈ 7.5s after first paint
                QTimer::singleShot(20000, &app, [ready]() {
                    *ready = true;
                    qCInfo(logApp) << QStringLiteral("[截图] 详情页就绪");
                });
            } else if (openVersionMenu) {
                // --open-version-menu mode: wait for results then open menu
                QTimer::singleShot(9000, &app, [ready]() {
                    *ready = true;
                    qCInfo(logApp) << QStringLiteral("[截图] 版本菜单就绪");
                });
            } else if (targetPage == 1 && targetTab == 3) {
                // RP tab: wait for search results
                QObject::connect(backend, &ShadowBackend::resourcepackSearchCompleted,
                    &app, [ready](const QVariantList&, int) {
                        *ready = true;
                        qCInfo(logApp) << QStringLiteral("[截图] 资源包搜索完成 就绪");
                    });
            } else if (targetPage == 1 && targetTab == 1) {
                // Mod tab: wait for mod search results
                QObject::connect(backend, &ShadowBackend::searchResultsReady,
                    &app, [ready](const QVariantList&) {
                        *ready = true;
                        qCInfo(logApp) << QStringLiteral("[截图] Mod搜索完成 就绪");
                    });
            } else {
                // Launch/Settings: ready after base render delay
                QTimer::singleShot(3000, &app, [ready]() {
                    *ready = true;
                });
            }

            // Poll until ready or timeout
            auto pollTimer = new QTimer(&app);
            auto maxTimer = new QTimer(&app);
            QObject::connect(pollTimer, &QTimer::timeout, &app, [ready, pollTimer, maxTimer, doScreenshot]() {
                if (*ready) {
                    qCInfo(logApp) << QStringLiteral("[截图] 内容就绪 开始截图");
                    pollTimer->stop();
                    maxTimer->stop();
                    // Small delay for final rendering
                    QTimer::singleShot(500, qApp, doScreenshot);
                }
            });
            QObject::connect(maxTimer, &QTimer::timeout, &app, [ready, pollTimer, doScreenshot]() {
                qCWarning(logApp) << QStringLiteral("[截图] 等待超时 强制截图");
                pollTimer->stop();
                *ready = true;  // force
                QTimer::singleShot(200, qApp, doScreenshot);
            });
            pollTimer->start(200);     // check every 200ms
            maxTimer->start(60000);    // 60s max timeout (icon download needs time)

        } else {
            // No navigation: take screenshot after QML render delay
            QTimer::singleShot(3000, &app, doScreenshot);
        }
    }

    // ── Auto-install-loader test mode ──
    int autoLoaderIdx = args.indexOf(QStringLiteral("--auto-install-loader"));
    if (autoLoaderIdx >= 0 && autoLoaderIdx + 4 < args.size()) {
        QString loaderMcVer = args[autoLoaderIdx + 1];
        QString loaderType = args[autoLoaderIdx + 2];
        QString loaderVer = args[autoLoaderIdx + 3];
        QString loaderName = args[autoLoaderIdx + 4];
        qCInfo(logApp) << QStringLiteral("[自动测试] 安装加载器 MC=%1").arg(loaderMcVer)
                       << loaderType << loaderVer << ">" << loaderName;
        QTimer::singleShot(2000, backend, [backend, loaderMcVer, loaderType, loaderVer, loaderName]() {
            qCInfo(logApp) << QStringLiteral("[自动测试] 先安装MC 版本=%1").arg(loaderMcVer);
            backend->installVersion(loaderMcVer);
            // Chain loader install after MC finishes
            QObject::connect(backend, &ShadowBackend::installComplete,
                backend, [backend, loaderMcVer, loaderType, loaderVer, loaderName](const QString& completedName) {
                    // Only chain if the completed install is the MC version we're waiting for
                    if (completedName != loaderMcVer) return;
                    qCInfo(logApp) << QStringLiteral("[自动测试] MC安装完成 安装加载器=%1").arg(loaderType);
                    QTimer::singleShot(1000, backend, [backend, loaderMcVer, loaderType, loaderVer, loaderName]() {
                        backend->installModLoader(loaderMcVer, loaderType, loaderVer, loaderName);
                    });
                });
        });
    }
    int dlIdx = args.indexOf(QStringLiteral("--auto-download"));
    if (dlIdx >= 0 && dlIdx + 1 < args.size()) {
        QString dlVersion = args[dlIdx + 1];
        qCInfo(logApp) << QStringLiteral("[自动测试] 自动下载模式 版本=%1").arg(dlVersion);
        QTimer::singleShot(5000, backend, [backend, dlVersion]() {
            qCInfo(logApp) << QStringLiteral("[自动测试] 触发下载安装 版本=%1").arg(dlVersion);
            backend->installVersion(dlVersion);
        });
    }

    // 关闭启动器不应连带关闭游戏：游戏是独立 java 进程，退出前先分离。
    QObject::connect(&app, &QCoreApplication::aboutToQuit, backend, [backend]() {
        if (backend->launchBackend()) {
            backend->launchBackend()->detachAllGames();
        }
    });

    return app.exec();
}
