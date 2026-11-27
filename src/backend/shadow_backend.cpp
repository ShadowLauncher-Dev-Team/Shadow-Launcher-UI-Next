// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "shadow_backend.h"
#include "../secrets.h"
#include "../core/http_client.h"
#include "../core/step_keys.h"
#include "../core/loader_plan.h"
#include "../core/cleanup_guard.h"
#include <QTemporaryDir>
#include "../core/source_policy.h"
#include "../core/file_downloader.h"
#include "../core/download_accept.h"
#include "../core/step_pipeline.h"
#include "../core/step_node.h"
#include "../core/resource_fetch_engine.h"
#include "../core/mod_manager.h"
#include "yggdrasil_skin_fetcher.h"
#include "../core/update_manager.h"
#include "../core/icon_cache.h"
#include "../core/modpack_importer.h"
#include "../core/modpack/modpack_exporter.h"
#include "../core/local_mod_manager.h"
#include "../multiplayer/multiplayer_manager.h"
#include "../multiplayer/relay_crypto.h"
#include "../utils/secure_wipe.h"
#include "../multiplayer/encrypted_addr.h"  // kWorker offset constants
#include "../core/version_downloader.h"
#include "../core/geoip_service.h"
#include "../core/mc_language.h"
#include <QApplication>
#include <QFileDialog>
#include <QTimer>
#include <QTimer>
#include <QDirIterator>
#include <QFile>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QProcess>
#include "../core/version_isolation.h"
#include "../utils/logger.h"
#include <QElapsedTimer>
#include <QMutex>
#include <QThread>
#include <QtConcurrent>
#include <QtCore/private/qzipreader_p.h>   // 读 jar 内 version.json（MC 版本的最终兜底）
#include <QRegularExpression>
#include <functional>
#include "account_backend.h"
#include "yggdrasil_backend.h"
#include "app_backend.h"
#include "check_backend.h"
#include "userdata_backend.h"
#include "launch_backend.h"
#include "resource_backend.h"
#include "minecraft_folder_backend.h"
#include "settings_backend.h"
#include "version_backend.h"
#include "../utils/temp_tracker.h"
#include "java_backend.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QLocale>
#include <QDesktopServices>
#include <QJsonDocument>
#include <QJsonObject>
#include <QGuiApplication>
#include <QCursor>
#include <QWindow>
#include <QDir>
#include <QDirIterator>
#include <QEvent>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QImage>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <memory>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QProcess>
#include <QRegularExpression>
#include <QTranslator>
#include <QUrl>

// libwebp: in-process webp→PNG decoding
#include <webp/decode.h>
#include <webp/encode.h>
#include <QSettings>
#include <QTextStream>
#include <QTimer>
#include <QUrl>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QEventLoop>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dpapi.h>
#endif

// 版本目录条目是否应跳过：junction/符号链接（Qt 的 isSymLink() 在 Windows 对
// junction(mount point) 返回 false，需直接查 reparse point——2026-08-19 实测）
static bool isVersionEntryLink(const QFileInfo& fi)
{
#ifdef Q_OS_WIN
    const QString p = fi.absoluteFilePath();
    const DWORD attr = GetFileAttributesW(reinterpret_cast<LPCWSTR>(p.utf16()));
    if (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
        return true;
    return false;
#else
    return fi.isSymLink();
#endif
}

namespace ShadowLauncher {

QObject* ShadowBackend::launchPipeline() const
{
    return m_launch ? m_launch->launchPipeline() : nullptr;
}

qreal ShadowBackend::launchOverallProgress() const
{
    return m_launch ? m_launch->launchOverallProgress() : 0.0;
}

int ShadowBackend::launchStepCount() const
{
    return m_launch ? m_launch->launchStepCount() : 0;
}

int ShadowBackend::launchStepNumber() const
{
    return m_launch ? m_launch->launchStepNumber() : 0;
}

QVariantList ShadowBackend::launchStepRows() const
{
    return m_launch ? m_launch->launchStepRows() : QVariantList{};
}

QVariantList ShadowBackend::launchRepairs() const
{
    return m_launch ? m_launch->launchRepairs() : QVariantList{};
}

bool ShadowBackend::launchFailed() const
{
    return m_launch ? m_launch->launchFailed() : false;
}

QString ShadowBackend::launchFailReason() const
{
    return m_launch ? m_launch->launchFailReason() : QString();
}

bool ShadowBackend::launchFinishedOk() const
{
    return m_launch ? m_launch->launchFinishedOk() : false;
}

ShadowBackend::ShadowBackend(QObject* parent)
    : QObject(parent)
{
    QElapsedTimer bt; bt.start();
    auto bp = [&bt](const char* label) {
        qCInfo(logApp) << QStringLiteral("[后端启动 +%1ms] %2").arg(bt.elapsed()).arg(label);
    };

    // Create all sub-backends
    m_app = new AppBackend(this);
    bp("AppBackend");
    m_account = new AccountBackend(this);
    bp("AccountBackend");
    m_yggdrasil = new YggdrasilBackend(this);
    bp("YggdrasilBackend");
    m_settings = new SettingsBackend(this);
    // 背景图库把导入的图复制到这里：与原图解耦，用户移动/删除原文件都不影响启动页。
    // 目录唯一来源 = AppBackend::dataDir()，不再各自拼 "../data"。
    m_settings->setBgStorageDir(m_app->dataDir() + QStringLiteral("/custom_bg"));
    bp("SettingsBackend");
    m_check = new CheckBackend(this);
    bp("CheckBackend");
    m_version = new VersionBackend(this);
    bp("VersionBackend");
    m_launch = new LaunchBackend(this);
    // 启动阶段节点变化 → 转发给 QML（启动浮层据此渲染）
    connect(m_launch, &LaunchBackend::launchStepsChanged,
            this, &ShadowBackend::launchPipelineChanged);
    bp("LaunchBackend");
    m_resource = new ResourceBackend(this);
    bp("ResourceBackend");
    m_java = new JavaBackend(this);
    bp("JavaBackend");

    // ── 注入 Java 自动安装器到 LaunchBackend（启动状态机内 Java 缺失时自动安装）──
    m_launch->setJavaInstaller(
        [this](int major,
               std::function<void(int, const QString&)> onProgress,
               std::function<void(bool, const QString&, const QString&)> onDone) {
            m_java->installJavaForLaunch(major, std::move(onProgress), std::move(onDone));
        });
    m_launch->setJavaCanceler([this]() {
        // JavaRuntimeInstaller::cancelInstall：下载中 abort+清理，解压/安装中不打断
        m_java->cancelJavaInstall();
    });
    // 需求解析：版本 JSON 链 + MC 版本推断（原 ShadowBackend::requiredJavaMajor）
    m_launch->setJavaMajorResolver(
        [this](const QString& versionId) { return requiredJavaMajor(versionId); });
    // 匹配器：手动 Java 优先（满足版本区间），否则自动匹配；含 8 精确 / 17→max21 规则
    m_launch->setJavaMatcher(
        [this](int requiredMajor) {
            if (requiredMajor <= 0) return QString();
            // 版本归一化：Tuna 无 JRE 16（404 实测），Java 17 兼容 1.17
            if (requiredMajor == 16) requiredMajor = 17;
            // 兼容上限：老版本 Forge/Mixin 不支持太新的 Java 类格式
            int maxMajor = 0;
            if (requiredMajor == 17) maxMajor = 21;
            const QString manualJava = m_settings->javaPath();
            if (!manualJava.isEmpty() && QFileInfo::exists(manualJava)) {
                const int manualMajor = m_settings->javaMajor();
                // Java 8 精确匹配（Java 9+ 模块问题，pre-1.13 LaunchWrapper 必崩）
                if (requiredMajor == 8 && manualMajor == 8)
                    return manualJava;
                if (requiredMajor != 8 && manualMajor >= requiredMajor
                    && (maxMajor <= 0 || manualMajor <= maxMajor))
                    return manualJava;
            }
            const QString matched = m_settings->findJavaForVersion(requiredMajor, maxMajor);
            if (!matched.isEmpty())
                emit logMessage(tr("[完成] 已自动匹配 Java %1: %2").arg(requiredMajor).arg(matched));
            return matched;
        });
    // 列表刷新器：扫描 + 等 javaScanFinished（SingleShot 连接）→ onDone；不弹 toast
    m_launch->setJavaRefresher(
        [this](std::function<void()> onDone) {
            auto* conn = new QMetaObject::Connection;
            *conn = connect(m_settings, &SettingsBackend::javaScanFinished, this,
                [this, conn, onDone]() {
                    disconnect(*conn);
                    delete conn;
                    if (onDone) onDone();
                });
            m_settings->scanJavaInstallations();
        });

    // ── Java 一键安装完成后：自动刷新两处 Java 状态 ──
    // 1) SettingsBackend 重新扫描系统 Java（设置-Java 列表更新）
    // 2) JavaRuntimeInstaller 重新前置检测（关于页一键安装卡片更新）
    connect(m_java, &JavaBackend::javaInstallFinished, this, [this](bool ok, const QString&) {
        if (!ok) return;  // 安装失败不需要刷新
        // 重新扫描设置-Java（findAllJava 现在含 java_cache，新装的会出现在列表）
        m_settings->scanJavaInstallations();
        // 刷新一键安装卡片的前置检测（scanSystemJavas 异步，完成后 emit systemJavaScanFinished）
        m_java->scanSystemJavas();
        qCInfo(logJava) << QStringLiteral("[Java安装] 安装完成，已触发 Java 列表与前置检测刷新");
    });

    m_userData = new UserDataBackend(this);
    bp("UserDataBackend");

    // 用户数据导出/导入日志接入主日志（诊断用）
    connect(m_userData, &UserDataBackend::logMessage,
            this, &ShadowBackend::logMessage);

    // ── Icon cache (3 separate caches: mod / shader / rp, each max 100) ──
    QString iconBase = m_app->dataDir() + "/icons";
    m_modIconCache = new IconCache(iconBase + "/mod", 100, this);
    m_shaderIconCache = new IconCache(iconBase + "/shader", 100, this);
    m_rpIconCache = new IconCache(iconBase + "/rp", 100, this);

    // ── 资源拉取引擎（司南）：统一列表 API + 图标拉取（并发/缓存/缩略图）──
    m_fetchEngine = new ResourceFetchEngine(m_app->dataDir() + "/cache/res", this);
    connect(m_fetchEngine, &ResourceFetchEngine::iconReady,
            this, [this](const QString& url, const QString& path) {
        emit iconReady(url, path);
    });
    if (m_resource)
        m_resource->setFetchEngine(m_fetchEngine);
    m_multiplayer = new MultiplayerManager(this);
    // ── 联机页的 MC LAN 端口来源 ──
    // 主通道：启动器解析游戏 JVM 输出里的 "Started serving on <port>"（可靠、与网络无关）；
    // 兜底：MultiplayerManager 内的 UDP 组播扫描器（多网卡/屏蔽环境下会漏）。
    if (m_launch && m_multiplayer) {
        connect(m_launch, &LaunchBackend::mcLanOpened,
                m_multiplayer, &MultiplayerManager::notifyMcLanPort);
        connect(m_multiplayer, &MultiplayerManager::hostWaitingForMcServer,
                this, [this]() {
            if (!m_launch || !m_multiplayer)
                return;
            // 1) 本进程捕获的 JVM 输出缓存（最准）
            const int cached = m_launch->lastMcLanPort();
            if (cached > 0) {
                m_multiplayer->notifyMcLanPort(cached);
                return;
            }
            // 2) 游戏已开着但启动器重启过（无 stdout 管道）→ 读日志文件兜底
            const int fromLog = m_launch->probeLanPortFromLogs();
            if (fromLog > 0)
                m_multiplayer->notifyMcLanPort(fromLog);
        });
    }
    m_localMods = new LocalModManager(this);
    m_modpackImporter = new ModpackImporter(this);
    m_modpackExporter = new ModpackExporter(this);
    {
        auto* exporter = qobject_cast<ModpackExporter*>(m_modpackExporter);
        if (exporter)
            exporter->setGameDir(m_app->gameDir());   // 初始化（否则 m_gameDir 为空，导出全路径失效）
    }
    {
        auto* importer = qobject_cast<ModpackImporter*>(m_modpackImporter);
        if (importer) {
            importer->setVersionBackend(m_version);
            importer->setGameDir(m_app->gameDir());
            importer->setIsolation(m_settings->isolation());
        }
    }

    // ── 外部 .minecraft 文件夹（选择/识别/读取，2026-08-18）──
    // 应用/回退通过信号驱动本类的 onApplyForeignFolder/onRevertForeignFolder，
    // 由本类完成全部子后端的目录切换接线。
    m_mcFolder = new MinecraftFolderBackend(this);
    m_mcFolder->setDataDir(m_app->dataDir());  // 游戏文件夹注册表存放目录
    connect(m_mcFolder, &MinecraftFolderBackend::applyRequested,
            this, &ShadowBackend::onApplyForeignFolder);
    connect(m_mcFolder, &MinecraftFolderBackend::revertRequested,
            this, &ShadowBackend::onRevertForeignFolder);
    connect(m_mcFolder, &MinecraftFolderBackend::foreignChanged,
            this, &ShadowBackend::isolationChanged);  // 外部形态变化 → UI 隔离开关刷新

    syncPlayerName();
    bp("IconCache");

    // ── Sync game directories: ALL backends use the same path ──
    m_version->setGameDir(m_app->gameDir());
    m_settings->setMinecraftDir(m_app->gameDir());
    m_settings->setIsolationGameDir(m_app->gameDir());
    m_localMods->setGameDir(m_app->gameDir());
    m_launch->setGameDir(m_app->gameDir());
    m_launch->setAccount(m_account);
    m_version->setIsolation(m_settings->isolation());

    // 2026-08-19：恢复上次使用的活动游戏文件夹（持久化）。
    // 必须放在默认目录同步之后，否则 249-255 的 setGameDir(默认) 会覆盖恢复结果。
    // 注册表中无活动外部目录/目录已不存在 → 保持默认，行为不变。
    m_mcFolder->restoreActiveFolder();

    // ── GeoIP service (auto-language detection) ──
    m_geoIp = new GeoIpService(this);
    // Pass initial settings
    m_version->setAutoLangMode(m_settings->autoLangMode());
    m_version->setDetectedRegion(m_geoIp->cachedRegion());
    // React to setting changes
    connect(m_settings, &SettingsBackend::autoLangModeChanged, this, [this]() {
        m_version->setAutoLangMode(m_settings->autoLangMode());
    });
    // When GeoIP detects region, update VersionBackend and retroactively apply
    connect(m_geoIp, &GeoIpService::regionDetected, this, [this](const QString& region) {
        m_version->setDetectedRegion(region);
        // If mode=2 (IP region), retroactively write options.txt for all installed versions
        if (m_settings->autoLangMode() == 2) {
            const auto ids = m_version->installedIds();
            for (const QString& id : ids) {
                QString versionGameDir = m_settings->getVersionGameDir(id);
                QString mcLang = mc_language::regionToMinecraftLang(region);
                mc_language::writeOptionsTxt(versionGameDir, mcLang);
            }
        }
    });
    // Background pre-detect (3s delay so it doesn't slow startup)
    QTimer::singleShot(3000, m_geoIp, &GeoIpService::detectRegion);

    bp("Signal wiring...");
    connect(m_account, &AccountBackend::accountChanged,
            this, &ShadowBackend::accountChanged);
    connect(m_account, &AccountBackend::accountChanged,
            this, &ShadowBackend::syncPlayerName);
    connect(m_account, &AccountBackend::accountsChanged,
            this, &ShadowBackend::accountsChanged);
    // 披风加载状态：AccountBackend 的标志要代理给 QML（详见头文件注释）
    if (m_account) {
        connect(m_account, &AccountBackend::capesLoadingChanged,
                this, &ShadowBackend::accountLoadingChanged);
        connect(m_account, &AccountBackend::capesAskedChanged,
                this, &ShadowBackend::capesAskedChanged);
    }
    // 外置登录成功 → 写入多账号列表（YggdrasilBackend 自己不知道账号列表现存结构）
    if (auto *ygg = static_cast<YggdrasilBackend*>(m_yggdrasil)) {
        connect(ygg, &YggdrasilBackend::loginSuccess, this, [this]() {
            auto *y = static_cast<YggdrasilBackend*>(m_yggdrasil);
            if (!y || !m_account) return;
            m_account->upsertExternalAccount(y->username(), y->uuid(), y->apiRoot(),
                                             y->accessToken(), y->clientToken());
        });
        // 令牌被判失效时把账号条目标记为"需重新登录"，
        // 这样点它只会打开登录表单，不会拿死令牌再恢复一次。
        connect(ygg, &YggdrasilBackend::externalSessionExpired, this,
                [this](const QString& user) {
            if (m_account) m_account->markNeedsRelogin(user, 2);
        });
        // refresh 会轮换 accessToken/clientToken。以前只写 session.json，
        // accounts.json 里留的还是旧令牌 → 下次"从多账号列表恢复"必然 403 被判过期。
        connect(ygg, &YggdrasilBackend::tokensRotated, this, [this]() {
            auto *y = static_cast<YggdrasilBackend*>(m_yggdrasil);
            if (!y || !m_account || !y->loggedIn()) return;
            m_account->upsertExternalAccount(y->username(), y->uuid(), y->apiRoot(),
                                             y->accessToken(), y->clientToken());
        });
        // 外置会话的恢复/失效是异步的：状态一变就要让 accountOnline 重新求值，
        // 否则启动页会一直停在切换那一刻的「离线」橙点上。
        connect(ygg, &YggdrasilBackend::stateChanged, this, [this]() {
            emit accountChanged();
        });
        // 外置账号的皮肤由 YggdrasilSkinFetcher 拉，AccountBackend 看不到，
        // 必须喂给它，否则这条账号永远没有自己的头像快照 ——
        // 切到别的账号后，外置那行就只剩字母（影报的「外置头像变字母」）。
        if (auto *sf = qobject_cast<YggdrasilSkinFetcher*>(ygg->skinFetcherObj())) {
            auto pushSkin = [this, sf]() {
                if (m_account) m_account->setExternalSkinPath(sf->skinPath());
            };
            connect(sf, &YggdrasilSkinFetcher::skinChanged, this, pushSkin);
            connect(sf, &YggdrasilSkinFetcher::skinReady, this, pushSkin);
            pushSkin();
        }
    }
    // 皮肤上传结果：复位衣柜忙碌态，并把失败原因交给 UI。
    // （以前这个信号没有任何接收方 → 上传失败时界面毫无反应。）
    connect(m_account, &AccountBackend::skinUploadFinished, this,
            [this](bool ok, const QString& err) {
        m_wardrobeBusy = false;
        emit wardrobeBusyChanged();
        if (ok) {
            emit logMessage(tr("皮肤已上传，正在同步头像"));
        } else {
            emit wardrobeError(err.isEmpty() ? tr("皮肤上传失败") : err);
        }
    });

    connect(m_account, &AccountBackend::skinReady,
            this, &ShadowBackend::skinReady);
    connect(m_account, &AccountBackend::offlineSkinReady,
            this, &ShadowBackend::offlineSkinReady);
    connect(m_account, &AccountBackend::offlineHistoryChanged,
            this, &ShadowBackend::offlineHistoryChanged);
    connect(m_account, &AccountBackend::logMessage,
            this, &ShadowBackend::logMessage);
    connect(m_account, &AccountBackend::microsoftLoginProgress,
            this, &ShadowBackend::microsoftLoginProgress);
    connect(m_account, &AccountBackend::microsoftLoginSuccess,
            this, &ShadowBackend::microsoftLoginSuccess);
    connect(m_account, &AccountBackend::microsoftLoginFailed,
            this, &ShadowBackend::microsoftLoginFailed);
    connect(m_account, &AccountBackend::microsoftLoginBusyChanged,
            this, &ShadowBackend::microsoftLoginBusyChanged);
    // Persist username on every login
    connect(m_account, &AccountBackend::accountChanged,
            this, [this]() {
                QString u = m_account->username();
                if (!u.isEmpty()) {
                    QSettings s(QCoreApplication::organizationName(),
                                QCoreApplication::applicationName());
                    s.setValue(QStringLiteral("account/lastUsername"), u);
                }
            });

    // ── Signal forwarding: SettingsBackend → ShadowBackend ──
    connect(m_settings, &SettingsBackend::javaPathChanged,
            this, &ShadowBackend::javaPathChanged);
    connect(m_settings, &SettingsBackend::javaScanFinished,
            this, &ShadowBackend::javaScanFinished);
    connect(m_settings, &SettingsBackend::memorySettingsChanged,
            this, &ShadowBackend::memorySettingsChanged);
    connect(m_settings, &SettingsBackend::generalSettingsChanged,
            this, &ShadowBackend::generalSettingsChanged);
    connect(m_settings, &SettingsBackend::isolationChanged,
            this, &ShadowBackend::isolationChanged);
    connect(m_settings, &SettingsBackend::embeddedLoginChanged,
            this, &ShadowBackend::embeddedLoginChanged);
    connect(m_settings, &SettingsBackend::customBgChanged,
            this, &ShadowBackend::customBgChanged);
    connect(m_settings, &SettingsBackend::bgLibraryChanged,
            this, &ShadowBackend::bgLibraryChanged);
    connect(m_settings, &SettingsBackend::colorSchemeChanged,
            this, &ShadowBackend::colorSchemeChanged);
    connect(m_settings, &SettingsBackend::logMessage,
            this, &ShadowBackend::logMessage);

    // ── Embedded login: sync SettingsBackend ↔ AccountBackend ──
    m_account->setEmbeddedLoginEnabled(m_settings->embeddedLoginEnabled());
    connect(m_settings, &SettingsBackend::embeddedLoginChanged, this, [this]() {
        m_account->setEmbeddedLoginEnabled(m_settings->embeddedLoginEnabled());
    });

    // ── Signal forwarding: CheckBackend → ShadowBackend ──
    connect(m_check, &CheckBackend::logMessage,
            this, &ShadowBackend::logMessage);

    // ── Signal forwarding: VersionBackend → ShadowBackend ──
    connect(m_version, &VersionBackend::versionRefreshFinished, this,
            [this](bool ok, const QString& message, int count) {
                emit versionRefreshFinished(ok, message, count);
            });
    connect(m_version, &VersionBackend::versionListReady, this, [this]() {
        m_versionListCacheValid = false;
        m_versionListCache.clear();
        m_versionDateMapCache.clear();
        emit versionListReady();
    });
    connect(m_version, &VersionBackend::installedVersionsChanged,
            this, [this]() {
                // 已安装列表就绪时恢复上次选中版本——只恢复「真实存在」的版本（installedIds）。
                // 旧逻辑挂在 versionListReady 且用 versionIds（manifest 在线清单），
                // manifest 有但未安装的版本会被误选中（如 26.2 vs 实际安装的 26.2-forge-65.1.0）。
                const QStringList installed = m_version->installedIds();
                const QString last = m_settings->lastSelectedVersion();
                if (!last.isEmpty() && installed.contains(last)) {
                    m_version->setSelectedVersion(last);
                    qCInfo(logLaunch) << QStringLiteral("恢复上次选中版本 版本=%1").arg(last);
                    return;
                }
                // 自愈：当前选中版本已不存在（被删除/文件夹被手动删掉）→ 自动切换到可用版本
                const QString cur = m_version->selectedVersion();
                if (!cur.isEmpty() && !installed.contains(cur)) {
                    m_version->ensureSelectedVersionValid();
                    qCInfo(logLaunch) << QStringLiteral("选中版本 %1 已不存在，已自动切换").arg(cur);
                }
            });
    connect(m_version, &VersionBackend::installedVersionsChanged,
            this, &ShadowBackend::installedVersionsChanged);
    connect(m_version, &VersionBackend::installedVersionsChanged,
            this, &ShadowBackend::activeVersionNamesChanged);
        connect(m_version, &VersionBackend::installStateChanged,
            this, &ShadowBackend::activeVersionNamesChanged);
    connect(m_version, &VersionBackend::selectedVersionChanged,
            this, &ShadowBackend::selectedVersionChanged);
    // 切换版本后 kicker 要跟着换
    connect(m_version, &VersionBackend::selectedVersionChanged,
            this, &ShadowBackend::lastPlayedChanged);
    // 上次游玩记录：启动时读一次 dataDir/last-played.json
    {
        QFile f(m_app->dataDir() + QStringLiteral("/last-played.json"));
        if (f.open(QIODevice::ReadOnly)) {
            const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
            for (auto it = obj.begin(); it != obj.end(); ++it)
                m_lastPlayed.insert(it.key(), qint64(it.value().toDouble()));
        }
    }
    connect(m_version, &VersionBackend::selectedVersionChanged, this, [this]() {
        QString vid = m_version->selectedVersion();
        // Persist last selected version (saved on exit, restored on next launch)
        m_settings->setLastSelectedVersion(vid);
        if (vid.isEmpty()) {
            m_currentVersionSummary.clear();
            emit currentVersionSummaryChanged();
            return;
        }

        // 异步计算：游戏目录/版本目录/assets 全量递归遍历在 worker 线程，
        // 避免模组上百后「选择版本」卡死 UI（选中即回显，大小稍后刷新）
        const QString gameDir = getVersionGameDir(vid);
        const QString versionDir = m_app->gameDir() + QStringLiteral("/versions/") + vid;
        const QString assetsPath = m_app->gameDir() + QStringLiteral("/assets/objects");
        QtConcurrent::run([this, vid, gameDir, versionDir, assetsPath]() {
            qint64 totalSize = 0;

            // Count game directory (worlds, mods, saves, screenshots, etc.)
            if (QDir(gameDir).exists()) {
                QDirIterator it(gameDir, QDir::Files, QDirIterator::Subdirectories);
                while (it.hasNext()) { it.next(); totalSize += it.fileInfo().size(); }
            }
            // Add version files (jar, json, libraries) — but NOT game/ subdir (already counted)
            if (QDir(versionDir).exists()) {
                QDirIterator it(versionDir, QDir::Files, QDirIterator::Subdirectories);
                while (it.hasNext()) {
                    QString fp = it.next();
                    // Skip game/ subdirectory for isolated versions (already counted via gameDir)
                    if (fp.contains(QStringLiteral("/game/")) || fp.contains(QStringLiteral("\\game\\")))
                        continue;
                    totalSize += it.fileInfo().size();
                }
            }
            // Count shared assets (objects/) for a realistic total
            if (QDir(assetsPath).exists()) {
                QDirIterator ait(assetsPath, QDir::Files, QDirIterator::Subdirectories);
                while (ait.hasNext()) { ait.next(); totalSize += ait.fileInfo().size(); }
            }

            QVariantMap summary;
            if (totalSize < 1024 * 1024)
                summary[QStringLiteral("sizeDisplay")] = QString::number(totalSize / 1024.0, 'f', 1) + QStringLiteral(" KB");
            else if (totalSize < 1024LL * 1024 * 1024)
                summary[QStringLiteral("sizeDisplay")] = QString::number(totalSize / (1024.0 * 1024), 'f', 1) + QStringLiteral(" MB");
            else
                summary[QStringLiteral("sizeDisplay")] = QString::number(totalSize / (1024.0 * 1024 * 1024), 'f', 2) + QStringLiteral(" GB");

            summary[QStringLiteral("modCount")] = 0;
            QMetaObject::invokeMethod(this, [this, vid, summary]() {
                // 防过期：选择已切换则丢弃旧结果
                if (m_version->selectedVersion() != vid) return;
                m_currentVersionSummary = summary;
                emit currentVersionSummaryChanged();
            }, Qt::QueuedConnection);
        });
    });
    connect(m_version, &VersionBackend::installStateChanged,
            this, &ShadowBackend::installStateChanged);
        // installPhaseChanged signal with different signature:
    // VersionBackend emits installPhaseChanged(const QString&), ShadowBackend emits installPhaseChanged()
    connect(m_version, &VersionBackend::installPhaseChanged,
            this, [this](const QString&) {
                emit installPhaseChanged();
                emit verifyRunningChanged();
            });
    connect(m_version, &VersionBackend::repairRunningChanged,
            this, &ShadowBackend::repairRunningChanged);
    connect(m_version, &VersionBackend::installFinished,
            this, &ShadowBackend::installFinished);
    connect(m_version, &VersionBackend::installComplete,
            this, &ShadowBackend::installComplete);
    connect(m_version, &VersionBackend::logMessage,
            this, &ShadowBackend::logMessage);
    connect(m_version, &VersionBackend::toastMessage,
            this, &ShadowBackend::toastMessage);
    // ── 2026-08-15：加载器安装期间自动下载的便携 Java → 刷新 Java 列表（不弹 toast）──
    // findAllJava 含 java_cache 扫描；scanJavaInstallations 只 emit logMessage/javaScanFinished，
    // 用户可见的"正在扫描 Java 环境"toast 由 SettingsJavaPage 自行弹出，此处静默刷新。
    connect(m_version, &VersionBackend::javaAutoInstalled,
            this, [this](int) {
                m_settings->scanJavaInstallations();
                m_java->scanSystemJavas();
                qCInfo(logJava) << QStringLiteral("[Java安装] 加载器自动下载的 Java 已就绪，已触发 Java 列表刷新");
            });
    // ── 2026-08-15：MC/加载器安装取消 → QML toast（此前 cancelNotification
    //    发射后无人转发，取消毫无用户反馈）──
    connect(m_version, &VersionBackend::cancelNotification,
            this, &ShadowBackend::cancelNotification);
    connect(m_version, &VersionBackend::verifyStarted,
            this, &ShadowBackend::verifyStarted);
    connect(m_version, &VersionBackend::verifyProgress,
            this, [this](int checked, int total) {
                emit verifyProgress(checked, total);
                emit verifyCheckedChanged();
                emit verifyTotalChanged();
            });
    connect(m_version, &VersionBackend::verifyFinished,
            this, [this](bool allPassed) {
        setVerifyResult(allPassed ? tr("所有文件校验通过") : tr("存在损坏/缺失文件，请修复后重试"), allPassed);
        emit verifyFinished(allPassed);
    });
                connect(m_version, &VersionBackend::verifyFailedFiles,
            this, [this](const QStringList& failedFiles) {
                // Generate error report
                if (!failedFiles.isEmpty()) {
                    // 2026-11-25 审计：这里原本用 ShadowBackend::m_gameDir，而该成员全类没有赋值点，
                    // 于是路径变成相对路径 "/verify_reports"，被解析到当前工作盘根（实测 D:\verify_reports）。
                    // 改用真正生效的游戏目录。
                    QDir reportsDir(m_app->gameDir() + QStringLiteral("/verify_reports"));
                    if (!reportsDir.exists()) reportsDir.mkpath(QStringLiteral("."));
                    QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
                    m_verifyReportPath = reportsDir.filePath(
                        QStringLiteral("verify_failed_%1.txt").arg(timestamp));
                    QFile report(m_verifyReportPath);
                    if (report.open(QIODevice::WriteOnly | QIODevice::Text)) {
                        QTextStream out(&report);
                        out << tr("Shadow Launcher — 版本完整性校验报告\n");
                        out << QStringLiteral("======================================\n");
                        out << tr("时间: ") << QDateTime::currentDateTime().toString(Qt::ISODate) << QStringLiteral("\n");
                        // 2026-11-25 审计：报表头原本取"当前选中版本"，与本次被校验的版本无关（用户可在列表里
                        // 随手点别的版本，报告就会张冠李戴）。改为取校验/修复入口写入的目标 id。
                        out << tr("版本: ") << m_version->verifyTargetId() << QStringLiteral("\n");
                        out << tr("异常文件数: ") << failedFiles.size() << QStringLiteral("\n");
                        out << QStringLiteral("--------------------------------------\n");
                        for (int i = 0; i < failedFiles.size(); ++i) {
                            out << (i + 1) << QStringLiteral(". ") << failedFiles[i] << QStringLiteral("\n");
                        }
                        out << QStringLiteral("--------------------------------------\n");
                        out << tr("请使用「一键修复」重新下载损坏/缺失的文件。\n");
                    }
                } else {
                    m_verifyReportPath.clear();
                }
                emit verifyFailedFiles(failedFiles);
            });
    connect(m_version, &VersionBackend::downloadQueueChanged,
            this, &ShadowBackend::downloadQueueChanged);
    connect(m_version, &VersionBackend::downloadQueueFull,
            this, &ShadowBackend::downloadQueueFull);

    // ── Signal forwarding: LaunchBackend → ShadowBackend ──
    connect(m_launch, &LaunchBackend::launchProgressChanged,
            this, &ShadowBackend::launchProgressChanged);
    connect(m_launch, &LaunchBackend::launchStateChanged,
            this, &ShadowBackend::launchStateChanged);
    connect(m_launch, &LaunchBackend::minecraftStarted,
            this, &ShadowBackend::minecraftStarted);
    // 游戏进程真的起来了才算"玩过"（检查失败/取消都不写）
    connect(m_launch, &LaunchBackend::minecraftStarted,
            this, [this]() { recordLastPlayed(selectedVersion()); });
    connect(m_launch, &LaunchBackend::minecraftStopped,
            this, &ShadowBackend::minecraftStopped);
    connect(m_launch, &LaunchBackend::crashDetected,
            this, [this](const QVariantMap& report) {
                m_lastCrash = report;
                m_crashAnalyzing = false;
                emit crashReportChanged();
                emit crashAnalyzingChanged();
                emit crashDetected(report);
            });
    connect(m_launch, &LaunchBackend::crashAnalysisStarted,
            this, [this]() {
                // 异步分析要读几 MB 日志：失败面板先显示"正在分析日志"，
                // 否则用户只看到"启动失败"却没有任何原因，会以为卡住。
                m_crashAnalyzing = true;
                emit crashAnalyzingChanged();
                emit crashAnalysisStarted();
            });
    connect(m_launch, &LaunchBackend::crashAnalysisReady,
            this, [this](const QVariantMap& report) {
                m_lastCrash = report;
                m_crashAnalyzing = false;
                emit crashReportChanged();
                emit crashAnalyzingChanged();
                emit crashAnalysisReady(report);
            });
    connect(m_launch, &LaunchBackend::launchRepairsChanged,
            this, &ShadowBackend::launchRepairsChanged);
    connect(m_launch, &LaunchBackend::isRunningChanged,
            this, &ShadowBackend::isRunningChanged);
    connect(m_launch, &LaunchBackend::runningCountChanged,
            this, &ShadowBackend::runningCountChanged);
    connect(m_launch, &LaunchBackend::logMessage,
            this, &ShadowBackend::logMessage);
    connect(m_launch, &LaunchBackend::launchCheckProgress,
            this, &ShadowBackend::launchCheckProgress);
    connect(m_launch, &LaunchBackend::launchCheckFailed,
            this, &ShadowBackend::launchCheckFailed);
    connect(m_launch, &LaunchBackend::launchCheckMissingFiles,
            this, &ShadowBackend::launchCheckMissingFiles);
    connect(m_launch, &LaunchBackend::launchCheckWarning,
            this, &ShadowBackend::launchCheckWarning);

    // ── Load persisted login mode ──
    {
        QSettings s(QCoreApplication::organizationName(),
                    QCoreApplication::applicationName());
        // 这两项是旧 UI「三选一登录」的残留持久化，只在下面「没有当前账号」时当兜底用；
        // 真正的权威是 accounts.json 的 current（见下方恢复逻辑）。
        m_lastLoginMode = s.value(QStringLiteral("account/lastLoginMode"), 1).toInt();
        QString lastUser = s.value(QStringLiteral("account/lastUsername")).toString();
        // Auto-restore login on startup.
        //
        // 权威是 accounts.json 的 current —— 它记录用户最后一次真正选中的账号。
        // 旧实现只看 QSettings 的 lastLoginMode：用户把当前账号切到正版后重启，
        // 这里仍按"上次是离线"把离线账号登回来，而 offlineLogin() 内部的
        // upsertAccount(makeCurrent=true) 会把 current 覆盖成离线那条 ——
        // 于是"我选了另一个角色，重启又回到新加的那个"（owner 实测，日志实锤）。
        QTimer::singleShot(100, this, [this, lastUser]() {
            const int cur = m_account ? m_account->currentAccount() : -1;
            const QVariantMap curAcc = (m_account && cur >= 0) ? m_account->accountAt(cur) : QVariantMap();
            if (!curAcc.isEmpty()) {
                const int curMode = curAcc.value(QStringLiteral("mode")).toInt();
                const QString curName = curAcc.value(QStringLiteral("name")).toString();
                // 登录方式必须跟着当前账号走：以前只在 switchAccount/removeAccount 同步，
                // 重启后 m_lastLoginMode 还是 QSettings 里的旧值（外置账号会走进正版分支，
                // 用户名取到空 → 启动前检查直接报「登录状态」不通过）。
                setLastLoginMode(curMode);
                if (curMode == 1) {
                    qCInfo(logApp) << QStringLiteral("[启动] 恢复离线登录(当前账号): ") << curName;
                    m_account->offlineLogin(curName);
                } else {
                    // 正版/外置：会话已由 loadMicrosoftSession() / YggdrasilBackend::loadSession() 恢复，
                    // 这里绝不能再用离线登录覆盖 current。
                    qCInfo(logApp) << QStringLiteral("[启动] 当前账号非离线，跳过离线恢复: ")
                                   << curName << QStringLiteral(" mode=") << curMode;
                }
                return;
            }
            // 兜底：没有当前账号（首启/数据缺失）才回退到 QSettings。
            if (m_lastLoginMode == 1 && !lastUser.isEmpty()) {
                qCInfo(logApp) << QStringLiteral("[启动] 恢复离线登录(兜底): ") << lastUser;
                m_account->offlineLogin(lastUser);
            }
        });

        // 通知 QML 恢复登录模式（包括外置登录）
        QTimer::singleShot(200, this, [this]() {
            emit loginModeChanged();
        });
    }

    // ── Signal forwarding: ResourceBackend → ShadowBackend ──
    connect(m_resource, &ResourceBackend::downloadStateChanged,
            this, [this]() {
                bool downloading = m_resource->isDownloading();
                if (!downloading) {
                    m_resourceDlProgress = 0;
                    m_resourceDlTotal = 0;
                    m_resourceDlSpeed = 0;
                    m_resourceDlFile.clear();
                    emit resourceDownloadProgress(0, 0, QString());
                    if (m_version) m_version->removeResourceCard(QStringLiteral("resource"));
                } else {
                    m_resourceDlProgress = 0;
                    m_resourceDlTotal = 0;
                    m_resourceDlFile.clear();
                    if (m_version) m_version->addResourceCard(QStringLiteral("resource"), tr("资源包下载"));
                }
                qCInfo(logLaunch) << QStringLiteral("[资源包下载] 状态变更 下载中=%1").arg(m_resource->isDownloading());
                emit resourceDownloadStateChanged();
            });
    connect(m_resource, &ResourceBackend::downloadProgressChanged,
            this, [this](int completed, int total, const QString& fileName) {
                m_resourceDlProgress = completed;
                m_resourceDlTotal = total;
                m_resourceDlSpeed = m_resource->dlSpeed();
                m_resourceDlFile = fileName;
                qCInfo(logLaunch) << QStringLiteral("[资源包下载] 进度 %1/%2 %3").arg(completed).arg(total).arg(fileName);
                emit resourceDownloadProgress(completed, total, fileName);
                if (m_version && total > 0) {
                    m_version->updateResourceCard(QStringLiteral("resource"),
                        (qreal)completed / total, fileName);
                }
            });
    connect(m_resource, &ResourceBackend::downloadFinished,
            this, [this](const QString&, bool success, const QString&) {
                qCInfo(logLaunch) << QStringLiteral("[资源包下载] 下载完成 成功=%1").arg(success);
                emit resourceDownloadDone(success);
                if (m_version) {
                    if (success) m_version->completeResourceCard(QStringLiteral("resource"));
                    else m_version->failResourceCard(QStringLiteral("resource"), tr("资源包下载失败"));
                }
            });
    connect(m_resource, &ResourceBackend::searchResultsReady,
            this, &ShadowBackend::searchResultsReady);
    connect(m_resource, &ResourceBackend::modSearchResultsReady,
            this, &ShadowBackend::modSearchResultsReady);
    connect(m_resource, &ResourceBackend::shaderSearchResultsReady,
            this, &ShadowBackend::shaderSearchResultsReady);
    connect(m_resource, &ResourceBackend::resourcepackSearchCompleted,
            this, [this](const QVariantList& results, int totalHits) {
                qDebug().noquote() << "[BACKEND] RP searchCompleted SIGNAL emitted, hits=" << results.size() << "total=" << totalHits;
                emit resourcepackSearchCompleted(results, totalHits);
            });
    connect(m_resource, &ResourceBackend::resourcepackSearchFailed,
            this, &ShadowBackend::resourcepackSearchFailed);
    connect(m_resource, &ResourceBackend::resourceSearchFailed,
            this, &ShadowBackend::resourceSearchFailed);
    connect(m_resource, &ResourceBackend::resourcepackDownloadFinished,
            this, &ShadowBackend::resourcepackDownloadFinished);
    connect(m_resource, &ResourceBackend::resourcepackVersionsLoaded,
            this, &ShadowBackend::resourcepackVersionsLoaded);
    connect(m_resource, &ResourceBackend::resourcepackVersionsPartial,
            this, &ShadowBackend::resourcepackVersionsPartial);
    connect(m_resource, &ResourceBackend::resourcepackVersionsProgress,
            this, &ShadowBackend::resourcepackVersionsProgress);
    connect(m_resource, &ResourceBackend::modVersionsLoaded,
            this, &ShadowBackend::modVersionsLoaded);
    connect(m_resource, &ResourceBackend::modVersionsPartial,
            this, &ShadowBackend::modVersionsPartial);
    connect(m_resource, &ResourceBackend::modVersionsProgress,
            this, &ShadowBackend::modVersionsProgress);
    connect(m_resource, &ResourceBackend::shaderVersionsLoaded,
            this, &ShadowBackend::shaderVersionsLoaded);
    connect(m_resource, &ResourceBackend::shaderVersionsPartial,
            this, &ShadowBackend::shaderVersionsPartial);
    connect(m_resource, &ResourceBackend::shaderVersionsProgress,
            this, &ShadowBackend::shaderVersionsProgress);
    connect(m_resource, &ResourceBackend::logMessage,
            this, &ShadowBackend::logMessage);

    // ── Mod file download forwarding ──
    connect(m_resource, &ResourceBackend::modFileDownloadStarted,
            this, [this](int dlId, const QString& fileName, qint64 fileSize, const QString& displayName) {
                Q_UNUSED(fileSize);
                QString cardId = QStringLiteral("mod:%1").arg(dlId);
                m_modDownloadCards.insert(dlId, cardId);
                if (m_version) m_version->addResourceCard(cardId, displayName.isEmpty() ? fileName : displayName);
            });
    connect(m_resource, &ResourceBackend::modFileDownloadProgress,
            this, [this](int dlId, qint64 received, qint64 total, qint64 speed) {
                if (m_modDownloadCards.contains(dlId) && m_version && total > 0) {
                    m_version->updateResourceCard(m_modDownloadCards[dlId],
                        (qreal)received / total, QString(), speed);
                }
            });
    connect(m_resource, &ResourceBackend::modFileDownloadFinished,
            this, [this](int dlId, bool success, const QString& filePath, const QString& displayName) {
                if (m_modDownloadCards.contains(dlId)) {
                    const QString cardId = m_modDownloadCards[dlId];
                    if (m_version) {
                        if (success) {
                            // 下载完成：卡片定格绿色完成态（不立即移除，QML 端保留展示）
                            m_version->completeResourceCard(cardId);
                        } else {
                            // 下载器回调 ok=false（如 SHA1 校验失败分支已走 Failed 信号，此处兜底）
                            m_version->failResourceCard(cardId, tr("下载失败"));
                        }
                    }
                    m_modDownloadCards.remove(dlId);
                }
                // ── 整合包下载完成 → 自动转入导入流程（用户输入版本名注册）──
                if (m_packDownloads.contains(dlId)) {
                    const PackDownloadInfo info = m_packDownloads.take(dlId);
                    m_packDownloading = false;   // 下载阶段结束（无论成败）
                    if (success && m_modpackImporter) {
                        auto* importer = qobject_cast<ModpackImporter*>(m_modpackImporter);
                        qCInfo(logApp) << QStringLiteral("[整合包] 下载完成，自动导入: %1 版本名=%2")
                            .arg(info.zipPath, info.versionName);
                        if (importer) {
                            // 图标随 startImport 传入（任务侧重置/落盘），不再走 setPackIcon 前置设置
                            importer->startImport(info.zipPath, info.versionName, false, info.iconUrl);
                        }
                    } else if (!success) {
                        qCInfo(logApp) << QStringLiteral("[整合包] 下载失败，不导入: %1").arg(info.zipPath);
                    }
                }
                // 透传信号给 QML（成功 Toast / 详情页错误弹窗）
                emit modFileDownloadFinished(dlId, success, filePath, displayName);
            });
    connect(m_resource, &ResourceBackend::modFileDownloadFailed,
            this, [this](int dlId, const QString& errorDetail, const QString& displayName) {
                if (m_modDownloadCards.contains(dlId)) {
                    const QString cardId = m_modDownloadCards[dlId];
                    if (m_version) m_version->failResourceCard(cardId, errorDetail);
                    m_modDownloadCards.remove(dlId);
                }
                // 整合包下载失败：移除待导入记录（不进入导入流程）
                if (m_packDownloads.contains(dlId)) {
                    m_packDownloads.remove(dlId);
                    m_packDownloading = false;
                    qCInfo(logApp) << QStringLiteral("[整合包] 下载失败，取消自动导入 dlId=%1").arg(dlId);
                }
                // 透传信号给 QML（失败 Toast / 详情页错误弹窗）
                emit modFileDownloadFailed(dlId, errorDetail, displayName);
            });
    // ── 2026-08-15：用户主动取消文件下载 ──
    // 卡片标记"已取消"（红色失败态，X 变 dismiss），并转发信号 → QML
    // 弹"xxx 取消成功" toast。此前取消后驿道回调静默 erase，卡片永久卡
    // 在下载中状态且无任何反馈。
    connect(m_resource, &ResourceBackend::modFileDownloadCancelled,
            this, [this](int dlId, const QString& displayName) {
                if (m_modDownloadCards.contains(dlId)) {
                    const QString cardId = m_modDownloadCards[dlId];
                    if (m_version) m_version->failResourceCard(cardId, tr("已取消"));
                    m_modDownloadCards.remove(dlId);
                }
                emit modFileDownloadCancelled(dlId, displayName);
            });
    // ── 2026-08-15：版本级前置依赖（悬停 tooltip）转发 ──
    connect(m_resource, &ResourceBackend::versionDependenciesResolved,
            this, &ShadowBackend::versionDependenciesResolved);
    connect(m_resource, &ResourceBackend::versionFileResolved,
            this, &ShadowBackend::versionFileResolved);
    // 整合包搜索完成透传（QML 回填列表）
    connect(m_resource, &ResourceBackend::modpackSearchResultsReady,
            this, &ShadowBackend::modpackSearchResultsReady);
    // 数据包搜索完成透传（QML 回填列表）
    connect(m_resource, &ResourceBackend::datapackSearchResultsReady,
            this, &ShadowBackend::datapackSearchResultsReady);
    // CF 前置依赖解析结果透传（QML 回填依赖卡片）
    connect(m_resource, &ResourceBackend::cfDependenciesResolved,
            this, &ShadowBackend::cfDependenciesResolved);

    // ── Signal forwarding: AppBackend → ShadowBackend ──
    connect(m_app, &AppBackend::gameDirChanged,
            this, &ShadowBackend::gameDirChanged);
    connect(m_app, &AppBackend::themeChanged,
            this, &ShadowBackend::themeChanged);
    connect(m_app, &AppBackend::logMessage,
            this, &ShadowBackend::logMessage);

    // ── Update manager ──
    m_updateManager = new UpdateManager(this);
    // ── 2026-08-15：更新服务器迁移（secrets 注入）──
    // secrets_local.h 定义 SHADOW_UPDATE_API_URL（自建服务器 latest.json）时优先；
    // 为空则回退 Gitee API（setRepo）。
    const QString customUpdateApi = QStringLiteral(SHADOW_UPDATE_API_URL).trimmed();
    if (!customUpdateApi.isEmpty()) {
        m_updateManager->setUpdateApiUrl(customUpdateApi);
    } else {
        m_updateManager->setRepo(QStringLiteral(SHADOW_GITEE_OWNER), QStringLiteral(SHADOW_GITEE_REPO));
    }
    m_updateManager->setCurrentVersion(appVersion());
    m_updateManager->setQtVersion(QStringLiteral(SHADOW_QT_VERSION));
    m_updateManager->setResourceEpoch(SHADOW_RESOURCE_EPOCH);
    connect(m_updateManager, &UpdateManager::stateChanged,
            this, &ShadowBackend::updateStateChanged);
    connect(m_updateManager, &UpdateManager::stateChanged,
            this, &ShadowBackend::updateCheckingChanged);
    connect(m_updateManager, &UpdateManager::toastMessage,
            this, &ShadowBackend::toastMessage);
    connect(m_updateManager, &UpdateManager::downloadProgress,
            this, [this](qint64 r, qint64 t) { emit updateDownloadProgress(r, t); });
    // ── 2026-08-15：下载完成 → QML 常驻 toast 引导用户立即重启安装 ──
    connect(m_updateManager, &UpdateManager::updateAvailableForInstall,
            this, &ShadowBackend::updateReadyForRestart);
    // Resume paused download from previous session
    m_updateManager->resumePausedDownload();
    // Check for post-update changelog (delay for QML init)
    QTimer::singleShot(500, this, [this] { checkChangelog(); });
    // Load persisted Java runtime settings (restored from previous session)
    loadJavaRuntimeSettings();
    // Auto-check on startup (silent)
    QTimer::singleShot(0, m_updateManager, &UpdateManager::checkSilent);
    bp("UpdateManager");

    bp("Constructor done");

    // ── Clean up orphaned temp dirs from previous (crashed) sessions ──
    qCInfo(logApp) << QStringLiteral("[追踪] 检查残留临时目录...");
    TempTracker::cleanupOrphans();

    // Sync m_currentLang from saved settings (prevents switchLanguage early-return bug)
    const QStringList codes = { QStringLiteral("zh_CN"), QStringLiteral("zh_HK"), QStringLiteral("zh_TW"), QStringLiteral("en") };
    int savedIdx = m_settings->languageIndex();
    if (savedIdx >= 0 && savedIdx < codes.size()) {
        m_currentLang = codes[savedIdx];
    }
    // Ensure language.txt is initialized (used by QML to recover ComboBox state)
    writeLanguageFile(savedIdx);
}

// ============================================================
// Account property getters
// ============================================================

QString ShadowBackend::username() const {
    return m_account->username();
}

QString ShadowBackend::offlineUsername() const {
    return m_account->offlineUsername();
}

bool ShadowBackend::isOnline() const {
    return m_account->isOnline();
}

bool ShadowBackend::accountOnline() const
{
    if (!m_account) return false;
    // 必须按「当前账号类型」判断，不能把三种身份混在一起：
    // 离线账号没有服务器会话，但 YggdrasilBackend 里可能还留着上一个外置会话，
    // 那种情况下单纯 isOnline || ygg.loggedIn 会把离线账号显示成在线（绿点）。
    switch (m_account->currentAccountMode()) {
    case 0: return m_account->isOnline();                    // 正版：微软会话有效
    case 2: {                                                // 外置：皮肤站会话有效
        auto *ygg = static_cast<YggdrasilBackend *>(m_yggdrasil);
        return ygg && ygg->loggedIn();
    }
    default: return false;                                   // 离线：永远不算在线
    }
}

QString ShadowBackend::currentAccountAvatar() const
{
    if (!m_account) return QString();
    const QString p = m_account->currentAccountAvatarFile();
    if (p.isEmpty()) return QString();
    // QML 的 Image 要 URL：和 accounts() 一样加 file:///，否则 source 非空却加载失败
    // → 既不出图也不出字母（影看到的空白胶囊）。
    return QUrl::fromLocalFile(p).toString();
}

// ── 统一身份视图 ──────────────────────────────────────────────
// 真源：accounts.json 的 current（currentAccountMode）+ 该类型的会话。
// 所有「当前账号是谁」的问题都从这里回答，别再各页面自己拼。

int ShadowBackend::activeAccountMode() const
{
    if (!m_account) return -1;
    const int mode = m_account->currentAccountMode();
    return mode >= 0 ? mode : m_lastLoginMode;
}

QString ShadowBackend::activeAccountName() const
{
    if (!m_account) return QString();
    switch (activeAccountMode()) {
    case 0: return m_account->username();
    case 2: {
        auto *ygg = static_cast<YggdrasilBackend *>(m_yggdrasil);
        if (ygg && !ygg->username().isEmpty()) return ygg->username();
        break;
    }
    case 1: return m_account->offlineUsername();
    default: break;
    }
    // 会话还没恢复好：回落到账号条目里的名字（至少名字是对的）
    const int cur = m_account->currentAccount();
    const QVariantMap acc = cur >= 0 ? m_account->accountAt(cur) : QVariantMap();
    return acc.value(QStringLiteral("name")).toString();
}

QString ShadowBackend::activeAccountUuid() const
{
    if (!m_account) return QString();
    switch (activeAccountMode()) {
    case 0: return m_account->accountUuid();
    case 2: {
        auto *ygg = static_cast<YggdrasilBackend *>(m_yggdrasil);
        if (ygg && !ygg->uuid().isEmpty()) return ygg->uuid();
        break;
    }
    case 1: return m_account->offlineUuid();
    default: break;
    }
    const int cur = m_account->currentAccount();
    const QVariantMap acc = cur >= 0 ? m_account->accountAt(cur) : QVariantMap();
    return acc.value(QStringLiteral("uuid")).toString();
}

bool ShadowBackend::activeAccountOnline() const
{
    return accountOnline();   // 同一套按类型分派的判据
}

QString ShadowBackend::activeAccountAvatar() const
{
    if (!m_account) return QString();
    switch (activeAccountMode()) {
    case 0: {
        const QString p = m_account->skinPath();
        return p.isEmpty() ? currentAccountAvatar() : p;
    }
    default:
        // 外置/离线没有实时 skinPath：用账号自己的头像快照
        return currentAccountAvatar();
    }
}

QString ShadowBackend::activeAccountSkin() const
{
    if (!m_account) return QString();
    // 只有正版有原始皮肤纹理（自己裁脸用）；外置/离线给空，走头像图
    return activeAccountMode() == 0 ? m_account->skinTexturePath() : QString();
}

bool ShadowBackend::microsoftLoginBusy() const {
    return m_account ? m_account->isMicrosoftLoginBusy() : false;
}

QString ShadowBackend::msStatus() const {
    return m_account ? m_account->msStatus() : QString();
}

QString ShadowBackend::accountUuid() const {
    return m_account->accountUuid();
}

QString ShadowBackend::offlineUuid() const {
    return m_account->offlineUuid();
}

QString ShadowBackend::skinPath() const {
    return m_account->skinPath();
}

QString ShadowBackend::skinTexturePath() const {
    return m_account ? m_account->skinTexturePath() : QString();
}

QString ShadowBackend::offlineSkinPath() const {
    return m_account->offlineSkinPath();
}

QStringList ShadowBackend::offlineUsernames() const {
    return m_account->offlineUsernames();
}

// ============================================================
// Settings property getters
// ============================================================

QString ShadowBackend::javaPath() const {
    return m_settings->javaPath();
}

QString ShadowBackend::javaVersion() const {
    return m_settings->javaVersion();
}

int ShadowBackend::javaMajor() const {
    return m_settings->javaMajor();
}

bool ShadowBackend::javaInstalled() const {
    return m_settings->isJavaReady();
}

int ShadowBackend::minMemoryMb() const {
    return m_settings->minMemoryMB();
}

int ShadowBackend::maxMemoryMb() const {
    return m_settings->maxMemoryMB();
}

// ── 2026-11-14：按**该版本的模组数**算建议内存──
// 原来 QML 只有全局 getMemoryStatus().recommended（看总内存），
// 版本设置页把它当成该版本的建议值显示 —— 一个 425 模组的整合包
// 和一个空实例显示同一个建议值，用户根本无从判断该给多少。
int ShadowBackend::recommendMemoryForVersion(const QString& versionId)
{
    if (!m_launch) return 2048;
    return m_launch->getAutoMemoryForVersion(versionId);
}


bool ShadowBackend::isolationEnabled() const {
    // 外部 .minecraft 目录：报告实际解析形态（版本隔离→true，共享/混合→false）
    if (m_mcFolder && m_mcFolder->isForeignActive())
        return m_mcFolder->effectiveIsolation();
    return m_isolationEnabled;
}

int ShadowBackend::fileDownloadSource() const { return m_settings->fileDownloadSource(); }
void ShadowBackend::setFileDownloadSource(int v) { m_settings->setFileDownloadSource(v); emit downloadSettingsChanged(); }
int ShadowBackend::listDownloadSource() const { return m_settings->listDownloadSource(); }
void ShadowBackend::setListDownloadSource(int v) { m_settings->setListDownloadSource(v); emit downloadSettingsChanged(); }
int ShadowBackend::maxDownloadThreads() const { return m_settings->maxDownloadThreads(); }
void ShadowBackend::setMaxDownloadThreads(int v) { m_settings->setMaxDownloadThreads(v); emit downloadSettingsChanged(); }
double ShadowBackend::downloadSpeedLimitMB() const { return m_settings->downloadSpeedLimitMB(); }
void ShadowBackend::setDownloadSpeedLimitMB(double v) { m_settings->setDownloadSpeedLimitMB(v); emit downloadSettingsChanged(); }

bool ShadowBackend::embeddedLoginEnabled() const {
    return m_settings->embeddedLoginEnabled();
}

void ShadowBackend::beginWindowMove()
{
    // 主窗口是唯一的 Qt::Window（任务小窗口是 Qt::Tool，弹窗是 Qt::Popup），
    // 用它而不是"第一个可见窗口"，避免拖到别的窗口上去。
    //
    // 为什么不用 QWindow::startSystemMove()：它走 WM_SYSCOMMAND(SC_MOVE)，由 Windows
    // 接管拖动。在部分机器上（实测本机）只会画一条传统拖影白框，窗口不实时跟随，
    // 手感很差。所以改成自己拖：按下时记住「光标全局坐标 - 窗口位置」的偏移，
    // 之后每次鼠标移动就用 setPosition(光标 - 偏移)。全局坐标不随窗口移动而变化，
    // 高 DPI 下也不会累积漂移。
    QWindow* target = nullptr;
    const auto windows = QGuiApplication::topLevelWindows();
    for (QWindow* w : windows) {
        if (!w || !w->isVisible()) continue;
        if (w->type() != Qt::Window) continue;
        target = w;
        break;
    }
    if (!target) return;
    m_dragWin = target;
    m_dragOffset = QCursor::pos() - target->position();
    m_dragging = true;
    qApp->installEventFilter(this);
}

bool ShadowBackend::eventFilter(QObject* obj, QEvent* ev)
{
    if (!m_dragging) return QObject::eventFilter(obj, ev);
    switch (ev->type()) {
    case QEvent::MouseMove:
        if (m_dragWin) m_dragWin->setPosition(QCursor::pos() - m_dragOffset);
        break;
    case QEvent::MouseButtonRelease:
        m_dragging = false;
        m_dragWin = nullptr;
        qApp->removeEventFilter(this);
        break;
    default:
        break;
    }
    // 不吞事件：拖动期间其它控件照常收事件（按下才开始的拖，正常也不该有别的交互）
    return QObject::eventFilter(obj, ev);
}

void ShadowBackend::setEmbeddedLoginEnabled(bool v) {
    m_settings->setEmbeddedLoginEnabled(v);
}

// ── 2026-08-15：实验性 tooltip 开关 ──


// ── Custom background ──
// 图库模型（2026-11-13 重做）：每张图各自保存 path + zoom/crop，切换只改 active。
// 所以这里**不再有「清空即删图」**的语义 —— 以前 setCustomBgPath("") 会顺手删缓存副本，
// 那正是「切回默认后自定义图就丢了」的元凶之一。
QString ShadowBackend::customBgPath() const { return m_settings->activeBgPath(); }
void ShadowBackend::setCustomBgPath(const QString& path) {
    // 空值 = 什么都不做（「恢复默认」走 restoreDefaultBg，只是切 active，不删任何图）
    if (path.isEmpty()) return;
    m_settings->importBgFile(path);
}

QString ShadowBackend::customBgUrl() const {
    // 当前使用的那张图的显示 URL：内置 → qrc，导入 → file:///
    return m_settings->activeBgSource();
}

qreal ShadowBackend::cropX() const { return m_settings->cropX(); }
void ShadowBackend::setCropX(qreal v) { m_settings->setCropX(v); }
qreal ShadowBackend::cropY() const { return m_settings->cropY(); }
void ShadowBackend::setCropY(qreal v) { m_settings->setCropY(v); }
void ShadowBackend::updateCrop(qreal x, qreal y) {
    m_settings->setCropX(x);
    m_settings->setCropY(y);
}

qreal ShadowBackend::bgZoom() const { return m_settings->bgZoom(); }
void ShadowBackend::setBgZoom(qreal v) { m_settings->setBgZoom(v); }
QVariantList ShadowBackend::bgPresets() const { return m_settings->bgPresets(); }
void ShadowBackend::applyBgPreset(const QString& presetId) { m_settings->applyBgPreset(presetId); }
void ShadowBackend::removeBgImage(const QString& presetId) { m_settings->removeBgImage(presetId); }
bool ShadowBackend::chooseBgImage() {
    // 复用既有 pickBackgroundImage（会复制到 dataDir/custom_bg 防止原图被移走）
    return !pickBackgroundImage().isEmpty();
}
void ShadowBackend::restoreDefaultBg() { m_settings->restoreDefaultBg(); }
void ShadowBackend::resetBgView() { m_settings->resetBgView(); }
QString ShadowBackend::colorScheme() const { return m_settings->colorScheme(); }
void ShadowBackend::setColorScheme(const QString& scheme) { m_settings->setColorScheme(scheme); }

QString ShadowBackend::pickBackgroundImage() {
    // 支持动图：gif 走 QML 的 AnimatedImage（Qt 自带 qgif 插件，无需额外依赖）。
    const QString path = QFileDialog::getOpenFileName(nullptr,
        QString::fromUtf8("选择背景图片或动图"), QString(),
        QString::fromUtf8("图片与动图 (*.png *.jpg *.jpeg *.bmp *.webp *.gif);;所有文件 (*)"));
    if (path.isEmpty()) return QString();

    // 上限 64 MB：动图会被整份读进内存逐帧解码，几百 MB 的 GIF 等于让启动器卡死。
    const qint64 kBgMaxBytes = 64LL * 1024 * 1024;
    if (QFileInfo(path).size() > kBgMaxBytes) {
        qCWarning(logUI) << QStringLiteral("[外观] 背景文件过大（>%1 MB），已拒绝: %2")
                             .arg(kBgMaxBytes / (1024 * 1024)).arg(path);
        return QString();
    }

    // 复制与登记都交给图库（按内容 sha1 去重，同一张图重复选不会占两份），
    // 这里**不再清空目录** —— 旧实现每换一次图就把之前所有图删掉，是丢图的主因。
    const QString id = m_settings->importBgFile(path);
    if (id.isEmpty()) return QString();
    return m_settings->activeBgPath();
}

QVariantList ShadowBackend::availableJavaList() const {
    return m_settings->availableJavaList();
}

int ShadowBackend::lastLoginMode() const {
    return m_lastLoginMode;
}

void ShadowBackend::setLastLoginMode(int mode) {
    // 只作内存态：它是账号页"登录方式 tab"的当前选择（正版/离线/外置三个表单），
    // 也是启动身份的判据。
    // 不要再持久化到 QSettings —— 那是旧 UI「三选一登录」的残留：那时需要单独记"上次用哪种方式"，
    // 现在账号列表 + accounts.json 的 current 才是权威。两套真源并存曾造成
    // "切到正版后重启又被离线账号登回来"（owner 实测，日志实锤）。
    if (m_lastLoginMode != mode) {
        m_lastLoginMode = mode;
        emit loginModeChanged();

        // 切回外置登录时主动校验会话：令牌可能早已在服务端失效，不校验就会一直
        // 显示“已登录”假状态、头像无限转圈（实测就是本问题）。
        if (mode == 2) {
            auto *ygg = static_cast<YggdrasilBackend*>(m_yggdrasil);
            if (ygg && ygg->loggedIn()) ygg->validateSession();
        }
    }
}

// ============================================================
// Version property getters
// ============================================================

QString ShadowBackend::selectedVersion() const {
    return m_version->selectedVersion();
}

// 界面语言 → QLocale。索引口径与 settings_backend.cpp:167 的注释、
// main_release.cpp:513 装翻译器的表一致（0=简体 1=繁体(港澳) 2=繁体(台湾) 3=English）。
static QLocale uiLocaleFromIndex(int idx)
{
    switch (idx) {
    case 1:  return QLocale(QLocale::Chinese, QLocale::HongKong);
    case 2:  return QLocale(QLocale::Chinese, QLocale::Taiwan);
    case 3:  return QLocale(QLocale::English, QLocale::UnitedStates);
    default: return QLocale(QLocale::Chinese, QLocale::China);
    }
}

// ── 上次游玩 ──────────────────────────────────────────────
// 只用我们自己真正观测到的记录（游戏进程起来那一刻写一次），不去猜文件 mtime：
// 非隔离版本的 logs/options.txt 是所有版本共用的，拿它当"上次玩这个版本"会撒谎。
// 没有记录 → 返回空串，QML 整行不显示（宁可没有，也不给假信息）。
QString ShadowBackend::formatLastPlayed(qint64 ms) const
{
    if (ms <= 0) return {};
    const QDateTime t = QDateTime::fromMSecsSinceEpoch(ms);
    const QDate today = QDate::currentDate();
    const qint64 days = t.date().daysTo(today);
    // 语言分支一律看 QLocale::language()，不看 tr() 结果：
    // en.ts 缺译文时 tr() 回落成中文原文，用译文当探针会判成「这是中文」，
    // 「今天 01:20」就这样漏进了英文界面（审计实测）。
    // 中文走相对词（今天/昨天/N 天前）；其他语言直接用 QLocale 的本地化日期时间，
    // 不新增任何译文条目，也就不会因为漏译再退回中文。
    const QLocale loc = uiLocaleFromIndex(m_settings ? m_settings->languageIndex() : 0);
    if (loc.language() != QLocale::Chinese)
        return loc.toString(t, QLocale::ShortFormat);

    const QString hm = t.toString(QStringLiteral("HH:mm"));
    if (days <= 0) return tr("今天 %1").arg(hm);
    if (days == 1) return tr("昨天 %1").arg(hm);
    if (days < 7) return tr("%1 天前").arg(days);
    // 中文习惯「6月12日」，跨年用 ISO，避免年份歧义。
    if (t.date().year() == today.year())
        return loc.toString(t.date(), QStringLiteral("M月d日"));
    return t.toString(QStringLiteral("yyyy-MM-dd"));
}

QString ShadowBackend::lastPlayedLabel() const
{
    const QString vid = selectedVersion();
    if (vid.isEmpty()) return {};
    return formatLastPlayed(m_lastPlayed.value(vid, 0));
}

QString ShadowBackend::lastPlayedLabelFor(const QString& versionId) const
{
    return formatLastPlayed(m_lastPlayed.value(versionId, 0));
}

void ShadowBackend::recordLastPlayed(const QString& versionId)
{
    if (versionId.isEmpty() || !m_app) return;
    const QString path = m_app->dataDir() + QStringLiteral("/last-played.json");
    // 每次都重读：run/旧实例可能刚写过，别让内存缓存覆盖磁盘上的新值
    QJsonObject obj;
    {
        QFile f(path);
        if (f.open(QIODevice::ReadOnly))
            obj = QJsonDocument::fromJson(f.readAll()).object();
    }
    obj.insert(versionId, double(QDateTime::currentMSecsSinceEpoch()));
    QDir().mkpath(m_app->dataDir());
    QFile out(path);
    if (out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        out.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
        out.close();
    }
    m_lastPlayed.clear();
    for (auto it = obj.begin(); it != obj.end(); ++it)
        m_lastPlayed.insert(it.key(), qint64(it.value().toDouble()));
    emit lastPlayedChanged();
}

QStringList ShadowBackend::versionIds() const {
    return m_version->versionIds();
}

QVariantList ShadowBackend::versionList() const {
    if (!m_versionListCacheValid) {
        m_versionListCache = m_version->versionInfoList();
        m_versionDateMapCache.clear();
        m_versionListCacheValid = true;
    }
    return m_versionListCache;
}

QVariantMap ShadowBackend::versionDateMap() const {
    if (!m_versionListCacheValid) {
        m_versionListCache = m_version->versionInfoList();
        m_versionListCacheValid = true;
    }
    if (m_versionDateMapCache.isEmpty() && !m_versionListCache.isEmpty()) {
        for (const auto& v : m_versionListCache) {
            const QVariantMap m = v.toMap();
            m_versionDateMapCache.insert(m.value(QStringLiteral("id")).toString(),
                                          m.value(QStringLiteral("date")));
        }
    }
    return m_versionDateMapCache;
}

QStringList ShadowBackend::installedVersions() const {
    return m_version->installedIds();
}

QStringList ShadowBackend::activeVersionNames() const {
    return m_version->activeVersionNames();
}

bool ShadowBackend::isInstalling() const {
    return m_version->isInstalling();
}




bool ShadowBackend::verifyRunning() const {
    return m_version && m_version->isVerifyRunning();
}
bool ShadowBackend::repairRunning() const {
    return m_version && m_version->isRepairRunning();
}





QObject* ShadowBackend::installCardsModel() const {
    return m_version ? m_version->installCardsModel() : nullptr;
}

int ShadowBackend::verifyChecked() const {
    return m_version ? m_version->verifyChecked() : 0;
}

int ShadowBackend::verifyTotal() const {
    return m_version ? m_version->verifyTotal() : 0;
}

QString ShadowBackend::installVersionId() const {
    return m_version->installVersionId();
}

QString ShadowBackend::installPhase() const {
    return m_version->installPhase();
}




QVariantList ShadowBackend::downloadQueue() const {
    return m_version ? m_version->downloadQueue() : QVariantList{};
}

QVariantList ShadowBackend::activeDownloads() const {
    return m_version ? m_version->activeDownloads() : QVariantList{};
}

QStringList ShadowBackend::releaseVersions() const {
    QStringList list;
    auto versions = m_version->cachedMcVersions();
    for (const auto& v : versions) {
        if (v.type == QStringLiteral("release")) list.append(v.id);
    }
    return list;
}

static bool isAprilFoolVersion(const McVersion& v)
{
    // "special" type from Mojang manifest
    if (v.type == QStringLiteral("special"))
        return true;

    // Specific April Fools version IDs
    static const QSet<QString> foolIds = {
        QStringLiteral("20w14infinite"),
        QStringLiteral("20w14\u221E"),          // 20w14∞
        QStringLiteral("3d shareware v1.34"),
        QStringLiteral("1.rv-pre1"),
        QStringLiteral("15w14a"),
        QStringLiteral("2.0"),
        QStringLiteral("22w13oneblockatatime"),
        QStringLiteral("23w13a_or_b"),
        QStringLiteral("24w14potato"),
        QStringLiteral("25w14craftmine"),
        QStringLiteral("26w14a")
    };
    if (foolIds.contains(v.id))
        return true;

    // Any snapshot released on April 1st (auto-detection)
    if (v.releaseTime.isValid()) {
        QDate d = v.releaseTime.date();
        if (d.month() == 4 && d.day() == 1)
            return true;
    }

    return false;
}

QStringList ShadowBackend::snapshotVersions() const {
    QStringList list;
    auto versions = m_version->cachedMcVersions();
    for (const auto& v : versions) {
        if (v.type == QStringLiteral("snapshot") && !isAprilFoolVersion(v))
            list.append(v.id);
    }
    return list;
}

QStringList ShadowBackend::oldVersions() const {
    QStringList list;
    auto versions = m_version->cachedMcVersions();
    for (const auto& v : versions) {
        if (v.type != QStringLiteral("release") && v.type != QStringLiteral("snapshot")
            && !isAprilFoolVersion(v))
            list.append(v.id);
    }
    return list;
}

QStringList ShadowBackend::aprilFoolVersions() const {
    QStringList list;
    auto versions = m_version->cachedMcVersions();
    for (const auto& v : versions) {
        if (isAprilFoolVersion(v)) list.append(v.id);
    }
    return list;
}

void ShadowBackend::refreshVersionDetails()
{
    // 两阶段异步：① 设置扫描状态让 QML 显示加载指示器
    //              ② 下一事件循环再执行实际扫描（给 QML 渲染时间）
    QTimer::singleShot(0, this, [this]() {
        if (m_isScanningVersions) return;
        m_isScanningVersions = true;
        emit scanningChanged();

        // 扫描体放到 worker 线程（大版本目录遍历/尺寸统计可能耗时数百 ms，避免卡 UI）
        const QString gameDirPath = m_app->gameDir();
        QtConcurrent::run([this, gameDirPath]() {
            QVariantList local;
            QDir gameDir(gameDirPath);
        QString versionsPath = gameDir.absoluteFilePath(QStringLiteral("versions"));
        QDir versionsDir(versionsPath);
        if (versionsDir.exists()) {

    // Map of known MC versions to their types (from cached manifest)
    QMap<QString, QString> knownTypes;
    auto cached = m_version->cachedMcVersions();
    for (const auto& v : cached) {
        knownTypes[v.id] = v.type;
    }

    const QFileInfoList entryInfos = versionsDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    QStringList entries;
    for (const QFileInfo& fi : entryInfos) {
        if (isVersionEntryLink(fi)) continue;  // 跳过 junction（pre-1.6 versions/.minecraft 误识别为版本）
        entries << fi.fileName();
    }
    // Build a lookup for release times
    QMap<QString, QDateTime> releaseTimes;
    for (const auto& v : cached) {
        if (v.releaseTime.isValid())
            releaseTimes[v.id] = v.releaseTime;
    }
    for (const QString& versionId : entries) {
        QString verPath = versionsDir.filePath(versionId);

        // === Find version JSON (flexible static helper) ===
        QString jsonPath = VersionBackend::findVersionJson(verPath, versionId);
        if (jsonPath.isEmpty()) continue;

        // Parse JSON to get the real version id
        QFile jf(jsonPath);
        QByteArray jsonBytes;
        QJsonObject verJson;
        if (jf.open(QIODevice::ReadOnly)) {
            jsonBytes = jf.readAll();
            jf.close();
            QJsonDocument doc = QJsonDocument::fromJson(jsonBytes);
            if (doc.isObject()) verJson = doc.object();
        }
        QString jsonText = QString::fromUtf8(jsonBytes);

        // === Find the main JAR (flexible static helper) ===
        QString jarPath = VersionBackend::findVersionJar(verPath, versionId);
        // If no jar found, that's OK — loader versions inherit from vanilla

        QVariantMap detail;
        detail[QStringLiteral("id")] = versionId;

        // ── Determine base MC version（多路取证，认不出就留空，绝不拿目录名冒充）──
        // ① inheritsFrom：加载器版本的标准写法，最可靠
        // ② clientVersion：版本 JSON 里记录的基础客户端版本（拍平/改名后仍常被保留，本机 "1" 就是靠它）
        // ③ JSON 的 id：原版版本用，但必须长得像版本号（用户能把目录改成 "1"，id 也随之变成 "1"）
        // ④ jar 内 version.json 的 id：原版 jar 自带的版本描述（字段 id 就是真实 MC 版本），
        //    兜底给"json 被写坏但不带 inheritsFrom/clientVersion"的情况（需 Qt CorePrivate 的 QZipReader）
        // ⑤ 全都不成立 → 空串，QML 显示"未识别"，不编
        QString baseMcVersion;
        QString baseMcSource;
        static const QRegularExpression mcVerRe(QStringLiteral(R"(^\d+\.\d+(\.\d+)?$)"));
        if (!verJson.isEmpty()) {
            const QString inherits = verJson.value(QStringLiteral("inheritsFrom")).toString();
            const QString clientVer = verJson.value(QStringLiteral("clientVersion")).toString();
            const QString jsonId = verJson.value(QStringLiteral("id")).toString();
            if (!inherits.isEmpty()) {
                baseMcVersion = inherits;
                baseMcSource = QStringLiteral("inheritsFrom");
            } else if (mcVerRe.match(clientVer).hasMatch()) {
                baseMcVersion = clientVer;
                baseMcSource = QStringLiteral("clientVersion");
            } else if (mcVerRe.match(jsonId).hasMatch()) {
                baseMcVersion = jsonId;
                baseMcSource = QStringLiteral("jsonId");
            }
        }
        if (baseMcVersion.isEmpty() && !jarPath.isEmpty()) {
            QZipReader jarZip(jarPath);
            if (jarZip.status() == QZipReader::NoError) {
                const QByteArray jarVerBytes = jarZip.fileData(QStringLiteral("version.json"));
                if (!jarVerBytes.isEmpty()) {
                    const QString jarVer = QJsonDocument::fromJson(jarVerBytes).object()
                                             .value(QStringLiteral("id")).toString();
                    if (mcVerRe.match(jarVer).hasMatch()) {
                        baseMcVersion = jarVer;
                        baseMcSource = QStringLiteral("jarVersionJson");
                    }
                }
            }
        }

        // ── 从版本 JSON 内容检测加载器类型 ──
        QString loaderType = tr("原版");
        QString loaderVersion;

        // Try to detect loader from versionId pattern: "XX.X-neoforge-XX.X" etc.
        static const QRegularExpression loaderIdPattern(R"(^(.+?)-(neoforge|forge|fabric|quilt)-(.+)$)");
        QRegularExpressionMatch loaderMatch = loaderIdPattern.match(versionId);
        if (loaderMatch.hasMatch()) {
            baseMcVersion = loaderMatch.captured(1);
            baseMcSource = QStringLiteral("dirName");
            loaderVersion = loaderMatch.captured(3);
        }

        // 基于 JSON 内容的加载器检测
        // This is more reliable than filesystem markers — a NeoForge version with
        // a mods/ dir but without neoforge/ marker would be misidentified as Forge.
        if (!jsonText.isEmpty()) {
            // Order matters: OptiFine/LiteLoader are standalone; NeoForge must be
            // checked BEFORE Forge (Forge check explicitly excludes "net.neoforge").
            if (jsonText.contains(QStringLiteral("optifine"), Qt::CaseInsensitive)) {
                loaderType = QStringLiteral("OptiFine");
                static const QRegularExpression ofVerRe(QStringLiteral("HD_U_([^\":/]+)"));
                QRegularExpressionMatch ofM = ofVerRe.match(jsonText);
                if (ofM.hasMatch())
                    loaderVersion = ofM.captured(1);
            } else if (jsonText.contains(QStringLiteral("liteloader"), Qt::CaseInsensitive)) {
                loaderType = QStringLiteral("LiteLoader");
            } else if (jsonText.contains(QStringLiteral("net.fabricmc:fabric-loader"))
                       || jsonText.contains(QStringLiteral("org.quiltmc:quilt-loader"))) {
                loaderType = jsonText.contains(QStringLiteral("org.quiltmc:quilt-loader"))
                    ? QStringLiteral("Quilt") : QStringLiteral("Fabric");
                static const QRegularExpression fabricVerRe(
                    QStringLiteral("(?:net\\.fabricmc:fabric-loader|org\\.quiltmc:quilt-loader):([\\d\\.]+(?:\\+build\\.\\d+)?)"));
                QRegularExpressionMatch fM = fabricVerRe.match(jsonText);
                if (fM.hasMatch())
                    loaderVersion = fM.captured(1);
            } else if (jsonText.contains(QStringLiteral("net.neoforge"))) {
                loaderType = QStringLiteral("NeoForge");
                // 查找 --fml.forgeVersion 或 --fml.neoForgeVersion
                static const QRegularExpression neoVerRe1(QStringLiteral("\"forgeVersion\"\\s*,\\s*\"([^\"]+)\""));
                QRegularExpressionMatch nM1 = neoVerRe1.match(jsonText);
                if (nM1.hasMatch()) {
                    loaderVersion = nM1.captured(1);
                } else {
                    static const QRegularExpression neoVerRe2(QStringLiteral("\"neoForgeVersion\"\\s*,\\s*\"([^\"]+)\""));
                    QRegularExpressionMatch nM2 = neoVerRe2.match(jsonText);
                    if (nM2.hasMatch())
                        loaderVersion = nM2.captured(1);
                }
            } else if (jsonText.contains(QStringLiteral("minecraftforge"))
                       && !jsonText.contains(QStringLiteral("net.neoforge"))) {
                loaderType = QStringLiteral("Forge");
                // 依次尝试 forge:MCVER-BUILD、net.minecraftforge:minecraftforge:VER、fmlloader
                static const QRegularExpression forgeVerRe1(
                    QStringLiteral("forge:[\\d\\.]+(?:_pre\\d*)?-([\\d\\.]+)"));
                QRegularExpressionMatch fgM = forgeVerRe1.match(jsonText);
                if (fgM.hasMatch()) {
                    loaderVersion = fgM.captured(1);
                } else {
                    static const QRegularExpression forgeVerRe2(
                        QStringLiteral("net\\.minecraftforge:minecraftforge:([\\d\\.]+)"));
                    fgM = forgeVerRe2.match(jsonText);
                    if (fgM.hasMatch()) {
                        loaderVersion = fgM.captured(1);
                    } else {
                        static const QRegularExpression forgeVerRe3(
                            QStringLiteral("net\\.minecraftforge:fmlloader:[\\d\\.]+-([\\d\\.]+)"));
                        fgM = forgeVerRe3.match(jsonText);
                        if (fgM.hasMatch())
                            loaderVersion = fgM.captured(1);
                    }
                }
            }
        }

        // Fallback: versionId pattern when JSON detection didn't match
        if (loaderType == tr("原版") && loaderMatch.hasMatch()) {
            QString key = loaderMatch.captured(2);
            if (key == QStringLiteral("neoforge")) loaderType = QStringLiteral("NeoForge");
            else if (key == QStringLiteral("forge")) loaderType = QStringLiteral("Forge");
            else if (key == QStringLiteral("fabric")) loaderType = QStringLiteral("Fabric");
            else if (key == QStringLiteral("quilt")) loaderType = QStringLiteral("Quilt");
        }
        detail[QStringLiteral("loaderType")] = loaderType;
        detail[QStringLiteral("loaderVersion")] = loaderVersion;
        // 基础 MC 版本：版本目录名是用户可自定义的（本机就叫 "1"），
        // 不能靠 QML 拆 id，必须把解析出来的 baseMcVersion 一起带出去。
        detail[QStringLiteral("mcVersion")] = baseMcVersion;
        detail[QStringLiteral("mcVersionSource")] = baseMcSource;  // inheritsFrom / clientVersion / jsonId / jarVersionJson / dirName

        // ── Version type: use base MC version for manifest lookup ──
        QString vtype = knownTypes.value(baseMcVersion, QString());
        if (vtype.isEmpty()) {
            // Not in manifest — run heuristic ONLY for vanilla versions
            if (loaderType == tr("原版") && baseMcVersion.contains(QRegularExpression(QStringLiteral("\\dw\\d|alpha|beta|inf"))))
                vtype = QStringLiteral("old");
            else
                vtype = QStringLiteral("release");
        } else {
            // Map Mojang raw types to simplified display types
            if (vtype == QStringLiteral("snapshot")) {
                vtype = QStringLiteral("snapshot");
            } else if (vtype == QStringLiteral("release")) {
                vtype = QStringLiteral("release");
            } else {
                vtype = QStringLiteral("old");  // old_alpha, old_beta, pending, etc.
            }
        }
        detail[QStringLiteral("versionType")] = vtype;

        // Release time (Unix ms) for sorting — use base MC version for loader versions
        QDateTime rt = releaseTimes.value(baseMcVersion);
        if (!rt.isValid()) rt = releaseTimes.value(versionId);
        detail[QStringLiteral("releaseTimeMs")] = rt.isValid() ? rt.toMSecsSinceEpoch() : 0;

        // 快速估算大小（避免递归遍历整个目录）
        qint64 totalSize = 0;
        QFileInfo jarFi(jarPath);
        if (jarFi.exists()) totalSize += jarFi.size();
        QFileInfo jsonFi(jsonPath);
        if (jsonFi.exists()) totalSize += jsonFi.size();
        // 只统计顶层子目录里的直接文件（不递归子子目录）
        static const QStringList topDirs = {
            QStringLiteral("mods"), QStringLiteral("resourcepacks"),
            QStringLiteral("shaderpacks"), QStringLiteral("saves")
        };
        for (const QString& d : topDirs) {
            QDir sub(verPath + QStringLiteral("/") + d);
            if (sub.exists()) {
                const auto files = sub.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
                for (const QFileInfo& fi : files)
                    totalSize += fi.size();
            }
        }
        detail[QStringLiteral("sizeBytes")] = totalSize;

        // Count mods
        int modCount = 0;
        QString modsDir = verPath + QStringLiteral("/mods");
        if (QDir(modsDir).exists()) {
            QDirIterator modIt(modsDir, QStringList() << QStringLiteral("*.jar"), QDir::Files);
            while (modIt.hasNext()) { modIt.next(); modCount++; }
        }
        detail[QStringLiteral("modCount")] = modCount;
        {
            // 整合包标记：isModpack=true 时读取标记内图标 URL（下载页传入），版本选择直接用真实图标
            const QString markerPath = verPath + QStringLiteral("/.shadow_modpack");
            const bool isModpack = QFileInfo::exists(markerPath);
            detail[QStringLiteral("isModpack")] = isModpack;
            if (isModpack) {
                const QString localIcon = verPath + QStringLiteral("/modpack_icon.png");
                // 本地图标优先（导入时已解码落盘）；无则退回标记里的 URL
                detail[QStringLiteral("modpackIconPath")] =
                    QFileInfo::exists(localIcon) ? QUrl::fromLocalFile(localIcon).toString() : QString();
                QFile mf(markerPath);
                if (mf.open(QIODevice::ReadOnly)) {
                    const QJsonDocument md = QJsonDocument::fromJson(mf.readAll());
                    mf.close();
                    if (md.isObject())
                        detail[QStringLiteral("modpackIcon")] =
                            md.object().value(QStringLiteral("icon")).toString();
                }
            }
        }
        detail[QStringLiteral("jsonPath")] = jsonPath;
        detail[QStringLiteral("jarPath")] = jarPath;

        local.append(detail);
    }

        }  // end if (versionsDir.exists())
        QMetaObject::invokeMethod(this, [this, local]() {
            m_versionDetails = local;
            emit versionDetailsReady();
            emit logMessage(tr("已扫描 %1 个已安装版本").arg(m_versionDetails.size()));
            m_isScanningVersions = false;
            emit scanningChanged();
        }, Qt::QueuedConnection);
        });  // end QtConcurrent::run lambda
    });  // end outer QTimer::singleShot lambda
}

QVariantMap ShadowBackend::systemMemoryInfo() const {
    return m_settings->getMemoryStatus();
}

// ============================================================
// Launch property getters
// ============================================================

bool ShadowBackend::isLaunching() const {
    return m_launch->isLaunching();
}

int ShadowBackend::launchProgress() const {
    return m_launch->launchProgress();
}

QString ShadowBackend::launchStatus() const {
    return m_launch->launchStatus();
}

bool ShadowBackend::isRunning() const {
    return m_launch->isRunning();
}


int ShadowBackend::runningCount() const {
    return m_launch->runningCount();
}

// ============================================================
// Resource property getters
// ============================================================

bool ShadowBackend::isResourceDownloading() const {
    return m_resource->isDownloading();
}

// ============================================================
// App property getters
// ============================================================

QString ShadowBackend::gameDir() const {
    return m_app->gameDir();
}

QString ShadowBackend::appDataDir() const {
    return m_app->dataDir();
}

QString ShadowBackend::theme() const {
    return m_app->theme();
}

QString ShadowBackend::appVersion() const {
    return m_app->appVersion();
}

bool ShadowBackend::devMode() const {
    return m_app->devMode();
}

static QString agreementConsentPath()
{
    return QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("agreement_consent.txt"));
}

bool ShadowBackend::agreementAccepted() const
{
    // Read consent from file next to the executable
    QFile f(agreementConsentPath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    QString content = QString::fromUtf8(f.readAll()).trimmed();
    QStringList parts = content.split('|');
    if (parts.size() < 2)
        return false;
    return parts[0] == AppBackend::AGREEMENT_VERSION && parts[1] == QStringLiteral("true");
}

void ShadowBackend::setMarkAgreed(bool v)
{
    if (!v) return;
    // Write consent file: VERSION|true
    QFile f(agreementConsentPath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        QString line = QString::fromLatin1(AppBackend::AGREEMENT_VERSION)
                       + QStringLiteral("|true\n");
        f.write(line.toUtf8());
        f.close();
    }
    emit agreementAcceptedChanged();
}

static QString readQrcFile(const QString& path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QStringLiteral("<p>无法加载协议文件</p>");
    return QString::fromUtf8(f.readAll());
}

QString ShadowBackend::betaAgreementHtml() const
{
    return readQrcFile(QStringLiteral(":/qt/qml/ShadowLauncher/agreements/beta_agreement.html"));
}

QString ShadowBackend::privacyAgreementHtml() const
{
    return readQrcFile(QStringLiteral(":/qt/qml/ShadowLauncher/agreements/privacy_policy.html"));
}

QString ShadowBackend::termsAgreementHtml() const
{
    return readQrcFile(QStringLiteral(":/qt/qml/ShadowLauncher/agreements/terms_of_service.html"));
}

// ============================================================
// Q_INVOKABLE methods — Account
// ============================================================

void ShadowBackend::offlineLogin(const QString& username) {
    m_account->offlineLogin(username);
}

bool ShadowBackend::isOfflineRestricted() const {
    // 地区由 GeoIpService 异步检测（ip-api.com，24h 缓存）；启动后 3s 触发
    const QString region = m_geoIp ? m_geoIp->cachedRegion().toUpper().trimmed() : QString();
    // 只有明确检测为 CN（中国大陆）才放行；
    // 未检测到地区（检测失败/被屏蔽/断网）同样受限——防止绕过合规限制
    if (region == QStringLiteral("CN")) return false;
    // 非中国大陆（国外/港澳台）或未检测到地区，且未正版登录 → 限制
    return !m_account->isLoggedIn();
}

void ShadowBackend::updateOfflineSkin(const QString& username) {
    m_account->updateOfflineSkin(username);
}

void ShadowBackend::removeOfflineUsername(const QString& username) {
    m_account->removeOfflineUsername(username);
}

void ShadowBackend::microsoftLogin() {
    m_account->microsoftLogin();
}

void ShadowBackend::cancelMicrosoftLogin() {
    m_account->cancelMicrosoftLogin();
}

void ShadowBackend::logout() {
    m_account->logout();
}

// ── 多账号 ──
QVariantList ShadowBackend::accounts() const { return m_account ? m_account->accounts() : QVariantList(); }
int ShadowBackend::currentAccount() const { return m_account ? m_account->currentAccount() : -1; }

void ShadowBackend::switchAccount(int index) {
    if (!m_account) return;
    const QVariantMap a = m_account->accountAt(index);
    if (a.isEmpty()) return;
    const int mode = a.value(QStringLiteral("mode")).toInt();
    auto *ygg = static_cast<YggdrasilBackend*>(m_yggdrasil);
    if (mode == 2) {
        // 外置：AccountBackend 只负责清掉本地正版/离线态，会话交给 YggdrasilBackend
        m_account->switchAccount(index);
        // 凭据已被判失效的账号不再自动恢复：拿死令牌打接口只会再吃一次 403，
        // 然后又把「需重新登录」重写一遍。UI 会在右侧给「重新登录」卡片。
        if (a.value(QStringLiteral("needsRelogin")).toBool()) {
            qCInfo(logApp) << QStringLiteral("[切号] 该外置账号需重新登录，跳过会话恢复");
            if (ygg && ygg->loggedIn()) ygg->logout();
        } else if (ygg) {
            ygg->restoreSession(a.value(QStringLiteral("apiRoot")).toString(),
                                a.value(QStringLiteral("accessToken")).toString(),
                                a.value(QStringLiteral("clientToken")).toString(),
                                a.value(QStringLiteral("name")).toString(),
                                a.value(QStringLiteral("uuid")).toString());
        }
    } else {
        // 切回本地账号：先退出外置会话，避免两套身份同时在线
        if (ygg && ygg->loggedIn()) ygg->logout();
        m_account->switchAccount(index);
    }
    // 同步"上次登录"到 QSettings：切换后它就是兜底依据，不跟着 current 走会继续两套状态打架
    const int cur = m_account->currentAccount();
    const QVariantMap curAcc = cur >= 0 ? m_account->accountAt(cur) : QVariantMap();
    if (!curAcc.isEmpty()) {
        QSettings s(QCoreApplication::organizationName(), QCoreApplication::applicationName());
        s.setValue(QStringLiteral("account/lastUsername"), curAcc.value(QStringLiteral("name")).toString());
        s.setValue(QStringLiteral("account/lastLoginMode"), curAcc.value(QStringLiteral("mode")).toInt());
        setLastLoginMode(curAcc.value(QStringLiteral("mode")).toInt());
    }
}

bool ShadowBackend::capesAsked() const
{
    return m_account ? m_account->capesAsked() : false;
}

bool ShadowBackend::accountLoading() const
{
    if (!m_account) return false;
    return m_account->capesLoading();
}

bool ShadowBackend::removeAccount(int index) {
    if (!m_account) return false;
    // 先记下被删的是哪一类账号：删完之后它已经从列表里消失，问不出来了。
    const QVariantMap goneAcc = m_account->accountAt(index);
    if (!m_account->removeAccount(index)) return false;

    // 外置账号的会话存在 YggdrasilBackend 的 session.json 里，
    // 只删 accounts.json 条目的话，下次启动仍会被 loadSession 恢复回来（同微软账号那个复活 bug）。
    if (goneAcc.value(QStringLiteral("mode")).toInt() == 2) {
        auto *goneYgg = static_cast<YggdrasilBackend*>(m_yggdrasil);
        // 条目已经删掉了，这里可以放心吊销服务端令牌；
        // 其它场合（切号）必须用 logout()，只清本地、保留令牌。
        if (goneYgg) goneYgg->logoutRevoking();
    }

    // AccountBackend::removeAccount 内部会切到列表中第一条，但那次切换不经过
    // ShadowBackend::switchAccount，于是 m_lastLoginMode 与外置会话都不会更新。
    // 结果是「当前账号是 A、实际身份还是 B」，删正版会顺带把外置会话打得半死。
    // 删完必须在这里按新的 current 重新落定身份。
    auto *ygg = static_cast<YggdrasilBackend*>(m_yggdrasil);
    const int cur = m_account->currentAccount();
    const QVariantMap curAcc = cur >= 0 ? m_account->accountAt(cur) : QVariantMap();

    if (curAcc.isEmpty()) {
        if (ygg && ygg->loggedIn()) ygg->logout();
        return true;
    }

    const int mode = curAcc.value(QStringLiteral("mode")).toInt();
    if (mode == 2) {
        if (ygg) {
            ygg->restoreSession(curAcc.value(QStringLiteral("apiRoot")).toString(),
                                curAcc.value(QStringLiteral("accessToken")).toString(),
                                curAcc.value(QStringLiteral("clientToken")).toString(),
                                curAcc.value(QStringLiteral("name")).toString(),
                                curAcc.value(QStringLiteral("uuid")).toString());
        }
    } else if (ygg && ygg->loggedIn()) {
        // 删完落到本地账号：外置会话必须一起退，否则两套身份同时在线
        ygg->logout();
    }

    QSettings s(QCoreApplication::organizationName(), QCoreApplication::applicationName());
    s.setValue(QStringLiteral("account/lastUsername"), curAcc.value(QStringLiteral("name")).toString());
    s.setValue(QStringLiteral("account/lastLoginMode"), mode);
    setLastLoginMode(mode);
    return true;
}

// ============================================================
// Q_INVOKABLE methods — Settings / Java
// ============================================================

QVariantList ShadowBackend::scanJavaInstallations() {
    emit logMessage(tr("正在扫描 Java 环境..."));
    QVariantList list = m_settings->scanJavaInstallations();
    qCInfo(logJava) << QStringLiteral("Java扫描完成 检出=%1").arg(list.size());
    return list;
}

QString ShadowBackend::autoSelectJava() {
    return m_settings->autoSelectJava();
}

QString ShadowBackend::jvmArgs() const {
    return m_app->jvmArgs();
}

void ShadowBackend::setJvmArgs(const QString& args) {
    m_app->setJvmArgs(args);
    emit logMessage(tr("[JVM] GC参数已更新: %1").arg(args));
    saveJvmArgs();
    emit jvmArgsChanged();
}

QString ShadowBackend::gameArgs() const {
    return m_app->gameArgs();
}

void ShadowBackend::setGameArgs(const QString& args) {
    m_app->setGameArgs(args);
    emit logMessage(tr("[GAME] 游戏附加参数已更新: %1").arg(args));
    saveGameArgs();
    emit gameArgsChanged();
}

bool ShadowBackend::highPerfGpu() const {
    return m_app->highPerfGpu();
}

void ShadowBackend::setHighPerfGpu(bool v) {
    m_app->setHighPerfGpu(v);
    emit logMessage(tr("[GPU] 高性能显卡模式: %1").arg(v ? QStringLiteral("开启") : QStringLiteral("关闭")));
    saveHighPerfGpu();
    emit highPerfGpuChanged();
}

// ── 启动细节（低垂果实批，2026-08-08：对齐主流启动器）──

int ShadowBackend::gcMode() const { return m_settings->gcMode(); }
void ShadowBackend::setGcMode(int v) { m_settings->setGcMode(v); emit launchDetailChanged(); }
int ShadowBackend::processPriority() const { return m_settings->processPriority(); }
void ShadowBackend::setProcessPriority(int v) { m_settings->setProcessPriority(v); emit launchDetailChanged(); }
bool ShadowBackend::fullscreenEnabled() const { return m_settings->fullscreenEnabled(); }
void ShadowBackend::setFullscreenEnabled(bool v) { m_settings->setFullscreenEnabled(v); emit launchDetailChanged(); }
QString ShadowBackend::autoJoinServer() const { return m_settings->autoJoinServer(); }
void ShadowBackend::setAutoJoinServer(const QString& v) { m_settings->setAutoJoinServer(v); emit launchDetailChanged(); }
QString ShadowBackend::windowTitleOverride() const { return m_settings->windowTitleOverride(); }
void ShadowBackend::setWindowTitleOverride(const QString& v) { m_settings->setWindowTitleOverride(v); emit launchDetailChanged(); }
QString ShadowBackend::preLaunchCommand() const { return m_settings->preLaunchCommand(); }
void ShadowBackend::setPreLaunchCommand(const QString& v) { m_settings->setPreLaunchCommand(v); emit launchDetailChanged(); }
QString ShadowBackend::postExitCommand() const { return m_settings->postExitCommand(); }
void ShadowBackend::setPostExitCommand(const QString& v) { m_settings->setPostExitCommand(v); emit launchDetailChanged(); }

int ShadowBackend::versionGcMode(const QString& versionId) const {
    return m_settings->versionGcMode(versionId);
}
void ShadowBackend::setVersionGcMode(const QString& versionId, int mode) {
    m_settings->setVersionGcMode(versionId, mode);
    emit versionLaunchSettingsChanged(versionId);
}
QString ShadowBackend::versionAutoJoinServer(const QString& versionId) const {
    return m_settings->versionAutoJoinServer(versionId);
}
void ShadowBackend::setVersionAutoJoinServer(const QString& versionId, const QString& addr) {
    m_settings->setVersionAutoJoinServer(versionId, addr);
    emit versionLaunchSettingsChanged(versionId);
}
int ShadowBackend::versionProcessPriorityMode(const QString& versionId) const {
    return m_settings->versionProcessPriorityMode(versionId);
}
void ShadowBackend::setVersionProcessPriorityMode(const QString& versionId, int mode) {
    m_settings->setVersionProcessPriorityMode(versionId, mode);
    emit launchDetailChanged();
}
int ShadowBackend::versionProcessPriority(const QString& versionId) const {
    return m_settings->versionProcessPriority(versionId);
}
void ShadowBackend::setVersionProcessPriority(const QString& versionId, int v) {
    m_settings->setVersionProcessPriority(versionId, v);
    emit launchDetailChanged();
}

int ShadowBackend::resolvedGcMode(const QString& versionId) const {
    int ver = m_settings->versionGcMode(versionId);
    return ver > 0 ? ver : m_settings->gcMode();
}
int ShadowBackend::resolvedProcessPriority(const QString& versionId) const {
    // mode==0 跟随全局；mode==1 用版本值。和 gcMode 同一套解析规则。
    const int ver = m_settings->versionProcessPriorityMode(versionId);
    return ver > 0 ? m_settings->versionProcessPriority(versionId) : m_settings->processPriority();
}
QString ShadowBackend::resolvedAutoJoinServer(const QString& versionId) const {
    QString ver = m_settings->versionAutoJoinServer(versionId);
    return ver.isEmpty() ? m_settings->autoJoinServer() : ver;
}

// ── 全屏/窗口标题/命令：版本级覆盖（mode==1 用版本值，否则全局）──

int ShadowBackend::versionFullscreenMode(const QString& versionId) const {
    return m_settings->versionFullscreenMode(versionId);
}
void ShadowBackend::setVersionFullscreenMode(const QString& versionId, int mode) {
    m_settings->setVersionFullscreenMode(versionId, mode);
    emit versionLaunchSettingsChanged(versionId);
}
bool ShadowBackend::versionFullscreen(const QString& versionId) const {
    return m_settings->versionFullscreen(versionId);
}
void ShadowBackend::setVersionFullscreen(const QString& versionId, bool v) {
    m_settings->setVersionFullscreen(versionId, v);
    emit versionLaunchSettingsChanged(versionId);
}
int ShadowBackend::versionWindowTitleMode(const QString& versionId) const {
    return m_settings->versionWindowTitleMode(versionId);
}
void ShadowBackend::setVersionWindowTitleMode(const QString& versionId, int mode) {
    m_settings->setVersionWindowTitleMode(versionId, mode);
    emit versionLaunchSettingsChanged(versionId);
}
QString ShadowBackend::versionWindowTitle(const QString& versionId) const {
    return m_settings->versionWindowTitle(versionId);
}
void ShadowBackend::setVersionWindowTitle(const QString& versionId, const QString& v) {
    m_settings->setVersionWindowTitle(versionId, v);
    emit versionLaunchSettingsChanged(versionId);
}
int ShadowBackend::versionPreLaunchMode(const QString& versionId) const {
    return m_settings->versionPreLaunchMode(versionId);
}
void ShadowBackend::setVersionPreLaunchMode(const QString& versionId, int mode) {
    m_settings->setVersionPreLaunchMode(versionId, mode);
    emit versionLaunchSettingsChanged(versionId);
}
QString ShadowBackend::versionPreLaunchCommand(const QString& versionId) const {
    return m_settings->versionPreLaunchCommand(versionId);
}
void ShadowBackend::setVersionPreLaunchCommand(const QString& versionId, const QString& v) {
    m_settings->setVersionPreLaunchCommand(versionId, v);
    emit versionLaunchSettingsChanged(versionId);
}
int ShadowBackend::versionPostExitMode(const QString& versionId) const {
    return m_settings->versionPostExitMode(versionId);
}
void ShadowBackend::setVersionPostExitMode(const QString& versionId, int mode) {
    m_settings->setVersionPostExitMode(versionId, mode);
    emit versionLaunchSettingsChanged(versionId);
}
QString ShadowBackend::versionPostExitCommand(const QString& versionId) const {
    return m_settings->versionPostExitCommand(versionId);
}
void ShadowBackend::setVersionPostExitCommand(const QString& versionId, const QString& v) {
    m_settings->setVersionPostExitCommand(versionId, v);
    emit versionLaunchSettingsChanged(versionId);
}
bool ShadowBackend::resolvedFullscreen(const QString& versionId) const {
    if (m_settings->versionFullscreenMode(versionId) == 1)
        return m_settings->versionFullscreen(versionId);
    return m_settings->fullscreenEnabled();
}
QString ShadowBackend::resolvedWindowTitle(const QString& versionId) const {
    if (m_settings->versionWindowTitleMode(versionId) == 1)
        return m_settings->versionWindowTitle(versionId);
    return m_settings->windowTitleOverride();
}
QString ShadowBackend::resolvedPreLaunchCommand(const QString& versionId) const {
    if (m_settings->versionPreLaunchMode(versionId) == 1)
        return m_settings->versionPreLaunchCommand(versionId);
    return m_settings->preLaunchCommand();
}
QString ShadowBackend::resolvedPostExitCommand(const QString& versionId) const {
    if (m_settings->versionPostExitMode(versionId) == 1)
        return m_settings->versionPostExitCommand(versionId);
    return m_settings->postExitCommand();
}

// 设置导入导出已随 SettingsBackend 一并删除（导入路径可导致任意命令执行）。


// ── Persistence helpers (delegated to SettingsBackend-style QSettings) ──
void ShadowBackend::saveJvmArgs() {
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("java/jvmArgs"), m_app->jvmArgs());
}

void ShadowBackend::saveGameArgs() {
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("java/gameArgs"), m_app->gameArgs());
}

void ShadowBackend::saveHighPerfGpu() {
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("java/highPerfGpu"), m_app->highPerfGpu());
}


void ShadowBackend::loadJavaRuntimeSettings() {
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    m_app->setJvmArgs(s.value(QStringLiteral("java/jvmArgs"), QString()).toString());
    m_app->setGameArgs(s.value(QStringLiteral("java/gameArgs"), QString()).toString());
    m_app->setHighPerfGpu(s.value(QStringLiteral("java/highPerfGpu"), false).toBool());
}

QString ShadowBackend::browseJava() {
    emit logMessage(tr("用户手动选择 Java 环境..."));
    return m_settings->browseJava();
}

void ShadowBackend::selectJavaByIndex(int index) {
    qCInfo(logJava) << QStringLiteral("选择Java index=%1").arg(index);
    m_settings->selectJavaByIndex(index);
}

QVariantMap ShadowBackend::getMemoryStatus() {
    return m_settings->getMemoryStatus();
}

void ShadowBackend::setMinMemory(int mb) {
    m_settings->setMinMemory(mb);
}

void ShadowBackend::setMaxMemory(int mb) {
    m_settings->setMaxMemory(mb);
}

void ShadowBackend::setIsolationEnabled(bool enabled) {
    // 外部目录：版本隔离状态由原布局决定，不允许切换（避免破坏导入目录）
    if (m_mcFolder && m_mcFolder->isForeignActive()) {
        emit logMessage(tr("外部 .minecraft 遵循原布局，不可切换版本隔离"));
        emit isolationChanged();
        return;
    }
    m_isolationEnabled = enabled;
    m_settings->setIsolationEnabled(enabled);
}

QString ShadowBackend::getVersionGameDir(const QString& versionId) const {
    return m_settings->getVersionGameDir(versionId);
}

void ShadowBackend::migrateVersionToIsolated(const QString& versionId) {
    m_settings->migrateVersionToIsolated(versionId);
}

// ════════════════════════════════════════════════════════════════
// 外部 .minecraft 目录应用/回退（MinecraftFolderBackend 信号驱动）
// ════════════════════════════════════════════════════════════════

void ShadowBackend::onApplyForeignFolder(const QString& root, int layout)
{
    if (root.isEmpty()) return;
    const auto mcLayout = static_cast<MinecraftLayout>(layout);

    // 1) 版本隔离解析切换到外部目录形态（只读尊重原布局，不写配置）
    m_settings->isolation()->setFolderLayout(mcLayout);

    // 2) 同步所有子后端的游戏目录（与构造函数装配一致）。
    //    setMinecraftDir 内含 mkpath(versions/libraries/assets)——对有效
    //    .minecraft 均已存在，无副作用；无效目录不会走到这里（probe 已校验）。
    m_app->setGameDir(root);
    m_settings->setMinecraftDir(root);
    m_settings->setIsolationGameDir(root);
    m_version->setGameDir(root);
    m_launch->setGameDir(root);
    m_localMods->setGameDir(root);
    if (m_modpackExporter)
        qobject_cast<ModpackExporter*>(m_modpackExporter)->setGameDir(root);
    if (m_modpackImporter)
        qobject_cast<ModpackImporter*>(m_modpackImporter)->setGameDir(root);

    emit gameDirChanged();
    emit isolationChanged();
    emit logMessage(tr("已切换到外部 .minecraft: %1").arg(root));
}

void ShadowBackend::onRevertForeignFolder()
{
    const QString defaultDir = QCoreApplication::applicationDirPath()
                               + QStringLiteral("/.minecraft");

    // 回到传统行为（由版本隔离开关控制，默认隔离）
    m_settings->isolation()->setFolderLayout(MinecraftLayout::Unknown);

    m_app->setGameDir(defaultDir);
    m_settings->setMinecraftDir(defaultDir);
    m_settings->setIsolationGameDir(defaultDir);
    m_version->setGameDir(defaultDir);
    m_launch->setGameDir(defaultDir);
    m_localMods->setGameDir(defaultDir);
    if (m_modpackExporter)
        qobject_cast<ModpackExporter*>(m_modpackExporter)->setGameDir(defaultDir);
    if (m_modpackImporter)
        qobject_cast<ModpackImporter*>(m_modpackImporter)->setGameDir(defaultDir);

    emit gameDirChanged();
    emit isolationChanged();
    emit logMessage(tr("已恢复默认游戏目录: %1").arg(defaultDir));
}

QObject* ShadowBackend::modManager() const
{
    return m_resource ? m_resource->modManager() : nullptr;
}

QObject* ShadowBackend::mcFolder() const
{
    return m_mcFolder;
}

QObject* ShadowBackend::multiplayer() const
{
    return m_multiplayer;
}

// 原生"选择保存文件夹"对话框。
// 这里用 QFileDialog（QtWidgets）而不是 QML 的 FolderDialog：本程序是 QApplication + Widgets 构建，
// QML FolderDialog 在 Windows 上会静默失败（不显示、还会把后续 SaveFile 对话框一起卡住）。
QString ShadowBackend::pickFolder(const QString &initialDir) {
    QString start = initialDir;
    if (start.isEmpty() || !QDir(start).exists())
        start = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    return QFileDialog::getExistingDirectory(nullptr, tr("选择保存文件夹"), start,
        QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks);
}

QString ShadowBackend::resolveIconUrl(const QString &url)
{
    return m_fetchEngine ? m_fetchEngine->iconLocalPath(url) : url;
}

// ── Helper: get the game directory for a given version ID ──
QString ShadowBackend::gameDirForVersion(const QString& versionId) const {
    if (versionId.isEmpty()) return m_app->gameDir();
    return getVersionGameDir(versionId);
}

void ShadowBackend::syncPlayerName()
{
    if (!m_multiplayer) return;

    // 2026-11-07：联机身份改为「设备」而非账号。
    // 昵称由 MultiplayerManager 自己从 QSettings(multiplayer/deviceName) 读取，首次取电脑名，
    // 用户可在联机页自行修改；这里不再用账号名覆盖它。
    // （旧 UI 的「你的昵称」输入框走 setPlayerName，仍等价 setDeviceName。）
}

bool ShadowBackend::openGameDir(const QString& versionId) {
    QString dir = gameDirForVersion(versionId);
    QDir().mkpath(dir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
    emit logMessage(tr("已打开游戏目录") + (versionId.isEmpty() ? QString() : QStringLiteral(" (") + versionId + QStringLiteral(")")));
    return true;
}

bool ShadowBackend::openLatestLog(const QString& versionId) {
    QString gameDir = gameDirForVersion(versionId);
    QString latestLog = gameDir + QStringLiteral("/logs/latest.log");
    if (QFileInfo::exists(latestLog)) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(latestLog));
        emit logMessage(tr("已打开最新日志"));
        return true;
    }
    return false;
}

bool ShadowBackend::isVersionInstalled(const QString& versionId) const {
    if (versionId.isEmpty()) return false;
    return QFileInfo::exists(m_app->gameDir() + QStringLiteral("/versions/") + versionId
                             + QStringLiteral("/") + versionId + QStringLiteral(".json"));
}

bool ShadowBackend::openLogsFolder(const QString& versionId) {
    if (!isVersionInstalled(versionId)) {
        qCWarning(logMod) << "[openLogsFolder] 版本不存在，拒绝打开/创建:" << versionId;
        return false;
    }
    QString logsDir = gameDirForVersion(versionId) + QStringLiteral("/logs");
    QDir().mkpath(logsDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(logsDir));
    emit logMessage(tr("已打开日志目录"));
    return true;
}

bool ShadowBackend::openLauncherLogsFolder() {
    QString logsDir = QCoreApplication::applicationDirPath() + QStringLiteral("/logs");
    QDir().mkpath(logsDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(logsDir));
    emit logMessage(tr("已打开启动器日志目录"));
    return true;
}

bool ShadowBackend::openCrashLog(const QString& versionId) {
    QString gameDir = gameDirForVersion(versionId);
    QString crashDir = gameDir + QStringLiteral("/crash-reports");
    QDir cd(crashDir);
    if (cd.exists()) {
        QStringList filters; filters << QStringLiteral("*.txt");
        QFileInfoList entries = cd.entryInfoList(filters, QDir::Files, QDir::Time);
        if (!entries.isEmpty()) {
            QDesktopServices::openUrl(QUrl::fromLocalFile(entries.first().absoluteFilePath()));
            emit logMessage(tr("已打开崩溃日志"));
            return true;
        }
    }
    // Fallback: check versions/{versionId}/game/crash-reports/
    QString altCrashDir = m_app->gameDir() + QStringLiteral("/versions/") + versionId + QStringLiteral("/game/crash-reports");
    QDir acd(altCrashDir);
    if (acd.exists()) {
        QStringList filters; filters << QStringLiteral("*.txt");
        QFileInfoList entries = acd.entryInfoList(filters, QDir::Files, QDir::Time);
        if (!entries.isEmpty()) {
            QDesktopServices::openUrl(QUrl::fromLocalFile(entries.first().absoluteFilePath()));
            emit logMessage(tr("已打开崩溃日志 (隔离目录)"));
            return true;
        }
    }
    return false;
}

void ShadowBackend::demoPrecheckFail(const QString& reason) {
    if (m_launch) m_launch->demoPrecheckFail(reason);
}

QString ShadowBackend::exportCrashLogs(const QString& destDir) {
    if (!m_launch) return {};
    return m_launch->exportCrashLogs(destDir);
}

QString ShadowBackend::exportLaunchScript(const QString& versionId, const QString& javaPath,
                                          int maxMemoryMB, const QString& jvmArgs,
                                          const QString& gameArgs, bool highPerfGpu) {
    if (!m_launch) return {};
    // 对齐启动流程：Java 按版本需求匹配（不能直接用全局 javaPath——26.2-forge 需要
    // Java 25，全局 Java 17 会导致 UnsupportedClassVersionError class file 69.0）
    QString resolvedJava = javaPath;
    if (m_settings) {
        const int requiredMajor = requiredJavaMajor(versionId);
        int maxMajor = 0;
        if (requiredMajor == 17) maxMajor = 21;
        const QString manualJava = m_settings->javaPath();
        if (!manualJava.isEmpty() && QFileInfo::exists(manualJava)
            && m_settings->javaMajor() >= requiredMajor
            && (maxMajor <= 0 || m_settings->javaMajor() <= maxMajor)) {
            resolvedJava = manualJava;
        } else {
            const QString matched = m_settings->findJavaForVersion(requiredMajor, maxMajor);
            if (!matched.isEmpty()) resolvedJava = matched;
        }
    }
    if (resolvedJava.isEmpty()) return QString();
    // 对齐启动流程：按登录方式注入账号信息（0=正版 1=离线 2=外置）
    // 2026-08-10 修：原实现只看 m_account->isOnline()，外置登录时导出的是无关的
    // 微软/离线账号信息，且外置 token/authlib-injector 完全不进脚本。
    auto *ygg = static_cast<YggdrasilBackend*>(m_yggdrasil);
    const int exportMode = activeAccountMode();
    if (exportMode == 2 && ygg && ygg->loggedIn()) {
        // 外置登录：ygg 账号信息 + ygg 模式（authlib-injector agent 由 launch_backend 注入）
        m_launch->setAuthInfo(ygg->username(), ygg->uuid(), ygg->accessToken(), true);
        m_launch->setYggdrasilMode(ygg->apiRoot(), ygg->accessToken());
    } else if (exportMode == 1) {
        // 离线登录：离线名/uuid，无 token（buildArgs 会以 0 占位）
        const QString name = m_account ? m_account->offlineUsername() : QString();
        const QString uuid = m_account ? m_account->offlineUuid() : QString();
        m_launch->setAuthInfo(name, uuid, QString(), false);
        m_launch->clearYggdrasilMode();
    } else {
        // 正版登录（微软）：校验令牌时效，过期先同步刷新，刷新失败降级离线
        // （2026-08-10 修：原实现不验证时效，过期令牌进脚本 → 游戏内 Realms 直接失效）
        m_launch->clearYggdrasilMode();
        QString token;
        bool online = false;
        if (m_account && m_account->isOnline()) {
            token = m_account->mcToken();
            online = true;
            if (!m_account->msMcTokenValid()) {
                if (m_account->msRefreshToken().isEmpty()) {
                    // 过期且无刷新令牌 → 无法自愈，直接降级离线
                    token = QString();
                    online = false;
                    emit logMessage(tr("正版令牌已过期且无刷新令牌，导出脚本将以离线方式启动（Realms 不可用）"));
                } else {
                qCInfo(logApp) << QStringLiteral("[导出脚本] 正版令牌已过期，尝试刷新...");
                QEventLoop loop;
                QTimer timeout;
                timeout.setSingleShot(true);
                QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
                QMetaObject::Connection c1 = connect(m_account, &AccountBackend::tokenRefreshed,
                    &loop, [&loop](bool ok) { if (ok) loop.quit(); });
                QMetaObject::Connection c2 = connect(m_account, &AccountBackend::tokenRefreshFailed,
                    &loop, [&loop](bool, const QString&) { loop.quit(); });
                timeout.start(15000);
                m_account->refreshMicrosoftToken();
                loop.exec();
                timeout.stop();
                disconnect(c1);
                disconnect(c2);
                if (m_account->msMcTokenValid()) {
                    token = m_account->mcToken();
                    qCInfo(logApp) << QStringLiteral("[导出脚本] 正版令牌刷新成功");
                } else {
                    token = QString();
                    online = false;
                    emit logMessage(tr("正版令牌已过期且刷新失败，导出脚本将以离线方式启动（Realms 不可用）"));
                }
                }
            }
        } else if (m_account) {
            // 当前未正版登录（微软账号未激活）——回退离线信息
            token = QString();
            online = false;
        }
        const QString name = online ? m_account->username() : (m_account ? m_account->offlineUsername() : QString());
        const QString uuid = online ? m_account->accountUuid() : (m_account ? m_account->offlineUuid() : QString());
        m_launch->setAuthInfo(name, uuid, token, online);
    }
    if (m_settings)
        m_launch->setVersionGameDir(m_settings->getVersionGameDir(versionId));
    // 对齐启动流程（proceedLaunch）：启动细节全部走 resolved*（版本级优先）解析后再注入
    // ——否则导出脚本用的是上次启动的残留值/默认值，版本级覆盖完全不生效（2026-08-10 修）
    if (m_settings && m_launch) {
        m_launch->setGcMode(resolvedGcMode(versionId));
    m_launch->setMinMemoryMB(m_settings->minMemoryMB());
        m_launch->setProcessPriority(resolvedProcessPriority(versionId));
        m_launch->setFullscreenEnabled(resolvedFullscreen(versionId));
        m_launch->setAutoJoinServer(resolvedAutoJoinServer(versionId));
        m_launch->setWindowTitleOverride(resolvedWindowTitle(versionId));
        m_launch->setPreLaunchCommand(resolvedPreLaunchCommand(versionId));
        m_launch->setPostExitCommand(resolvedPostExitCommand(versionId));
    }
    return m_launch->exportLaunchScript(versionId, resolvedJava, maxMemoryMB,
                                        jvmArgs, gameArgs, highPerfGpu);
}

bool ShadowBackend::saveTextFile(const QString& path, const QString& content) {
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    f.write(content.toUtf8());
    f.close();
    return true;
}

void ShadowBackend::openPath(const QString& path) {
    if (m_launch) m_launch->openPath(path);
}

void ShadowBackend::cleanupCrashArtifacts() {
    if (m_launch) m_launch->cleanupCrashArtifacts();
}

bool ShadowBackend::openSavesFolder(const QString& versionId) {
    if (!isVersionInstalled(versionId)) {
        qCWarning(logMod) << "[openSavesFolder] 版本不存在，拒绝打开/创建:" << versionId;
        return false;
    }
    QString savesDir = gameDirForVersion(versionId) + QStringLiteral("/saves");
    QDir().mkpath(savesDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(savesDir));
    emit logMessage(tr("已打开存档文件夹"));
    return true;
}

bool ShadowBackend::openScreenshotsFolder(const QString& versionId) {
    if (!isVersionInstalled(versionId)) {
        qCWarning(logMod) << "[openScreenshotsFolder] 版本不存在，拒绝打开/创建:" << versionId;
        return false;
    }
    QString screenshotsDir = gameDirForVersion(versionId) + QStringLiteral("/screenshots");
    QDir().mkpath(screenshotsDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(screenshotsDir));
    emit logMessage(tr("已打开截图文件夹"));
    return true;
}

bool ShadowBackend::openModsFolder(const QString& versionId) {
    if (!isVersionInstalled(versionId)) {
        qCWarning(logMod) << "[openModsFolder] 版本不存在，拒绝打开/创建:" << versionId;
        return false;
    }
    QString modsDir = gameDirForVersion(versionId) + QStringLiteral("/mods");
    QDir().mkpath(modsDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(modsDir));
    emit logMessage(tr("已打开 Mod 文件夹"));
    return true;
}

bool ShadowBackend::openResourcePacksFolder(const QString& versionId) {
    if (!isVersionInstalled(versionId)) {
        qCWarning(logMod) << "[openResourcePacksFolder] 版本不存在，拒绝打开/创建:" << versionId;
        return false;
    }
    QString rpDir = gameDirForVersion(versionId) + QStringLiteral("/resourcepacks");
    QDir().mkpath(rpDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(rpDir));
    emit logMessage(tr("已打开资源包文件夹"));
    return true;
}

bool ShadowBackend::openShaderPacksFolder(const QString& versionId) {
    QString spDir = gameDirForVersion(versionId) + QStringLiteral("/shaderpacks");
    QDir().mkpath(spDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(spDir));
    emit logMessage(tr("已打开光影包文件夹"));
    return true;
}

// ── Mod/local file operations ──

QVariantList ShadowBackend::listMods(const QString& versionId) const
{
    if (!m_localMods) return {};
    return m_localMods->scanMods(versionId);
}

// ── 异步列表加载：parseJar / 目录遍历在 worker 线程，完成后回主线程发信号 ──
void ShadowBackend::listModsAsync(const QString& versionId)
{
    if (!m_localMods) return;
    LocalModManager* lmm = m_localMods;
    QtConcurrent::run([this, lmm, versionId]() {
        const QVariantList result = lmm->scanMods(versionId);
        QMetaObject::invokeMethod(this, [this, versionId, result]() {
            emit modsListReady(versionId, result);
        }, Qt::QueuedConnection);
    });
}

void ShadowBackend::listResourcePacksAsync(const QString& versionId)
{
    if (!m_localMods) return;
    LocalModManager* lmm = m_localMods;
    QtConcurrent::run([this, lmm, versionId]() {
        const QVariantList result = lmm->scanResourcePacks(versionId);
        QMetaObject::invokeMethod(this, [this, versionId, result]() {
            emit resourcePacksListReady(versionId, result);
        }, Qt::QueuedConnection);
    });
}

// 光影包列表（2026-11-13）：只列目录、不解压 zip，所以同步扫也很快；
// 仍然走 worker 线程，与 Mod / 资源包三页保持同一套调用形态。
void ShadowBackend::listShaderPacksAsync(const QString& versionId)
{
    if (!m_localMods) return;
    LocalModManager* lmm = m_localMods;
    QtConcurrent::run([this, lmm, versionId]() {
        const QVariantList result = lmm->scanShaderPacks(versionId);
        QMetaObject::invokeMethod(this, [this, versionId, result]() {
            emit shaderPacksListReady(versionId, result);
        }, Qt::QueuedConnection);
    });
}

static qint64 computeDirSize(const QString& path)
{
    qint64 total = 0;
    QDirIterator it(path, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        if (it.fileInfo().isFile())
            total += it.fileInfo().size();
    }
    return total;
}

// ── 辅助：格式化文件大小为可读字符串 ──
static QString formatSizeDisplay(qint64 bytes)
{
    if (bytes < 1024) return QString::number(bytes) + QStringLiteral(" B");
    if (bytes < 1024 * 1024) return QString::number(bytes / 1024.0, 'f', 1) + QStringLiteral(" KB");
    if (bytes < 1024LL * 1024 * 1024)
        return QString::number(bytes / (1024.0 * 1024.0), 'f', 1) + QStringLiteral(" MB");
    return QString::number(bytes / (1024.0 * 1024.0 * 1024.0), 'f', 2) + QStringLiteral(" GB");
}

QVariantList ShadowBackend::listSaves(const QString& versionId) const
{
    QString savesDir = gameDirForVersion(versionId) + QStringLiteral("/saves");
    QDir dir(savesDir);
    QVariantList result;
    if (dir.exists()) {
        const auto dirs = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const auto& fi : dirs) {
            QVariantMap m;
            m[QStringLiteral("name")] = fi.fileName();

            // Size (reuse the cached result from fi if available — QFileInfo caches)
            qint64 sizeBytes = computeDirSize(fi.absoluteFilePath());
            m[QStringLiteral("sizeBytes")] = sizeBytes;
            m[QStringLiteral("sizeDisplay")] = formatSizeDisplay(sizeBytes);

            // Icon
            QString iconPath = fi.absoluteFilePath() + QStringLiteral("/icon.png");
            if (QFile::exists(iconPath))
                m[QStringLiteral("iconPath")] = QUrl::fromLocalFile(iconPath).toString();
            else
                m[QStringLiteral("iconPath")] = QString();

            result.append(m);
        }
    }
    return result;
}


void ShadowBackend::listSavesAsync(const QString& versionId)
{
    const QString savesDir = gameDirForVersion(versionId) + QStringLiteral("/saves");
    QtConcurrent::run([this, versionId, savesDir]() {
        QVariantList result;
        QDir dir(savesDir);
        if (dir.exists()) {
            const auto dirs = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
            for (const auto& fi : dirs) {
                QVariantMap m;
                m[QStringLiteral("name")] = fi.fileName();
                qint64 sizeBytes = 0;
                QDirIterator it(fi.absoluteFilePath(), QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot,
                                QDirIterator::Subdirectories);
                while (it.hasNext()) {
                    it.next();
                    if (it.fileInfo().isFile()) sizeBytes += it.fileInfo().size();
                }
                m[QStringLiteral("sizeBytes")] = sizeBytes;
                m[QStringLiteral("sizeDisplay")] = formatSizeDisplay(sizeBytes);
                QString iconPath = fi.absoluteFilePath() + QStringLiteral("/icon.png");
                m[QStringLiteral("iconPath")] = QFile::exists(iconPath)
                    ? QUrl::fromLocalFile(iconPath).toString() : QString();
                result.append(m);
            }
        }
        QMetaObject::invokeMethod(this, [this, versionId, result]() {
            emit savesListReady(versionId, result);
        }, Qt::QueuedConnection);
    });
}

// ── 辅助：递归计算目录大小 ──
void ShadowBackend::deleteSave(const QString& saveName, const QString& versionId)
{
    if (saveName.isEmpty()) return;
    QString savePath = gameDirForVersion(versionId) + QStringLiteral("/saves/") + saveName;
    QDir dir(savePath);
    if (!dir.exists()) {
        emit logMessage(QStringLiteral("存档不存在: ") + saveName);
        return;
    }
    if (dir.removeRecursively()) {
        emit logMessage(QStringLiteral("已删除存档: ") + saveName);
    } else {
        emit logMessage(QStringLiteral("删除存档失败: ") + saveName);
    }
}

void ShadowBackend::deleteMod(const QString& filename, const QString& versionId)
{
    if (!m_localMods) return;
    if (m_localMods->deleteMod(filename, versionId))
        emit logMessage(QStringLiteral("已删除 Mod: ") + filename);
}

void ShadowBackend::setModEnabled(const QString& filename, const QString& versionId, bool enabled)
{
    if (!m_localMods) return;
    if (m_localMods->setModEnabled(filename, versionId, enabled))
        emit logMessage(QStringLiteral("%1 Mod: %2").arg(enabled ? QStringLiteral("已启用") : QStringLiteral("已禁用"), filename));
}

int ShadowBackend::setAllModsEnabled(const QString& versionId, bool enabled)
{
    if (!m_localMods) return 0;
    const int n = m_localMods->setAllModsEnabled(versionId, enabled);
    if (n > 0)
        emit logMessage(enabled
            ? QStringLiteral("已全部启用 %1 个模组").arg(n)
            : QStringLiteral("已全部禁用 %1 个模组").arg(n));
    return n;
}

void ShadowBackend::deleteResourcePack(const QString& filename, const QString& versionId)
{
    if (!m_localMods) return;
    if (m_localMods->deleteResourcePack(filename, versionId))
        emit logMessage(QStringLiteral("已删除资源包: ") + filename);
}

// ══ 全局拖入识别 ══════════════════════════════════════════════
// 拖进启动器的东西可能是：整合包、Mod、资源包、光影包、存档、authlib-injector，
// 或者一个 authlib-injector 的拖拽链接。只看扩展名会错（.zip 有四种可能），
// 所以这里真的打开压缩包看结构。
QString ShadowBackend::parseAuthlibInjectorLink(const QString &text)
{
    static const QString kPrefix = QStringLiteral("authlib-injector:yggdrasil-server:");
    QString s = text.trimmed();
    if (!s.startsWith(kPrefix, Qt::CaseInsensitive)) return QString();
    s = s.mid(kPrefix.length()).trimmed();
    // 拖拽链接里的地址是百分号编码的（https%3A%2F%2F...）
    s = QUrl::fromPercentEncoding(s.toUtf8());
    while (s.endsWith(QLatin1Char('/'))) s.chop(1);
    return s;
}

QString ShadowBackend::classifyDroppedTarget(const QString &pathOrUrl)
{
    QString s = pathOrUrl.trimmed();
    if (s.isEmpty()) return QStringLiteral("unknown");

    // 1) authlib-injector 拖拽链接
    if (!parseAuthlibInjectorLink(s).isEmpty()) return QStringLiteral("authlib-link");

    // 2) 普通 URL（从浏览器拖出来的 http 链接）
    if (s.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)
        || s.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive))
        return QStringLiteral("url");

    // 3) file:// -> 本地路径
    QString path = s;
    if (path.startsWith(QStringLiteral("file:"), Qt::CaseInsensitive))
        path = QUrl(path).toLocalFile();
    if (path.isEmpty() || !QFileInfo::exists(path)) return QStringLiteral("unknown");

    const QString suffix = QFileInfo(path).suffix().toLower();

    // 4) .mrpack 一定是整合包，不用打开看
    if (suffix == QStringLiteral("mrpack")) return QStringLiteral("modpack");

    // 5) 打开压缩包看结构（.jar / .zip）
    if (suffix == QStringLiteral("jar") || suffix == QStringLiteral("zip")) {
        QZipReader zip(path);
        if (zip.status() != QZipReader::NoError) {
            // 打不开就当未知，别硬猜
            return QStringLiteral("unknown");
        }
        const QList<QZipReader::FileInfo> files = zip.fileInfoList();
        bool hasModrinth = false, hasCfManifest = false, hasFabricMod = false, hasModsToml = false;
        bool hasShadersDir = false, hasPackMeta = false, hasLevelDat = false;
        bool hasAuthlib = false;
        for (const auto &fi : files) {
            const QString name = fi.filePath;
            const QString lower = name.toLower();
            if (lower == QLatin1String("modrinth.index.json")) hasModrinth = true;
            else if (lower == QLatin1String("manifest.json")) hasCfManifest = true;
            else if (lower == QLatin1String("fabric.mod.json")) hasFabricMod = true;
            else if (lower == QLatin1String("meta-inf/mods.toml")
                     || lower == QLatin1String("meta-inf/neoforge.mods.toml")) hasModsToml = true;
            else if (lower == QLatin1String("pack.mcmeta")) hasPackMeta = true;
            else if (lower == QLatin1String("level.dat")) hasLevelDat = true;
            else if (lower.startsWith(QLatin1String("authlib-injector"))
                     || lower.contains(QLatin1String("yggdrasil"))) hasAuthlib = true;
            else if (lower.startsWith(QLatin1String("shaders/"))) hasShadersDir = true;
        }

        // 整合包优先判定：它的标志文件最明确，且用户拖错时的代价最大
        if (hasModrinth) return QStringLiteral("modpack");
        if (hasCfManifest && suffix == QStringLiteral("zip")) return QStringLiteral("modpack");
        if (hasAuthlib) return QStringLiteral("authlib");
        if (hasLevelDat) return QStringLiteral("world");
        if (hasShadersDir) return QStringLiteral("shaderpack");
        if (hasFabricMod || hasModsToml) return QStringLiteral("mod");
        if (hasPackMeta) return QStringLiteral("resourcepack");

        // 有 zip 结构但认不出：仍然按扩展名给一个"较可能"的答案，
        // 让上层能提示"未知内容"，而不是默默什么都不做
        return QStringLiteral("unknown");
    }

    // 6) 其它扩展名：按常识归类
    if (suffix == QStringLiteral("datapack")) return QStringLiteral("datapack");
    return QStringLiteral("unknown");
}

bool ShadowBackend::importMod(const QString& filePath, const QString& versionId)
{
    if (!m_localMods) return false;
    return m_localMods->importMod(filePath, versionId);
}

bool ShadowBackend::importResourcePack(const QString& filePath, const QString& versionId)
{
    if (!m_localMods) return false;
    return m_localMods->importResourcePack(filePath, versionId);
}

// ── 光影包（2026-11-13）──
void ShadowBackend::deleteShaderPack(const QString& filename, const QString& versionId)
{
    if (!m_localMods) return;
    if (m_localMods->deleteShaderPack(filename, versionId))
        emit logMessage(QStringLiteral("已删除光影包: ") + filename);
}

bool ShadowBackend::importShaderPack(const QString& filePath, const QString& versionId)
{
    if (!m_localMods) return false;
    return m_localMods->importShaderPack(filePath, versionId);
}

bool ShadowBackend::setShaderPackEnabled(const QString& filename, const QString& versionId, bool enabled)
{
    if (!m_localMods) return false;
    const bool ok = m_localMods->setShaderPackEnabled(filename, versionId, enabled);
    if (ok)
        emit logMessage(QStringLiteral("%1 光影包: %2").arg(
            enabled ? QStringLiteral("已启用") : QStringLiteral("已禁用"), filename));
    return ok;
}

bool ShadowBackend::openVersionDir(const QString& versionId) {
    return m_settings->openVersionDir(versionId);
}

void ShadowBackend::deleteVersion(const QString& versionId) {
    // 2026-08-19：外部目录不再拦截删除 —— 用户可完全导入并接管外部 .minecraft。
    // 删除版本是用户主动操作：删 versions/<id>（含该版本数据）与自家目录行为完全一致。
    // "不破坏导入目录"约束针对启动器自动操作，不限制用户的明确删除意图。
    m_settings->deleteVersion(versionId);
    // Refresh the installed list (deleted version disappears)
    m_version->refreshInstalled();
    // 2026-11-22：同时重建 versionDetails —— 版本选择列表直接绑定这个属性。
    // 只刷 refreshInstalled 的话列表停在旧快照，要退出页面再进来才刷新；
    // 用户在旧列表里点中已删版本，回主页启动就会失败。
    refreshVersionDetails();
    // If the deleted version was selected, reset to unselected
    if (m_version->selectedVersion() == versionId) {
        m_version->setSelectedVersion(QString());
        // Inform QML so it can explicitly re-read the value
        emit selectedVersionClearedAfterDelete();
    }
}

// ============================================================
// Q_INVOKABLE methods — Version
// ============================================================

void ShadowBackend::refreshVersionList() {
    m_version->refreshVersionList();
}

void ShadowBackend::refreshInstalled() {
    m_version->refreshInstalled();
}

void ShadowBackend::installVersion(const QString& versionId) {
    m_version->installVersion(versionId);
}

void ShadowBackend::cancelVersionInstall(const QString& versionId) {
    // ── 资源文件下载卡片（mod:N）：取消下载并移除卡片 ──
    if (versionId.startsWith(QStringLiteral("mod:"))) {
        bool ok = false;
        const int dlId = versionId.mid(4).toInt(&ok);
        if (ok) {
            m_resource->cancelModFileDownload(dlId);
            if (m_packDownloads.contains(dlId)) {
                m_packDownloads.remove(dlId);
                m_packDownloading = false;   // 取消整合包下载 → 释放单任务占位
            }
            if (m_modDownloadCards.contains(dlId)) {
                if (m_version) m_version->removeResourceCard(m_modDownloadCards[dlId]);
                m_modDownloadCards.remove(dlId);
            }
        }
        return;
    }
    if (m_version) m_version->cancelVersionInstall(versionId);
}

void ShadowBackend::dismissCard(const QString& installId) {
    if (m_version) m_version->dismissCard(installId);
}

void ShadowBackend::retryVersionInstall(const QString& installId) {
    // 整合包任务卡片（modpack-*）：转发到 ModpackImporter 的加载器重试（只重跑加载器，保留 MC+模组）
    if (m_version && m_version->isTaskCard(installId) && m_modpackImporter) {
        auto* imp = qobject_cast<ModpackImporter*>(m_modpackImporter);
        if (imp) { imp->retryLoader(); return; }
    }
    if (m_version) m_version->retryVersionInstall(installId);
}

void ShadowBackend::cancelQueuedDownload(const QString& versionId) {
    if (m_version) m_version->cancelQueuedDownload(versionId);
}

void ShadowBackend::setSelectedVersion(const QString& versionId) {
    m_version->setSelectedVersion(versionId);
    m_settings->setLastLaunchedVersion(versionId);
}

// ============================================================
// Q_INVOKABLE methods — Launch
// ============================================================

void ShadowBackend::launch(const QString& versionId, bool online) {
    // Prepare server.properties for multiplayer (disable online-mode)
    if (m_multiplayer) {
        m_multiplayer->prepareServerProperties(m_app->gameDir(), versionId);
    }

    // 外置登录模式：从 yggdrasil backend 获取用户名和 token
    // 三种登录方式严格分离（用户要求）：0=正版(微软账号)、1=离线(离线名)、2=外置(ygg)
    QString username;
    auto *ygg = static_cast<YggdrasilBackend*>(m_yggdrasil);
    // 身份判据 = 当前账号类型（accounts.json 的 current），m_lastLoginMode 只在没有当前账号时兜底。
    // 两套真源并存过：切号/重启后 m_lastLoginMode 与 current 不一致，启动就会拿错身份。
    int authMode = m_account ? m_account->currentAccountMode() : -1;
    if (authMode < 0) authMode = m_lastLoginMode;
    if (authMode == 2 && ygg && ygg->loggedIn()) {
        username = ygg->username();
        // 通知 launch backend 使用外置登录
        m_launch->setYggdrasilMode(ygg->apiRoot(), ygg->accessToken());
    } else if (authMode == 1) {
        // 离线登录：用离线用户名（m_account->username() 是微软正版账号名，离线时为空）
        username = m_account->offlineUsername();
        m_launch->clearYggdrasilMode();
    } else {
        // 正版登录：微软账号用户名
        username = m_account->username();
        m_launch->clearYggdrasilMode();
    }

    // Check per-version memory override
    int verMode = m_settings->versionMemoryMode(versionId);
    int maxMemory;
    if (verMode == 1) {
        // Per-version: auto
        maxMemory = m_launch->getAutoMemoryForVersion(versionId);
    } else if (verMode == 2) {
        // Per-version: manual
        maxMemory = m_settings->versionMemoryManualMB(versionId);
    } else {
        // Per-version: follow global (0 or unset)
        maxMemory = m_settings->autoMemoryEnabled()
            ? m_launch->getAutoMemoryForVersion(versionId)
            : m_settings->maxMemoryMB();
    }
    qCInfo(logApp) << QStringLiteral("启动内存: %1MB (verMode=%2, auto=%3)").arg(maxMemory).arg(verMode).arg(m_settings->autoMemoryEnabled());
    QString jvmArgs = resolvedJvmArgs(versionId);
    QString gameArgs = resolvedGameArgs(versionId);

    // 外置登录：自动进入服务器
    auto *yggServer = static_cast<YggdrasilBackend*>(m_yggdrasil);
    if (m_lastLoginMode == 2 && yggServer && yggServer->loggedIn()
            && yggServer->autoJoinServer() && !yggServer->serverAddress().isEmpty()) {
        QString addr = yggServer->serverAddress();
        // 二次验证（防御性编程，理论上 setter 已过滤）
        if (!YggdrasilBackend::isValidServerAddress(addr)) {
            qCWarning(logApp) << QStringLiteral("[服务端] 服务器地址无效，跳过自动连接: %1").arg(addr);
        } else {
            QStringList parts = addr.split(QLatin1Char(':'));
            QString host = parts.value(0);
            int port = 25565;
            if (parts.size() >= 2) {
                bool ok = false;
                int parsed = parts.value(1).toInt(&ok);
                if (ok && parsed > 0 && parsed <= 65535)
                    port = parsed;
            }
            gameArgs += QStringLiteral(" --server %1 --port %2").arg(host).arg(port);
            qCInfo(logApp) << QStringLiteral("[服务端] 自动连接: %1:%2").arg(host).arg(port);
        }
    }

    bool highPerfGpu = resolvedHighPerfGpu(versionId);
    m_launchVersion = versionId;
    m_launchUsername = username;

    // ── 2026-08-08：Java 检测/匹配/自动安装全部下沉到 LaunchBackend 状态机 Step 1 ──
    // 这里不提前解析需求、不匹配、不安装——避免 Java 检测独立于启动检查流程
    // （用户要求：正常启动流程不受影响，Java 检测是启动检查的一部分）。
    // javaPath 传空，由状态机 Step 1 判定需求 → 匹配 → 缺失自动安装。
    QString javaPath;

    // Pass auth info based on mode
    // 判据只看当前账号类型（authMode），不看调用方传的 online ——
    // 以前 QML 传 b.isOnline，外置账号它是 false，于是外置身份被当成离线送进去，
    // 用户名取到空 → 启动前检查第 0 步「登录状态」直接拦下（影实测）。
    const bool useOnline = (authMode == 0 || authMode == 2);
    if (useOnline) {
        auto *ygg2 = static_cast<YggdrasilBackend*>(m_yggdrasil);
        if (authMode == 2 && ygg2 && ygg2->loggedIn()) {
            // 外置登录
            qCInfo(logLaunch) << QStringLiteral("[认证] 外置登录模式启动 玩家名=%1 uuid=%2").arg(ygg2->username(), ygg2->uuid());
            m_launch->setAuthInfo(ygg2->username(), ygg2->uuid(),
                                  ygg2->accessToken(), true);
            m_launch->setYggdrasilMode(ygg2->apiRoot(), ygg2->accessToken());
        } else {
            // ── 2026-11-19 修「放置久了再启动会进离线模式」──
            // 旧实现直接把 m_account->mcToken() 塞进启动参数，**不校验时效、不刷新**。
            // 微软 accessToken 只有约 24 小时，启动器开着放一夜后再启动，
            // 送进去的就是一个过期令牌 → 服务端拒绝 → 游戏内表现为离线（Realms 也废）。
            // 导出脚本那条路（exportLaunchScript）一直有校验+刷新，主启动路径漏了。
            // 这里补上同样的逻辑：过期先同步刷新（最长等 15 秒），失败才降级离线。
            QString token = m_account->mcToken();
            if (!m_account->msMcTokenValid()) {
                if (m_account->msRefreshToken().isEmpty()) {
                    token.clear();
                    emit logMessage(tr("正版令牌已过期且没有刷新令牌，本次启动将以离线身份进入（请重新登录正版账号）"));
                    qCWarning(logLaunch) << QStringLiteral("[认证] 令牌过期且无 refresh_token，降级离线");
                } else {
                    qCInfo(logLaunch) << QStringLiteral("[认证] 正版令牌已过期，启动前同步刷新...");
                    QEventLoop loop;
                    QTimer timeout;
                    timeout.setSingleShot(true);
                    QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
                    QMetaObject::Connection c1 = connect(m_account, &AccountBackend::tokenRefreshed,
                        &loop, [&loop](bool ok) { loop.quit(); });
                    QMetaObject::Connection c2 = connect(m_account, &AccountBackend::tokenRefreshFailed,
                        &loop, [&loop](bool, const QString&) { loop.quit(); });
                    timeout.start(15000);
                    m_account->refreshMicrosoftToken();
                    loop.exec();
                    timeout.stop();
                    disconnect(c1);
                    disconnect(c2);
                    if (m_account->msMcTokenValid()) {
                        token = m_account->mcToken();
                        qCInfo(logLaunch) << QStringLiteral("[认证] 令牌刷新成功，按正版身份启动");
                    } else {
                        token.clear();
                        emit logMessage(tr("正版令牌过期且刷新失败（网络或账号问题），本次以离线身份进入"));
                        qCWarning(logLaunch) << QStringLiteral("[认证] 刷新失败，降级离线");
                    }
                }
            }
            qCInfo(logLaunch) << QStringLiteral("[认证] 在线模式启动 玩家名=%1 uuid=%2 令牌=%3")
                                     .arg(m_account->username(), m_account->accountUuid(),
                                          token.isEmpty() ? QStringLiteral("无(离线)") : QStringLiteral("有效"));
            m_launch->setAuthInfo(m_account->username(), m_account->accountUuid(), token, !token.isEmpty());
        }
    } else {
        qCInfo(logLaunch) << QStringLiteral("[认证] 离线模式启动 玩家名=%1 uuid=%2").arg(m_account->offlineUsername(), m_account->offlineUuid());
        m_launch->setAuthInfo(m_account->offlineUsername(), m_account->offlineUuid(), QString(), false);
    }

    proceedLaunch(versionId, online, javaPath, maxMemory, jvmArgs, gameArgs, highPerfGpu);
}

void ShadowBackend::proceedLaunch(const QString& versionId, bool online, const QString& javaPath,
                                  int maxMemory, const QString& jvmArgs, const QString& gameArgs,
                                  bool highPerfGpu)
{
    // 启动参数由 LaunchBackend 状态机持有；Java 自动安装已在状态机内完成（若需要）
    m_launch->setAutoLangMode(m_settings->autoLangMode());
    m_launch->setDetectedRegion(m_geoIp ? m_geoIp->cachedRegion() : QString());
    m_launch->setVersionGameDir(m_settings->getVersionGameDir(versionId));
    // ── 启动细节（低垂果实批，2026-08-08）：版本级优先 → 全局 ──
    m_launch->setGcMode(resolvedGcMode(versionId));
    m_launch->setMinMemoryMB(m_settings->minMemoryMB());
    m_launch->setProcessPriority(resolvedProcessPriority(versionId));
    m_launch->setFullscreenEnabled(resolvedFullscreen(versionId));
    m_launch->setAutoJoinServer(resolvedAutoJoinServer(versionId));
    m_launch->setWindowTitleOverride(resolvedWindowTitle(versionId));
    m_launch->setPreLaunchCommand(resolvedPreLaunchCommand(versionId));
    m_launch->setPostExitCommand(resolvedPostExitCommand(versionId));
    // 854x480 只用于 pre-1.6 版本的 ${resolution_width}/${resolution_height} 占位符；
    // 现代版本不解析该占位符，游戏窗口大小由 MC 自己的 options.txt 决定。
    // 所以这里不再暴露成用户可配置项（2026-11-10 影：不该支持改动）。
    m_launch->launch(versionId, m_launchUsername, javaPath, maxMemory, jvmArgs, gameArgs, highPerfGpu,
                     854, 480);
}

void ShadowBackend::cancelLaunch() {
    // Java 自动安装在 LaunchBackend 状态机内（cancelLaunch 内部会清理安装状态）
    m_launch->cancelLaunch();
}

void ShadowBackend::demoLaunch(int mode) {
    Q_UNUSED(m_settings);
    m_launch->demoLaunch(mode);
}

void ShadowBackend::stopDemo() {
    m_launch->stopDemo();
}

int ShadowBackend::requiredJavaMajor(const QString& versionId)
{
    // Walk version JSON + inheritsFrom chain to find javaVersion.majorVersion
    // This handles Forge/NeoForge/Fabric installs where javaVersion may be in the base MC JSON
    QString gameDir = m_app->gameDir();
    QString currentId = versionId;
    QStringList seen;

    while (!currentId.isEmpty() && !seen.contains(currentId)) {
        seen.append(currentId);
        QString jsonPath = gameDir + QStringLiteral("/versions/") + currentId
                         + QStringLiteral("/") + currentId + QStringLiteral(".json");
        QFile f(jsonPath);
        if (!f.open(QIODevice::ReadOnly)) break;

        QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        f.close();
        QJsonObject json = doc.object();

        // Check javaVersion field first
        QJsonObject javaVer = json[QStringLiteral("javaVersion")].toObject();
        if (!javaVer.isEmpty()) {
            int major = javaVer[QStringLiteral("majorVersion")].toInt(0);
            if (major > 0) {
                qCInfo(logLaunch) << QStringLiteral("[JAVA] Version %1 inherits %2 → requires Java %3")
                                    .arg(versionId, currentId).arg(major);
                return major;
            }
        }

        // Walk up inheritsFrom chain
        currentId = json[QStringLiteral("inheritsFrom")].toString();
    }

    // Fallback: parse MC version from versionId and infer Java requirement
    // Examples: "1.12.2-forge-14.23.5.2860" → "1.12.2" → Java 8
    //           "26.1.1-forge-63.0.2" → "26.1.1" → no known mapping → try base version
    // Parse MC version: everything before first "-" that follows a digit
    QString mcVer;
    // Strip loader suffix: "X.Y.Z-forge-..." → "X.Y.Z"
    static QRegularExpression mcVerRe(QStringLiteral("^(\\d+\\.\\d+(?:\\.\\d+)?)"));
    QRegularExpressionMatch match = mcVerRe.match(versionId);
    if (match.hasMatch()) {
        mcVer = match.captured(1);
    }
    
    int javaMajor = inferJavaByMcVersion(mcVer);
    qCInfo(logLaunch) << QStringLiteral("[JAVA] Version %1 → MC %2 → inferred Java %3 (no javaVersion in chain)")
                        .arg(versionId, mcVer.isEmpty() ? QStringLiteral("unknown") : mcVer).arg(javaMajor);
    return javaMajor;
}

int ShadowBackend::inferJavaByMcVersion(const QString& mcVersion)
{
    // Fallback: infer Java major version from MC version string.
    // Used when version JSON + inheritsFrom chain has no javaVersion field.
    //
    // Source: Minecraft Wiki + ModReady version table
    //   MC < 1.17                 → Java 8
    //   MC 1.17~1.17.1            → Java 16
    //   MC 1.18~1.20.4            → Java 17
    //   MC 1.20.5~1.21.5          → Java 21
    //   MC 22.x+ (post-rename)    → Java 25 (java-runtime-beta)
    //
    if (mcVersion.isEmpty()) return 8;

    // Parse major.minor[.revision] from version string
    QStringList parts = mcVersion.split(QStringLiteral("."));
    if (parts.size() < 2) return 8;
    
    int major = parts[0].toInt();
    int minor = parts[1].toInt();
    int rev = (parts.size() >= 3) ? parts[2].split(QStringLiteral("-"))[0].toInt() : 0;
    
    // ── Post-rename era: "22.x.x" ~ "26.x.x" ──
    // Mojang renamed 1.22+ to 22.x (e.g. 26.1 = Tiny Takeover, 26.2 = Chaos Cubed)
    // These all use java-runtime-beta → Java 25
    if (major >= 22) return 25;
    
    // ── Classic era: "1.X.Y" ──
    if (major == 1) {
        // 1.21.x (regardless of rev) → Java 21
        if (minor >= 22) return 25;   // 1.22+ (if it exists) → same as post-rename
        if (minor >= 21) return 21;
        // 1.20.x: 1.20.5+ → Java 21, 1.20.0~1.20.4 → Java 17
        if (minor >= 20) return (rev >= 5) ? 21 : 17;
        if (minor == 18 || minor == 19) return 17;
        if (minor == 17) return 16;
        return 8;  // 1.16.x and below
    }
    
    // Unknown version scheme → conservative
    return 21;
}

void ShadowBackend::killGameProcess() {
    m_launch->killGameProcess();
}

/// 只用于核对 B1 失败面板：造一份崩溃诊断 + 让管线停在失败态。
void ShadowBackend::killGameByPid(qint64 pid) {
    m_launch->killGameByPid(pid);
}

QVariantList ShadowBackend::runningGames() {
    return m_launch->runningGames();
}

int ShadowBackend::getAutoMemory() {
    return m_launch->getAutoMemory();
}

bool ShadowBackend::autoMemoryEnabled() const {
    return m_settings->autoMemoryEnabled();
}

void ShadowBackend::setAutoMemoryEnabled(bool enabled) {
    m_settings->setAutoMemoryEnabled(enabled);
}

int ShadowBackend::versionMemoryMode(const QString& versionId) const {
    return m_settings->versionMemoryMode(versionId);
}

void ShadowBackend::setVersionMemoryMode(const QString& versionId, int mode) {
    m_settings->setVersionMemoryMode(versionId, mode);
}

int ShadowBackend::resolvedMemoryMB(const QString& versionId) {
    int verMode = m_settings->versionMemoryMode(versionId);
    if (verMode == 1) return m_launch->getAutoMemory();
    if (verMode == 2) return m_settings->versionMemoryManualMB(versionId);
    return m_settings->autoMemoryEnabled()
        ? m_launch->getAutoMemory()
        : m_settings->maxMemoryMB();
}

int ShadowBackend::versionMemoryManualMB(const QString& versionId) const {
    return m_settings->versionMemoryManualMB(versionId);
}

void ShadowBackend::setVersionMemoryManualMB(const QString& versionId, int mb) {
    m_settings->setVersionMemoryManualMB(versionId, mb);
}

// ── Per-version Java/launch overrides ──

int ShadowBackend::versionJavaMode(const QString& versionId) const {
    return m_settings->versionJavaMode(versionId);
}
void ShadowBackend::setVersionJavaMode(const QString& versionId, int mode) {
    m_settings->setVersionJavaMode(versionId, mode);
}

int ShadowBackend::versionJvmArgsMode(const QString& versionId) const {
    return m_settings->versionJvmArgsMode(versionId);
}
void ShadowBackend::setVersionJvmArgsMode(const QString& versionId, int mode) {
    m_settings->setVersionJvmArgsMode(versionId, mode);
}
QString ShadowBackend::versionJvmArgs(const QString& versionId) const {
    return m_settings->versionJvmArgs(versionId);
}
void ShadowBackend::setVersionJvmArgs(const QString& versionId, const QString& args) {
    m_settings->setVersionJvmArgs(versionId, args);
    emit versionLaunchSettingsChanged(versionId);
}
QString ShadowBackend::resolvedJvmArgs(const QString& versionId) const {
    if (versionJvmArgsMode(versionId) == 1)
        return versionJvmArgs(versionId);
    return m_app->jvmArgs();
}

int ShadowBackend::versionGameArgsMode(const QString& versionId) const {
    return m_settings->versionGameArgsMode(versionId);
}
void ShadowBackend::setVersionGameArgsMode(const QString& versionId, int mode) {
    m_settings->setVersionGameArgsMode(versionId, mode);
}
QString ShadowBackend::versionGameArgs(const QString& versionId) const {
    return m_settings->versionGameArgs(versionId);
}
void ShadowBackend::setVersionGameArgs(const QString& versionId, const QString& args) {
    m_settings->setVersionGameArgs(versionId, args);
    emit versionLaunchSettingsChanged(versionId);
}
QString ShadowBackend::resolvedGameArgs(const QString& versionId) const {
    if (versionGameArgsMode(versionId) == 1)
        return versionGameArgs(versionId);
    return m_app->gameArgs();
}

int ShadowBackend::versionHighPerfGpuMode(const QString& versionId) const {
    return m_settings->versionHighPerfGpuMode(versionId);
}
void ShadowBackend::setVersionHighPerfGpuMode(const QString& versionId, int mode) {
    m_settings->setVersionHighPerfGpuMode(versionId, mode);
}
bool ShadowBackend::versionHighPerfGpu(const QString& versionId) const {
    return m_settings->versionHighPerfGpu(versionId);
}
void ShadowBackend::setVersionHighPerfGpu(const QString& versionId, bool v) {
    m_settings->setVersionHighPerfGpu(versionId, v);
    emit versionLaunchSettingsChanged(versionId);
}
bool ShadowBackend::resolvedHighPerfGpu(const QString& versionId) const {
    if (versionHighPerfGpuMode(versionId) == 1)
        return versionHighPerfGpu(versionId);
    return m_app->highPerfGpu();
}

// ============================================================
// Q_INVOKABLE methods — Resource
// ============================================================

void ShadowBackend::searchModsEx(const QString& query, const QString& loader,
    const QString& category, const QString& gameVersion,
    const QString& environment, const QString& license,
    int offset, int limit, const QString& source) {
    QStringList versions;
    if (!gameVersion.isEmpty())
        versions << gameVersion;
    m_resource->searchModsEx(query, loader, category, versions,
                             environment, license, offset, limit, source);
}

QVariantMap ShadowBackend::resourcePoolState(const QString& kind) const
{
    if (!m_resource) return {};
    return m_resource->resourcePoolState(kind);
}

void ShadowBackend::searchShadersEx(const QString& query, const QStringList& gameVersions,
    const QStringList& categories, const QStringList& performance,
    const QStringList& loader, int offset, int limit, const QString& source) {
    m_resource->searchShadersEx(query, gameVersions, categories, performance, loader, offset, limit, source);
}

// 翻页预取：只预热缓存，不产生聚合信号
void ShadowBackend::prefetchModsEx(const QString& query, const QString& loader,
    const QString& category, const QStringList& gameVersions,
    int offset, int limit, const QString& source) {
    m_resource->prefetchModsEx(query, loader, category, gameVersions, offset, limit, source);
}

void ShadowBackend::prefetchShadersEx(const QString& query, const QStringList& gameVersions,
    const QStringList& categories, int offset, int limit, const QString& source) {
    m_resource->prefetchShadersEx(query, gameVersions, categories, offset, limit, source);
}

void ShadowBackend::prefetchResourcepacks(const QString& query, const QString& gameVersion,
    int offset, const QStringList& categories, const QString& source) {
    m_resource->prefetchResourcepacks(query, gameVersion, categories, offset, 20, source);
}

void ShadowBackend::searchResourcepacks(const QString& query, const QString& gameVersion, int offset, const QStringList& categories, const QString& source) {
    m_resource->searchResourcepacks(query, gameVersion, offset, categories, source);
}

void ShadowBackend::fetchResourcepackVersions(const QStringList& slugs) {
    m_resource->fetchResourcepackVersions(slugs);
}

void ShadowBackend::fetchModVersions(const QStringList& slugs) {
    m_resource->fetchModVersions(slugs);
}

void ShadowBackend::fetchShaderVersions(const QStringList& slugs) {
    m_resource->fetchShaderVersions(slugs);
}

// CurseForge 详情页版本转发（复用 modVersionsPartial 等信号）
void ShadowBackend::fetchModVersionsCf(const QString& modId, const QString& gameVersion, const QString& loader) {
    m_resource->fetchModVersionsCf(modId, gameVersion, loader);
}

void ShadowBackend::fetchShaderVersionsCf(const QString& modId, const QString& gameVersion, const QString& loader) {
    m_resource->fetchShaderVersionsCf(modId, gameVersion, loader);
}

void ShadowBackend::fetchResourcepackVersionsCf(const QString& modId, const QString& gameVersion, const QString& loader) {
    m_resource->fetchResourcepackVersionsCf(modId, gameVersion, loader);
}

QString ShadowBackend::resolveModZh(const QString& title) const {
    return m_resource->resolveModZh(title);
}

QVariantMap ShadowBackend::resolveProjectLinks(const QString& title, const QString& slug, const QString& kind) const {
    if (!m_resource) return {};
    return m_resource->resolveProjectLinks(title, slug, kind);
}

// ── 整合包：双源搜索 / 详情版本 / 下载→自动导入 ──
void ShadowBackend::searchModpacksEx(const QString& query, const QString& loader,
    const QString& category, const QStringList& gameVersions,
    int offset, int limit, const QString& source) {
    m_resource->searchModpacksEx(query, loader, category, gameVersions, offset, limit, source);
}

void ShadowBackend::fetchModpackVersions(const QString& slug, const QString& gameVersion, const QString& loader) {
    m_resource->fetchModpackVersions(slug, gameVersion, loader);
}

void ShadowBackend::prefetchModpacks(const QString& query, const QString& loader,
    const QString& category, const QStringList& gameVersions,
    int offset, int limit, const QString& source) {
    m_resource->prefetchModpacks(query, loader, category, gameVersions, offset, limit, source);
}

// ── 数据包：双源搜索 / 翻页预取 ──
void ShadowBackend::searchDatapacksEx(const QString& query, const QString& category,
    const QStringList& gameVersions, const QString& sort,
    int offset, int limit, const QString& source) {
    m_resource->searchDatapacksEx(query, category, gameVersions, sort, offset, limit, source);
}

void ShadowBackend::prefetchDatapacks(const QString& query, const QString& category,
    const QStringList& gameVersions, const QString& sort,
    int offset, int limit, const QString& source) {
    m_resource->prefetchDatapacks(query, category, gameVersions, sort, offset, limit, source);
}

// ── Mod file download proxy ──
int ShadowBackend::downloadModFile(const QString& url, const QString& savePath,
                                    const QString& displayName, qint64 expectedSize,
                                    const QString& sha1, qint64 receivedOffset, int resumeId) {
    return m_resource->downloadModFile(url, savePath, displayName, expectedSize, sha1, receivedOffset, resumeId);
}
void ShadowBackend::cancelModFileDownload(int downloadId) {
    if (m_packDownloads.contains(downloadId)) {
        m_packDownloads.remove(downloadId);
        m_packDownloading = false;   // 取消整合包下载 → 释放单任务占位
    }
    m_resource->cancelModFileDownload(downloadId);
}

void ShadowBackend::pauseModFileDownload(int downloadId) {
    m_resource->pauseModFileDownload(downloadId);
}

void ShadowBackend::resumeModFileDownload(int downloadId) {
    m_resource->resumeModFileDownload(downloadId);
}

void ShadowBackend::retryModFileDownload(int downloadId) {
    m_resource->retryModFileDownload(downloadId);
}

// ── 2026-08-15：版本级前置依赖（详情页悬停 tooltip）──
void ShadowBackend::fetchVersionDependencies(const QString& slug, const QString& versionId) {
    m_resource->fetchVersionDependencies(slug, versionId);
}

void ShadowBackend::fetchVersionFile(const QString& versionId) {
    m_resource->fetchVersionFile(versionId);
}

// 2026-11-25 审计：CF 前置依赖的入口补转发（此前只有 ResourceBackend 有，
// QML 侧 `backend.fetchCfDependencies` 为 undefined，详情页 CF 前置永不出现）。
void ShadowBackend::fetchCfDependencies(const QString& modId) {
    m_resource->fetchCfDependencies(modId);
}

void ShadowBackend::resolveCfDependencies(const QString& modId, const QVariantList& deps) {
    m_resource->resolveCfDependencies(modId, deps);
}

// ═══ Wardrobe (衣帽间) ═══

void ShadowBackend::initCapeCache() {
    if (!m_capeCache.isEmpty()) return;

    struct CapeEntry { QString name; QString file; };
    QList<CapeEntry> capes = {
        {QStringLiteral("15th Anniversary"), QStringLiteral("15th_anniversary.png")},
        {QStringLiteral("Builder"), QStringLiteral("builder.png")},
        {QStringLiteral("Cherry Blossom"), QStringLiteral("cherry_blossom.png")},
        {QStringLiteral("Common"), QStringLiteral("common.png")},
        {QStringLiteral("Copper"), QStringLiteral("copper.png")},
        {QStringLiteral("Follower's"), QStringLiteral("followers.png")},
        {QStringLiteral("Founder's"), QStringLiteral("founders.png")},
        {QStringLiteral("Home"), QStringLiteral("home.png")},
        {QStringLiteral("MCC 15th Year"), QStringLiteral("mcc_15th_year.png")},
        {QStringLiteral("Menace"), QStringLiteral("menace.png")},
        {QStringLiteral("Migrator"), QStringLiteral("migrator.png")},
        {QStringLiteral("MineCon 2011"), QStringLiteral("minecon_2011.png")},
        {QStringLiteral("MineCon 2012"), QStringLiteral("minecon_2012.png")},
        {QStringLiteral("MineCon 2013"), QStringLiteral("minecon_2013.png")},
        {QStringLiteral("MineCon 2015"), QStringLiteral("minecon_2015.png")},
        {QStringLiteral("MineCon 2016"), QStringLiteral("minecon_2016.png")},
        {QStringLiteral("MC Experience"), QStringLiteral("minecraft_experience.png")},
        {QStringLiteral("Mojang"), QStringLiteral("mojang.png")},
        {QStringLiteral("Mojang Studios"), QStringLiteral("mojang_studios.png")},
        {QStringLiteral("Pan"), QStringLiteral("pan.png")},
        {QStringLiteral("Purple Heart"), QStringLiteral("purple_heart.png")},
        {QStringLiteral("Mapmaker"), QStringLiteral("realms_mapmaker.png")},
        {QStringLiteral("Translator CN"), QStringLiteral("translator_chinese.png")},
        {QStringLiteral("Vanilla"), QStringLiteral("vanilla.png")},
        {QStringLiteral("Yearn"), QStringLiteral("yearn.png")},
        {QStringLiteral("Zombie Horse"), QStringLiteral("zombie_horse.png")},
    };

    for (const auto& entry : capes) {
        QVariantMap m;
        m[QStringLiteral("name")] = entry.name;
        m[QStringLiteral("preview")] = QStringLiteral("qrc:/qt/qml/ShadowLauncher/resources/capes/") + entry.file;
        m[QStringLiteral("url")] = entry.name;
        m_capeCache.append(m);
    }
}

QVariantList ShadowBackend::availableCapes() const {
    const_cast<ShadowBackend*>(this)->initCapeCache();
    return m_capeCache;
}

QString ShadowBackend::loginType() const {
    switch (activeAccountMode()) {
    case 0: return QStringLiteral("microsoft");
    case 2: return QStringLiteral("yggdrasil");
    default: return QStringLiteral("offline");
    }
}

void ShadowBackend::browseSkin() {
    QString file = QFileDialog::getOpenFileName(nullptr, tr("选择皮肤图片"), QString(),
        tr("PNG 图片 (*.png)"));
    if (file.isEmpty()) return;

    // Validate PNG dimensions (64x64 or 64x32)
    QImage img(file);
    if (img.isNull()) {
        emit wardrobeError(tr("无法读取图片"));
        return;
    }
    int w = img.width();
    int h = img.height();
    bool valid = (w == 64 && h == 64) || (w == 64 && h == 32);
    if (!valid) {
        emit wardrobeError(tr("皮肤尺寸必须为 64x64 或 64x32，当前为 %1x%2").arg(w).arg(h));
        return;
    }

    m_selectedSkinPath = file;
    emit logMessage(tr("已选择皮肤: %1 (%2x%3)").arg(file).arg(w).arg(h));
    emit skinChanged();
}

void ShadowBackend::uploadSkin(const QString& skinPath, int modelType) {
    if (skinPath.isEmpty()) return;
    if (!m_account) {
        emit wardrobeError(tr("账户后端未就绪"));
        return;
    }
    // 统一走 AccountBackend：那边用官方 multipart 上传，成功后 downloadSkin() 重新拉取皮肤，
    // 头像/皮肤贴图才会真的变。旧实现在这里另写了一套 JSON + base64 data URL，
    // 成功后不刷新任何东西 → 表现就是"选完文件换不了皮肤"。
    const QString variant = (modelType == 2) ? QStringLiteral("slim") : QStringLiteral("classic");
    m_wardrobeBusy = true;
    emit wardrobeBusyChanged();
    m_account->uploadSkin(skinPath, variant);
}

void ShadowBackend::saveWardrobeSettings(const QString& skinPath, const QString& capeId, int modelType) {
    qCInfo(logApp) << QStringLiteral("衣帽间保存 skin=%1 cape=%2 model=%3").arg(skinPath, capeId).arg(modelType);

    if (activeAccountMode() == 0 && m_account && !m_account->mcToken().isEmpty()) {
        // Online: upload to Mojang
        if (!skinPath.isEmpty()) {
            uploadSkin(skinPath, modelType);
        }
        if (!capeId.isEmpty()) {
            // 披风切换走 AccountBackend::selectCape（PATCH /minecraft/profile/capes/active），
            // 走 aliases/ID 都可；这里保留旧入口做兼容。
            m_account->selectCape(capeId);
        }
    } else {
        // 离线账号没有皮肤服务：旧代码把 PNG 拷到 <数据目录>/skins/custom_skin.png，
        // 但全仓库没有任何地方读这个文件，头像渲染走的是 UUID 哈希 → 等于什么也没发生。
        // 与其假装成功，不如直说。
        emit wardrobeError(tr("离线账号无法更换皮肤（仅正版账号支持上传）"));
    }
}

// ────────────────────────────────────────────────────────────
// Save Skin To File (user-chosen destination via file dialog)
// ────────────────────────────────────────────────────────────

void ShadowBackend::saveSkinToFile()
{
    if (!m_account) {
        emit wardrobeError(tr("未就绪"));
        return;
    }

    // Online mode: fetch fresh full skin from Mojang API
    if (m_account->isOnline()) {
        qCInfo(logApp) << QStringLiteral("在线保存皮肤: 正在从Mojang获取最新皮肤");
        qCInfo(logApp) << QStringLiteral("正在获取最新皮肤...");

        QNetworkRequest req(QUrl(QStringLiteral("https://api.minecraftservices.com/minecraft/profile")));
        req.setRawHeader("Authorization",
            QStringLiteral("Bearer %1").arg(m_account->mcToken()).toUtf8());

        QNetworkReply* profileReply = HttpClient::instance().getRaw(req);
        connect(profileReply, &QNetworkReply::finished, this, [this, profileReply]() {
            profileReply->deleteLater();

            if (profileReply->error() != QNetworkReply::NoError) {
                emit wardrobeError(tr("获取皮肤信息失败: %1").arg(profileReply->errorString()));
                return;
            }

            QJsonDocument doc = QJsonDocument::fromJson(profileReply->readAll());
            QJsonArray skins = doc.object()[QStringLiteral("skins")].toArray();

            QString skinUrl;
            for (const QJsonValue& sv : skins) {
                QJsonObject s = sv.toObject();
                if (s[QStringLiteral("state")].toString() == QStringLiteral("ACTIVE")) {
                    skinUrl = s[QStringLiteral("url")].toString();
                    break;
                }
            }

            if (skinUrl.isEmpty()) {
                emit wardrobeError(tr("未找到活跃皮肤"));
                return;
            }

            qCInfo(logApp) << QStringLiteral("正在下载皮肤纹理: ") << skinUrl;
            QNetworkRequest skinReq(skinUrl);
            QNetworkReply* skinReply = HttpClient::instance().getRaw(skinReq);
            connect(skinReply, &QNetworkReply::finished, this, [this, skinReply]() {
                skinReply->deleteLater();

                if (skinReply->error() != QNetworkReply::NoError) {
                    emit wardrobeError(tr("皮肤纹理下载失败: %1").arg(skinReply->errorString()));
                    return;
                }

                QByteArray skinData = skinReply->readAll();

                QString dest = QFileDialog::getSaveFileName(nullptr, tr("保存皮肤文件"),
                    QStringLiteral("skin.png"), tr("PNG 图片 (*.png)"));
                if (dest.isEmpty()) return;

                QFile file(dest);
                if (file.open(QIODevice::WriteOnly)) {
                    file.write(skinData);
                    file.close();
                    qCInfo(logApp) << QStringLiteral("皮肤已在线保存到: ") << dest;
                    emit wardrobeError(tr("皮肤已保存到: %1").arg(dest));
                } else {
                    emit wardrobeError(tr("保存失败: %1").arg(dest));
                }
            });
        });
        return;
    }

    // Offline mode: save local cached skin (fix file:/// prefix bug)
    QString srcPath;
    srcPath = m_account->offlineSkinPath();
    if (srcPath.isEmpty())
        srcPath = m_selectedSkinPath;

    // Resolve file:/// prefix before any QFile operations
    if (srcPath.startsWith(QStringLiteral("file:///")))
        srcPath = srcPath.mid(8);

    if (srcPath.isEmpty() || !QFile::exists(srcPath)) {
        emit wardrobeError(tr("没有可保存的皮肤"));
        return;
    }

    QString dest = QFileDialog::getSaveFileName(nullptr, tr("保存皮肤文件"),
        QStringLiteral("skin.png"), tr("PNG 图片 (*.png)"));
    if (dest.isEmpty()) return;

    if (QFile::copy(srcPath, dest)) {
        emit wardrobeError(tr("皮肤已保存到: %1").arg(dest));
    } else {
        // Try reading + writing if copy fails (e.g. across drives)
        QFile inFile(srcPath);
        if (inFile.open(QIODevice::ReadOnly)) {
            QByteArray data = inFile.readAll();
            inFile.close();
            QFile outFile(dest);
            if (outFile.open(QIODevice::WriteOnly)) {
                outFile.write(data);
                outFile.close();
                emit wardrobeError(tr("皮肤已保存到: %1").arg(dest));
                return;
            }
        }
        emit wardrobeError(tr("保存失败: %1").arg(dest));
    }
}

// ============================================================
// fetchResourcepackVersions
// Q_INVOKABLE methods — App
// ============================================================

void ShadowBackend::setTheme(const QString& theme) {
    m_app->setTheme(theme);
}


// ============================================================
// Q_INVOKABLE methods — Version management
// ============================================================

void ShadowBackend::verifyVersion(const QString& versionId) {
    m_version->verifyVersion(versionId);
}

void ShadowBackend::cleanCorruptVersion(const QString& versionId) {
    m_version->cleanCorruptVersion(versionId);
}

bool ShadowBackend::renameVersion(const QString& oldId, const QString& newId) {
    return m_version->renameVersion(oldId, newId);
}

bool ShadowBackend::cloneVersion(const QString& sourceId, const QString& newId) {
    return m_version->cloneVersion(sourceId, newId);
}

bool ShadowBackend::cloneVersion(const QString& sourceId) {
    // Auto-generate name: "1.21.6-fabric-0.19.3 (\u526f\u672c)"
    QString newId = sourceId + QString::fromUtf8(" (\u526f\u672c)");
    return m_version->cloneVersion(sourceId, newId);
}

bool ShadowBackend::renameVersion(const QString& oldId) {
    // Single-param: called from QML with just oldId — QML shows rename dialog
    qDebug() << "[renameVersion] single-param stub called for" << oldId << "– QML should show dialog";
    return false;
}

void ShadowBackend::migrateVersion(const QString& versionId) {
    qDebug() << "[migrateVersion]" << versionId;
    m_settings->migrateVersionToIsolated(versionId);
}

QString ShadowBackend::copyVersionPath(const QString& versionId) {
    return m_version->copyVersionPath(versionId);
}

void ShadowBackend::repairVersion(const QString& versionId) {
    m_version->repairVersion(versionId);
}

QString ShadowBackend::verifyResultText() const { return m_verifyResultText; }
bool ShadowBackend::verifyResultOk() const { return m_verifyResultOk; }
void ShadowBackend::setVerifyResult(const QString& text, bool ok) {
    m_verifyResultText = text;
    m_verifyResultOk = ok;
    emit verifyResultTextChanged();
}

void ShadowBackend::cancelVerify() {
    if (m_version) m_version->cancelVerify();
}

void ShadowBackend::openVerifyReport() {
    if (!m_verifyReportPath.isEmpty() && QFile::exists(m_verifyReportPath)) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_verifyReportPath));
    }
}

// ============================================================
// Q_INVOKABLE methods — Check
// ============================================================

QVariantMap ShadowBackend::checkAll(const QString& versionId) {
    return m_check->checkAll(versionId,
                             m_settings->javaPath(),
                             m_settings->maxMemoryMB(),
                             m_app->gameDir());
}

// ============================================================
// Q_INVOKABLE methods — Clipboard
// ============================================================

void ShadowBackend::copyToClipboard(const QString& text)
{
    QClipboard* clipboard = QGuiApplication::clipboard();
    if (clipboard) {
        clipboard->setText(text);
    }
}

// ============================================================
// Mod Loader version queries (BMCLAPI)
// ============================================================

static void queryModLoaderApi(ShadowBackend* self, const QString& url,
                               const QString& loaderName,
                               std::function<QVariantList(const QByteArray&)> parseFn,
                               std::function<void(const QVariantList&)> emitFn) {
    // Fire request immediately (no throttling needed)
    QTimer::singleShot(0, self, [=]() {
        auto* mgr = new QNetworkAccessManager(self);
    QUrl qurl(url);
    QNetworkRequest req(qurl);
    req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply* reply = mgr->get(req);
    qCInfo(logApp) << QStringLiteral("[加载器] 查询版本列表 加载器=%1 url=%2").arg(loaderName, url);

    // Track for cancellation
    self->m_modLoaderReplies.append(reply);

    QObject::connect(reply, &QNetworkReply::finished, self, [self, reply, mgr, loaderName, parseFn, emitFn]() {
        // Remove from tracking
        self->m_modLoaderReplies.removeAll(reply);

        if (self->m_modLoaderQueriesCancelled) {
            qCInfo(logApp) << QStringLiteral("[加载器] 查询已取消 加载器=%1").arg(loaderName);
            reply->deleteLater();
            mgr->deleteLater();
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(logApp) << QStringLiteral("[加载器] 查询失败 加载器=%1 错误=%2").arg(loaderName, reply->errorString());
            reply->deleteLater();
            mgr->deleteLater();
            emitFn({});
            return;
        }
        QByteArray data = reply->readAll();
        reply->deleteLater();
        mgr->deleteLater();
        qCInfo(logApp) << QStringLiteral("[加载器] 获取版本数据 加载器=%1 大小=%2字节").arg(loaderName).arg(data.size());
        QVariantList list = parseFn(data);
        qCInfo(logApp) << QStringLiteral("[加载器] 解析版本完成 加载器=%1 版本数=%2").arg(loaderName).arg(list.size());
        emitFn(list);
    });
    });  // QTimer::singleShot
}

// ── Forge 官方 HTML 版本列表解析 ──
// URL: https://files.minecraftforge.net/maven/net/minecraftforge/forge/index_{mcVer}.html
// 注意：- 需要替换为 _（兼容 1.7.10-pre4 等版本）
static QVariantList parseForgeOfficialVersions(const QByteArray& html, const QString& filterMc) {
    QString text = QString::fromUtf8(html);
    if (text.length() < 1000) return {};

    QVariantList result;

    // Split by <td class="download-version" to get individual version blocks
    QStringList versionBlocks = text.split(QStringLiteral("<td class=\"download-version"));
    // First element is before the first version block
    for (int blockIdx = 1; blockIdx < versionBlocks.size(); ++blockIdx) {
        const QString& block = versionBlocks[blockIdx];

        // Extract version name: e.g. "50.1.9"
        QRegularExpression nameRe(QStringLiteral("[0-9]+(?:\\.[0-9]+)+"));
        QString versionName;
        QRegularExpressionMatch nameMatch = nameRe.match(block);
        if (nameMatch.hasMatch())
            versionName = nameMatch.captured();
        if (versionName.isEmpty()) continue;

        bool isRecommended = block.contains(QStringLiteral("fa promo-recommended"));

        // Extract branch from URL: e.g. "forge-50.1.9-1.10.0-installer.jar" → "1.10.0"
        QString branch;
        QRegularExpression branchRe(QStringLiteral("-") + QRegularExpression::escape(versionName) + QStringLiteral("-([^\"]+?)(?=-[a-z]+\\.[a-z]{3})"));
        QRegularExpressionMatch branchMatch = branchRe.match(block);
        if (branchMatch.hasMatch())
            branch = branchMatch.captured(1);
        // 已知有问题的特殊版本
        if (versionName == QStringLiteral("11.15.1.2318") ||
            versionName == QStringLiteral("11.15.1.1902") ||
            versionName == QStringLiteral("11.15.1.1890"))
            branch = QStringLiteral("1.8.9");
        if (branch.isEmpty() && filterMc == QStringLiteral("1.7.10")) {
            // For 1.7.10, branch is needed when version's fourth segment >= 1300
            QStringList vParts = versionName.split(QLatin1Char('.'));
            if (vParts.size() >= 4 && vParts[3].toInt() >= 1300)
                branch = QStringLiteral("1.7.10");
        }

        // Extract release time: e.g. "2021-02-15 03:24:02"
        QRegularExpression timeRe(QStringLiteral("(?<=download-time\" title=\")[^\"]+"));
        QString releaseTime;
        QRegularExpressionMatch timeMatch = timeRe.match(block);
        if (timeMatch.hasMatch()) {
            QString orig = timeMatch.captured();
            // Convert "2021-02-15 03:24:02" → "2021-02-15"
            releaseTime = orig.left(10);
        }

        // Determine category and extract hash
        QString category;
        QString fileHash;
        if (block.contains(QStringLiteral("classifier-installer\""))) {
            // installer.jar
            QString sub = block.mid(block.indexOf(QStringLiteral("installer.jar")));
            QRegularExpression hashRe(QStringLiteral("(?<=MD5:</strong> )[^<]+"));
            QRegularExpressionMatch hashMatch = hashRe.match(sub);
            if (hashMatch.hasMatch())
                fileHash = hashMatch.captured().trimmed();
            category = QStringLiteral("installer");
        } else if (block.contains(QStringLiteral("classifier-universal\""))) {
            QString sub = block.mid(block.indexOf(QStringLiteral("universal.zip")));
            QRegularExpression hashRe(QStringLiteral("(?<=MD5:</strong> )[^<]+"));
            QRegularExpressionMatch hashMatch = hashRe.match(sub);
            if (hashMatch.hasMatch())
                fileHash = hashMatch.captured().trimmed();
            category = QStringLiteral("universal");
        } else if (block.contains(QStringLiteral("client.zip"))) {
            QString sub = block.mid(block.indexOf(QStringLiteral("client.zip")));
            QRegularExpression hashRe(QStringLiteral("(?<=MD5:</strong> )[^<]+"));
            QRegularExpressionMatch hashMatch = hashRe.match(sub);
            if (hashMatch.hasMatch())
                fileHash = hashMatch.captured().trimmed();
            category = QStringLiteral("client");
        } else {
            // No downloadable file for this entry
            continue;
        }

        // 对齐 主流启动器：只保留 installer 类别（universal/client 无法自动安装）2026-08-07
        if (category != QStringLiteral("installer")) continue;

        QVariantMap m;
        m[QStringLiteral("version")] = versionName;
        m[QStringLiteral("type")] = isRecommended ? QStringLiteral("recommended") : QStringLiteral("release");
        m[QStringLiteral("date")] = releaseTime;
        m[QStringLiteral("branch")] = branch;
        m[QStringLiteral("category")] = category;
        m[QStringLiteral("hash")] = fileHash;
        result.append(m);
    }

    return result;
}

// ── Forge BMCLAPI JSON 解析（抽取为独立函数供双源复用）──
static QVariantList parseForgeBmclapiVersions(const QByteArray& data, const QString& mcVersion,
                                                std::function<void(const QString&, const QString&, const QString&)> cacheBranchFn) {
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray()) return {};
    QJsonArray arr = doc.array();
    QVariantList list;
    for (const QJsonValue& v : arr) {
        QJsonObject obj = v.toObject();
        QString ver = obj.value(QStringLiteral("version")).toString();
        if (ver.isEmpty()) continue;
        QString date = obj.value(QStringLiteral("modified")).toString().left(10);
        QString installerSha1;
        bool hasInstaller = false;
        if (obj.contains(QStringLiteral("files"))) {
            for (const QJsonValue& fv : obj[QStringLiteral("files")].toArray()) {
                QJsonObject f = fv.toObject();
                const QString cat = f.value(QStringLiteral("category")).toString();
                if (cat == QStringLiteral("installer")) {
                    installerSha1 = f.value(QStringLiteral("hash")).toString();
                    hasInstaller = true;
                    break;
                }
            }
        }
        // 对齐 主流启动器（PageDownloadInstall L724/757）：只保留 installer 类别，
        // universal/client（1.6.1 及更早）无法自动安装 → 直接过滤（2026-08-07）
        if (!hasInstaller) continue;
        QString branch = obj.value(QStringLiteral("branch")).toString();
        if (!branch.isEmpty() && cacheBranchFn)
            cacheBranchFn(mcVersion, ver, branch);
        QVariantMap m;
        m[QStringLiteral("version")] = ver;
        m[QStringLiteral("type")] = QStringLiteral("release");
        m[QStringLiteral("date")] = date;
        if (!installerSha1.isEmpty())
            m[QStringLiteral("installerSha1")] = installerSha1;
        m[QStringLiteral("branch")] = branch;
        list.append(m);
    }
    return list;
}

void ShadowBackend::queryForgeVersions(const QString& mcVersion) {
    m_modLoaderQueriesCancelled = false;

    // 1.5 及更早（1.0~1.5.x）：老式 Forge 安装格式，FML 4.x 运行时依赖 fmllibs
    // （argo-2.25/guava-12.0.1/asm-all-4.0/bcprov-jdk15on-147 等），官方源
    // files.minecraftforge.net/fmllibs/ 已死（404 实测）→ 装完也启动不了。
    // 从根源杜绝：列表层直接过滤（对齐 主流启动器，2026-08-07）
    static const QRegularExpression legacyForgeVer(QStringLiteral(R"(^1\.[0-5](?:\.|$))"));
    if (legacyForgeVer.match(mcVersion).hasMatch()) {
        qCInfo(logApp) << QStringLiteral("[加载器] Forge 版本列表过滤: MC %1（1.5 及更早不支持自动安装）").arg(mcVersion);
        emit forgeVersionsReady(QVariantList());
        return;
    }

    struct SourceReq { bool done = false; QByteArray data; };
    struct DualState { SourceReq bmcl; SourceReq official; bool parsedBmcl = false; bool parsedOfficial = false; QVariantList bmclResult; QVariantList officialResult; bool emitted = false; };
    auto state = std::make_shared<DualState>();

    // Capture this for the BMCLAPI parser lambda (ShadowBackend member)
    auto cacheBranch = [this](const QString& mc, const QString& ver, const QString& branch) {
        cacheForgeInstallerBranch(mc, ver, branch);
    };

    auto checkSourceComplete = [this, state, mcVersion, cacheBranch](bool isBmcl) {
        if (state->emitted) return;
        SourceReq& src = isBmcl ? state->bmcl : state->official;
        if (!src.done) return;

        QVariantList list;
        if (isBmcl) {
            list = parseForgeBmclapiVersions(src.data, mcVersion, cacheBranch);
            state->bmclResult = list;
            state->parsedBmcl = true;
        } else {
            list = parseForgeOfficialVersions(src.data, mcVersion);
            state->officialResult = list;
            state->parsedOfficial = true;
        }

        if (!list.isEmpty()) {
            state->emitted = true;
            // Cache branch info from official source results too
            if (!isBmcl) {
                for (const QVariant& v : list) {
                    QVariantMap m = v.toMap();
                    QString ver = m.value(QStringLiteral("version")).toString();
                    QString branch = m.value(QStringLiteral("branch")).toString();
                    if (!ver.isEmpty() && !branch.isEmpty())
                        cacheForgeInstallerBranch(mcVersion, ver, branch);
                }
            }
            emit forgeVersionsReady(list);
            return;
        }
        bool otherParsed = isBmcl ? state->parsedOfficial : state->parsedBmcl;
        if (otherParsed) {
            state->emitted = true;
            const QVariantList& otherResult = isBmcl ? state->officialResult : state->bmclResult;
            emit forgeVersionsReady(otherResult.isEmpty() ? QVariantList() : otherResult);
        }
    };

    auto fireRequest = [this, state, checkSourceComplete, &mcVersion](bool isBmcl) {
        // Official URL: replace - with _ for versions like 1.7.10-pre4
        QString mcSanitized = mcVersion;
        mcSanitized.replace(QLatin1Char('-'), QLatin1Char('_'));

        QString url = isBmcl
            ? QStringLiteral("https://bmclapi2.bangbang93.com/forge/minecraft/") + mcVersion
            : QStringLiteral("https://files.minecraftforge.net/maven/net/minecraftforge/forge/index_") + mcSanitized + QStringLiteral(".html");

        auto* mgr = new QNetworkAccessManager(this);
        QNetworkRequest req{QUrl(url)};
        req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply* reply = mgr->get(req);
        qCInfo(logApp) << QStringLiteral("[加载器] 查询版本列表 加载器=Forge url=%1").arg(url);
        m_modLoaderReplies.append(reply);

        QObject::connect(reply, &QNetworkReply::finished, this,
            [this, reply, mgr, isBmcl, state, checkSourceComplete]() {
                m_modLoaderReplies.removeAll(reply);
                if (m_modLoaderQueriesCancelled) {
                    qCInfo(logApp) << QStringLiteral("[加载器] 查询已取消 加载器=Forge");
                    reply->deleteLater(); mgr->deleteLater(); return;
                }
                if (reply->error() != QNetworkReply::NoError) {
                    qCWarning(logApp) << QStringLiteral("[加载器] 查询失败 加载器=Forge 源=%1 错误=%2")
                        .arg(isBmcl ? QStringLiteral("BMCLAPI") : QStringLiteral("官方"))
                        .arg(reply->errorString());
                } else {
                    SourceReq& src = isBmcl ? state->bmcl : state->official;
                    src.data = reply->readAll();
                    qCInfo(logApp) << QStringLiteral("[加载器] 获取版本数据 加载器=Forge 源=%1 大小=%2字节")
                        .arg(isBmcl ? QStringLiteral("BMCLAPI") : QStringLiteral("官方"))
                        .arg(src.data.size());
                }
                SourceReq& src = isBmcl ? state->bmcl : state->official;
                src.done = true;
                reply->deleteLater();
                mgr->deleteLater();
                checkSourceComplete(isBmcl);
            });
    };

    fireRequest(true);
    fireRequest(false);
}

void ShadowBackend::queryFabricVersions(const QString& mcVersion) {
    m_modLoaderQueriesCancelled = false;

    struct SourceReq { bool done = false; QByteArray data; };
    struct DualState { SourceReq bmcl; SourceReq official; bool parsedBmcl = false; bool parsedOfficial = false; QVariantList bmclResult; QVariantList officialResult; bool emitted = false; };
    auto state = std::make_shared<DualState>();

    auto checkSourceComplete = [this, state](bool isBmcl) {
        if (state->emitted) return;
        SourceReq& src = isBmcl ? state->bmcl : state->official;
        if (!src.done) return;

        // Parse Fabric versions (same JSON format for both BMCLAPI and official)
        QJsonDocument doc = QJsonDocument::fromJson(src.data);
        QJsonArray arr;
        if (doc.isArray()) {
            arr = doc.array();
        } else if (doc.isObject()) {
            arr = doc.object().value(QStringLiteral("versions")).toArray();
        }

        QVariantList list;
        for (const QJsonValue& v : arr) {
            QJsonObject obj = v.toObject();
            QJsonObject loader = obj.value(QStringLiteral("loader")).toObject();
            QString ver = loader.value(QStringLiteral("version")).toString();
            if (ver.isEmpty()) continue;
            bool stable = loader.value(QStringLiteral("stable")).toBool(true);
            QVariantMap m;
            m[QStringLiteral("version")] = ver;
            m[QStringLiteral("type")] = stable ? QStringLiteral("release") : QStringLiteral("beta");
            m[QStringLiteral("date")] = QString();
            list.append(m);
        }

        if (isBmcl) {
            state->bmclResult = list;
            state->parsedBmcl = true;
        } else {
            state->officialResult = list;
            state->parsedOfficial = true;
        }

        if (!list.isEmpty()) {
            state->emitted = true;
            emit fabricVersionsReady(list);
            return;
        }
        // This source returned empty; check if the other source is ready
        bool otherParsed = isBmcl ? state->parsedOfficial : state->parsedBmcl;
        if (otherParsed) {
            state->emitted = true;
            const QVariantList& otherResult = isBmcl ? state->officialResult : state->bmclResult;
            emit fabricVersionsReady(otherResult.isEmpty() ? QVariantList() : otherResult);
        }
    };

    auto fireRequest = [this, state, checkSourceComplete, &mcVersion](bool isBmcl) {
        QString url = isBmcl
            ? QStringLiteral("https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/") + mcVersion
            : QStringLiteral("https://meta.fabricmc.net/v2/versions/loader/") + mcVersion;

        auto* mgr = new QNetworkAccessManager(this);
        QNetworkRequest req{QUrl(url)};
        req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply* reply = mgr->get(req);
        qCInfo(logApp) << QStringLiteral("[加载器] 查询版本列表 加载器=Fabric url=%1").arg(url);
        m_modLoaderReplies.append(reply);

        QObject::connect(reply, &QNetworkReply::finished, this,
            [this, reply, mgr, isBmcl, state, checkSourceComplete]() {
                m_modLoaderReplies.removeAll(reply);
                if (m_modLoaderQueriesCancelled) {
                    qCInfo(logApp) << QStringLiteral("[加载器] 查询已取消 加载器=Fabric");
                    reply->deleteLater(); mgr->deleteLater(); return;
                }
                if (reply->error() != QNetworkReply::NoError) {
                    qCWarning(logApp) << QStringLiteral("[加载器] 查询失败 加载器=Fabric 源=%1 错误=%2")
                        .arg(isBmcl ? QStringLiteral("BMCLAPI") : QStringLiteral("官方"))
                        .arg(reply->errorString());
                } else {
                    SourceReq& src = isBmcl ? state->bmcl : state->official;
                    src.data = reply->readAll();
                    qCInfo(logApp) << QStringLiteral("[加载器] 获取版本数据 加载器=Fabric 源=%1 大小=%2字节")
                        .arg(isBmcl ? QStringLiteral("BMCLAPI") : QStringLiteral("官方"))
                        .arg(src.data.size());
                }
                SourceReq& src = isBmcl ? state->bmcl : state->official;
                src.done = true;
                reply->deleteLater();
                mgr->deleteLater();
                checkSourceComplete(isBmcl);
            });
    };

    fireRequest(true);
    fireRequest(false);
}


static QStringList parseNeoForgeApiNames(const QByteArray& data) {
    if (data.isEmpty()) return {};
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) return {};
    QJsonObject obj = doc.object();

    // Try official Maven API: {"versions": ["str", ...]}
    QJsonArray arr = obj.value(QStringLiteral("versions")).toArray();
    if (!arr.isEmpty()) {
        QStringList names;
        for (const QJsonValue& v : arr) {
            if (v.isString()) {
                QString n = v.toString();
                if (!n.isEmpty()) names.append(n);
            }
        }
        if (!names.isEmpty()) return names;
    }

    // Try BMCLAPI: {"files": [{"name": "str", ...}, ...]}
    arr = obj.value(QStringLiteral("files")).toArray();
    QStringList names;
    for (const QJsonValue& v : arr) {
        if (v.isObject()) {
            QString n = v.toObject().value(QStringLiteral("name")).toString();
            if (!n.isEmpty()) names.append(n);
        }
    }
    return names;
}

static QVariantList parseNeoForgeVersions(const QByteArray& latestData, const QByteArray& legacyData, const QString& filterMc) {
    QStringList versionNames = parseNeoForgeApiNames(latestData);
    versionNames.append(parseNeoForgeApiNames(legacyData));

    QVariantList result;
    for (const QString& apiName : versionNames) {
        bool isBeta = apiName.contains(QStringLiteral("beta"), Qt::CaseInsensitive)
                   || apiName.contains(QStringLiteral("alpha"), Qt::CaseInsensitive);
        QString versionName;
        QString inherit;

        // Format 1: Legacy 1.20.1-47.1.99
        if (apiName.contains(QStringLiteral("1.20.1"))) {
            versionName = apiName;
            versionName.replace(QStringLiteral("1.20.1-"), QString());
            inherit = QStringLiteral("1.20.1");
        }
        // Format 2: Experimental / snapshot 0.25w14craftmine.3-beta
        else if (apiName.startsWith(QStringLiteral("0."))) {
            versionName = apiName;
            QStringList segments = apiName.section(QLatin1Char('-'), 0, 0).split(QLatin1Char('.'));
            inherit = segments.value(1);
            if (inherit.isEmpty()) continue;
        }
        // Format 3: Standard 20.4.30-beta or 26.1.0.0-alpha
        else {
            versionName = apiName;
            QString verStr = apiName.section(QLatin1Char('-'), 0, 0);
            QStringList parts = verStr.split(QLatin1Char('.'));
            if (parts.size() < 3) continue;
            int major = parts[0].toInt();
            int minor = parts[1].toInt();
            if (major >= 24) {
                inherit = QStringLiteral("%1.%2").arg(major).arg(minor);
            } else {
                inherit = QStringLiteral("1.%1.%2").arg(major).arg(minor);
            }
            if (inherit.endsWith(QStringLiteral(".0")))
                inherit.chop(2);
        }

        if (inherit != filterMc) continue;

        QVariantMap m;
        m[QStringLiteral("version")] = versionName;
        m[QStringLiteral("type")] = isBeta ? QStringLiteral("beta") : QStringLiteral("release");
        m[QStringLiteral("date")] = QString();
        m[QStringLiteral("inherit")] = inherit;
        result.append(m);
    }
    return result;
}


void ShadowBackend::queryNeoForgeVersions(const QString& mcVersion) {
    m_modLoaderQueriesCancelled = false;

    struct SubReq { bool done = false; QByteArray data; };
    struct SourceState {
        SubReq latest; SubReq legacy; bool parsed = false; QVariantList result;
    };
    struct DualState { SourceState bmcl; SourceState official; bool emitted = false; };
    auto state = std::make_shared<DualState>();

    auto checkSourceComplete = [this, state, mcVersion](bool isBmcl) {
        if (state->emitted) return;
        SourceState& src = isBmcl ? state->bmcl : state->official;
        if (!src.latest.done || !src.legacy.done) return;
        if (src.parsed) return;
        src.parsed = true;
        src.result = parseNeoForgeVersions(src.latest.data, src.legacy.data, mcVersion);

        if (!src.result.isEmpty()) {
            state->emitted = true;
            emit neoforgeVersionsReady(src.result);
            return;
        }
        SourceState& other = isBmcl ? state->official : state->bmcl;
        if (other.parsed) {
            state->emitted = true;
            emit neoforgeVersionsReady(other.result.isEmpty() ? QVariantList() : other.result);
        }
    };

    auto fireSubRequest = [this, state, checkSourceComplete](bool isBmcl, bool isLatest) {
        QString url = isBmcl
            ? (isLatest
                ? QStringLiteral("https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/neoforge")
                : QStringLiteral("https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/forge"))
            : (isLatest
                ? QStringLiteral("https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge")
                : QStringLiteral("https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/forge"));

        auto* mgr = new QNetworkAccessManager(this);
        QNetworkRequest req{QUrl(url)};
        req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
        QNetworkReply* reply = mgr->get(req);
        m_modLoaderReplies.append(reply);

        QObject::connect(reply, &QNetworkReply::finished, this,
            [this, reply, mgr, isBmcl, isLatest, state, checkSourceComplete]() {
                m_modLoaderReplies.removeAll(reply);
                if (m_modLoaderQueriesCancelled) {
                    reply->deleteLater(); mgr->deleteLater(); return;
                }
                SubReq& sub = isBmcl
                    ? (isLatest ? state->bmcl.latest : state->bmcl.legacy)
                    : (isLatest ? state->official.latest : state->official.legacy);
                if (reply->error() == QNetworkReply::NoError)
                    sub.data = reply->readAll();
                sub.done = true;
                reply->deleteLater();
                mgr->deleteLater();
                checkSourceComplete(isBmcl);
            });
    };

    fireSubRequest(true, true);
    fireSubRequest(true, false);
    fireSubRequest(false, true);
    fireSubRequest(false, false);
}



// ── OptiFine HTML 官方源解析 ──

static QVariantList parseOptifineOfficialVersions(const QByteArray& html, const QString& filterMc) {
    QString text = QString::fromUtf8(html);
    if (text.length() < 200) return {};

    // Extract version names: e.g. "OptiFine_1.12.2_HD_U_C8.jar"
    QRegularExpression nameRe(QStringLiteral("OptiFine_([0-9A-Za-z_.]+)(?=\\.jar\")"));
    // Extract Forge compatibility: e.g. "Forge 61.0.8" or "Forge N/A"
    QRegularExpression forgeRe(QStringLiteral("(?<=colForge'>)[^<]*"));
    // Extract release dates: e.g. "2024.1.15"
    QRegularExpression dateRe(QStringLiteral("(?<=colDate'>)[^<]+"));

    QStringList names;
    QRegularExpressionMatchIterator ni = nameRe.globalMatch(text);
    while (ni.hasNext()) names.append(ni.next().captured(1));

    QStringList forgeStrs;
    QRegularExpressionMatchIterator fi = forgeRe.globalMatch(text);
    while (fi.hasNext()) forgeStrs.append(fi.next().captured());

    QStringList dates;
    QRegularExpressionMatchIterator di = dateRe.globalMatch(text);
    while (di.hasNext()) dates.append(di.next().captured());

    if (names.isEmpty()) return {};

    QVariantList result;
    int count = qMin(names.size(), qMin(forgeStrs.size(), dates.size()));
    if (count == 0) count = names.size();  // fallback if colCount mismatch

    for (int i = 0; i < names.size(); ++i) {
        QString rawName = names[i];  // e.g. "1.12.2_HD_U_C8"
        QString spaced = rawName;
        spaced.replace(QStringLiteral("_"), QStringLiteral(" "));  // "1.12.2 HD U C8"
        QStringList parts = spaced.split(QStringLiteral(" "));
        if (parts.isEmpty()) continue;
        QString inherit = parts[0];  // MC version from the name
        if (inherit.endsWith(QStringLiteral(".0")))
            inherit.chop(2);

        // Filter by requested MC version
        if (inherit != filterMc) continue;

        // Reconstruct version string like BMCLAPI: e.g. "HD_U_C8"
        QString prefix = QStringLiteral("OptiFine_") + filterMc + QStringLiteral("_");
        QString ver = rawName;
        if (ver.startsWith(prefix))
            ver = ver.mid(prefix.length());

        QVariantMap m;
        m[QStringLiteral("version")] = ver;
        m[QStringLiteral("type")] = QStringLiteral("release");
        // 解析日期格式 "2024.1.15" → "2024/01/15"
        QString dateStr;
        if (i < dates.size()) {
            QStringList d = dates[i].split(QLatin1Char('.'));
            if (d.size() == 3)
                dateStr = QStringLiteral("%1/%2/%3").arg(d[2], 2, QLatin1Char('0')).arg(d[1], 2, QLatin1Char('0')).arg(d[0], 2, QLatin1Char('0'));
        }
        m[QStringLiteral("date")] = dateStr;
        // Derive bmclType/bmclPatch from version string (consistent with BMCLAPI format)
        // ver e.g. "HD_U_C8" → type="HD_U", patch="C8"
        // ver e.g. "HD_U_J9_pre1" → type="HD_U", patch="J9_pre1"
        {
            QStringList vParts = ver.split(QLatin1Char('_'));
            if (vParts.size() >= 2) {
                m[QStringLiteral("bmclType")] = vParts[0] + QLatin1Char('_') + vParts[1];
                vParts.removeFirst(); vParts.removeFirst();
                m[QStringLiteral("bmclPatch")] = vParts.join(QLatin1Char('_'));
            } else {
                m[QStringLiteral("bmclType")] = QStringLiteral("HD_U");
                m[QStringLiteral("bmclPatch")] = ver;
            }
        }
        // Forge compatibility
        if (i < forgeStrs.size()) {
            QString f = forgeStrs[i];
            if (f.contains(QStringLiteral("N/A")))
                m[QStringLiteral("forge")] = QStringLiteral("Forge N/A");
            else if (!f.isEmpty())
                m[QStringLiteral("forge")] = f;
            else
                m[QStringLiteral("forge")] = QString();
        } else {
            m[QStringLiteral("forge")] = QString();
        }
        result.append(m);
    }
    return result;
}

void ShadowBackend::queryOptifineVersions(const QString& mcVersion) {
    m_modLoaderQueriesCancelled = false;

    struct SourceReq { bool done = false; QByteArray data; };
    struct DualState { SourceReq bmcl; SourceReq official; bool parsedBmcl = false; bool parsedOfficial = false; QVariantList bmclResult; QVariantList officialResult; bool emitted = false; };
    auto state = std::make_shared<DualState>();

    auto parseBmclJson = [mcVersion](const QByteArray& data) -> QVariantList {
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (!doc.isArray()) return {};
        QJsonArray arr = doc.array();
        QVariantList list;
        for (const QJsonValue& v : arr) {
            QJsonObject obj = v.toObject();
            QString fn = obj.value(QStringLiteral("filename")).toString();
            if (fn.isEmpty()) continue;
            // 剥掉可选的 "preview_" 前缀（BMCLAPI preview 文件名形如
            // "preview_OptiFine_1.16.5_HD_U_G7_pre10.jar"）
            QString stripped = fn;
            if (stripped.startsWith(QStringLiteral("preview_")))
                stripped = stripped.mid(8);
            QString prefix = QStringLiteral("OptiFine_") + mcVersion + QStringLiteral("_");
            QString ver = stripped;
            if (stripped.startsWith(prefix)) ver = stripped.mid(prefix.length());
            if (ver.endsWith(QStringLiteral(".jar"))) ver = ver.left(ver.length() - 4);
            QVariantMap m;
            m[QStringLiteral("version")] = ver;
            // preview 文件 → preview 类型（前端按类型排后，不抢占"最新"）
            m[QStringLiteral("type")] = fn.startsWith(QStringLiteral("preview_"))
                ? QStringLiteral("preview")
                : QStringLiteral("release");
            m[QStringLiteral("date")] = QString();
            m[QStringLiteral("bmclType")] = obj.value(QStringLiteral("type")).toString();
            m[QStringLiteral("bmclPatch")] = obj.value(QStringLiteral("patch")).toString();
            m[QStringLiteral("forge")] = obj.value(QStringLiteral("forge")).toString();
            list.append(m);
        }
        return list;
    };

    auto checkSourceComplete = [this, state, parseBmclJson, mcVersion](bool isBmcl) {
        if (state->emitted) return;
        SourceReq& src = isBmcl ? state->bmcl : state->official;
        if (!src.done) return;

        QVariantList list;
        if (isBmcl) {
            list = parseBmclJson(src.data);
            state->bmclResult = list;
            state->parsedBmcl = true;
        } else {
            list = parseOptifineOfficialVersions(src.data, mcVersion);
            state->officialResult = list;
            state->parsedOfficial = true;
        }

        if (!list.isEmpty()) {
            state->emitted = true;
            emit optifineVersionsReady(list);
            return;
        }
        bool otherParsed = isBmcl ? state->parsedOfficial : state->parsedBmcl;
        if (otherParsed) {
            state->emitted = true;
            const QVariantList& otherResult = isBmcl ? state->officialResult : state->bmclResult;
            emit optifineVersionsReady(otherResult.isEmpty() ? QVariantList() : otherResult);
        }
    };

    auto fireRequest = [this, state, checkSourceComplete, &mcVersion](bool isBmcl) {
        QString url = isBmcl
            ? QStringLiteral("https://bmclapi2.bangbang93.com/optifine/") + mcVersion
            : QStringLiteral("https://optifine.net/downloads");

        auto* mgr = new QNetworkAccessManager(this);
        QNetworkRequest req{QUrl(url)};
        req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply* reply = mgr->get(req);
        qCInfo(logApp) << QStringLiteral("[加载器] 查询版本列表 加载器=OptiFine url=%1").arg(url);
        m_modLoaderReplies.append(reply);

        QObject::connect(reply, &QNetworkReply::finished, this,
            [this, reply, mgr, isBmcl, state, checkSourceComplete]() {
                m_modLoaderReplies.removeAll(reply);
                if (m_modLoaderQueriesCancelled) {
                    qCInfo(logApp) << QStringLiteral("[加载器] 查询已取消 加载器=OptiFine");
                    reply->deleteLater(); mgr->deleteLater(); return;
                }
                if (reply->error() != QNetworkReply::NoError) {
                    qCWarning(logApp) << QStringLiteral("[加载器] 查询失败 加载器=OptiFine 源=%1 错误=%2")
                        .arg(isBmcl ? QStringLiteral("BMCLAPI") : QStringLiteral("官方"))
                        .arg(reply->errorString());
                } else {
                    SourceReq& src = isBmcl ? state->bmcl : state->official;
                    src.data = reply->readAll();
                    qCInfo(logApp) << QStringLiteral("[加载器] 获取版本数据 加载器=OptiFine 源=%1 大小=%2字节")
                        .arg(isBmcl ? QStringLiteral("BMCLAPI") : QStringLiteral("官方"))
                        .arg(src.data.size());
                }
                SourceReq& src = isBmcl ? state->bmcl : state->official;
                src.done = true;
                reply->deleteLater();
                mgr->deleteLater();
                checkSourceComplete(isBmcl);
            });
    };

    fireRequest(true);
    fireRequest(false);
}

void ShadowBackend::queryFabricApiVersions(const QString& mcVersion) {
    auto parseResponse = [](const QByteArray& data) -> QVariantList {
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (!doc.isArray()) return {};
        QJsonArray arr = doc.array();
        QVariantList list;
        for (const QJsonValue& v : arr) {
            QJsonObject obj = v.toObject();
            QJsonArray files = obj.value(QStringLiteral("files")).toArray();
            if (files.isEmpty()) continue;
            QJsonObject file = files.first().toObject();
            QVariantMap m;
            m[QStringLiteral("version")] = obj.value(QStringLiteral("version_number")).toString();
            m[QStringLiteral("name")] = obj.value(QStringLiteral("name")).toString();
            m[QStringLiteral("date")] = obj.value(QStringLiteral("date_published")).toString().left(10);
            m[QStringLiteral("url")] = file.value(QStringLiteral("url")).toString();
            m[QStringLiteral("filename")] = file.value(QStringLiteral("filename")).toString();
            m[QStringLiteral("sha1")] = file.value(QStringLiteral("hashes")).toObject().value(QStringLiteral("sha1")).toString();
            m[QStringLiteral("size")] = file.value(QStringLiteral("size")).toDouble();
            list.append(m);
        }
        return list;
    };

    const QString path = QStringLiteral("/project/fabric-api/version"
        "?loaders=[%22fabric%22]&game_versions=[%22") + mcVersion + QStringLiteral("%22]");
    const QString mcimUrl = QStringLiteral("https://mod.mcimirror.top/modrinth/v2") + path;
    const QString fallbackUrl = QStringLiteral("https://api.modrinth.com/v2") + path;

    qCDebug(logApp) << "[FabricApi] querying MCIM mirror:" << mcimUrl;
    HttpClient::instance().get(mcimUrl,
        [this, parseResponse, fallbackUrl](int status, const QByteArray& body) {
            if (m_modLoaderQueriesCancelled) {
                qCDebug(logApp) << "[FabricApi] query cancelled";
                return;
            }
            if (status == 200 && !body.isEmpty()) {
                QVariantList list = parseResponse(body);
                qCDebug(logApp) << "[FabricApi] MCIM got" << list.size() << "versions";
                emit fabricApiVersionsReady(list);
                return;
            }
            if (m_modLoaderQueriesCancelled) return;
            qCWarning(logApp) << QStringLiteral("[FabricApi] MCIM镜像失败 状态码=%1").arg(status)
                               << "), falling back to Modrinth direct";
            HttpClient::instance().get(fallbackUrl,
                [this, parseResponse](int status2, const QByteArray& body2) {
                    if (m_modLoaderQueriesCancelled) {
                        qCDebug(logApp) << "[FabricApi] fallback query cancelled";
                        return;
                    }
                    if (status2 == 200 && !body2.isEmpty()) {
                        QVariantList list = parseResponse(body2);
                        qCDebug(logApp) << "[FabricApi] direct got" << list.size() << "versions";
                        emit fabricApiVersionsReady(list);
                    } else {
                        qCWarning(logApp) << QStringLiteral("[FabricApi] 直连也失败 状态码=%1").arg(status2);
                        emit fabricApiVersionsReady({});
                    }
                });
        });
}

QString ShadowBackend::getForgeInstallerSha1(const QString& mcVer, const QString& forgeVer) const {
    return m_forgeInstallerSha1Cache.value(mcVer + QStringLiteral("-") + forgeVer);
}

void ShadowBackend::cacheForgeInstallerBranch(const QString& mcVer, const QString& forgeVer, const QString& branch) {
    m_forgeInstallerBranchCache.insert(mcVer + QStringLiteral("-") + forgeVer, branch);
}

QString ShadowBackend::getForgeInstallerBranch(const QString& mcVer, const QString& forgeVer) const {
    return m_forgeInstallerBranchCache.value(mcVer + QStringLiteral("-") + forgeVer);
}

void ShadowBackend::installModLoader(const QString& mcVersion, const QString& loaderType,
                                      const QString& loaderVersion, const QString& installName,
                                      const QString& fabricApiVersion,
                                      const QString& fabricApiUrl,
                                      const QString& fabricApiSavePath,
                                      const QString& forgeInstallerSha1) {
    qDebug() << "[install] ShadowBackend::installModLoader" << loaderType << mcVersion << loaderVersion << installName;
    QString sha1 = forgeInstallerSha1.isEmpty()
        ? getForgeInstallerSha1(mcVersion, loaderVersion)
        : forgeInstallerSha1;
    if (!sha1.isEmpty())
        qDebug() << "[install] Forge SHA1 cached:" << sha1.left(16) << "...";
    // Always look up branch from cache (populated alongside SHA1 in queryForgeVersions)
    QString branch = getForgeInstallerBranch(mcVersion, loaderVersion);
    if (!branch.isEmpty())
        qDebug() << "[install] Forge branch:" << branch;
    if (m_version) m_version->installModLoader(mcVersion, loaderType, loaderVersion, installName,
                                                 fabricApiVersion, fabricApiUrl, fabricApiSavePath, sha1, branch);
}

void ShadowBackend::installOptifine(const QString& mcVersion, const QString& optifineVersion,
                                     const QString& forgeVersion, const QString& installName,
                                     const QString& bmclType, const QString& bmclPatch) {
    qDebug() << "[install] ShadowBackend::installOptifine" << mcVersion << optifineVersion << forgeVersion << installName;
    if (m_version) m_version->installOptifine(mcVersion, optifineVersion, forgeVersion, installName, bmclType, bmclPatch);
}

void ShadowBackend::installOptifineJar(const QString& mcVersion, const QString& optifineVersion,
                                       const QString& bmclType, const QString& bmclPatch,
                                       const QString& installName) {
    if (m_version) m_version->installOptifineJar(mcVersion, optifineVersion, bmclType, bmclPatch, installName);
}

void ShadowBackend::setPendingUserDataImport(const QString& installId, const QString& archivePath) {
    if (m_version) m_version->setPendingUserDataImport(installId, archivePath);
}

void ShadowBackend::cancelPendingUserDataImport(const QString& installId) {
    if (m_version) m_version->cancelPendingUserDataImport(installId);
}

// ── Language hot-switch implementation ──
bool ShadowBackend::event(QEvent* ev)
{
    if (ev->type() == QEvent::LanguageChange) {
        // Cached strings that need retranslation after LanguageChange
        // (QML bindings are handled by engine->retranslate() above)
    }
    return QObject::event(ev);
}

void ShadowBackend::writeLanguageFile(int index) const
{
    QString path = m_app->dataDir() + "/language.txt";
    QFile f(path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QByteArray::number(index));
        f.close();
        qDebug() << "[Language] written" << index << "to" << path;
    }
}

// ============================================================
// Beta key gate
// ============================================================

bool ShadowBackend::betaGateEnabled()
{
#ifdef SHADOW_ENABLE_BETA_GATE
    return true;
#else
    return false;
#endif
}

void ShadowBackend::submitBetaKey(const QString& key)
{
    if (key.trimmed().isEmpty()) {
        emit betaKeyInvalid(QStringLiteral("请输入内测密钥"));
        return;
    }

    m_betaStatus = QStringLiteral("checking");
    emit betaStatusChanged();

    // Beta key verification endpoint — decrypted from opaque flat blob on each call.
    // Not cached: decrypted inline, zeroed after QNetworkRequest consumes it.
    const uint8_t* blob = getAssembledBlob();
    QByteArray plain = aesGcmDecrypt(
        blob + kWorkerNonceOff, kWorkerNonceLen,
        blob + kWorkerCTOff,   kWorkerCTLen,
        blob + kWorkerTagOff,  kWorkerTagLen,
        blob + kWorkerKeyOff,  blob + kWorkerSaltOff);
    QString kWorkerUrl;
    if (!plain.isEmpty())
        kWorkerUrl = QString::fromUtf8(plain);
    SecureZeroMemory(plain.data(), plain.size());

    if (kWorkerUrl.isEmpty()) {
        qCInfo(logApp) << QStringLiteral("[BetaKey] 验证跳过 未配置Worker URL");
        m_betaStatus = QStringLiteral("disabled");
        emit betaStatusChanged();
        return;
    }

    auto* mgr = new QNetworkAccessManager(this);
    QNetworkRequest req{QUrl(kWorkerUrl)};
    // Worker URL consumed by QNetworkRequest — zero the local copy
    secureWipe(kWorkerUrl);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject body;
    body["key"] = key.trimmed();

    QNetworkReply* reply = mgr->post(req, QJsonDocument(body).toJson());
    connect(reply, &QNetworkReply::finished, this, [this, key, reply, mgr]() {
        reply->deleteLater();
        mgr->deleteLater();

        bool ok = false;
        if (reply->error() == QNetworkReply::NoError) {
            auto json = QJsonDocument::fromJson(reply->readAll()).object();
            ok = json["allowed"].toBool();
            if (ok) {
                // Save encrypted key locally
                if (saveBetaKey(key)) {
                    m_betaStatus = QStringLiteral("verified");
                    emit betaStatusChanged();
                    emit betaVerified();
                } else {
                    emit betaKeyInvalid(QStringLiteral("密钥保存失败，请检查磁盘空间"));
                }
                return;
            }
        }

        m_betaStatus.clear();
        emit betaStatusChanged();
        emit betaKeyInvalid(QStringLiteral("无效的内测密钥"));
    });
}

bool ShadowBackend::saveBetaKey(const QString& key)
{
    QString keyPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                      + QStringLiteral("/.shadow_beta_key");
    QDir().mkpath(QFileInfo(keyPath).absolutePath());

#ifdef Q_OS_WIN
    DATA_BLOB in, out;
    QByteArray utf8 = key.toUtf8();
    in.pbData = reinterpret_cast<BYTE*>(utf8.data());
    in.cbData = static_cast<DWORD>(utf8.size());

    if (!CryptProtectData(&in, L"Shadow Beta", nullptr, nullptr, nullptr,
                          0, &out)) {
        qCWarning(logApp) << QStringLiteral("[BetaKey] CryptProtectData失败");
        return false;
    }

    QFile f(keyPath);
    if (!f.open(QIODevice::WriteOnly)) {
        LocalFree(out.pbData);
        return false;
    }
    f.write(reinterpret_cast<const char*>(out.pbData), static_cast<qint64>(out.cbData));
    f.close();
    LocalFree(out.pbData);
    qCInfo(logApp) << QStringLiteral("[BetaKey] 加密密钥已保存");
    return true;
#else
    // Non-Windows: store as plain text (beta gate is Windows-only for now)
    QFile f(keyPath);
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write(key.toUtf8());
    f.close();
    return true;
#endif
}

QString ShadowBackend::loadBetaKey()
{
    QString keyPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                      + QStringLiteral("/.shadow_beta_key");
    QFile f(keyPath);
    if (!f.exists()) return {};

    if (!f.open(QIODevice::ReadOnly)) return {};
    QByteArray encrypted = f.readAll();
    f.close();

#ifdef Q_OS_WIN
    DATA_BLOB in, out;
    in.pbData = reinterpret_cast<BYTE*>(encrypted.data());
    in.cbData = static_cast<DWORD>(encrypted.size());

    if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, 0, &out)) {
        qCWarning(logApp) << QStringLiteral("[BetaKey] CryptUnprotectData失败 密钥可能已损坏");
        f.remove();
        return {};
    }

    QString key = QString::fromUtf8(reinterpret_cast<const char*>(out.pbData),
                                     static_cast<int>(out.cbData));
    LocalFree(out.pbData);
    return key;
#else
    return QString::fromUtf8(encrypted);
#endif
}

bool ShadowBackend::validateBetaKey(const QString& key, QString* outError)
{
    // Decrypt Worker endpoint from opaque flat blob (AES-256-GCM).
    // With public all-zero placeholder → decrypt fails → validation disabled.
    // Not cached: decrypted inline, zeroed after QNetworkRequest consumes it.
    const uint8_t* blob = getAssembledBlob();
    QByteArray plain = aesGcmDecrypt(
        blob + kWorkerNonceOff, kWorkerNonceLen,
        blob + kWorkerCTOff,   kWorkerCTLen,
        blob + kWorkerTagOff,  kWorkerTagLen,
        blob + kWorkerKeyOff,  blob + kWorkerSaltOff);
    QString kWorkerUrl;
    if (!plain.isEmpty())
        kWorkerUrl = QString::fromUtf8(plain);
    SecureZeroMemory(plain.data(), plain.size());

    if (kWorkerUrl.isEmpty()) {
        if (outError) *outError = QStringLiteral("内测验证未配置");
        return false;
    }

    QNetworkAccessManager mgr;
    QNetworkRequest req{QUrl(kWorkerUrl)};
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    secureWipe(kWorkerUrl);

    QJsonObject body;
    body["key"] = key;

    QNetworkReply* reply = mgr.post(req, QJsonDocument(body).toJson());

    // 5-second timeout so we don't hang on network issues
    QTimer timeout;
    timeout.setSingleShot(true);
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QObject::connect(&timeout, &QTimer::timeout, &loop, [&]() {
        reply->abort();
        loop.quit();
    });
    timeout.start(5000);
    loop.exec();

    bool ok = false;
    if (reply->error() == QNetworkReply::NoError) {
        auto json = QJsonDocument::fromJson(reply->readAll()).object();
        ok = json["allowed"].toBool();
    } else if (outError) {
        *outError = reply->errorString();
    }
    reply->deleteLater();
    return ok;
}

// ── 更新后首次启动标记 .just_updated：由 main_release.cpp PreInit 写入（当前没有消费方）──
// ============================================================
// Update
// ============================================================

void ShadowBackend::checkChangelog()
{
    QString updateDir = QCoreApplication::applicationDirPath()
                        + QStringLiteral("/_update/");

    // ── Debug mechanism: force changelog popup via debug file ──
    QString debugPath = updateDir + QStringLiteral("debug_changelog.json");
    QFileInfo debugFi(debugPath);
    if (debugFi.exists() && debugFi.size() <= 65536) {
        QFile df(debugPath);
        if (df.open(QIODevice::ReadOnly)) {
            QJsonParseError derr;
            QJsonDocument ddoc = QJsonDocument::fromJson(df.readAll(), &derr);
            df.close();
            if (derr.error == QJsonParseError::NoError) {
                QJsonObject dobj = ddoc.object();
                QString dver = dobj.value("version").toString();
                bool dPersistent = dobj.value("persistent").toBool(false); // 默认 false：仅弹出一次

                // ── 更新服务器模式: 从更新服务器 API 获取最新发布说明 ──
                // （更新服务器地址已脱敏为占位符，发布前由构建方注入真实值）
                if (dobj.value("gitee").toBool()) {
                    if (dver.isEmpty()) dver = appVersion();
                    qCInfo(logApp) << "[ShadowBackend] 调试公告 — 从更新服务器获取发布说明"
                                   << (dPersistent ? "[持久模式]" : "[单次模式]");
                    QString giteeUrl = QStringLiteral(
                        "https://gitee.com/api/v5/repos/" SHADOW_GITEE_OWNER "/" SHADOW_GITEE_REPO "/releases/latest");
                    HttpClient::instance().get(giteeUrl,
                        [this, dver, dPersistent, debugPath](int status, const QByteArray& body) {
                            if (status != 200 || body.isEmpty()) {
                                qCWarning(logApp) << "[ShadowBackend] Gitee获取失败 status=" << status;
                                if (!dPersistent) QFile::remove(debugPath);
                                return;
                            }
                            QJsonParseError perr;
                            QJsonDocument pdoc = QJsonDocument::fromJson(body, &perr);
                            if (perr.error != QJsonParseError::NoError) {
                                qCWarning(logApp) << "[ShadowBackend] Gitee响应JSON解析失败";
                                if (!dPersistent) QFile::remove(debugPath);
                                return;
                            }
                            QJsonObject release = pdoc.object();
                            QString rawNotes = release.value("body").toString();
                            if (rawNotes.isEmpty()) {
                                qCWarning(logApp) << "[ShadowBackend] Gitee发布说明为空";
                                if (!dPersistent) QFile::remove(debugPath);
                                return;
                            }
                            // 规范化换行以适应 Markdown 渲染：
                            //   \r\n → \n\n（空白行 = 段落间隔）
                            //   连续 \n\n → 单个 \n\n（避免三重空行）
                            QString giteeNotes = rawNotes;
                            giteeNotes.replace(QStringLiteral("\r\n"), QStringLiteral("\n\n"));
                            giteeNotes.replace(QRegularExpression(QStringLiteral("\n{3,}")),
                                               QStringLiteral("\n\n"));
                            qCInfo(logApp) << "[ShadowBackend] Gitee公告获取成功 version=" << dver
                                           << " len=" << giteeNotes.size();
                            emit updateChangelogAvailable(dver, giteeNotes);
                            // 非持久模式：发射信号后立即删除调试文件，下次启动不再弹出
                            if (!dPersistent) {
                                QFile::remove(debugPath);
                                qCInfo(logApp) << "[ShadowBackend] 调试公告文件已删除（单次模式）";
                            }
                        },
                        [debugPath, dPersistent](const QString& err) {
                            qCWarning(logApp) << "[ShadowBackend] Gitee请求失败:" << err;
                            if (!dPersistent) QFile::remove(debugPath);
                        });
                    return;
                }
                // ── Local mode: use notes from debug file ──
                QString dnotes = dobj.value("notes").toString();
                if (!dver.isEmpty() && !dnotes.isEmpty()) {
                    qCInfo(logApp) << "[ShadowBackend] 调试公告触发 version=" << dver
                                   << (dPersistent ? "[持久模式]" : "[单次模式]");
                    emit updateChangelogAvailable(dver, dnotes);
                    // 非持久模式：删除调试文件
                    if (!dPersistent) {
                        QFile::remove(debugPath);
                        qCInfo(logApp) << "[ShadowBackend] 调试公告文件已删除（单次模式）";
                    }
                    return;
                }
            }
        }
    }

    // ── Normal post-update changelog ──
    QString clPath = updateDir + QStringLiteral("changelog_to_show.json");
    QFileInfo fi(clPath);
    if (!fi.exists() || fi.size() > 65536) return; // 64KB sanity limit

    QFile f(clPath);
    if (!f.open(QIODevice::ReadOnly)) return;

    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();

    if (err.error != QJsonParseError::NoError) {
        QFile::remove(clPath);
        return;
    }

    QJsonObject obj = doc.object();
    QString version = obj.value("version").toString();
    QString notes = obj.value("notes").toString();

    if (version == appVersion() && !notes.isEmpty()) {
        qCInfo(logApp) << "[ShadowBackend] 发现更新公告 version=" << version
                       << " len=" << notes.size();
        emit updateChangelogAvailable(version, notes);
    }

    QFile::remove(clPath);
}

void ShadowBackend::checkForUpdate()
{
    if (!m_updateManager) return;
    m_updateManager->checkUserInitiated();
}

// ── 2026-08-15：用户确认"立即重启安装"后，自动重启启动器触发 PreInit 安装 ──
// state.json 已标记 Ready。原实现只 quit()（用户必须手动重开启动器才走 PreInit，
// 体验断裂）。改为：先 startDetached 启动新进程（其 main() PreInit 会检测
// state.json=Ready → 解压 → SLUpdater 安装 → SLUpdater 替换 exe 后自动重启
// 新版本），再延迟退出当前进程。
void ShadowBackend::quitForUpdate()
{
    qCInfo(logApp) << QStringLiteral("[更新] 用户确认重启安装，自动重启启动器触发更新");
    const QString exePath = QCoreApplication::applicationFilePath();
    if (!QProcess::startDetached(exePath, QStringList())) {
        // ── 2026-11-13：重启失败时不能退出 ──
        // 原实现只记一条日志照样 quit：用户点了「立即重启安装」，启动器关掉却没起来，
        // 更新也没装，桌面只剩一个消失的窗口。改为提示并留在当前版本。
        qCWarning(logApp) << QStringLiteral("[更新] 自动重启启动器失败，请手动打开") << exePath;
        emit toastMessage(tr("自动重启失败，请手动重新打开启动器以完成更新"));
        return;
    }
    // 给子进程一点启动时间再退出（避免当前进程过早退出影响文件锁）
    QTimer::singleShot(500, qApp, &QCoreApplication::quit);
}

bool ShadowBackend::updateChecking() const
{
    return m_updateManager ? m_updateManager->isBusy() : false;
}

int ShadowBackend::updateState() const
{
    return m_updateManager ? static_cast<int>(m_updateManager->state()) : 0;
}

} // namespace ShadowLauncher

