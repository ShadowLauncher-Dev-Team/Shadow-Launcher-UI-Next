// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "launch_backend.h"
#include "version_backend.h"
#include "account_backend.h"
#include "../core/launcher.h"
#include "../core/crash_detector.h"
#include "../utils/logger.h"

#include <QDir>
#include <QDirIterator>
#include <QDateTime>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <algorithm>
#include <QRegularExpression>
#include <QTcpSocket>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QEventLoop>
#include <QNetworkRequest>
#include <QDate>
#include <QPointer>
#include <QUrl>
#include <QDesktopServices>
#include <QCoreApplication>
#include <QSysInfo>

#ifdef Q_OS_WIN
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  include <windows.h>
#  include <psapi.h>
#endif

namespace ShadowLauncher {

namespace {

// 令牌刷新单次尝试超时。整条链路 MS→XBL→XSTS→MC→Profile 共 5 跳、每跳各自
// 10s 传输超时，旧的 12s 覆盖不住合法慢链路；链路每推进一步会重置本超时。
static constexpr int kTokenRefreshTimeoutMs = 30000;

// 取进程创建时间（自 epoch 毫秒）。用于 detach 后下次启动校验 PID 是否复用。
// 失败返回 -1。
qint64 processCreationTimeMs(qint64 pid)
{
#ifdef Q_OS_WIN
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
    if (!h) return -1;
    FILETIME createT, exitT, kernelT, userT;
    qint64 r = -1;
    if (GetProcessTimes(h, &createT, &exitT, &kernelT, &userT)) {
        ULARGE_INTEGER ul;
        ul.LowPart = createT.dwLowDateTime;
        ul.HighPart = createT.dwHighDateTime;
        // FILETIME：1601-01-01 起 100ns 单位 → 转为 epoch 毫秒
        r = qint64(ul.QuadPart - 116444736000000000ULL) / 10000;
    }
    CloseHandle(h);
    return r;
#else
    Q_UNUSED(pid);
    return -1;
#endif
}

QString detachedGamesFilePath(const QString& gameDir)
{
    return gameDir + QStringLiteral("/shadow-detached-games.json");
}

void writeDetachedGamesJson(const QString& path, const QJsonArray& arr)
{
    QFile f(path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
        f.close();
    }
}

} // namespace

// ============================================================
// Constructor / Destructor
// ============================================================

LaunchBackend::LaunchBackend(QObject* parent)
    : QObject(parent)
{
    qCInfo(logLaunch) << QStringLiteral("[启动] 启动模块已初始化");

    // 浮层显隐依赖 launching / launchFailed / launchFinishedOk 三者，
    // 任何状态翻转都要让 QML 重读行数据，否则浮层会停在不该停的样子。
    connect(this, &LaunchBackend::launchStateChanged,
            this, &LaunchBackend::launchStepsChanged);
}

LaunchBackend::~LaunchBackend()
{
    // Clean up all running launchers
    killGameProcess();
}

// ============================================================
// Configuration
// ============================================================

void LaunchBackend::setGameDir(const QString& dir)
{
    m_gameDir = dir;
}

void LaunchBackend::setYggdrasilMode(const QString &apiRoot, const QString &accessToken)
{
    m_yggApiRoot = apiRoot;
    m_yggAccessToken = accessToken;
    m_yggdrasilMode = true;
}

void LaunchBackend::clearYggdrasilMode()
{
    m_yggApiRoot.clear();
    m_yggAccessToken.clear();
    m_yggdrasilMode = false;
}

// ============================================================
// Slot: launch
// ============================================================

void LaunchBackend::launch(const QString& versionId, const QString& username,
                           const QString& javaPath, int maxMemoryMB,
                           const QString& jvmArgs, const QString& gameArgs,
                           bool highPerfGpu,
                           int windowWidth, int windowHeight)
{
    if (m_launching) {
        emit logMessage(tr("已在启动中"));
        return;
    }

    m_launching = true;
    m_launchFailed = false;
    m_launchFailReason.clear();
    // 新一轮启动必须丢掉上一轮的预检失败原因，否则它会顶掉这次的分析结果。
    m_precheckReason.clear();
    m_launchFinishedOk = false;
    qCInfo(logUI) << QStringLiteral("启动游戏: ") << versionId << username;
    m_cancelled = false;
    m_launchProgress = 0;
    m_javaListRefreshed = false;   // 新一轮启动：Step 1 重新刷新 Java 列表
    m_authlibProbed = false;       // 新一轮启动：重新探测外置服务器
    m_authlibArgAdded = false;     // 避免 javaagent 参数被注入两次

    m_launchStatus = tr("正在准备...");
    emit launchStateChanged();
    qCInfo(logLaunch) << QStringLiteral("[启动] 开始启动 版本=%1 Java=%2 内存=%3MB").arg(versionId, javaPath).arg(maxMemoryMB);
    emit logMessage(tr("启动 %1 | %2 | JVM: %3").arg(versionId, username,
                      jvmArgs.isEmpty() ? tr("默认G1GC") : jvmArgs));

    // ============================================================
    // Async pre-launch checks (stepped with QTimer)
    // ============================================================

    // Save parameters for async step processing
    m_pendingVersionId = versionId;
    m_pendingJavaPath = javaPath;
    m_pendingMaxMemory = maxMemoryMB;
    m_pendingJvmArgs = jvmArgs;
    m_pendingGameArgs = gameArgs;
    m_pendingHighPerfGpu = highPerfGpu;
    m_windowWidth = windowWidth;
    m_windowHeight = windowHeight;
    m_checkStep = 0;

    // 重建本轮的阶段节点（QML 浮层据此渲染，节点数/名称全由后端决定）
    buildLaunchPipeline();

    if (!m_checkTimer) {
        m_checkTimer = new QTimer(this);
        m_checkTimer->setInterval(300);  // 300ms per step for visible progress
        connect(m_checkTimer, &QTimer::timeout, this, &LaunchBackend::runNextCheck);
    }
    m_checkTimer->start();
}

// ============================================================
// Slot: cancelLaunch
// ============================================================

void LaunchBackend::cancelLaunch()
{
    qCDebug(logLaunch) << "[PROCESS] cancelLaunch() called";
    m_cancelled = true;
    if (m_demoTimer) m_demoTimer->stop();
    m_demoFailMode = false;
    m_demoForceOnline = false;
    m_demoFailPending = false;
    m_launchFailed = false;
    m_launchFailReason.clear();
    m_launchFinishedOk = false;
    if (m_checkTimer) m_checkTimer->stop();
    if (m_refreshTimeoutTimer) m_refreshTimeoutTimer->stop();
    cleanupJavaInstallPoll();
    // Java 自动安装中：下载中取消 → abort+清理；解压中 → 不打断（JavaRuntimeInstaller 语义）
    if (m_javaAutoInstallMajor > 0 && m_javaCancelFn) {
        qCInfo(logLaunch) << QStringLiteral("[启动] 取消 Java %1 自动安装（下载中终止并清理，安装中不打断）")
            .arg(m_javaAutoInstallMajor);
        m_javaCancelFn();
    }
    m_javaAutoInstallMajor = 0;

    // If a game process was already started, kill it
    if (m_activeLauncher) {
        m_activeLauncher->killProcess();
        if (m_runningLaunchers.contains(m_activeLauncher)) {
            m_runningLaunchers.removeOne(m_activeLauncher);
            emit runningCountChanged();
            if (m_runningLaunchers.isEmpty()) emit isRunningChanged();
        }
        m_activeLauncher->deleteLater();
        m_activeLauncher = nullptr;
        emit logMessage(tr("用户取消启动，已结束游戏进程"));
    } else {
        emit logMessage(tr("用户取消了启动"));
    }

    m_launching = false;
    m_launchFinishedOk = false;  // 与 launching 一起落，否则浮层卡在'完成态'不消失
    m_launchProgress = 0;
    m_launchStatus.clear();
    emit launchProgressChanged(0, QString());
    emit launchStateChanged();
}

// ============================================================
// Slot: killGameProcess
// ============================================================

void LaunchBackend::killGameProcess()
{
    qCDebug(logLaunch) << "[PROCESS] killGameProcess() called —" << m_runningLaunchers.size() << "games to kill";
    for (Launcher* launcher : m_runningLaunchers) {
        launcher->killProcess();  // Kill immediately with taskkill /F /T
        launcher->deleteLater();
    }
    m_runningLaunchers.clear();

    m_launching = false;
    m_launchFinishedOk = false;  // 与 launching 一起落，否则浮层卡在'完成态'不消失
    m_launchProgress = 0;
    m_launchStatus.clear();
    emit launchProgressChanged(0, QString());
    emit runningCountChanged();
    emit isRunningChanged();
    emit logMessage(tr("已强制结束所有游戏进程"));
}

// 启动器退出（aboutToQuit）时调用：把运行中的游戏与启动器解耦。
// 游戏是独立 java 进程，关闭启动器不应连带关闭它；Launcher 对象仍随
// 本类 children 销毁，但 detach() 后其析构不再 forceKill。
void LaunchBackend::detachAllGames()
{
    if (m_runningLaunchers.isEmpty()) {
        m_activeLauncher = nullptr;
        return;
    }
    qCInfo(logLaunch) << QStringLiteral("[退出] 分离 %1 个运行中的游戏进程（启动器退出后游戏继续运行）")
                             .arg(m_runningLaunchers.size());
    QJsonArray persisted;
    for (Launcher* launcher : m_runningLaunchers) {
        qint64 pid = launcher->pid();
        QString ver = launcher->property("launchVersion").toString();
        launcher->detach();
        if (pid > 0) {
            QJsonObject o;
            o.insert(QStringLiteral("pid"), double(pid));
            o.insert(QStringLiteral("version"), ver);
            o.insert(QStringLiteral("created"), double(processCreationTimeMs(pid)));
            persisted.append(o);
        }
    }
    m_runningLaunchers.clear();
    m_activeLauncher = nullptr;
    m_launching = false;
    m_launchFinishedOk = false;  // 与 launching 一起落，否则浮层卡在'完成态'不消失
    // 持久化 detach 的进程，供下次启动 adoptDetachedGames 接管
    if (!m_gameDir.isEmpty()) {
        writeDetachedGamesJson(detachedGamesFilePath(m_gameDir), persisted);
    }
    emit runningCountChanged();
    emit isRunningChanged();
}

// 启动后调用：接管上次退出时 detach 后仍存活的游戏进程。
// 无 QProcess 对象，仅凭 PID（+创建时间校验）建立 ghost Launcher，
// 恢复 runningCount / 强制结束按钮；用户点强制结束后走 forceKill（纯 Win32）。
void LaunchBackend::adoptDetachedGames()
{
    if (m_gameDir.isEmpty()) return;
    const QString path = detachedGamesFilePath(m_gameDir);
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return;
    QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    f.close();

    QJsonArray alive;
    int adopted = 0;
    for (const QJsonValue& v : arr) {
        QJsonObject o = v.toObject();
        qint64 pid = qint64(o.value(QStringLiteral("pid")).toDouble());
        QString ver = o.value(QStringLiteral("version")).toString();
        qint64 recordedCreated = qint64(o.value(QStringLiteral("created")).toDouble());
        if (pid <= 0) continue;

        qint64 nowCreated = processCreationTimeMs(pid);
        if (nowCreated < 0) continue;  // 进程已不存在
        // 双方都有创建时间时比对，避免 PID 被新进程复用后误接管
        if (recordedCreated > 0 && nowCreated > 0 && recordedCreated != nowCreated)
            continue;

        Launcher* launcher = new Launcher(this);
        launcher->setProperty("launchVersion", ver);
        launcher->adoptDetachedProcess(pid);
        m_runningLaunchers.append(launcher);

        QJsonObject keep;
        keep.insert(QStringLiteral("pid"), double(pid));
        keep.insert(QStringLiteral("version"), ver);
        keep.insert(QStringLiteral("created"), double(nowCreated));
        alive.append(keep);
        ++adopted;
    }

    if (adopted > 0) {
        qCInfo(logLaunch) << QStringLiteral("[启动] 接管 %1 个上次分离后仍存活的游戏进程")
                                 .arg(adopted);
        writeDetachedGamesJson(path, alive);
        emit runningCountChanged();
        emit isRunningChanged();
    } else if (!arr.isEmpty()) {
        // 全部已退出：清理残留记录
        writeDetachedGamesJson(path, QJsonArray());
    }
}

void LaunchBackend::setAuthInfo(const QString& username, const QString& uuid,
                           const QString& accessToken, bool isOnline)
{
    m_authName = username;
    m_authUuid = uuid;
    m_authToken = accessToken;
    m_authIsOnline = isOnline;
}

// ============================================================
// Slot: getAutoMemory
// ============================================================

int LaunchBackend::getAutoMemory()
{
    return getAutoMemoryForVersion(QString());
}

// 分层需求 + 阶梯预分配算法（单位 GB）：
//   1. 需求分层：可装模组版本按 mods 目录文件数动态估算（最低 / T1 / T2 / T3）；
//      OptiFine 版本与普通版本用固定档位。
//   2. 阶梯预分配：0~T1 段 100% 给（基础需求优先保证）、T1~T2 段 70%、
//      T2~T3 段 40%、T3~2×T3 段 15%（高需求段递减，保护系统余量）。
//   3. 下限 = 最低需求（ramMin）；上限 = min(T2, 物理内存一半, 物理内存-4GB)，转 MB 后钳制 [512, 32768]。
int LaunchBackend::getAutoMemoryForVersion(const QString& versionId)
{
#ifdef Q_OS_WIN
    MEMORYSTATUSEX memStatus;
    memStatus.dwLength = sizeof(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&memStatus)) {
        // ── 2026-11-14：基准从「可用内存」改为「总物理内存」──
        // 旧实现用 ullAvailPhys：可用内存随时变化，开着浏览器/其他程序时会把结果压到很低，
        // 同一个版本两次启动可能差出几 GB。总量才是稳定基准。
        double totalGB = double(memStatus.ullTotalPhys) / (1024.0 * 1024.0 * 1024.0);

        double ramMin, t1, t2, t3;
        const bool moddable = versionIsModdable(versionId);
        const bool optifineOnly = !moddable && versionId.contains(QStringLiteral("OptiFine"));
        int modCount = 0;
        if (moddable) {
            modCount = countModsForVersion(versionId);
            // 档位按模组数（对齐 GDLauncher 口径：中型 6–8GB、大型 8–12GB）：
            //   425 个模组 → 最低 2.9 / 舒适 5.0 / 宽裕 9.6 / 上限 14.1 GB
            // 基础档不能太低：Forge/Fabric 本身（含模组加载器）就要 2–3GB，
            // 0 模组的加载器实例给 3GB 才能起来。
            if (modCount == 0) {
                // 加载器的空实例：Forge/Fabric 核心 + ASM 转换本身就要 2–3GB，
                // 按 3000MB 给会很紧（进世界就卡），直接用原版档 4GB 起步。
                ramMin = 1.0; t1 = 2.0; t2 = 4.0; t3 = 5.0;
            } else {
                ramMin = 1.0  + modCount / 200.0;
                t1     = 2.0  + modCount / 120.0;
                t2     = 3.0  + modCount / 60.0;
                t3     = 4.0  + modCount / 40.0;
            }
        } else if (optifineOnly) {
            ramMin = 1.0; t1 = 2.0; t2 = 4.0; t3 = 6.0;
        } else {
            // 原版：GDLauncher 给的参考值就是 4GB
            ramMin = 1.0; t1 = 2.0; t2 = 4.0; t3 = 5.0;
        }

        // 阶梯预分配：低需求段优先保证，高需求段逐步减配，保护系统余量。
        double ramGive = 0.0;
        double avail = totalGB;

        double delta = t1;                                     // 阶段一 0~T1：100%
        ramGive += qMin(avail, delta); avail -= qMin(avail, delta);
        if (avail >= 0.1) {                                   // 阶段二 T1~T2：70%
            delta = t2 - t1;
            double use = qMin(avail * 0.7, delta);
            ramGive += use; avail -= use / 0.7;
        }
        if (avail >= 0.1) {                                   // 阶段三 T2~T3：40%
            delta = t3 - t2;
            double use = qMin(avail * 0.4, delta);
            ramGive += use; avail -= use / 0.4;
        }
        if (avail >= 0.1) {                                   // 阶段四 T3~上限：15%
            delta = t3;
            double use = qMin(avail * 0.15, delta);
            ramGive += use; avail -= use / 0.15;
        }

        // 上限三重约束：
        //   t2       —— 「宽裕」档就够了，再多也不会真正用上；
        //   total*0.5 —— 业界通用上限（不超过物理内存一半）；
        //   total-4GB —— 硬性给系统留余量，否则 8GB 机器会被挤死。
        double cap = qMin(qMin(totalGB * 0.5, totalGB - 4.0), t2);
        ramGive = qMax(ramGive, ramMin);
        ramGive = qMin(ramGive, qMax(ramMin, cap));

        int mb = qRound(ramGive * 1024.0);
        return qBound(512, mb, 32768);
    }
#endif
    return 2048; // fallback: 2GB
}

// 版本是否具备模组能力（mods 目录存在，或加载器版本）
bool LaunchBackend::versionIsModdable(const QString& versionId) const
{
    if (versionId.isEmpty()) return false;
    const QString base = m_gameDir + QStringLiteral("/versions/") + versionId;
    if (QDir(base + QStringLiteral("/mods")).exists()
        || QDir(base + QStringLiteral("/game/mods")).exists())
        return true;
    const QString lower = versionId.toLower();
    return lower.contains(QStringLiteral("forge"))
        || lower.contains(QStringLiteral("neoforge"))
        || lower.contains(QStringLiteral("fabric"))
        || lower.contains(QStringLiteral("quilt"));
}

// 统计版本 mods 目录中的模组文件数（jar/zip/litemod）
int LaunchBackend::countModsForVersion(const QString& versionId) const
{
    if (versionId.isEmpty()) return 0;
    const QString base = m_gameDir + QStringLiteral("/versions/") + versionId;
    int count = 0;
    const QStringList dirs = { base + QStringLiteral("/mods"),
                               base + QStringLiteral("/game/mods") };
    for (const QString& d : dirs) {
        QDir dir(d);
        if (dir.exists())
            count += dir.entryInfoList({QStringLiteral("*.jar"),
                                        QStringLiteral("*.zip"),
                                        QStringLiteral("*.litemod")},
                                       QDir::Files | QDir::NoDotAndDotDot).size();
    }
    return count;
}


// ============================================================
// Slot: getSystemMemory
// ============================================================

int LaunchBackend::getSystemMemory()
{
#ifdef Q_OS_WIN
    MEMORYSTATUSEX memStatus;
    memStatus.dwLength = sizeof(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&memStatus)) {
        return static_cast<int>(memStatus.ullTotalPhys / (1024 * 1024));
    }
#endif
    return 4096;
}

// ============================================================
// Slot: getMemoryStatus
// ============================================================

QVariantMap LaunchBackend::getMemoryStatus()
{
    QVariantMap status;
#ifdef Q_OS_WIN
    MEMORYSTATUSEX memStatus;
    memStatus.dwLength = sizeof(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&memStatus)) {
        auto totalMB = static_cast<int>(memStatus.ullTotalPhys / (1024 * 1024));
        auto availMB = static_cast<int>(memStatus.ullAvailPhys / (1024 * 1024));
        int usedMB = totalMB - availMB;
        int usagePercent = totalMB > 0 ? (usedMB * 100 / totalMB) : 0;

        status[QStringLiteral("totalMB")] = totalMB;
        status[QStringLiteral("availMB")] = availMB;
        status[QStringLiteral("usedMB")] = usedMB;
        status[QStringLiteral("usagePercent")] = usagePercent;
        status[QStringLiteral("recommendedMB")] = getAutoMemory();
    }
#endif
    return status;
}

// ============================================================
// Async Pre-launch Check Steps
// ============================================================

/// 启动状态机内自动安装 Java：调注入的安装器（worker 下载/解压），
/// 进度经 launchCheckProgress 上报（QML toast 显示），完成后
/// 更新 m_pendingJavaPath 并继续状态机；失败则 abortCheck。
/// 注意：必须先暂停状态机 timer（否则 300ms 后 runNextCheck 重入 Step 1
/// → 二次安装 → 锁冲突 + 互相清理，2026-08-08 实测双触发 bug）。
void LaunchBackend::startJavaAutoInstall(int requiredMajor)
{
    if (!m_javaInstallFn) {
        abortCheck(tr("Java 自动安装"), tr("安装器未就绪"));
        return;
    }
    // 防重入：暂停状态机 + 忽略重复请求（Step 1 检测到已在安装则直接等待）
    if (m_checkTimer) m_checkTimer->stop();
    if (m_javaAutoInstallMajor > 0) {
        qCInfo(logLaunch) << QStringLiteral("[启动] Java %1 已在安装中，忽略重复请求")
            .arg(requiredMajor);
        return;
    }
    m_javaAutoInstallMajor = requiredMajor;
    m_javaInstallFailed = false;

    qCInfo(logLaunch) << QStringLiteral("[启动] 开始自动安装 Java %1 (版本 %2)")
        .arg(requiredMajor).arg(m_pendingVersionId);
    emit logMessage(tr("正在自动下载 Java %1...").arg(requiredMajor));

    m_javaInstallFn(requiredMajor,
        // 进度回调（JavaRuntimeInstaller 下载进度 → toast）
        [this, requiredMajor](int pct, const QString& status) {
            if (m_cancelled) return;
            if (pct > 0) {
                emit launchCheckProgress(tr("正在下载 Java %1 (%2%)...").arg(requiredMajor).arg(pct));
                updateRepair(QStringLiteral("java"), pct, status);
            } else if (!status.isEmpty()) {
                emit launchCheckProgress(status);
                updateRepair(QStringLiteral("java"), -1, status);
            }
        },
        // 完成回调
        [this, requiredMajor](bool ok, const QString& err, const QString& javaExe) {
            cleanupJavaInstallPoll();
            m_javaAutoInstallMajor = 0;
            if (m_cancelled) {
                // 用户取消启动：不继续，overlay 已关闭
                return;
            }
            if (!ok) {
                m_javaInstallFailed = true;
                qCWarning(logLaunch) << QStringLiteral("[启动] 自动安装 Java %1 失败: %2").arg(requiredMajor).arg(err);
                emit logMessage(tr("[失败] Java %1 自动安装失败: %2").arg(requiredMajor).arg(err));
                finishRepair(QStringLiteral("java"), false, tr("下载安装失败"));
                abortCheck(tr("Java 自动安装"), tr("Java %1 下载安装失败: %2").arg(requiredMajor).arg(err));
                return;
            }
            qCInfo(logLaunch) << QStringLiteral("[启动] 自动安装 Java %1 完成: %2").arg(requiredMajor).arg(javaExe);
            emit logMessage(tr("[完成] Java %1 已自动安装").arg(requiredMajor));
            emit launchCheckProgress(tr("Java %1 下载完成，正在继续启动...").arg(requiredMajor));
            finishRepair(QStringLiteral("java"), true, tr("已就绪"));
            // 更新 Java 路径并继续状态机（从 Step 1 的下一个 step 开始）
            m_pendingJavaPath = javaExe;
            if (m_checkTimer) {
                m_checkStep++;   // Step 1 已通过（Java 就绪）
                m_checkTimer->start();
            }
        });
}

void LaunchBackend::cleanupJavaInstallPoll()
{
    if (m_javaInstallPoll) {
        m_javaInstallPoll->stop();
        m_javaInstallPoll->deleteLater();
        m_javaInstallPoll = nullptr;
    }
}

// ============================================================
// 启动阶段管线
// ============================================================

// ============================================================
// 自动补全任务（A2「准备运行环境」）
// 只做一件事：把散落在各个 emit launchCheckProgress 调用点里的
// "正在下载 X (N%)" 归并成结构化的任务行，QML 才能并排显示多项。
// ============================================================
static int repairIndexOf(const QVariantList& list, const QString& key)
{
    for (int i = 0; i < list.size(); ++i) {
        if (list.at(i).toMap().value(QStringLiteral("key")).toString() == key)
            return i;
    }
    return -1;
}

void LaunchBackend::clearRepairs()
{
    if (m_repairs.isEmpty()) return;
    m_repairs.clear();
    emit launchRepairsChanged();
}

void LaunchBackend::beginRepair(const QString& key, const QString& name, const QString& detail)
{
    QVariantMap row;
    row.insert(QStringLiteral("key"), key);
    row.insert(QStringLiteral("name"), name);
    row.insert(QStringLiteral("detail"), detail);
    row.insert(QStringLiteral("progress"), 0);
    row.insert(QStringLiteral("state"), 1);
    const int idx = repairIndexOf(m_repairs, key);
    if (idx >= 0) m_repairs[idx] = row;
    else m_repairs.append(row);
    emit launchRepairsChanged();
}

void LaunchBackend::updateRepair(const QString& key, int pct, const QString& detail)
{
    const int idx = repairIndexOf(m_repairs, key);
    if (idx < 0) return;
    QVariantMap row = m_repairs.at(idx).toMap();
    row.insert(QStringLiteral("progress"), qBound(0, pct, 100));
    if (!detail.isEmpty()) row.insert(QStringLiteral("detail"), detail);
    row.insert(QStringLiteral("state"), 1);
    m_repairs[idx] = row;
    emit launchRepairsChanged();
}

void LaunchBackend::finishRepair(const QString& key, bool ok, const QString& detail)
{
    const int idx = repairIndexOf(m_repairs, key);
    if (idx < 0) return;
    QVariantMap row = m_repairs.at(idx).toMap();
    row.insert(QStringLiteral("state"), ok ? 2 : 3);
    if (ok) row.insert(QStringLiteral("progress"), 100);
    if (!detail.isEmpty()) row.insert(QStringLiteral("detail"), detail);
    m_repairs[idx] = row;
    emit launchRepairsChanged();
}

void LaunchBackend::buildLaunchPipeline()
{
    clearRepairs();   // 每次启动重新收集，绝不把上一轮的补全任务带进来
    if (!m_pipeline) {
        m_pipeline = new StepPipeline(this);

        // 现有的一行状态文本自动落到"当前节点"的 detail 上
        // （不改动任何 emit 站点，避免动到真实启动逻辑）
        connect(this, &LaunchBackend::launchCheckProgress, this, [this](const QString& msg) {
            if (!m_pipeline) return;
            if (StepNode* node = m_pipeline->stepNode(m_checkStep)) {
                if (node->detail() != msg) node->setDetail(msg);
            }
            emit launchStepsChanged();
        });

        if (StepModel* model = m_pipeline->stepModel()) {
            connect(model, &QAbstractItemModel::dataChanged,
                    this, [this] { emit launchStepsChanged(); });
            connect(model, &QAbstractItemModel::modelReset,
                    this, [this] { emit launchStepsChanged(); });
            connect(model, &QAbstractItemModel::rowsInserted,
                    this, [this] { emit launchStepsChanged(); });
        }
    }

    m_pipeline->clearSteps();
    emit launchStepsChanged();   // 管线对象刚创建时也让 QML 重读一次

    // 顺序必须与 runNextCheck() 的 case 0..6 一一对应
    m_pipeline->addStep(QStringLiteral("login"),   tr("检查登录状态"));
    m_pipeline->addStep(QStringLiteral("java"),    tr("检查 Java 环境"));
    m_pipeline->addStep(QStringLiteral("version"), tr("检查版本文件"));
    m_pipeline->addStep(QStringLiteral("deps"),    tr("检查依赖文件"));
    m_pipeline->addStep(QStringLiteral("memory"),  tr("检查内存分配"));
    // 2026-11-13：外置登录的服务器探测 + authlib-injector.jar 下载原来塞在「检查内存分配」
    // 里，用户会在内存那行卡十几秒下载网络文件、失败也标在内存上。单列一个节点。
    // 始终添加（保证 case 索引恒定），非外置时标记跳过并隐藏。
    m_pipeline->addStep(QStringLiteral("authlib"), tr("准备外置登录组件"));
    m_pipeline->addStep(QStringLiteral("process"), tr("启动游戏进程"));

    // 离线账户不校验登录：该节点标记为跳过并隐藏（不计入总进度权重）
    // m_demoForceOnline 只在 --ui-demo-launch 的在线演示模式下为真，
    // 用来验证"正版/外置 6 节点"这条分支的排版，生产路径恒为 false。
    const bool needLogin = m_authIsOnline || m_yggdrasilMode || m_demoForceOnline;
    if (!needLogin) {
        if (StepNode* node = m_pipeline->step(QStringLiteral("login"))) {
            node->setSkipped();
            node->setHidden(true);
        }
    }
    // 只有外置登录才需要 authlib-injector；其它模式该节点不存在（跳过并隐藏）
    if (!m_yggdrasilMode) {
        if (StepNode* node = m_pipeline->step(QStringLiteral("authlib"))) {
            node->setSkipped();
            node->setHidden(true);
        }
    }

    emit launchStepsChanged();
}

void LaunchBackend::syncPipelineStep(int step)
{
    if (!m_pipeline) return;
    const int count = m_pipeline->totalSteps();
    if (count == 0) return;

    for (int i = 0; i < count; ++i) {
        StepNode* node = m_pipeline->stepNode(i);
        if (!node) continue;
        const StepStatus st = node->status();
        if (st == StepStatus::Skipped) continue;
        if (i < step) {
            if (st != StepStatus::Completed && st != StepStatus::Failed)
                node->setCompleted();
        } else if (i == step) {
            if (st == StepStatus::Pending)
                node->setActive();
        }
    }
    emit launchStepsChanged();
}

void LaunchBackend::completePipeline()
{
    if (!m_pipeline) return;
    for (int i = 0; i < m_pipeline->totalSteps(); ++i) {
        if (StepNode* node = m_pipeline->stepNode(i)) {
            if (node->status() != StepStatus::Skipped)
                node->setCompleted();
        }
    }
    m_launchFinishedOk = true;
    emit launchStepsChanged();
    emit launchStateChanged();
}

void LaunchBackend::failPipelineStep(const QString& reason)
{
    if (!m_pipeline) return;
    if (StepNode* node = m_pipeline->stepNode(m_checkStep)) {
        node->setFailed(reason);
        // 子行必须给"具体原因"，否则用户只看到红色的"失败"两个字，
        // 不知道去哪修——而失败态是唯一能看到错误的地方。
        if (!reason.isEmpty()) node->setDetail(reason);
    }
    // 失败态必须常驻到用户处理：浮层用 m_launchFailed 而不是 m_launching 判可见，
    // 否则 abortCheck 里 m_launching=false 会把错误连同原因一起藏起来。
    m_launchFailed = true;
    m_launchFailReason = reason;
    emit launchStepsChanged();
    emit launchStateChanged();
}

QObject* LaunchBackend::launchPipeline() const
{
    return m_pipeline;
}

qreal LaunchBackend::launchOverallProgress() const
{
    // 阶段级进度：已完成可见节点 / 可见节点总数。
    // 不能用 weightedProgress()——它把节点内的字节百分比也混进来（依赖文件下到 60%
    // 会让总进度条走到 76%），属于"编造百分比"，与设计契约第 3 节冲突。
    if (!m_pipeline) return 0.0;
    int total = 0;
    int done = 0;
    for (int i = 0; i < m_pipeline->totalSteps(); ++i) {
        StepNode* node = m_pipeline->stepNode(i);
        if (!node || node->isHidden()) continue;
        ++total;
        if (node->status() == StepStatus::Completed) ++done;
    }
    return total > 0 ? qreal(done) / qreal(total) : 0.0;
}

QVariantList LaunchBackend::launchStepRows() const
{
    QVariantList rows;
    if (!m_pipeline) return rows;

    const int total = m_pipeline->totalSteps();
    int visible = 0;
    for (int i = 0; i < total; ++i) {
        StepNode* node = m_pipeline->stepNode(i);
        if (node && !node->isHidden()) ++visible;
    }

    int emitted = 0;
    for (int i = 0; i < total; ++i) {
        StepNode* node = m_pipeline->stepNode(i);
        if (!node || node->isHidden()) continue;
        ++emitted;
        QVariantMap row;
        row.insert(QStringLiteral("key"), node->key());
        row.insert(QStringLiteral("name"), node->name());
        row.insert(QStringLiteral("detail"), node->detail());
        row.insert(QStringLiteral("status"), node->statusInt());
        row.insert(QStringLiteral("isLast"), emitted == visible);
        rows.append(row);
    }
    return rows;
}

int LaunchBackend::launchStepCount() const
{
    if (!m_pipeline) return 0;
    int count = 0;
    for (int i = 0; i < m_pipeline->totalSteps(); ++i) {
        if (StepNode* node = m_pipeline->stepNode(i)) {
            if (!node->isHidden()) ++count;
        }
    }
    return count;
}

int LaunchBackend::launchStepNumber() const
{
    if (!m_pipeline) return 0;
    int num = 0;
    const int last = qMin(m_checkStep, m_pipeline->totalSteps() - 1);
    for (int i = 0; i <= last; ++i) {
        if (StepNode* node = m_pipeline->stepNode(i)) {
            if (!node->isHidden()) ++num;
        }
    }
    return qMax(1, num);
}

// ============================================================
// 开发期安全演示（--ui-demo-launch / --ui-demo-fail）
// ============================================================
// 只驱动阶段管线：不刷新 Java 列表、不读版本文件、不创建进程。
// 用的是与真机同一条 buildLaunchPipeline() → syncPipelineStep() →
// failPipelineStep()/completePipeline() 代码路径，所以演示里画得出来，
// 真机上就是同一套数据；反过来，演示里画不出来的，真机也一定有 bug。

void LaunchBackend::demoLaunch(int mode)
{
    if (m_demoTimer) m_demoTimer->stop();
    if (m_checkTimer) m_checkTimer->stop();

    // mode: bit0 = 失败演示，bit1 = 假装在线（显示 login 节点，验证 6 节点布局）
    m_demoFailMode = (mode & 1) != 0;
    m_demoForceOnline = (mode & 2) != 0;
    m_demoFailPending = false;
    m_demoStep = 0;
    m_checkStep = 0;
    m_cancelled = false;
    m_launchFailed = false;
    m_launchFailReason.clear();
    m_precheckReason.clear();
    m_launchFinishedOk = false;
    m_launching = true;
    m_launchProgress = 0;
    m_launchStatus = tr("正在准备...");

    buildLaunchPipeline();
    emit launchProgressChanged(0, m_launchStatus);
    emit launchStateChanged();

    if (!m_demoTimer) {
        m_demoTimer = new QTimer(this);
        m_demoTimer->setInterval(1000);
        connect(m_demoTimer, &QTimer::timeout, this, &LaunchBackend::demoTick);
    }
    m_demoTimer->start();
    demoTick();
}

void LaunchBackend::stopDemo()
{
    if (m_demoTimer) m_demoTimer->stop();
    m_demoStep = 0;
    m_demoFailMode = false;
    m_demoForceOnline = false;
    m_demoFailPending = false;
    m_launchFailed = false;
    m_launchFailReason.clear();
    m_launchFinishedOk = false;
    m_launching = false;
    clearRepairs();
    emit launchStateChanged();
}

/// 只用于截图核对「准备运行环境」卡片：填两条补全任务并停在 Java 节点，
/// 不装 Java、不联网、不起进程。生产路径永远不会调它。
void LaunchBackend::demoRepairs()
{
    if (m_demoTimer) m_demoTimer->stop();
    buildLaunchPipeline();   // 内部会 clearRepairs()

    m_demoStep = 1;
    m_checkStep = 1;
    m_cancelled = false;
    m_launchFailed = false;
    m_launchFailReason.clear();
    m_launchFinishedOk = false;
    m_launching = true;

    if (m_pipeline) {
        // 演示要看到"第 2 / 6 步 + 17%"，而离线账户的 login 默认隐藏且不计权重。
        // 这里把 login 显式放出来再标完成，仅影响演示数据。
        StepNode* login = m_pipeline->step(QStringLiteral("login"));
        if (login) {
            login->setHidden(false);
            login->setCompleted();
        }
        StepNode* java = m_pipeline->step(QStringLiteral("java"));
        if (java) {
            java->setActive();
            java->setDetail(tr("见上方「准备运行环境」"));
        }
    }

    beginRepair(QStringLiteral("java"), tr("Java 21（本机缺失）"), tr("正在下载并安装"));
    updateRepair(QStringLiteral("java"), 37, QString());
    beginRepair(QStringLiteral("authlib"), tr("authlib-injector.jar"), tr("外置登录依赖，正在下载"));
    updateRepair(QStringLiteral("authlib"), 62, tr("1.2 / 1.9 MB"));

    m_launchProgress = qRound(launchOverallProgress() * 100);
    m_launchStatus = tr("准备运行环境");
    emit launchProgressChanged(m_launchProgress, m_launchStatus);
    emit launchStepsChanged();
    emit launchStateChanged();
}

/// 只用于截图核对 B1 失败面板：把节点推到"启动游戏进程失败"，
/// 不启动任何进程；诊断数据由 ShadowBackend::demoLaunchFailure 填。
void LaunchBackend::demoFailure()
{
    if (m_demoTimer) m_demoTimer->stop();
    buildLaunchPipeline();

    m_launching = false;
    m_launchFinishedOk = false;
    clearRepairs();

    if (m_pipeline) {
        StepNode* login = m_pipeline->step(QStringLiteral("login"));
        if (login) {
            login->setHidden(false);
            login->setCompleted();
        }
        for (int i = 1; i + 1 < m_pipeline->totalSteps(); ++i) {
            if (StepNode* n = m_pipeline->stepNode(i)) n->setCompleted();
        }
        m_checkStep = m_pipeline->totalSteps() - 1;
    }

    failPipelineStep(tr("java.lang.OutOfMemoryError: Java heap space"));
    m_launchStatus = tr("启动失败");
    emit launchProgressChanged(0, m_launchStatus);
}

void LaunchBackend::demoTick()
{
    if (!m_pipeline) { stopDemo(); return; }
    const int count = m_pipeline->totalSteps();

    auto finish = [this]() {
        if (m_demoTimer) m_demoTimer->stop();
        m_launchProgress = 100;
        m_launchStatus = tr("启动完成");
        completePipeline();
        m_launching = false;
        emit launchProgressChanged(100, m_launchStatus);
        emit launchStateChanged();
        // 完成态停留 2.2s 再收起（与真机 handleLaunchStarted 的收起节奏一致）
        QTimer::singleShot(2200, this, [this]() {
            m_launchFinishedOk = false;
            emit launchStepsChanged();
            emit launchStateChanged();
        });
    };

    // 离线时 login 是隐藏节点，不该占一拍
    while (m_demoStep < count) {
        StepNode* n = m_pipeline->stepNode(m_demoStep);
        if (n && !n->isHidden()) break;
        ++m_demoStep;
    }
    if (m_demoStep >= count) { finish(); return; }

    m_checkStep = m_demoStep;
    syncPipelineStep(m_demoStep);

    StepNode* node = m_pipeline->stepNode(m_demoStep);
    const QString key = node ? node->key() : QString();
    if (node) {
        if (key == QLatin1String("login"))        node->setDetail(tr("正在刷新正版登录令牌"));
        else if (key == QLatin1String("java"))    node->setDetail(tr("正在检测 Java 环境"));
        else if (key == QLatin1String("version")) node->setDetail(tr("检查版本文件"));
        else if (key == QLatin1String("deps"))    node->setDetail(tr("正在下载 libraries 12 / 48"));
        else if (key == QLatin1String("memory"))  node->setDetail(tr("检查内存分配"));
        else                                      node->setDetail(tr("正在启动游戏进程"));
    }

    // 失败演示：Java 节点先亮一拍"进行中"，下一拍再转红（与真机观感一致）
    if (m_demoFailMode && key == QLatin1String("java")) {
        if (!m_demoFailPending) {
            m_demoFailPending = true;
            emit launchStepsChanged();
            return;
        }
        if (m_demoTimer) m_demoTimer->stop();
        m_launching = false;
        m_launchStatus = tr("启动失败");
        failPipelineStep(tr("启动失败：未找到 Java 21，可在版本设置中指定"));
        emit launchProgressChanged(0, m_launchStatus);
        emit launchStateChanged();
        return;
    }

    ++m_demoStep;
    m_launchProgress = qRound(launchOverallProgress() * 100);
    emit launchProgressChanged(m_launchProgress, m_launchStatus);
    emit launchStepsChanged();
}

void LaunchBackend::abortCheck(const QString& phase, const QString& reason)
{
    qCDebug(logLaunch) << "[PROGRESS] ABORT: " << phase << "—" << reason;
    failPipelineStep(reason);
    m_launching = false;
    m_launchFinishedOk = false;  // 与 launching 一起落，否则浮层卡在'完成态'不消失
    m_activeLauncher = nullptr;
    if (m_checkTimer) {
        m_checkTimer->stop();
    }
    if (m_refreshTimeoutTimer) {
        m_refreshTimeoutTimer->stop();
    }
    emit launchProgressChanged(0, reason);
    emit launchCheckFailed(phase, reason);
    emit launchStateChanged();
    qCCritical(logLaunch) << QStringLiteral("[启动] 启动前检查失败 阶段=%1 原因=%2").arg(phase, reason);
    emit logMessage(tr("启动失败: %1").arg(reason));

    // 2026-08-19：预检失败时也记录启动器日志路径 —— 崩溃弹窗「导出全部日志」
    // 才能打包启动器自身的 [启动] 日志。此前 m_launcherLogPath 只在游戏进程
    // 启动失败后设置，预检失败导出为空（外部文件夹「无法导出日志」）。
    m_launcherLogPath = QCoreApplication::applicationDirPath()
                        + QStringLiteral("/logs/shadow_launcher_")
                        + QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"))
                        + QStringLiteral(".log");

    // ── 预检失败也走同一条异步分析路径（与游戏崩溃一致）──
    // 不再手揉一份 report 发 legacy crashDetected：那条路与 v2 链路会各产生一份结果，
    // 两份都往 lastCrash 写就是“两个窗口/两份数据打架”的根源。
    // 此时游戏未启动，分析源是启动器日志与检查结果（CrashDetector 已有 precheck 分支）。
    m_precheckReason = phase + QStringLiteral("：") + reason;
    m_pendingOutput.clear();
    m_jvmFullLogPath.clear();
    emit crashAnalysisStarted();
    QTimer::singleShot(120, this, &LaunchBackend::runCrashAnalysis);
}

// ── Begin token refresh attempt (with retry support) ──
// Uses Qt::SingleShotConnection (Qt 6.0+) — connections auto-disconnect after first fire,
// eliminating the need for heap-allocated connection handles and refreshHandled guards.
void LaunchBackend::beginTokenRefreshAttempt()
{
    if (m_cancelled || !m_account) {
        if (m_checkTimer) m_checkTimer->stop();
        return;
    }

    // Clean up previous attempt's connections
    m_refreshTimeoutTimer->stop();
    disconnect(m_refreshTimeoutTimer, &QTimer::timeout, this, nullptr);
    disconnect(m_account, &AccountBackend::tokenRefreshed, this, nullptr);
    disconnect(m_account, &AccountBackend::tokenRefreshFailed, this, nullptr);
    disconnect(m_account, &AccountBackend::microsoftLoginProgress, this, nullptr);

    m_refreshTimeoutTimer->start(kTokenRefreshTimeoutMs);

    // 认证链每推进一步就重置超时：合法但偏慢的刷新（弱网/多跳）不再被误判超时
    connect(m_account, &AccountBackend::microsoftLoginProgress, this,
        [this](const QString&, const QString&) {
            if (m_refreshTimeoutTimer && m_refreshTimeoutTimer->isActive())
                m_refreshTimeoutTimer->start(kTokenRefreshTimeoutMs);
        });

    // Timeout handler
    connect(m_refreshTimeoutTimer, &QTimer::timeout, this, [this]() {
        if (m_cancelled) return;
        qCWarning(logLaunch) << QStringLiteral("[启动] 令牌刷新超时 重试次数=%1").arg(m_refreshRetryCount);

        if (m_refreshRetryCount < 2) {
            m_refreshRetryCount++;
            m_refreshTimeoutTimer->stop();
            // 关键：清掉假死的“刷新中”标记，让重试真正重新发起（旧实现被静默 no-op）
            if (m_account) m_account->resetRefreshState();
            emit logMessage(tr("令牌刷新超时，正在重试(%1/3)...").arg(m_refreshRetryCount));
            emit launchCheckProgress(tr("令牌刷新超时，重试(%1/3)...").arg(m_refreshRetryCount));
            emit launchProgressChanged(7, tr("令牌刷新超时，重试(%1/3)...").arg(m_refreshRetryCount));
            QTimer::singleShot(2000, this, [this]() {
                if (!m_cancelled) beginTokenRefreshAttempt();
            });
            return;
        }

        qCWarning(logLaunch) << QStringLiteral("[启动] 令牌刷新超时，重试耗尽");
        finishTokenRefreshOnFailure(tr("网络超时，无法验证正版登录状态"));
    });

    // Connection 1: tokenRefreshed — handle success only
    // When ok=false, tokenRefreshFailed will fire right after, so just ignore here
    connect(m_account, &AccountBackend::tokenRefreshed, this,
        [this](bool ok) {
            if (!ok) return;  // tokenRefreshFailed handles the failure

            m_refreshTimeoutTimer->stop();
            disconnect(m_account, &AccountBackend::tokenRefreshFailed, this, nullptr);

            qCInfo(logLaunch) << QStringLiteral("[启动] 令牌刷新成功");
            m_authToken = m_account->mcToken();

            emit launchCheckProgress(tr("正版授权验证通过"));
            emit launchProgressChanged(9, tr("正版授权验证通过"));
            emit logMessage(tr("正版令牌验证通过"));

            if (m_checkTimer && !m_checkTimer->isActive()) {
                m_checkStep++;
                m_checkTimer->start();
            }
        }, Qt::SingleShotConnection);

    // Connection 2: tokenRefreshFailed — decide retry vs abort vs proceed
    connect(m_account, &AccountBackend::tokenRefreshFailed, this,
        [this](bool tokenExpired, const QString& reason) {
            m_refreshTimeoutTimer->stop();

            if (tokenExpired) {
                qCWarning(logLaunch) << QStringLiteral("[启动] 令牌已过期，阻止启动");
                abortCheck(tr("登录状态"), tr("正版登录已过期，请重新登录"));
                return;
            }

            // Transient error — retry up to 3 times total
            if (m_refreshRetryCount < 2) {
                m_refreshRetryCount++;
                emit logMessage(tr("令牌刷新失败(%1)，正在重试(%2/3)...").arg(reason).arg(m_refreshRetryCount));
                emit launchCheckProgress(tr("令牌刷新失败(%1)，重试(%2/3)...").arg(reason).arg(m_refreshRetryCount));
                emit launchProgressChanged(7, tr("令牌刷新失败(%1)，重试(%2/3)...").arg(reason).arg(m_refreshRetryCount));
                QTimer::singleShot(2000, this, [this]() {
                    if (!m_cancelled) beginTokenRefreshAttempt();
                });
                return;
            }

            // Max retries reached — 仅当缓存令牌本身仍有效才继续，否则拦住
            qCWarning(logLaunch) << QStringLiteral("[启动] 令牌刷新重试耗尽 原因=%1").arg(reason);
            finishTokenRefreshOnFailure(reason);
        }, Qt::SingleShotConnection);

    // Show attempt progress
    if (m_refreshRetryCount > 0) {
        emit launchCheckProgress(tr("正在刷新正版登录令牌(%1/3)...").arg(m_refreshRetryCount));
        emit launchProgressChanged(7, tr("正在刷新正版登录令牌(%1/3)...").arg(m_refreshRetryCount));
    }

    m_account->refreshMicrosoftToken();
}

// ── 令牌刷新最终失败后的收尾 ──
// 旧实现无论令牌是否过期都“使用缓存令牌继续”，这正是游戏内“无效会话”的来源：
// 刷新本就是把过期令牌救回来，救不回来还硬启动，进服必然被拒。
void LaunchBackend::finishTokenRefreshOnFailure(const QString& reason)
{
    const bool stillUsable = m_account && m_account->msMcTokenValid();
    if (!m_refreshNeededForExpiry && stillUsable && m_account) {
        qCWarning(logLaunch) << QStringLiteral("[启动] 令牌续期失败(%1)，缓存令牌仍有效，继续启动").arg(reason);
        emit logMessage(tr("令牌刷新失败(%1)，缓存令牌仍有效，继续启动").arg(reason));
        emit launchCheckProgress(tr("令牌刷新失败，使用本地令牌继续"));
        emit launchProgressChanged(9, tr("令牌刷新失败，使用本地令牌继续"));
        m_authToken = m_account->mcToken();
        if (m_checkTimer && !m_checkTimer->isActive()) {
            m_checkStep++;
            m_checkTimer->start();
        }
        return;
    }

    qCWarning(logLaunch) << QStringLiteral("[启动] 无法获得有效令牌(%1)，阻止启动").arg(reason);
    abortCheck(tr("登录状态"), tr("正版登录已过期或无法验证，请重新登录"));
}

void LaunchBackend::runNextCheck()
{
    if (m_cancelled) {
        m_checkTimer->stop();
        return;
    }

    syncPipelineStep(m_checkStep);

    switch (m_checkStep) {
    case 0: {
        // Step 0 (5%): Login status
        emit launchCheckProgress(tr("检查登录状态..."));
        m_launchProgress = 5;
        emit launchProgressChanged(5, tr("检查登录状态..."));
        qCDebug(logLaunch) << "[PROGRESS] 5% - 检查登录状态...";
        if (m_authName.isEmpty()) {
            // 身份没传进来。正常路径下不该发生：ShadowBackend 已按当前账号类型
            // 决定用哪套凭据；真走到这里说明会话没恢复或账号条目损坏。
            qCWarning(logLaunch) << QStringLiteral("[启动] 身份为空，无法启动 在线=%1 外置模式=%2")
                                        .arg(m_authIsOnline).arg(m_yggdrasilMode);
            abortCheck(tr("登录状态"),
                       tr("当前账号身份未就绪，请重新登录后再启动"));
            return;
        }
        qCInfo(logLaunch) << QStringLiteral("[启动] 身份=%1 在线=%2 外置=%3 uuid=%4")
                                  .arg(m_authName).arg(m_authIsOnline).arg(m_yggdrasilMode).arg(m_authUuid);
        // For online auth: refresh the Minecraft token before launching
        // (skip for yggdrasil mode - authlib-injector handles token validation)
        if (m_authIsOnline && m_account && !m_yggdrasilMode) {
            // 判定口径（2026-10-08 修）：
            //   msMcTokenValid() = MC 令牌本身是否在有效期内 —— 已过期的令牌绝不能进游戏
            //                      （否则游戏内表现为“无效会话”，且无法挽回）
            //   shouldRefresh()  = 是否进入续期窗口（默认到期前 1 小时），续期失败仍可继续
            const bool mcValid = m_account->msMcTokenValid();
            const bool needRefresh = m_account->shouldRefresh();
            if (!needRefresh && mcValid) {
                qCInfo(logLaunch) << QStringLiteral("[启动] 令牌未过期，直接使用（跳过刷新）");
            } else if (m_account->msRefreshToken().isEmpty()) {
                // 无刷新令牌 = 无法自愈：过期必须拦下；未过期才允许放行
                if (!mcValid) {
                    qCWarning(logLaunch) << QStringLiteral("[启动] 令牌已过期且无刷新令牌，阻止启动");
                    abortCheck(tr("登录状态"), tr("正版登录已过期，请重新登录"));
                    return;
                }
                qCInfo(logLaunch) << QStringLiteral("[启动] 无刷新令牌（令牌仍有效），跳过刷新");
            } else {
                m_checkTimer->stop();  // Pause until refresh completes
                m_refreshRetryCount = 0;
                m_refreshNeededForExpiry = !mcValid;

                // Progress: show refresh phase
                emit launchCheckProgress(tr("正在刷新正版登录令牌..."));
                emit launchProgressChanged(7, tr("正在刷新正版登录令牌..."));

                // Timeout guard: 30s per attempt + 链路有进展就重置
                if (!m_refreshTimeoutTimer) {
                    m_refreshTimeoutTimer = new QTimer(this);
                    m_refreshTimeoutTimer->setSingleShot(true);
                }

                // Start first refresh attempt
                beginTokenRefreshAttempt();
                return;  // Don't advance; wait for callback
            }
        }
        // 外置登录：光有名字不够，authlib-injector 必须拿到 accessToken 才能握手。
        if (m_yggdrasilMode && m_authToken.isEmpty()) {
            abortCheck(tr("登录状态"),
                       tr("外置登录凭据缺失，请重新登录该账号"));
            return;
        }
        qCInfo(logLaunch) << QStringLiteral("[启动] 登录状态通过");
        break;
    }
    case 1: {
        // Step 1 (10%): Java environment
        // ── 2026-08-08：Java 检测/匹配/自动安装全部在启动状态机内完成 ──
        // 先刷新 Java 列表（保证检测基于最新安装，启动器开着时删 Java 也能感知；
        // 刷新不弹 toast），完成后再做需求判定与匹配。
        emit launchCheckProgress(tr("检查 Java 环境..."));
        m_launchProgress = 10;
        emit launchProgressChanged(10, tr("检查 Java 环境..."));
        qCDebug(logLaunch) << "[PROGRESS] 10% - 检查 Java 环境...";

        // 0) 首次进入 Step 1：刷新 Java 列表（异步），完成后重新进入本步继续
        if (!m_javaListRefreshed && m_javaRefreshFn) {
            m_javaListRefreshed = true;
            m_checkTimer->stop();   // 暂停状态机，等刷新完成
            emit launchCheckProgress(tr("正在检测 Java 环境..."));
            qCInfo(logLaunch) << QStringLiteral("[启动] 刷新 Java 列表...");
            m_javaRefreshFn([this]() {
                if (m_cancelled) return;
                qCInfo(logLaunch) << QStringLiteral("[启动] Java 列表刷新完成，继续检查");
                if (m_checkTimer) m_checkTimer->start();   // 重新进入 Step 1
            });
            return;
        }

        // 0) 若调用方已提供明确路径（手动选择）且存在 → 直接用
        if (!m_pendingJavaPath.isEmpty() && QFileInfo::exists(m_pendingJavaPath)) {
            qCInfo(logLaunch) << QStringLiteral("[启动] 使用指定的 Java: %1").arg(m_pendingJavaPath);
        } else {
            // 1) 解析需求版本（版本 JSON + inheritsFrom 链 / MC 版本推断）
            int requiredMajor = m_javaMajorResolver ? m_javaMajorResolver(m_pendingVersionId) : 0;
            if (requiredMajor > 0)
                qCInfo(logLaunch) << QStringLiteral("[启动] 版本 %1 需要 Java %2")
                    .arg(m_pendingVersionId).arg(requiredMajor);

            // 2) 在已安装 Java 中匹配兼容版本
            if (m_javaMatcher) {
                const QString matched = m_javaMatcher(requiredMajor);
                if (!matched.isEmpty()) {
                    m_pendingJavaPath = matched;
                    qCInfo(logLaunch) << QStringLiteral("[启动] 已匹配 Java: %1").arg(matched);
                }
            }

            // 3) 未匹配 → 自动安装（纳入启动流程，overlay/toast 可见）
            if (m_pendingJavaPath.isEmpty()) {
                if (requiredMajor > 0 && m_javaInstallFn) {
                    qCInfo(logLaunch) << QStringLiteral("[启动] Java 无效，自动安装 Java %1").arg(requiredMajor);
                    emit launchCheckWarning(tr("正在自动下载 Java %1...").arg(requiredMajor));
                    emit launchCheckProgress(tr("正在自动下载 Java %1...").arg(requiredMajor));
                    beginRepair(QStringLiteral("java"),
                                tr("Java %1（本机缺失）").arg(requiredMajor),
                                tr("正在下载并安装"));
                    startJavaAutoInstall(requiredMajor);
                    return;  // 状态机暂停，安装完成回调继续
                }
                abortCheck(tr("Java 可执行文件"),
                           tr("未找到匹配的 Java（需要 %1+）").arg(requiredMajor));
                return;
            }
        }
        QString arch = checkJavaArchitecture(m_pendingJavaPath);
        if (arch == QStringLiteral("32")) {
            if (m_pendingMaxMemory > 1536) {
                m_pendingMaxMemory = 1536;
                emit launchCheckWarning(tr("检测到 32 位 Java，已限制内存 1536MB"));
            }
        }
        qCInfo(logLaunch) << QStringLiteral("[启动] Java 检查通过");
        break;
    }
    case 2: {
        // Step 2 (30%): Version core files
        emit launchCheckProgress(tr("检查版本文件..."));
        m_launchProgress = 30;
        emit launchProgressChanged(30, tr("检查版本文件..."));
        qCDebug(logLaunch) << "[PROGRESS] 30% - 检查版本文件...";
        QString versionDir = m_gameDir + QStringLiteral("/versions/") + m_pendingVersionId;
        if (!QDir(versionDir).exists()) {
            abortCheck(tr("版本目录"), tr("目录不存在")); return;
        }

        // 灵活查找版本 JSON（目录名≠文件名时仍能定位）
        QString jsonPath = VersionBackend::findVersionJson(versionDir, m_pendingVersionId);
        m_resolvedJsonPath = jsonPath;
        if (jsonPath.isEmpty()) {
            abortCheck(tr("版本配置"), tr("未找到有效的版本配置文件")); return;
        }
        QFile jsonFile(jsonPath);
        if (!jsonFile.open(QIODevice::ReadOnly)) {
            abortCheck(tr("版本配置"), tr("配置文件无法读取")); return;
        }
        QByteArray jsonBytes = jsonFile.readAll();
        jsonFile.close();
        QJsonParseError parseErr;
        QJsonDocument jsonDoc = QJsonDocument::fromJson(jsonBytes, &parseErr);
        // ── 2026-11-13：JSON 解析失败必须拦 ──
        // 原实现只发一条 warning 就继续：接着 Step 3 的 checkVersionLibraries 也因解析失败
        // 直接 return 空列表 → 依赖缺失检查整条失效 → 带着坏配置启动，游戏侧才崩。
        if (parseErr.error != QJsonParseError::NoError) {
            abortCheck(tr("版本配置"),
                       tr("版本配置文件格式损坏（%1）").arg(parseErr.errorString()));
            return;
        }

        // 灵活查找主 JAR（可选——加载器版本继承原版 jar）
        QString jarPath = VersionBackend::findVersionJar(versionDir, m_pendingVersionId);
        m_resolvedJarPath = jarPath;
        if (jarPath.isEmpty()) {
            // 无 jar 时检查 JSON 是否有 inheritsFrom（继承自原版）
            bool hasInherit = false;
            if (jsonDoc.isObject()) {
                QJsonObject jo = jsonDoc.object();
                hasInherit = jo.contains(QStringLiteral("inheritsFrom"))
                    && !jo.value(QStringLiteral("inheritsFrom")).toString().isEmpty();
            }
            if (!hasInherit) {
                abortCheck(tr("核心 Jar"), tr("未找到版本 jar 文件，且无继承来源")); return;
            }
            // 有 inheritsFrom 则放行
            qCInfo(logLaunch) << QStringLiteral("[启动] 无独立核心文件，将继承原版核心");
        }

        // JSON id 与目录名不一致时仅警告（自定义版本可能不同名）
        if (jsonDoc.isObject()) {
            QString jsonId = jsonDoc.object().value(QStringLiteral("id")).toString();
            if (!jsonId.isEmpty() && jsonId != m_pendingVersionId) {
                qCInfo(logLaunch) << QStringLiteral("[启动] 版本目录名与 JSON id 不一致: %1 vs %2").arg(m_pendingVersionId, jsonId);
                emit launchCheckWarning(tr("版本名 \"%1\" 与 JSON 内 id 不一致").arg(m_pendingVersionId));
            }
        }
        qCInfo(logLaunch) << QStringLiteral("[启动] 版本目录和核心文件检查通过");
        break;
    }
    case 3: {
        // Step 3 (50%): Dependencies
        emit launchCheckProgress(tr("检查依赖文件..."));
        m_launchProgress = 50;
        emit launchProgressChanged(50, tr("检查依赖文件..."));
        qCDebug(logLaunch) << "[PROGRESS] 50% - 检查依赖文件...";
        QStringList missingLibs = checkVersionLibraries(m_pendingVersionId);
        if (!missingLibs.isEmpty()) {
            QStringList d = missingLibs.mid(0, 5);
            QString detail = d.join(QStringLiteral(", "));
            if (missingLibs.size() > 5) detail += tr(" ...共%1个").arg(missingLibs.size());
            abortCheck(tr("依赖库文件"), detail); return;
        }
        QStringList missingNatives = checkVersionMissingNatives(m_pendingVersionId);
        if (!missingNatives.isEmpty()) {
            QStringList d = missingNatives.mid(0, 5);
            QString detail = d.join(QStringLiteral(", "));
            if (missingNatives.size() > 5) detail += tr(" ...共%1个").arg(missingNatives.size());
            abortCheck(tr("运行库文件"), detail); return;
        }
        qCInfo(logLaunch) << QStringLiteral("[启动] 依赖库检查通过");
        break;
    }
    case 4: {
        // Step 4 (65%)：内存分配 —— 这一步只做内存。
        // 2026-11-13：原来这里还塞着「外置登录服务器 5s 探测 + authlib-injector.jar 下载」
        // 和 launcher_profiles.json 写入 —— 用户会在「检查内存分配」这一行卡十几秒下载网络
        // 文件，失败时红色也标在「检查内存分配」上，完全对不上。现已拆到 Step 5。
        emit launchCheckProgress(tr("检查内存分配..."));
        m_launchProgress = 65;
        emit launchProgressChanged(65, tr("检查内存分配..."));
        qCDebug(logLaunch) << "[PROGRESS] 65% - 检查内存分配...";

        // 原实现只有一句 if (<512) 警告，「检查内存」名不副实，从不与真实物理内存比对。
        // 现在真比对：超过物理内存必崩（拦），超过当前可用内存会频繁卡顿（警告）。
#ifdef Q_OS_WIN
        MEMORYSTATUSEX memInfo{};
        memInfo.dwLength = sizeof(memInfo);
        if (GlobalMemoryStatusEx(&memInfo)) {
            const quint64 totalMB = memInfo.ullTotalPhys / (1024ull * 1024ull);
            const quint64 availMB = memInfo.ullAvailPhys / (1024ull * 1024ull);
            const quint64 needMB = static_cast<quint64>(qMax(m_pendingMaxMemory, 0));
            qCInfo(logLaunch) << QStringLiteral("[启动] 内存 分配=%1MB 可用=%2MB 总计=%3MB")
                                        .arg(needMB).arg(availMB).arg(totalMB);
            if (needMB > totalMB) {
                abortCheck(tr("内存分配"),
                           tr("分配 %1 MB 超过物理内存 %2 MB，游戏无法启动")
                               .arg(needMB).arg(totalMB));
                return;
            }
            if (needMB > availMB) {
                emit launchCheckWarning(tr("当前可用内存 %1 MB 小于分配值 %2 MB，可能卡顿")
                                            .arg(availMB).arg(needMB));
            }
        }
#endif
        if (m_pendingMaxMemory < 512)
            emit launchCheckWarning(tr("内存不足 512MB，可能影响运行"));
        break;
    }
    case 5: {
        // Step 5 (70%)：启动前的最后准备 —— 外置登录组件 + launcher_profiles.json
        emit launchCheckProgress(tr("准备启动环境..."));
        m_launchProgress = 70;
        emit launchProgressChanged(70, tr("准备启动环境..."));
        // Inject authlib-injector JVM arg for Yggdrasil mode
        if (m_yggdrasilMode && !m_yggApiRoot.isEmpty()) {
            // ── 验证外置登录服务器可达性 ──
            // 2026-11-13：原来用栈上 QNAM + QEventLoop 同步等 5 秒 —— 整个启动器 UI
            // （浮层动画、进度条、取消按钮）全部冻结，用户以为卡死。
            // 改为异步：暂停状态机，回调里恢复，与 Java 列表刷新同一套模式。
            if (!m_authlibProbed) {
                emit launchCheckProgress(tr("验证外置登录服务器..."));
                m_checkTimer->stop();
                auto *nam = new QNetworkAccessManager(this);
                QNetworkRequest checkReq{QUrl(m_yggApiRoot)};
                checkReq.setTransferTimeout(4000);  // authlib-injector 默认 15s，提前告知
                QNetworkReply *probe = nam->get(checkReq);
                connect(probe, &QNetworkReply::finished, this, [this, probe, nam]() {
                    const bool ok = probe->error() == QNetworkReply::NoError;
                    const QString errText = probe->errorString();
                    probe->deleteLater();
                    nam->deleteLater();
                    if (m_cancelled) return;
                    m_authlibProbed = true;   // 无论成败都算问过，避免死循环
                    if (!ok) {
                        abortCheck(tr("外置登录服务器"),
                                   tr("无法连接到认证服务器（%1）").arg(errText));
                        return;
                    }
                    qCInfo(logLaunch) << QStringLiteral("[启动] 外置登录服务器可达: %1").arg(m_yggApiRoot);
                    if (m_checkTimer) m_checkTimer->start();   // 重新进入本步继续
                });
                return;
            }

            QString jarPath = m_gameDir + QStringLiteral("/authlib-injector.jar");
            // ── 2026-08-17：javaagent 路径加引号 ──
            // 游戏目录含空格（如 "D:\MC FAN\.minecraft"）时，裸路径在按 \s+
            // 拆分 JVM 参数时被劈成两段（-javaagent:D:\MC + FAN\...），JVM 报
            // "Error opening zip file or JAR manifest missing : D:\MC"。引号包裹
            // 后配合 launcher.cpp 的引号感知拆分可整体作为一个参数。
            const QString nativeJar = QDir::toNativeSeparators(jarPath);
            QString agentArg = QStringLiteral("-javaagent:\"") + nativeJar
                              + QStringLiteral("\"=") + m_yggApiRoot;
            if (!m_authlibArgAdded) {
                m_authlibArgAdded = true;
                if (!m_pendingJvmArgs.isEmpty())
                    m_pendingJvmArgs += QStringLiteral(" ");
                m_pendingJvmArgs += agentArg;
                m_pendingJvmArgs += QStringLiteral(" -Dauthlibinjector.side=client");
                qCInfo(logLaunch) << QStringLiteral("[启动] 已添加 authlib-injector 参数: %1").arg(agentArg);
            }

            if (!QFileInfo::exists(jarPath)) {
                emit launchCheckWarning(tr("正在下载 authlib-injector.jar..."));
                emit launchCheckProgress(tr("正在下载 authlib-injector.jar..."));
                beginRepair(QStringLiteral("authlib"),
                            tr("authlib-injector.jar"),
                            tr("外置登录依赖，正在下载"));

                // 尝试从多个镜像下载
                QStringList urls = {
                    QStringLiteral("https://authlib-injector.yushi.moe/artifact/latest.json"),
                    QStringLiteral("https://bmclapi.bangbang93.cn/mirrors/authlib-injector/artifact/latest.json"),
                };

                bool dlOk = false;
                for (const QString &metaUrl : urls) {
                    QNetworkAccessManager nam;
                    QNetworkReply *metaReply = nam.get(QNetworkRequest(QUrl(metaUrl)));
                    QEventLoop loop;
                    QObject::connect(metaReply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
                    loop.exec();

                    if (metaReply->error() != QNetworkReply::NoError) {
                        metaReply->deleteLater();
                        continue;
                    }

                    QByteArray metaData = metaReply->readAll();
                    metaReply->deleteLater();

                    QJsonDocument metaDoc = QJsonDocument::fromJson(metaData);
                    QJsonObject metaObj = metaDoc.object();
                    QString downloadUrl = metaObj.value(QStringLiteral("download_url")).toString();
                    if (downloadUrl.isEmpty())
                        downloadUrl = metaObj.value(QStringLiteral("downloadUrl")).toString();
                    if (downloadUrl.isEmpty())
                        downloadUrl = metaObj.value(QStringLiteral("artifact")).toObject()
                                      .value(QStringLiteral("url")).toString();

                    if (!downloadUrl.isEmpty()) {
                        QNetworkReply *jarReply = nam.get(QNetworkRequest(QUrl(downloadUrl)));
                        QEventLoop loop2;
                        QObject::connect(jarReply, &QNetworkReply::finished, &loop2, &QEventLoop::quit);
                        QObject::connect(jarReply, &QNetworkReply::downloadProgress, this, [this](qint64 recv, qint64 total) {
                            if (total > 0) {
                                int pct = qMin((int)(recv * 100 / total), 100);
                                emit launchCheckProgress(tr("正在下载 authlib-injector.jar (%1%)...").arg(pct));
                                updateRepair(QStringLiteral("authlib"), pct,
                                             tr("%1 / %2 MB").arg(recv / 1048576.0, 0, 'f', 1)
                                                              .arg(total / 1048576.0, 0, 'f', 1));
                            }
                        });
                        loop2.exec();

                        if (jarReply->error() == QNetworkReply::NoError) {
                            QFile file(jarPath);
                            if (file.open(QIODevice::WriteOnly)) {
                                file.write(jarReply->readAll());
                                file.close();
                                dlOk = true;
                                qCInfo(logLaunch) << QStringLiteral("[启动] 已下载 authlib-injector.jar: %1").arg(jarPath);
                                jarReply->deleteLater();
                                break;
                            }
                        }
                        jarReply->deleteLater();
                    }
                }

                if (!dlOk) {
                    // 最后尝试从 GitHub Releases API 获取下载链接
                    QString ghApiUrl = QStringLiteral("https://api.github.com/repos/yushijinhun/authlib-injector/releases/latest");
                    QNetworkAccessManager ghNam;
                    QNetworkRequest ghReq2;
                    ghReq2.setUrl(QUrl(ghApiUrl));
                    ghReq2.setRawHeader("User-Agent", "ShadowLauncher/1.0");
                    ghReq2.setRawHeader("Accept", "application/json");
                    QNetworkReply *ghReply = ghNam.get(ghReq2);
                    QEventLoop ghLoop;
                    QObject::connect(ghReply, &QNetworkReply::finished, &ghLoop, &QEventLoop::quit);
                    ghLoop.exec();

                    if (ghReply->error() == QNetworkReply::NoError) {
                        QByteArray ghData = ghReply->readAll();
                        ghReply->deleteLater();

                        QJsonDocument ghDoc = QJsonDocument::fromJson(ghData);
                        QJsonArray assets = ghDoc.object().value(QStringLiteral("assets")).toArray();
                        QString ghDownloadUrl;
                        for (const QJsonValue &av : assets) {
                            QJsonObject asset = av.toObject();
                            QString name = asset.value(QStringLiteral("name")).toString();
                            if (name.endsWith(QStringLiteral(".jar")) && !name.contains(QStringLiteral("-sources"))) {
                                ghDownloadUrl = asset.value(QStringLiteral("browser_download_url")).toString();
                                break;
                            }
                        }

                        if (!ghDownloadUrl.isEmpty()) {
                            QNetworkReply *jarReply = ghNam.get(QNetworkRequest(QUrl(ghDownloadUrl)));
                            QEventLoop jarLoop;
                            QObject::connect(jarReply, &QNetworkReply::finished, &jarLoop, &QEventLoop::quit);
                            QObject::connect(jarReply, &QNetworkReply::downloadProgress, this, [this](qint64 recv, qint64 total) {
                                if (total > 0) {
                                    int pct = qMin((int)(recv * 100 / total), 100);
                                    emit launchCheckProgress(tr("正在下载 authlib-injector.jar (%1%)...").arg(pct));
                                    updateRepair(QStringLiteral("authlib"), pct,
                                                 tr("%1 / %2 MB").arg(recv / 1048576.0, 0, 'f', 1)
                                                                  .arg(total / 1048576.0, 0, 'f', 1));
                                }
                            });
                            jarLoop.exec();

                            if (jarReply->error() == QNetworkReply::NoError) {
                                QFile file(jarPath);
                                if (file.open(QIODevice::WriteOnly)) {
                                    file.write(jarReply->readAll());
                                    file.close();
                                    dlOk = true;
                                    qCInfo(logLaunch) << QStringLiteral("[启动] 已从 GitHub 下载 authlib-injector.jar");
                                }
                            }
                            jarReply->deleteLater();
                        }
                    }
                }

                if (!dlOk) {
                    emit launchCheckWarning(tr("authlib-injector.jar 下载失败，外置登录可能无法正常工作"));
                    finishRepair(QStringLiteral("authlib"), false, tr("下载失败，外置登录可能不可用"));
                } else {
                    finishRepair(QStringLiteral("authlib"), true, tr("已就绪"));
                }
            }
        }

        // ── 写入 launcher_profiles.json（官方启动器兼容）──
        // 某些 Mod 会读取此文件来获取玩家身份。
        // 2026-08-08：改为始终预创建（离线也写基础文件——主流启动器 McFolderLauncherProfilesJsonCreate
        // 语义），在线时附带认证信息。
        writeLauncherProfilesJson();

        qCInfo(logLaunch) << QStringLiteral("[启动] 全部检查通过，准备启动 Minecraft");
        break;
    }
    case 6: {
        // Step 6 (75%): Launch
        m_checkTimer->stop();
        emit launchCheckProgress(tr("正在启动..."));
        m_launchProgress = 75;
        emit launchProgressChanged(75, tr("正在启动 Minecraft..."));
        qCDebug(logLaunch) << "[PROGRESS] 75% - 正在启动 Minecraft...";
        Launcher* launcher = new Launcher(this);
        // 游戏「对局域网开放」→ 记录端口并转发（联机页用它，不必依赖 UDP 组播）
        connect(launcher, &Launcher::minecraftLanOpened, this, [this](int port) {
            m_lastMcLanPort = port;
            emit mcLanOpened(port);
        });
        connect(launcher, &Launcher::minecraftLanClosed, this, [this]() {
            m_lastMcLanPort = 0;
            emit mcLanClosed();
        });
        launcher->setGameDir(m_gameDir);
        launcher->setAuthInfo(m_authName, m_authUuid, m_authToken, m_authIsOnline);
        launcher->setAutoLangMode(m_autoLangMode);
        launcher->setDetectedRegion(m_detectedRegion);
        launcher->setVersionGameDir(m_versionGameDir);
        launcher->setResolution(m_windowWidth, m_windowHeight);
        // ── 启动细节配置（低垂果实批，2026-08-08）──
        launcher->setGcMode(m_gcMode);
        launcher->setMinMemoryMB(m_minMemoryMB);
        launcher->setProcessPriority(m_processPriority);
        launcher->setFullscreen(m_fullscreenEnabled);
        launcher->setAutoJoinServer(m_autoJoinServer);
        launcher->setWindowTitleOverride(m_windowTitleOverride);
        launcher->setPreLaunchCommand(m_preLaunchCommand);
        launcher->setPostExitCommand(m_postExitCommand);
        launcher->setProperty("launchVersion", m_pendingVersionId);
        // Connect signals
        m_activeLauncher = launcher;  // only this launcher's progress feeds the overlay
        connect(launcher, &Launcher::launchProgress, this, &LaunchBackend::onLaunchProgress);
        connect(launcher, &Launcher::launchStarted, this, [this, launcher]() { handleLaunchStarted(launcher); });
        connect(launcher, &Launcher::launchFinished, this, [this, launcher](bool ok, const QString& err) { handleLaunchFinished(launcher, ok, err); });
        launcher->start(m_pendingVersionId, m_pendingJavaPath, m_pendingMaxMemory,
                        m_pendingJvmArgs, m_pendingGameArgs, m_pendingHighPerfGpu,
                        m_resolvedJsonPath, m_resolvedJarPath);
        return;
    }
    default:
        m_checkTimer->stop();
        return;
    }

    m_checkStep++;
}


// ============================================================
// Private Slots
// ============================================================

void LaunchBackend::handleLaunchStarted(Launcher* launcher)
{
    // Add to running list
    // C3 进程面板要显示"运行了多久"：启动时刻记在 launcher 上，runningGames() 一起带出去。
    launcher->setProperty("launchStartedAt", QDateTime::currentSecsSinceEpoch());
    m_runningLaunchers.append(launcher);
    qCDebug(logLaunch) << "[PROCESS] Game added to running list (total:" << m_runningLaunchers.size() << ")";
    emit runningCountChanged();
    emit isRunningChanged();

    // Phase 3: Process started, wait for window
    m_launchProgress = 80;
    m_launchStatus = tr("进程已启动，等待窗口...");
    emit launchProgressChanged(80, m_launchStatus);
    qCDebug(logLaunch) << "[PROGRESS] 80% - 进程已启动，等待窗口...";
    completePipeline();
    emit minecraftStarted();

    // After 3s, check if process still alive
    // BUGFIX(2026-08-04): 用 QPointer 捕获——游戏失败时 handleLaunchFinished 会
    // deleteLater launcher，3 秒后 lambda 裸指针访问已销毁对象 → Qt6Core 崩溃
    // （movzx [d_ptr+0x304] = isSignalConnected 空指针，崩溃偏移 0x297bb4 稳定复现）
    const QPointer<Launcher> weakLauncher(launcher);
    QTimer::singleShot(3000, this, [this, weakLauncher]() {
        if (m_cancelled) return;  // Guard: cancel may have fired
        Launcher* launcher = weakLauncher.data();
        if (!launcher) return;    // launcher 已销毁（启动失败被清理），跳过
        if (!launcher->isRunning()) {
            emit launchProgressChanged(0, tr("游戏进程意外退出"));
            emit launchCheckFailed(tr("进程存活"), tr("游戏进程在窗口出现前退出"));
            emit logMessage(tr("启动失败: 进程意外退出"));
            // Remove from list (guard: may have been removed by killGameByPid)
            if (m_runningLaunchers.contains(launcher)) {
                m_runningLaunchers.removeOne(launcher);
                launcher->deleteLater();
                emit runningCountChanged();
                if (m_runningLaunchers.isEmpty()) emit isRunningChanged();
                emit minecraftStopped();
                qCDebug(logLaunch) << "[PROCESS] Death check: game process died, minecraftStopped emitted";
            } else {
                qCDebug(logLaunch) << "[PROCESS] Death check skipped (already removed by kill)";
            }
            m_launching = false;
            m_launchFinishedOk = false;  // 与 launching 一起落，否则浮层卡在'完成态'不消失
            emit launchStateChanged();
            return;
        }
        // Phase 4: Window ready
        m_launchProgress = 100;
        m_launchStatus = tr("启动完成");
        emit launchProgressChanged(100, m_launchStatus);
        qCDebug(logLaunch) << "[PROGRESS] 100% - 启动完成 (窗口就绪)";
        qCInfo(logLaunch) << QStringLiteral("[启动] 游戏启动完成 版本=%1").arg(launcher->property("launchVersion").toString());
        emit logMessage(tr("Minecraft 启动完成"));
        m_activeLauncher = nullptr;  // release progress isolation
        // Delay m_launching=false until after overlay animation
        QTimer::singleShot(2200, this, [this]() {
            m_launching = false;
            m_launchFinishedOk = false;  // 与 launching 一起落，否则浮层卡在'完成态'不消失
            qCDebug(logLaunch) << "[STATE] m_launching = false (after overlay animation)";
            emit launchStateChanged();
        });
    });
}

void LaunchBackend::onLaunchProgress(const QString& message)
{
    // Only accept progress from the currently-launching launcher
    if (sender() != m_activeLauncher) {
        return;
    }

    // Once Minecraft process has started, freeze progress at 100%
    if (m_launchProgress >= 95) {
        emit logMessage(message);
        return;
    }

    // Before Minecraft starts, only show our curated status messages
    // Raw Minecraft log lines from Launcher::launchProgress are logged but not shown
    if (m_launchProgress >= 50) {
        // Post-check phase: Minecraft is starting, don't show raw log
        emit logMessage(message);
        return;
    }

    m_launchProgress = qMin(m_launchProgress + 5, 50);
    m_launchStatus = message;
    emit launchProgressChanged(m_launchProgress, message);
    emit logMessage(message);
}

void LaunchBackend::handleLaunchFinished(Launcher* launcher, bool success, const QString& errorMsg)
{
    // Guard: launcher may have been removed by killGameByPid already
    if (!m_runningLaunchers.contains(launcher)) {
        qCDebug(logLaunch) << "[PROCESS] handleLaunchFinished skipped (already removed by kill)";
        return;
    }

    // Remove from running list
    m_runningLaunchers.removeOne(launcher);
    qCDebug(logLaunch) << "[PROCESS] Game removed from running list (total:" << m_runningLaunchers.size() << ") success=" << success;
    // BUGFIX: defer deletion — QProcess may still have pending queued signals
    // Deferred via singleShot to a clean event-loop iteration
    launcher->disconnect();
    QTimer::singleShot(0, launcher, &QObject::deleteLater);
    emit runningCountChanged();
    if (m_runningLaunchers.isEmpty()) emit isRunningChanged();

    // Always emit stopped for UI to react
    emit minecraftStopped();
    qCDebug(logLaunch) << "[PROCESS] minecraftStopped emitted";

    if (!m_launching) return;  // Already handled in handleLaunchStarted death check

    // Cancel any pending refresh timeout — game already finished
    if (m_refreshTimeoutTimer) m_refreshTimeoutTimer->stop();

    // Emit progress BEFORE setting launching=false so QML checkFailed is set first
    if (success) {
        m_launchProgress = 100;
        m_launchStatus = tr("启动完成");
        emit launchProgressChanged(100, tr("启动完成"));
        qCInfo(logLaunch) << QStringLiteral("[启动] Minecraft 启动成功");
        emit logMessage(tr("Minecraft 启动成功"));
    } else {
        m_launchProgress = 0;
        m_launchStatus.clear();
        emit launchProgressChanged(0, errorMsg);
        emit launchCheckFailed(tr("启动失败"), errorMsg);
        qCCritical(logLaunch) << QStringLiteral("[启动] Minecraft 启动失败 原因=%1").arg(errorMsg);
        emit logMessage(tr("启动失败: %1").arg(errorMsg));

        // ── Crash detection: async full analysis ──
        // 1) Immediately notify QML (toast: "启动失败，正在分析日志信息…")
        // 2) Run analysis off the UI thread via singleShot
        m_pendingOutput = launcher->recentOutput(300);
        m_jvmFullLogPath = launcher->jvmFullLogPath();
        m_launcherLogPath = QCoreApplication::applicationDirPath()
                            + QStringLiteral("/logs/shadow_launcher_")
                            + QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"))
                            + QStringLiteral(".log");
        emit crashAnalysisStarted();
        QTimer::singleShot(120, this, &LaunchBackend::runCrashAnalysis);
    }
    m_launching = false;
    m_launchFinishedOk = false;  // 与 launching 一起落，否则浮层卡在'完成态'不消失
}

// ============================================================
// Pre-launch check: Java architecture (32/64 bit)
// ============================================================

QString LaunchBackend::checkJavaArchitecture(const QString& javaPath)
{
#ifdef Q_OS_WIN
    QFile f(javaPath);
    if (!f.open(QIODevice::ReadOnly)) {
        emit logMessage(tr("无法读取 Java 可执行文件以检测架构"));
        return QStringLiteral("64");  // assume 64-bit as safe default
    }

    // Read PE header
    // DOS header: offset 0x3C contains e_lfanew (PE signature offset)
    if (!f.seek(0x3C)) {
        f.close();
        return QStringLiteral("64");
    }

    QByteArray peOffsetData = f.read(4);
    if (peOffsetData.size() < 4) {
        f.close();
        return QStringLiteral("64");
    }

    // e_lfanew is little-endian DWORD
    quint32 peOffset = static_cast<quint32>(
        static_cast<unsigned char>(peOffsetData[0]) |
        (static_cast<unsigned char>(peOffsetData[1]) << 8) |
        (static_cast<unsigned char>(peOffsetData[2]) << 16) |
        (static_cast<unsigned char>(peOffsetData[3]) << 24));

    // Seek to PE signature and verify "PE\0\0"
    if (!f.seek(peOffset)) {
        f.close();
        return QStringLiteral("64");
    }

    QByteArray peSig = f.read(4);
    if (peSig.size() < 4 || peSig[0] != 'P' || peSig[1] != 'E') {
        f.close();
        emit logMessage(tr("无法识别 PE 签名，假设为 64-bit"));
        return QStringLiteral("64");
    }

    // COFF header (20 bytes after PE signature):
    // offset 0: Machine (2 bytes)
    QByteArray coffHeader = f.read(20);
    f.close();

    if (coffHeader.size() < 2) return QStringLiteral("64");

    quint16 machine = static_cast<quint16>(
        static_cast<unsigned char>(coffHeader[0]) |
        (static_cast<unsigned char>(coffHeader[1]) << 8));

    // 0x014C = x86 (32-bit), 0x8664 = x64 (64-bit)
    if (machine == 0x014C) {
        emit logMessage(tr("检测到 32 位 Java (x86)"));
        return QStringLiteral("32");
    } else if (machine == 0x8664) {
        emit logMessage(tr("检测到 64 位 Java (x64)"));
        return QStringLiteral("64");
    } else if (machine == 0xAA64) {
        emit logMessage(tr("检测到 ARM64 Java"));
        return QStringLiteral("64");
    }

    emit logMessage(tr("未知架构 Machine=0x%1，假设为 64-bit")
                        .arg(machine, 4, 16, QLatin1Char('0')));
    return QStringLiteral("64");
#else
    Q_UNUSED(javaPath)
    return QStringLiteral("64");
#endif
}

// ============================================================
// Pre-launch check: Library file completeness
// ============================================================

// Helper: resolve all libraries including inherited versions (Forge/NeoForge inheritsFrom chain)
static QJsonArray resolveMergedLibraries(const QString& gameDir, const QJsonObject& topJson) {
    QJsonArray all = topJson.value(QStringLiteral("libraries")).toArray();
    QString inherits = topJson.value(QStringLiteral("inheritsFrom")).toString();
    QStringList seen;
    while (!inherits.isEmpty() && !seen.contains(inherits)) {
        seen.append(inherits);
        QFile f(gameDir + QStringLiteral("/versions/") + inherits + QStringLiteral("/") + inherits + QStringLiteral(".json"));
        if (!f.open(QIODevice::ReadOnly)) break;
        QJsonObject parent = QJsonDocument::fromJson(f.readAll()).object();
        f.close();
        if (parent.isEmpty()) break;
        for (const auto& lib : parent.value(QStringLiteral("libraries")).toArray())
            all.append(lib);
        inherits = parent.value(QStringLiteral("inheritsFrom")).toString();
    }
    return all;
}

QStringList LaunchBackend::checkVersionLibraries(const QString& versionId)
{
    QStringList missing;

    const QString gameDir = m_gameDir;
    const QString versionDir = gameDir + QStringLiteral("/versions/") + versionId;
    const QString jsonPath = VersionBackend::findVersionJson(versionDir, versionId);
    if (jsonPath.isEmpty()) {
        emit logMessage(tr("[警告] 未找到版本 JSON，跳过库文件检查"));
        return missing;
    }
    const QString libsDir = gameDir + QStringLiteral("/libraries");

    // Read version JSON
    QFile jsonFile(jsonPath);
    if (!jsonFile.open(QIODevice::ReadOnly)) {
        emit logMessage(tr("[警告] 无法读取版本 JSON 以检查库文件"));
        return missing;
    }

    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(jsonFile.readAll(), &parseErr);
    jsonFile.close();

    if (parseErr.error != QJsonParseError::NoError || !doc.isObject()) {
        emit logMessage(tr("[警告] 版本 JSON 解析失败，无法检查库文件"));
        return missing;
    }

    QJsonObject versionJson = doc.object();
    QJsonArray libraries = resolveMergedLibraries(gameDir, versionJson);

    for (const QJsonValue& libVal : libraries) {
        QJsonObject lib = libVal.toObject();

        // Skip platform-specific rules (client-side only)
        QJsonArray rules = lib.value(QStringLiteral("rules")).toArray();
        bool skip = false;
        for (const QJsonValue& ruleVal : rules) {
            QJsonObject rule = ruleVal.toObject();
            QString action = rule.value(QStringLiteral("action")).toString();
            QJsonObject os = rule.value(QStringLiteral("os")).toObject();
            QString osName = os.value(QStringLiteral("name")).toString();
            // If rule says "allow" for non-windows or "disallow" for windows
            if (!osName.isEmpty()) {
                bool isWindows = osName.contains(QStringLiteral("windows"), Qt::CaseInsensitive);
                if (action == QStringLiteral("allow") && !isWindows) {
                    skip = true;
                    break;
                }
                if (action == QStringLiteral("disallow") && isWindows) {
                    skip = true;
                    break;
                }
            }
        }
        if (skip) continue;

        QJsonObject downloads = lib.value(QStringLiteral("downloads")).toObject();

        // Check main artifact
        QJsonObject artifact = downloads.value(QStringLiteral("artifact")).toObject();
        bool hasArtifactCheck = false;
        if (!artifact.isEmpty()) {
            hasArtifactCheck = true;
            QString path = artifact.value(QStringLiteral("path")).toString();
            QString fullPath = libsDir + QStringLiteral("/") + path;
            if (!QFileInfo::exists(fullPath)) {
                missing.append(path);
            }
        }

        // Check native classifiers (Windows)：按本机架构选 classifier
        static const QString nativeClassifier = []() -> QString {
            const QString arch = QSysInfo::currentCpuArchitecture();
            if (arch.contains(QStringLiteral("arm64"), Qt::CaseInsensitive))
                return QStringLiteral("natives-windows-arm64");
            if (arch == QStringLiteral("x86") || arch == QStringLiteral("i386"))
                return QStringLiteral("natives-windows-x86");
            return QStringLiteral("natives-windows");
        }();
        QJsonObject classifiers = downloads.value(QStringLiteral("classifiers")).toObject();
        for (auto it = classifiers.begin(); it != classifiers.end(); ++it) {
            QString key = it.key().toLower();
            // 原条件把同一个字符串写了两遍（第二个是死代码），且不区分架构。
            // Mojang 的 classifier 有 natives-windows / natives-windows-arm64 / natives-windows-x86，
            // 必须按本机架构挑，否则 ARM 机器会把 x64 的 dll 当必需、x64 机器也可能误判。
            if (key == nativeClassifier) {
                hasArtifactCheck = true;
                QJsonObject clsArt = it.value().toObject();
                QString path = clsArt.value(QStringLiteral("path")).toString();
                if (!path.isEmpty()) {
                    QString fullPath = libsDir + QStringLiteral("/") + path;
                    if (!QFileInfo::exists(fullPath)) {
                        missing.append(path);
                    }
                }
            }
        }

        // Fallback: derive path from Maven name (Fabric-style: "net.fabricmc:fabric-loader:0.19.3")
        // 2026-08-19：支持 HMCL 式 4 段 classifier 名（downloads 为空时仍能正确解析）。
        //   例如 "net.minecraftforge:forge:26.2-65.1.1:client" → forge-26.2-65.1.1-client.jar。
        //   此前只取前 3 段 → 拼出 forge-26.2-65.1.1.jar（不存在）→ HMCL 目录误报库缺失。
        if (!hasArtifactCheck) {
            QString mavenName = lib.value(QStringLiteral("name")).toString();
            QStringList parts = mavenName.split(QLatin1Char(':'));
            if (parts.size() >= 3) {
                QString groupPath = parts[0].replace(QLatin1Char('.'), QLatin1Char('/'));
                QString relPath = groupPath + QLatin1Char('/') + parts[1] + QLatin1Char('/')
                                 + parts[2] + QLatin1Char('/') + parts[1] + QLatin1Char('-') + parts[2];
                if (parts.size() >= 4)
                    relPath += QLatin1Char('-') + parts[3];
                relPath += QStringLiteral(".jar");
                QString fullPath = libsDir + QStringLiteral("/") + relPath;
                if (!QFileInfo::exists(fullPath)) {
                    missing.append(relPath);
                }
            }
        }
    }

    if (!missing.isEmpty()) {
        qCWarning(logLaunch) << QStringLiteral("[启动] 缺少依赖库 数量=%1 版本=%2").arg(missing.size()).arg(versionId);
        emit logMessage(tr("[警告] 缺少 %1 个依赖库文件").arg(missing.size()));
    } else {
        qCInfo(logLaunch) << QStringLiteral("[启动] 依赖库检查通过 版本=%1").arg(versionId);
        emit logMessage(tr("[完成] 所有依赖库文件完整"));
    }

    return missing;
}

// ============================================================
// Pre-launch check: Natives presence
// ============================================================

bool LaunchBackend::checkVersionHasNatives(const QString& versionId)
{
    return checkVersionMissingNatives(versionId).isEmpty();
}

QStringList LaunchBackend::checkVersionMissingNatives(const QString& versionId)
{
    QStringList missing;

    const QString gameDir = m_gameDir;
    const QString versionDir = gameDir + QStringLiteral("/versions/") + versionId;
    const QString jsonPath = VersionBackend::findVersionJson(versionDir, versionId);
    if (jsonPath.isEmpty()) {
        emit logMessage(tr("[警告] 未找到版本 JSON，跳过运行库检查"));
        return missing;
    }

    // First, check if extracted natives exist
    QString primaryNatives = versionDir + QStringLiteral("/") + versionId + QStringLiteral("-natives");
    QString fallbackNatives = versionDir + QStringLiteral("/natives");
    bool hasExtractedNatives = false;

    if (QDir(primaryNatives).exists()) {
        QDirIterator it(primaryNatives, QStringList() << QStringLiteral("*.dll"), QDir::Files);
        if (it.hasNext()) {
            emit logMessage(tr("找到运行库: %1").arg(primaryNatives));
            hasExtractedNatives = true;
        }
    }
    if (!hasExtractedNatives && QDir(fallbackNatives).exists()) {
        QDirIterator it(fallbackNatives, QStringList() << QStringLiteral("*.dll"), QDir::Files);
        if (it.hasNext()) {
            emit logMessage(tr("找到运行库: %1").arg(fallbackNatives));
            hasExtractedNatives = true;
        }
    }

    // If extracted natives exist, we're good
    if (hasExtractedNatives) {
        return missing;
    }

    // No extracted natives — check if native library JARs exist and report missing ones
    const QString libsDir = gameDir + QStringLiteral("/libraries");

    // Read version JSON to find native libraries
    QFile jsonFile(jsonPath);
    if (!jsonFile.open(QIODevice::ReadOnly)) {
        emit logMessage(tr("[警告] 无法读取版本 JSON 以检查原生库"));
        missing.append(tr("(无法读取版本配置)"));
        return missing;
    }

    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(jsonFile.readAll(), &parseErr);
    jsonFile.close();

    if (parseErr.error != QJsonParseError::NoError || !doc.isObject()) {
        emit logMessage(tr("[警告] 版本 JSON 解析失败"));
        missing.append(tr("(版本配置解析失败)"));
        return missing;
    }

    QJsonObject versionJson = doc.object();
    QJsonArray libraries = resolveMergedLibraries(gameDir, versionJson);

    bool foundAnyNative = false;
    for (const QJsonValue& libVal : libraries) {
        QJsonObject lib = libVal.toObject();

        // Skip platform-specific rules
        QJsonArray rules = lib.value(QStringLiteral("rules")).toArray();
        bool skip = false;
        for (const QJsonValue& ruleVal : rules) {
            QJsonObject rule = ruleVal.toObject();
            QString action = rule.value(QStringLiteral("action")).toString();
            QJsonObject os = rule.value(QStringLiteral("os")).toObject();
            QString osName = os.value(QStringLiteral("name")).toString();
            if (!osName.isEmpty()) {
                bool isWindows = osName.contains(QStringLiteral("windows"), Qt::CaseInsensitive);
                if (action == QStringLiteral("allow") && !isWindows) { skip = true; break; }
                if (action == QStringLiteral("disallow") && isWindows) { skip = true; break; }
            }
        }
        if (skip) continue;

        QJsonObject downloads = lib.value(QStringLiteral("downloads")).toObject();
        QJsonObject classifiers = downloads.value(QStringLiteral("classifiers")).toObject();
        for (auto it = classifiers.begin(); it != classifiers.end(); ++it) {
            QString key = it.key().toLower();
            if (key == QStringLiteral("natives-windows")) {   // 与库检查同一口径（x64 主机）
                foundAnyNative = true;
                QJsonObject clsArt = it.value().toObject();
                QString path = clsArt.value(QStringLiteral("path")).toString();
                if (!path.isEmpty()) {
                    QString fullPath = libsDir + QStringLiteral("/") + path;
                    if (!QFileInfo::exists(fullPath)) {
                        missing.append(QStringLiteral("natives/%1").arg(path));
                    }
                }
            }
        }
    }

    if (!foundAnyNative) {
        // No native libraries defined in JSON — this is fine for some versions
        emit logMessage(tr("版本未定义原生库 (可能无需原生库)"));
        return missing; // empty = OK
    }

    if (!missing.isEmpty()) {
        emit logMessage(tr("[警告] 缺少 %1 个原生库文件").arg(missing.size()));
    } else {
        emit logMessage(tr("[完成] 所有原生库文件完整"));
    }

    return missing;
}

// ============================================================
// Multi-instance: kill one game by PID
// ============================================================

void LaunchBackend::killGameByPid(qint64 pid)
{
    qCDebug(logLaunch) << "[PROCESS] killGameByPid(" << pid << ") —" << m_runningLaunchers.size() << "games total";
    for (int i = 0; i < m_runningLaunchers.size(); ++i) {
        if (m_runningLaunchers[i]->pid() == pid) {
            Launcher* launcher = m_runningLaunchers.takeAt(i);
            launcher->killProcess();
            launcher->deleteLater();
            emit runningCountChanged();
            if (m_runningLaunchers.isEmpty()) emit isRunningChanged();
            emit logMessage(tr("已结束游戏进程 (PID: %1)").arg(pid));
            return;
        }
    }
    qCWarning(logLaunch) << QStringLiteral("[启动] 按 PID 强制结束失败 PID=%1 未找到").arg(pid);
}

// ============================================================
// Multi-instance: list running games
// ============================================================

QVariantList LaunchBackend::runningGames() const
{
    QVariantList list;
    
    // Count instances per version for (1), (2) suffixes
    QMap<QString, int> versionCounts;
    for (int i = 0; i < m_runningLaunchers.size(); ++i) {
        QString ver = m_runningLaunchers[i]->property("launchVersion").toString();
        versionCounts[ver]++;
    }
    
    QMap<QString, int> versionSeen;
    for (int i = 0; i < m_runningLaunchers.size(); ++i) {
        QVariantMap info;
        qint64 pid = m_runningLaunchers[i]->pid();
        info["pid"] = QVariant::fromValue(pid);
        QString ver = m_runningLaunchers[i]->property("launchVersion").toString();
        info["version"] = ver;
        
        if (versionCounts[ver] > 1) {
            versionSeen[ver]++;
            info["displayVersion"] = ver + " (" + QString::number(versionSeen[ver]) + ")";
        } else {
            info["displayVersion"] = ver;
        }
        // C3：进程面板的"运行时长"。0 表示未知（老实例恢复时可能没有）。
        const qint64 startedAt = m_runningLaunchers[i]->property("launchStartedAt").toLongLong();
        info["startedAt"] = QVariant::fromValue(startedAt);
        
        list.append(info);
    }
    return list;
}

// ── 写入 launcher_profiles.json（官方启动器兼容）──
// 一些 Mod 会读取此文件来获取玩家身份
void LaunchBackend::writeLauncherProfilesJson()
{
    QString path = m_gameDir + QStringLiteral("/launcher_profiles.json");

    // 固定 ID（使用固定值避免每次写入不同的 ID）
    const QString accountId  = QStringLiteral("00000111112222233333444445555566");
    const QString profileId  = QStringLiteral("66666555554444433333222221111100");
    const QString clientToken = QStringLiteral("23323323323323323323323323323333");

    QJsonObject root;

    // 如果文件已存在，保留其他内容
    QFileInfo fi(path);
    if (fi.exists()) {
        QFile f(path);
        if (f.open(QIODevice::ReadOnly)) {
            QJsonParseError err;
            root = QJsonDocument::fromJson(f.readAll(), &err).object();
            f.close();
            if (err.error != QJsonParseError::NoError) {
                qCWarning(logLaunch) << QStringLiteral("[启动] launcher_profiles.json 解析失败，正在重建 错误=%1").arg(err.errorString());
                root = QJsonObject();
            }
        }
    }

    // ── profiles 段（主流启动器 McFolderLauncherProfilesJsonCreate 基础结构）──
    // 某些 Mod/服务端工具会读取 profiles/selectedProfile 判断启动器
    if (!root.contains(QStringLiteral("profiles"))) {
        QJsonObject profileEntry;
        profileEntry[QStringLiteral("icon")] = QStringLiteral("Grass");
        profileEntry[QStringLiteral("name")] = QStringLiteral("Shadow");
        profileEntry[QStringLiteral("lastVersionId")] = QStringLiteral("latest-release");
        profileEntry[QStringLiteral("type")] = QStringLiteral("latest-release");
        QJsonObject profiles;
        profiles[QStringLiteral("Shadow")] = profileEntry;
        root[QStringLiteral("profiles")] = profiles;
        root[QStringLiteral("selectedProfile")] = QStringLiteral("Shadow");
    }
    if (!root.contains(QStringLiteral("clientToken"))) {
        root[QStringLiteral("clientToken")] = clientToken;
    }

    // 在线模式：构建认证信息（离线时保留已有或跳过）
    if (m_authIsOnline && !m_authName.isEmpty()) {
        QJsonObject authDb;
        QJsonObject account;
        account[QStringLiteral("username")] = m_authName;
        QJsonObject profile;
        profile[QStringLiteral("displayName")] = m_authName;
        QJsonObject profiles;
        profiles[profileId] = profile;
        account[QStringLiteral("profiles")] = profiles;
        authDb[accountId] = account;

        root[QStringLiteral("authenticationDatabase")] = authDb;
        root[QStringLiteral("clientToken")] = clientToken;

        QJsonObject selectedUser;
        selectedUser[QStringLiteral("account")] = accountId;
        selectedUser[QStringLiteral("profile")] = profileId;
        root[QStringLiteral("selectedUser")] = selectedUser;
    }

    // 写入文件（UTF-8；主流启动器 用 GB18030 但官方启动器/Mod 读 UTF-8 更稳）
    QFile f(path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        QJsonDocument doc(root);
        f.write(doc.toJson(QJsonDocument::Indented));
        f.close();
        qCInfo(logLaunch) << QStringLiteral("[启动] launcher_profiles.json 已写入 玩家=%1 在线=%2")
            .arg(m_authName.isEmpty() ? QStringLiteral("(离线)") : m_authName).arg(m_authIsOnline);
    } else {
        qCWarning(logLaunch) << QStringLiteral("[启动] launcher_profiles.json 写入失败 错误=%1").arg(f.errorString());
    }
}

// ============================================================
// Crash analysis (async)
// ============================================================

void LaunchBackend::runCrashAnalysis()
{
    if (m_crashAnalysisRunning)
        return;
    m_crashAnalysisRunning = true;

    qCInfo(logLaunch) << QStringLiteral("[崩溃分析] 异步分析开始 目录=%1").arg(m_gameDir);

    // 分析是 CPU/IO 密集（读日志 + 51 条 DotMatchesEverything 正则跑全文本，
    // latest.log 数 MB 时会阻塞 UI 线程数秒）→ 必须放后台线程。
    // CrashDetector 是纯计算类（无 QObject 状态），analyzeCrash 线程安全。
    // 2026-08-19：收集/分析用「游戏实际运行目录」（m_versionGameDir）。
    //   共享/非隔离模式 m_versionGameDir==m_gameDir（行为与原实现完全一致，不回归）；
    //   版本隔离时游戏把日志写到运行目录 versions/<id>，原实现只看根目录 → 导不出
    //   （外部 HMCL 目录 + 隔离场景）。m_versionGameDir 为空时回退根目录。
    const QString gameDir = m_versionGameDir.isEmpty() ? m_gameDir : m_versionGameDir;
    const QStringList pendingOutput = m_pendingOutput;
    const QString launcherLogPath = m_launcherLogPath;
    // 跨线程只读副本：成员可能在分析期间被下一次启动清掉。
    const QString precheckReason = m_precheckReason;

    QtConcurrent::run([this, gameDir, pendingOutput, launcherLogPath, precheckReason]() {
        CrashDetector detector;
        CrashReport cr = detector.analyzeCrash(gameDir, pendingOutput, launcherLogPath, precheckReason);
        const QString reportFilePath = cr.reportFilePath;
        const QVariantMap report = cr.toVariantMap();

        QMetaObject::invokeMethod(this, [this, report, reportFilePath]() {
            // 原因由 detector 直接写入 precheckReason，报告文件与面板因此同源。
            qCDebug(logLaunch) << "[CRASH] analysis ready" << report.value("type").toString()
                               << report.value("reason").toString()
                               << "suggestions=" << report.value("suggestions").toStringList().size();

            // 保存诊断报告路径，供“导出全部日志”打包（zip 内含 analysis-report.md）
            m_crashReportPath = reportFilePath;

            // 只发 crashAnalysisReady（v2 主信号）；crashDetected 是 legacy 兼容信号，
            // 双发会导致 QML onCrashDetected+onCrashAnalysisReady 都设置 crashData →
            // CrashDialog onCrashDataChanged 触发两次 open()（Popup 重复打开竞态）
            emit crashAnalysisReady(report);
            m_crashAnalysisRunning = false;
        });
    });
}

void LaunchBackend::demoPrecheckFail(const QString& reason)
{
    qCInfo(logLaunch) << "[DEMO] precheck fail (acceptance hook)";
    // 停掉 demo 状态机，否则它下一拍会把失败态推回成功态。
    if (m_demoTimer) m_demoTimer->stop();
    m_cancelled = false;
    m_launching = true;
    buildLaunchPipeline();
    m_checkStep = 1;
    abortCheck(tr("核心 Jar"), reason.isEmpty()
        ? tr("未找到版本 jar 文件，且无继承来源")
        : reason);
}

QString LaunchBackend::exportCrashLogs(const QString& destDir)
{
    QString zipPath = destDir;
    if (zipPath.isEmpty()) {
        QString base = m_gameDir + QStringLiteral("/crash-analysis");
        QDir().mkpath(base);
        QString ts = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
        zipPath = base + QStringLiteral("/crash-logs-") + ts + QStringLiteral(".zip");
    } else if (!zipPath.endsWith(QLatin1String(".zip"), Qt::CaseInsensitive)) {
        zipPath += QStringLiteral(".zip");
    }

    CrashDetector detector;
    // 2026-08-19：导出同样从「游戏实际运行目录」收集（隔离模式日志在运行目录）。
    //   共享/非隔离模式 m_versionGameDir==m_gameDir，行为与原实现一致，不回归。
    //   zip 落点仍用根目录 crash-analysis/（用户查找习惯不变）。
    const QString runDir = m_versionGameDir.isEmpty() ? m_gameDir : m_versionGameDir;
    // 打包 JVM 全量输出 + 最近截取 + 诊断报告 + 崩溃报告/日志
    QString result = detector.exportLogs(runDir, zipPath, m_launcherLogPath,
                                         m_pendingOutput, m_crashReportPath, m_jvmFullLogPath);
    if (!result.isEmpty()) {
        qCInfo(logLaunch) << "[崩溃分析] 日志已导出:" << result;
        emit logMessage(tr("日志已导出到: %1").arg(result));
    }
    return result;
}

void LaunchBackend::openPath(const QString& path)
{
    if (path.isEmpty())
        return;
    QUrl url = QUrl::fromLocalFile(path);
    if (!QDesktopServices::openUrl(url)) {
        qCWarning(logLaunch) << "[崩溃分析] 打开路径失败:" << path;
        emit logMessage(tr("无法打开: %1").arg(path));
    }
}

void LaunchBackend::cleanupCrashArtifacts()
{
    // 用户要求：崩溃分析完毕、用户完成导出等操作后，关闭窗口即销毁
    // 启动器生成的所有分析文件。
    // - 删除 crash-analysis/<时间戳>/ 子目录（分析报告 + 日志副本）
    // - 保留 crash-analysis/ 根级 zip（用户导出的成果）
    // - 不碰启动器 logs/（自身日志）
    // - 不碰游戏侧日志（.minecraft/logs、crash-reports 等）
    // 2026-08-19：同时清理「根目录」与「运行目录」的 crash-analysis。
    //   隔离模式的分析报告写到运行目录 versions/<id>/crash-analysis；根目录可能
    //   残留历史产物。两者都清——根目录清理逻辑与原实现完全一致，不回归。
    QStringList bases;
    bases << (m_gameDir + QStringLiteral("/crash-analysis"));
    const QString runDir = m_versionGameDir.isEmpty() ? m_gameDir : m_versionGameDir;
    if (runDir != m_gameDir)
        bases << (runDir + QStringLiteral("/crash-analysis"));

    int removed = 0;
    QStringList cleanedDirs;
    for (const QString& base : bases) {
        QDir dir(base);
        if (!dir.exists()) continue;

        const auto entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& fi : entries) {
            // 时间戳子目录（如 20260804-171523）是分析产物
            if (QDir(fi.absoluteFilePath()).removeRecursively())
                removed++;
        }

        // 根级非 zip 文件也清掉（如历史遗留的散落日志），zip 保留
        const auto files = dir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
        for (const QFileInfo& fi : files) {
            if (fi.suffix().compare(QLatin1String("zip"), Qt::CaseInsensitive) != 0) {
                QFile::remove(fi.absoluteFilePath());
                removed++;
            }
        }
        if (!base.isEmpty())
            cleanedDirs.append(base);
    }

    if (removed > 0)
        qCInfo(logLaunch) << "[崩溃分析] 已清理分析产物 目录=" << cleanedDirs.join(QLatin1Char(','))
                          << "清理项=" << removed;

    // 全量 JVM 输出日志（启动器生成，每次启动覆盖）也一并清理
    if (!m_jvmFullLogPath.isEmpty() && QFile::exists(m_jvmFullLogPath)) {
        QFile::remove(m_jvmFullLogPath);
        qCInfo(logLaunch) << "[崩溃分析] 已清理全量 JVM 输出日志:" << m_jvmFullLogPath;
    }

    // 重置内部状态，避免下次导出引用已删除的报告
    m_crashReportPath.clear();
    m_pendingOutput.clear();
    m_jvmFullLogPath.clear();
}

// ── 启动脚本导出（脱机启动/排障，2026-08-07）──
QString LaunchBackend::exportLaunchScript(const QString& versionId, const QString& javaPath,
                                          int maxMemoryMB, const QString& jvmArgs,
                                          const QString& gameArgs, bool highPerfGpu)
{
    if (versionId.isEmpty() || javaPath.isEmpty()) return QString();
    Launcher launcher;
    launcher.setGameDir(m_gameDir);
    launcher.setVersionGameDir(m_versionGameDir.isEmpty() ? m_gameDir : m_versionGameDir);
    launcher.setAuthInfo(m_authName, m_authUuid, m_authToken, m_authIsOnline);
    launcher.setAutoLangMode(m_autoLangMode);
    launcher.setDetectedRegion(m_detectedRegion);
    launcher.setResolution(m_windowWidth, m_windowHeight);
    // ── 启动细节配置（低垂果实批，2026-08-08：脚本与图形启动一致）──
    launcher.setGcMode(m_gcMode);
    launcher.setMinMemoryMB(m_minMemoryMB);
    launcher.setFullscreen(m_fullscreenEnabled);
    launcher.setAutoJoinServer(m_autoJoinServer);
    launcher.setProcessPriority(m_processPriority);
    launcher.setWindowTitleOverride(m_windowTitleOverride);
    launcher.setPreLaunchCommand(m_preLaunchCommand);
    launcher.setPostExitCommand(m_postExitCommand);
    // 外置登录：注入 authlib-injector agent（对齐启动流程 Step 5）——
    // 否则脚本启动后不带 ygg 认证，外置服务器直接拒连（2026-08-10）
    QString effectiveJvmArgs = jvmArgs;
    if (m_yggdrasilMode && !m_yggApiRoot.isEmpty()) {
        const QString jarPath = QDir::toNativeSeparators(
            m_gameDir + QStringLiteral("/authlib-injector.jar"));
        // 2026-08-17：路径加引号（含空格的游戏目录在脚本/拆分时不劈裂）
        QString agentArg = QStringLiteral("-javaagent:\"") + jarPath
                         + QStringLiteral("\"=") + m_yggApiRoot;
        effectiveJvmArgs = agentArg + QStringLiteral(" -Dauthlibinjector.side=client");
        if (!jvmArgs.isEmpty()) effectiveJvmArgs += QStringLiteral(" ") + jvmArgs;
        qCInfo(logLaunch) << QStringLiteral("[导出脚本] 已注入 authlib-injector 参数: %1").arg(agentArg);
    }
    return launcher.buildLaunchScript(versionId, javaPath, maxMemoryMB,
                                      effectiveJvmArgs, gameArgs, highPerfGpu);
}

// ── 从游戏日志文件兜底探测 LAN 端口（2026-11-08）──
// 用途：游戏已经开着、但启动器重启过（detach 接管，没有 QProcess stdout 管道）时，
// 仍能从 logs/latest.log 里找到最近一次 "Started serving on <port>"。
// 会校验该端口当前是否真的在监听，避免拿到上一个已关闭世界的旧端口。
int LaunchBackend::probeLanPortFromLogs() const
{
    static const QRegularExpression rx(QStringLiteral("Started serving on ([0-9]+)"));

    QStringList candidates;
    if (!m_versionGameDir.isEmpty())
        candidates << m_versionGameDir + QStringLiteral("/logs/latest.log");
    if (!m_gameDir.isEmpty()) {
        candidates << m_gameDir + QStringLiteral("/logs/latest.log");
        // 版本隔离：启动器重启后 m_versionGameDir 可能为空，
        // 因此再按目录时间取最近改动的若干个版本目录，看它们的 isolated 日志。
        QDir vroot(m_gameDir + QStringLiteral("/versions"));
        const QFileInfoList dirs =
            vroot.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::NoSort);
        QList<QPair<QDateTime, QString>> logFiles;
        logFiles.reserve(dirs.size());
        for (const QFileInfo& d : dirs) {
            const QString p = d.absoluteFilePath() + QStringLiteral("/logs/latest.log");
            QFileInfo lg(p);
            if (lg.exists())
                logFiles.append({lg.lastModified(), p});
        }
        std::sort(logFiles.begin(), logFiles.end(),
                  [](const QPair<QDateTime, QString>& a,
                     const QPair<QDateTime, QString>& b) { return a.first > b.first; });
        for (int i = 0; i < logFiles.size() && i < 3; ++i)
            candidates << logFiles.at(i).second;
    }

    for (const QString& path : candidates) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly))
            continue;
        // 只读尾部 256 KB：latest.log 可能很大，LAN 行总在最近
        const qint64 size = f.size();
        const qint64 from = qMax<qint64>(0, size - 256 * 1024);
        f.seek(from);
        const QString text = QString::fromUtf8(f.readAll());
        f.close();

        int lastPort = 0;
        auto it = rx.globalMatch(text);
        while (it.hasNext())
            lastPort = it.next().captured(1).toInt();

        if (lastPort <= 0 || lastPort >= 65536)
            continue;

        // 端口仍在监听才算数（旧世界的端口不会 Listen）
        QTcpSocket probe;
        probe.connectToHost(QStringLiteral("127.0.0.1"), static_cast<quint16>(lastPort));
        if (probe.waitForConnected(500)) {
            probe.disconnectFromHost();
            qCInfo(logLaunch) << QStringLiteral("[联机] 从游戏日志探测到 LAN 端口 %1").arg(lastPort);
            return lastPort;
        }
    }
    return 0;
}

} // namespace ShadowLauncher

