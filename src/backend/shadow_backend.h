// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QMap>
#include <QTranslator>
#include <QEvent>
#include <QNetworkReply>
#include <QPointer>

class QQmlEngine;

// Q_PROPERTY(QObject*) getter 需要完整类型（派生→基类指针转换），直接 include
#include "java_backend.h"
#include "userdata_backend.h"

namespace ShadowLauncher {

class AppBackend;
class AccountBackend;
class SettingsBackend;
class CheckBackend;
class VersionBackend;
class LaunchBackend;
class ResourceBackend;
class ModpackImporter;
class ModpackExporter;
class JavaBackend;
class UserDataBackend;
class YggdrasilBackend;
class ModManager;
class LocalModManager;
class IconCache;
class ResourceFetchEngine;
class MultiplayerManager;
class UpdateManager;
class MinecraftFolderBackend;

class ShadowBackend : public QObject {
    Q_OBJECT
    // Allow the static helper to access reply tracking members
    friend void queryModLoaderApi(ShadowBackend*, const QString&, const QString&,
                                  std::function<QVariantList(const QByteArray&)>,
                                  std::function<void(const QVariantList&)>);
    // ── Account ──
    Q_PROPERTY(QObject* account READ account CONSTANT)
    Q_PROPERTY(QObject* yggdrasil READ yggdrasil CONSTANT)
    Q_PROPERTY(QString username READ username NOTIFY accountChanged)
    Q_PROPERTY(QString offlineUsername READ offlineUsername NOTIFY accountChanged)
    Q_PROPERTY(bool isOnline READ isOnline NOTIFY accountChanged)
    Q_PROPERTY(QString accountUuid READ accountUuid NOTIFY accountChanged)
    Q_PROPERTY(QString offlineUuid READ offlineUuid NOTIFY accountChanged)
    Q_PROPERTY(QString skinPath READ skinPath NOTIFY skinReady)
    Q_PROPERTY(QString skinTexturePath READ skinTexturePath NOTIFY skinReady)
    Q_PROPERTY(QString offlineSkinPath READ offlineSkinPath NOTIFY offlineSkinReady)
    Q_PROPERTY(QStringList offlineUsernames READ offlineUsernames NOTIFY offlineHistoryChanged)
    // ── 多账号列表（2026-11-04）──
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)
    Q_PROPERTY(int currentAccount READ currentAccount NOTIFY accountsChanged)
    // 账户页需要：登录中状态 + 后端推送的当前步骤文案（account_backend 有，这里转发）
    Q_PROPERTY(bool microsoftLoginBusy READ microsoftLoginBusy NOTIFY microsoftLoginBusyChanged)
    Q_PROPERTY(QString msStatus READ msStatus NOTIFY microsoftLoginProgress)
    Q_PROPERTY(int lastLoginMode READ lastLoginMode WRITE setLastLoginMode NOTIFY loginModeChanged)

    // ── Settings ──
    Q_PROPERTY(QString javaPath READ javaPath NOTIFY javaPathChanged)
    Q_PROPERTY(QString javaVersion READ javaVersion NOTIFY javaPathChanged)
    Q_PROPERTY(int javaMajor READ javaMajor NOTIFY javaPathChanged)
    Q_PROPERTY(bool javaInstalled READ javaInstalled NOTIFY javaPathChanged)
    Q_PROPERTY(bool javaReady READ javaInstalled NOTIFY javaPathChanged)
    Q_PROPERTY(int minMemoryMb READ minMemoryMb NOTIFY memorySettingsChanged)
    Q_PROPERTY(int maxMemoryMb READ maxMemoryMb NOTIFY memorySettingsChanged)
    Q_PROPERTY(bool isolationEnabled READ isolationEnabled NOTIFY isolationChanged)
    Q_PROPERTY(bool embeddedLoginEnabled READ embeddedLoginEnabled WRITE setEmbeddedLoginEnabled NOTIFY embeddedLoginChanged)
    // 2026-08-15：实验性——版本悬停前置依赖 tooltip（可能卡顿/信息有误）
    Q_PROPERTY(QVariantList availableJavaList READ availableJavaList NOTIFY javaPathChanged)

    // ── Version ──
    Q_PROPERTY(QString selectedVersion READ selectedVersion NOTIFY selectedVersionChanged)
    // 上次游玩（真实记录，不猜）：启动页 kicker 用；没有记录就返回空串、QML 整行不显示
    Q_PROPERTY(QString lastPlayedLabel READ lastPlayedLabel NOTIFY lastPlayedChanged)
    Q_PROPERTY(QStringList versionIds READ versionIds NOTIFY versionListReady)
    Q_PROPERTY(QVariantList versionList READ versionList NOTIFY versionListReady)
    // 列表页日期查询表（id → yyyy-MM-dd）：QML 若直接逐项访问 QVariantList，
    // 每次下标访问都会回调一次 C++ getter（QVariantList 在 QML 里是序列包装，
    // 不是 JS 数组副本），907 个版本 × 重建 907 个 map = O(n²) ≈ 7 秒卡死。
    // 这里一次性算成 QVariantMap（QML 侧转 JS 对象一次完成），QML 只查表。
    Q_PROPERTY(QVariantMap versionDateMap READ versionDateMap NOTIFY versionListReady)
    Q_PROPERTY(QStringList releaseVersions READ releaseVersions NOTIFY versionListReady)
    Q_PROPERTY(QStringList snapshotVersions READ snapshotVersions NOTIFY versionListReady)
    Q_PROPERTY(QStringList oldVersions READ oldVersions NOTIFY versionListReady)
    Q_PROPERTY(QStringList aprilFoolVersions READ aprilFoolVersions NOTIFY versionListReady)
    Q_PROPERTY(QStringList installedVersions READ installedVersions NOTIFY installedVersionsChanged)
    Q_PROPERTY(QStringList activeVersionNames READ activeVersionNames NOTIFY activeVersionNamesChanged)
    Q_PROPERTY(bool installing READ isInstalling NOTIFY installStateChanged)
    Q_PROPERTY(QString installVersionId READ installVersionId NOTIFY installStateChanged)
    Q_PROPERTY(QString installPhase READ installPhase NOTIFY installPhaseChanged)

    // ── Launch ──
    Q_PROPERTY(bool launching READ isLaunching NOTIFY launchStateChanged)
    // B1 失败面板：最后一份崩溃诊断（precheck 与分析完成两条路径都会写这里）
    Q_PROPERTY(QVariantMap lastCrash READ lastCrash NOTIFY crashReportChanged)
    Q_PROPERTY(bool crashAnalyzing READ crashAnalyzing NOTIFY crashAnalyzingChanged)
    Q_PROPERTY(QString launchStatus READ launchStatus NOTIFY launchProgressChanged)
    Q_PROPERTY(bool isRunning READ isRunning NOTIFY isRunningChanged)
    Q_PROPERTY(int runningCount READ runningCount NOTIFY runningCountChanged)
    Q_PROPERTY(QString launchVersion READ launchVersion NOTIFY launchStateChanged)
    Q_PROPERTY(QString launchUsername READ launchUsername NOTIFY launchStateChanged)
    // ── 启动阶段管线（转发自 LaunchBackend，供启动浮层使用）──
    Q_PROPERTY(QObject* launchPipeline READ launchPipeline NOTIFY launchPipelineChanged)
    Q_PROPERTY(qreal launchOverallProgress READ launchOverallProgress NOTIFY launchPipelineChanged)
    Q_PROPERTY(int launchStepCount READ launchStepCount NOTIFY launchPipelineChanged)
    Q_PROPERTY(int launchStepNumber READ launchStepNumber NOTIFY launchPipelineChanged)
    // 浮层行数据 + 失败/完成态（同样是转发，QML 只认 backend 一个入口）
    Q_PROPERTY(QVariantList launchStepRows READ launchStepRows NOTIFY launchPipelineChanged)
    Q_PROPERTY(bool launchFailed READ launchFailed NOTIFY launchPipelineChanged)
    Q_PROPERTY(QString launchFailReason READ launchFailReason NOTIFY launchPipelineChanged)
    Q_PROPERTY(bool launchFinishedOk READ launchFinishedOk NOTIFY launchPipelineChanged)
    // A2「准备运行环境」：自动补全任务行（Java / authlib），空数组表示本次无需补全
    Q_PROPERTY(QVariantList launchRepairs READ launchRepairs NOTIFY launchRepairsChanged)

    // ── Resource ──
    Q_PROPERTY(bool downloading READ isResourceDownloading NOTIFY resourceDownloadStateChanged)
    Q_PROPERTY(int resourceDownloadProgress READ resourceDownloadProgress NOTIFY resourceDownloadProgress)
    Q_PROPERTY(int resourceDownloadTotal READ resourceDownloadTotal NOTIFY resourceDownloadProgress)
    Q_PROPERTY(int resourceDownloadSpeed READ resourceDownloadSpeed NOTIFY resourceDownloadProgress)
    Q_PROPERTY(QString resourceDownloadFile READ resourceDownloadFile NOTIFY resourceDownloadProgress)

    Q_PROPERTY(QObject* modManager READ modManager CONSTANT)
    Q_PROPERTY(QObject* multiplayer READ multiplayer CONSTANT)

    // ── App ──
    Q_PROPERTY(QString gameDir READ gameDir NOTIFY gameDirChanged)
    Q_PROPERTY(QString dataDir READ appDataDir CONSTANT)
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(QString theme READ theme NOTIFY themeChanged)
    Q_PROPERTY(bool devMode READ devMode CONSTANT)

    // ── Modpack Import ──
    Q_PROPERTY(QObject* modpackImporter READ modpackImporter CONSTANT)
    Q_PROPERTY(QObject* modpackExporter READ modpackExporter CONSTANT)

    // ── 外部 .minecraft 文件夹（选择/识别/读取，2026-08-18）──
    Q_PROPERTY(QObject* mcFolder READ mcFolder CONSTANT)

    // ── Update ──
    Q_PROPERTY(bool updateChecking READ updateChecking NOTIFY updateCheckingChanged)
    Q_PROPERTY(int updateState READ updateState NOTIFY updateStateChanged)

    // ── Agreements ──
    Q_PROPERTY(bool agreementAccepted READ agreementAccepted NOTIFY agreementAcceptedChanged)
    Q_PROPERTY(QString betaAgreementHtml READ betaAgreementHtml CONSTANT)
    Q_PROPERTY(QString privacyAgreementHtml READ privacyAgreementHtml CONSTANT)
    Q_PROPERTY(QString termsAgreementHtml READ termsAgreementHtml CONSTANT)
    Q_PROPERTY(bool markAgreed READ isMarkAgreed WRITE setMarkAgreed)
    // 编译期内测开关（SHADOW_ENABLE_BETA_GATE）：公测版恒 false，QML 据此隐藏内测 UI
    Q_PROPERTY(bool betaGateEnabled READ betaGateEnabled CONSTANT)
    bool isMarkAgreed() const { return false; }
    void setMarkAgreed(bool v);

    // ── Custom background ──
    Q_PROPERTY(QString customBgPath READ customBgPath NOTIFY customBgChanged)
    Q_PROPERTY(qreal sidebarOpacity READ sidebarOpacity NOTIFY customBgChanged)
    Q_PROPERTY(qreal contentOpacity READ contentOpacity NOTIFY customBgChanged)
    Q_PROPERTY(qreal backgroundBlur READ backgroundBlur NOTIFY customBgChanged)
    Q_PROPERTY(qreal cropX READ cropX WRITE setCropX NOTIFY customBgChanged)
    Q_PROPERTY(qreal cropY READ cropY WRITE setCropY NOTIFY customBgChanged)

    // ── Version details/summary ──
    Q_PROPERTY(QVariantList versionDetails READ versionDetails NOTIFY versionDetailsReady)
    Q_PROPERTY(bool isScanningVersions READ isScanningVersions NOTIFY scanningChanged)
    Q_PROPERTY(QVariantMap currentVersionSummary READ currentVersionSummary NOTIFY currentVersionSummaryChanged)

    // ── Download queue ──
    Q_PROPERTY(QVariantList downloadQueue READ downloadQueue NOTIFY downloadQueueChanged)
    Q_PROPERTY(QVariantList activeDownloads READ activeDownloads NOTIFY downloadQueueChanged)

    // ── Game info（2026-08-07 清理：版本文件夹卡片已删，gameDirInfo/gameDirectories/diskFree/diskPercent 随左侧卡片移除）──
    Q_PROPERTY(bool autoMemoryEnabled READ autoMemoryEnabled NOTIFY memorySettingsChanged)
    Q_PROPERTY(QVariantMap systemMemoryInfo READ systemMemoryInfo NOTIFY memorySettingsChanged)
    Q_PROPERTY(QVariantList availableCapes READ availableCapes CONSTANT)
    Q_PROPERTY(QString loginType READ loginType CONSTANT)
    Q_PROPERTY(QString selectedSkinPath READ selectedSkinPath NOTIFY skinChanged)
    Q_PROPERTY(bool wardrobeBusy READ isWardrobeBusy NOTIFY wardrobeBusyChanged)
    // 账号身份装载中（切号→令牌链→MC档案→披风下载）。
    // QML 拿到的 b 是 ShadowBackend，AccountBackend 的 identityLoading 它看不见，
    // 所以必须在这一层代理出去，否则顶部 SLoadingBar 永远不亮（实测踩过）。
    Q_PROPERTY(bool accountLoading READ accountLoading NOTIFY accountLoadingChanged)
    Q_PROPERTY(int fileDownloadSource READ fileDownloadSource WRITE setFileDownloadSource NOTIFY downloadSettingsChanged)
    Q_PROPERTY(int listDownloadSource READ listDownloadSource WRITE setListDownloadSource NOTIFY downloadSettingsChanged)
    Q_PROPERTY(int maxDownloadThreads READ maxDownloadThreads WRITE setMaxDownloadThreads NOTIFY downloadSettingsChanged)
    Q_PROPERTY(double downloadSpeedLimitMB READ downloadSpeedLimitMB WRITE setDownloadSpeedLimitMB NOTIFY downloadSettingsChanged)
    Q_PROPERTY(QString jvmArgs READ jvmArgs NOTIFY jvmArgsChanged)
    Q_PROPERTY(QString gameArgs READ gameArgs NOTIFY gameArgsChanged)
    Q_PROPERTY(bool highPerfGpu READ highPerfGpu NOTIFY highPerfGpuChanged)
    // ── 启动细节（低垂果实批，2026-08-08）──
    Q_PROPERTY(int gcMode READ gcMode WRITE setGcMode NOTIFY launchDetailChanged)
    Q_PROPERTY(int processPriority READ processPriority WRITE setProcessPriority NOTIFY launchDetailChanged)
    Q_PROPERTY(bool fullscreenEnabled READ fullscreenEnabled WRITE setFullscreenEnabled NOTIFY launchDetailChanged)
    Q_PROPERTY(QString autoJoinServer READ autoJoinServer WRITE setAutoJoinServer NOTIFY launchDetailChanged)
    Q_PROPERTY(QString windowTitleOverride READ windowTitleOverride WRITE setWindowTitleOverride NOTIFY launchDetailChanged)
    Q_PROPERTY(QString preLaunchCommand READ preLaunchCommand WRITE setPreLaunchCommand NOTIFY launchDetailChanged)
    Q_PROPERTY(QString postExitCommand READ postExitCommand WRITE setPostExitCommand NOTIFY launchDetailChanged)

    // ── Verify ──
    Q_PROPERTY(bool verifyRunning READ verifyRunning NOTIFY verifyRunningChanged)
    Q_PROPERTY(bool repairRunning READ repairRunning NOTIFY repairRunningChanged)
    Q_PROPERTY(int verifyChecked READ verifyChecked NOTIFY verifyCheckedChanged)
    Q_PROPERTY(int verifyTotal READ verifyTotal NOTIFY verifyTotalChanged)
    Q_PROPERTY(bool verifyResultOk READ verifyResultOk NOTIFY verifyResultTextChanged)
    Q_PROPERTY(QString verifyResultText READ verifyResultText NOTIFY verifyResultTextChanged)
    // InstallCardModel (QAbstractListModel) — exposed as QObject* for QML compat
    Q_PROPERTY(QObject* installCardsModel READ installCardsModel CONSTANT)

    // ── Beta key gate ──
    Q_PROPERTY(QString betaStatus READ betaStatus NOTIFY betaStatusChanged)

public:
    explicit ShadowBackend(QObject* parent = nullptr);

    // ── Account getters ──
    QString username() const;
    QString offlineUsername() const;
    bool isOnline() const;
    QString accountUuid() const;
    QString offlineUuid() const;
    // Q_PROPERTY loginType 的 READ 函数（不再额外暴露成方法；新 UI 用自己的 typeText）
    QString loginType() const;

    QString skinPath() const;
    QString skinTexturePath() const;
    QString offlineSkinPath() const;
    QStringList offlineUsernames() const;
    QVariantList accounts() const;
    int currentAccount() const;
    bool microsoftLoginBusy() const;
    QString msStatus() const;
    int lastLoginMode() const;
    void setLastLoginMode(int mode);

    // ── Settings getters ──
    QString javaPath() const;
    QString javaVersion() const;
    int javaMajor() const;
    bool javaInstalled() const;
    int minMemoryMb() const;
    int maxMemoryMb() const;
    bool isolationEnabled() const;
    int fileDownloadSource() const;
    void setFileDownloadSource(int v);
    int listDownloadSource() const;
    void setListDownloadSource(int v);
    int maxDownloadThreads() const;
    void setMaxDownloadThreads(int v);
    double downloadSpeedLimitMB() const;
    void setDownloadSpeedLimitMB(double v);
    bool embeddedLoginEnabled() const;
    Q_INVOKABLE void setEmbeddedLoginEnabled(bool v);

    // 让系统接管一次窗口拖动（无边框窗口没有系统标题栏，必须显式请求）。
    // 用 QWindow::startSystemMove() 而不是在 QML 里改 window.x/y：后者在高 DPI 下会漂移，
    // 也拿不到 Windows 的贴边吸附。
    Q_INVOKABLE void beginWindowMove();
    // 2026-08-15：实验性 tooltip 开关

    // ── Custom background ──
    QString customBgPath() const;
    Q_INVOKABLE void setCustomBgPath(const QString& path);
    qreal sidebarOpacity() const;
    Q_INVOKABLE void setSidebarOpacity(qreal v);
    qreal contentOpacity() const;
    Q_INVOKABLE void setContentOpacity(qreal v);
    qreal backgroundBlur() const;
    Q_INVOKABLE void setBackgroundBlur(qreal v);
    qreal cropX() const;
    Q_INVOKABLE void setCropX(qreal v);
    qreal cropY() const;
    Q_INVOKABLE void setCropY(qreal v);
    Q_INVOKABLE void updateCrop(qreal x, qreal y);
    Q_INVOKABLE QString pickBackgroundImage();

    QVariantList availableJavaList() const;

    // ── Version getters ──
    QString selectedVersion() const;
    QString lastPlayedLabel() const;
    /// 版本管理页用：任意版本的"上次游玩"文案（无记录返回空串）
    Q_INVOKABLE QString lastPlayedLabelFor(const QString& versionId) const;
    void recordLastPlayed(const QString& versionId);
    QStringList versionIds() const;
    QVariantList versionList() const;
    QVariantMap versionDateMap() const;
    QStringList releaseVersions() const;
    QStringList snapshotVersions() const;
    QStringList oldVersions() const;
    QStringList aprilFoolVersions() const;
    QStringList installedVersions() const;
    QStringList activeVersionNames() const;
    bool isInstalling() const;
    QString installVersionId() const;
    QString installPhase() const;
    QVariantList versionDetails() const { return m_versionDetails; }
    QVariantMap currentVersionSummary() const { return m_currentVersionSummary; }

    // ── Download queue ──
    QVariantList downloadQueue() const;
    QVariantList activeDownloads() const;

    // ── Launch getters ──
    bool isLaunching() const;
    int launchProgress() const;
    QString launchStatus() const;
    bool isRunning() const;
    int runningCount() const;
    QString launchVersion() const { return m_launchVersion; }
    QString launchUsername() const { return m_launchUsername; }
    void setLaunchVersion(const QString& v) { m_launchVersion = v; }
    void setLaunchUsername(const QString& u) { m_launchUsername = u; }

    // ── Crash getters ──
    QVariantMap lastCrash() const { return m_lastCrash; }
    bool crashAnalyzing() const { return m_crashAnalyzing; }

    // ── Resource getters ──
    bool isResourceDownloading() const;
    int resourceDownloadProgress() const { return m_resourceDlProgress; }
    int resourceDownloadTotal() const { return m_resourceDlTotal; }
    int resourceDownloadSpeed() const { return m_resourceDlSpeed; }
    QString resourceDownloadFile() const { return m_resourceDlFile; }

    // ── App getters ──
    QString gameDir() const;
    QString appDataDir() const;
    QString appVersion() const;
    QString theme() const;
    bool devMode() const;
    bool agreementAccepted() const;
    QString betaAgreementHtml() const;
    QString privacyAgreementHtml() const;
    QString termsAgreementHtml() const;

    bool autoMemoryEnabled() const;
    QVariantMap systemMemoryInfo() const;
    QString gameArgs() const;
    bool highPerfGpu() const;
    QString jvmArgs() const;

    // ── 启动细节（低垂果实批，2026-08-08）──
    int gcMode() const;
    Q_INVOKABLE void setGcMode(int v);
    int processPriority() const;
    Q_INVOKABLE void setProcessPriority(int v);
    bool fullscreenEnabled() const;
    Q_INVOKABLE void setFullscreenEnabled(bool v);
    QString autoJoinServer() const;
    Q_INVOKABLE void setAutoJoinServer(const QString& v);
    QString windowTitleOverride() const;
    Q_INVOKABLE void setWindowTitleOverride(const QString& v);
    QString preLaunchCommand() const;
    Q_INVOKABLE void setPreLaunchCommand(const QString& v);
    QString postExitCommand() const;
    Q_INVOKABLE void setPostExitCommand(const QString& v);
    /// 版本级覆盖：GC 模式（0=跟随全局）
    Q_INVOKABLE int versionGcMode(const QString& versionId) const;
    Q_INVOKABLE int versionProcessPriorityMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionProcessPriorityMode(const QString& versionId, int mode);
    Q_INVOKABLE int versionProcessPriority(const QString& versionId) const;
    Q_INVOKABLE void setVersionProcessPriority(const QString& versionId, int v);
    int resolvedProcessPriority(const QString& versionId) const;
    Q_INVOKABLE void setVersionGcMode(const QString& versionId, int mode);
    /// 版本级覆盖：自动进服地址（空=跟随全局）
    Q_INVOKABLE QString versionAutoJoinServer(const QString& versionId) const;
    Q_INVOKABLE void setVersionAutoJoinServer(const QString& versionId, const QString& addr);
    /// 版本级覆盖：全屏（mode 0=跟随全局 1=版本覆盖）
    Q_INVOKABLE int versionFullscreenMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionFullscreenMode(const QString& versionId, int mode);
    Q_INVOKABLE bool versionFullscreen(const QString& versionId) const;
    Q_INVOKABLE void setVersionFullscreen(const QString& versionId, bool v);
    /// 版本级覆盖：窗口标题
    Q_INVOKABLE int versionWindowTitleMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionWindowTitleMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionWindowTitle(const QString& versionId) const;
    Q_INVOKABLE void setVersionWindowTitle(const QString& versionId, const QString& v);
    /// 版本级覆盖：启动前命令
    Q_INVOKABLE int versionPreLaunchMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionPreLaunchMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionPreLaunchCommand(const QString& versionId) const;
    Q_INVOKABLE void setVersionPreLaunchCommand(const QString& versionId, const QString& v);
    /// 版本级覆盖：退出后命令
    Q_INVOKABLE int versionPostExitMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionPostExitMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionPostExitCommand(const QString& versionId) const;
    Q_INVOKABLE void setVersionPostExitCommand(const QString& versionId, const QString& v);
    /// 解析后的 GC 模式（版本级优先）
    int resolvedGcMode(const QString& versionId) const;
    /// 解析后的自动进服地址（版本级优先）
    QString resolvedAutoJoinServer(const QString& versionId) const;
    /// 解析后的全屏（版本级优先）
    bool resolvedFullscreen(const QString& versionId) const;
    /// 解析后的窗口标题（版本级优先）
    QString resolvedWindowTitle(const QString& versionId) const;
    /// 解析后的启动前命令（版本级优先）
    QString resolvedPreLaunchCommand(const QString& versionId) const;
    /// 解析后的退出后命令（版本级优先）
    QString resolvedPostExitCommand(const QString& versionId) const;
    // ── 设置导入导出（转发 SettingsBackend）──
    
    
    

    // ── Language hot-switch ──
    void setEngine(QQmlEngine* engine) { m_engine = engine; }
    void writeLanguageFile(int index) const;
    bool event(QEvent* event) override;

    // ── Verify stubs ──
    bool verifyRunning() const;
    bool repairRunning() const;
    int verifyChecked() const;
    int verifyTotal() const;
    QObject* installCardsModel() const;
    bool verifyResultOk() const;
    QString verifyResultText() const;
    void setVerifyResult(const QString& text, bool ok);

    // ── Mod/file list stubs ──
    Q_INVOKABLE QVariantList listMods(const QString& versionId = {}) const;
    Q_INVOKABLE QVariantList listSaves(const QString& versionId = {}) const;

    // ── 异步列表加载（模组上百时 parseJar/目录遍历耗时，worker 线程执行不卡 UI）──
    Q_INVOKABLE void listModsAsync(const QString& versionId = {});
    Q_INVOKABLE void listResourcePacksAsync(const QString& versionId = {});
    Q_INVOKABLE void listSavesAsync(const QString& versionId = {});

    // ── Q_INVOKABLE methods ──
    Q_INVOKABLE void offlineLogin(const QString& username);
    /// 离线登录是否受限：地区未明确检测为 CN（含检测失败/未完成/海外/港澳台）且未完成正版登录 → true
    /// （检测不出 CN 即受限——防止断网/屏蔽 GeoIP 绕过合规限制；正版登录后不受限）
    Q_INVOKABLE bool isOfflineRestricted() const;
    Q_INVOKABLE void updateOfflineSkin(const QString& username);
    Q_INVOKABLE void removeOfflineUsername(const QString& username);
    Q_INVOKABLE void microsoftLogin();
    Q_INVOKABLE void cancelMicrosoftLogin();
    void logout();
    /// 切到多账号列表第 index 个（外置账号会交给 YggdrasilBackend 恢复会话）
    Q_INVOKABLE void switchAccount(int index);
    Q_INVOKABLE bool removeAccount(int index);
    Q_INVOKABLE QVariantList scanJavaInstallations();
    Q_INVOKABLE QString autoSelectJava();
    Q_INVOKABLE QString browseJava();
    Q_INVOKABLE void selectJavaByIndex(int index);
    Q_INVOKABLE QVariantMap getMemoryStatus();
    Q_INVOKABLE void setMinMemory(int mb);
    Q_INVOKABLE void setMaxMemory(int mb);
    Q_INVOKABLE void setIsolationEnabled(bool enabled);
    Q_INVOKABLE QString getVersionGameDir(const QString& versionId) const;
    Q_INVOKABLE void migrateVersionToIsolated(const QString& versionId);
    Q_INVOKABLE bool openGameDir(const QString& versionId = {});
    Q_INVOKABLE bool openLatestLog(const QString& versionId = {});
    Q_INVOKABLE bool openLogsFolder(const QString& versionId = {});
    Q_INVOKABLE bool openLauncherLogsFolder();
    Q_INVOKABLE bool openCrashLog(const QString& versionId = {});
    // ── Crash analysis (forwarded to LaunchBackend) ──
    Q_INVOKABLE void analyzeCrashNow();
    Q_INVOKABLE QString exportCrashLogs(const QString& destDir = {});
    Q_INVOKABLE void openPath(const QString& path);
    Q_INVOKABLE void cleanupCrashArtifacts();
    Q_INVOKABLE bool openSavesFolder(const QString& versionId = {});
    Q_INVOKABLE bool openScreenshotsFolder(const QString& versionId = {});
    Q_INVOKABLE bool openModsFolder(const QString& versionId = {});
    Q_INVOKABLE bool openResourcePacksFolder(const QString& versionId = {});
    Q_INVOKABLE bool openShaderPacksFolder(const QString& versionId = {});
    Q_INVOKABLE bool openVersionDir(const QString& versionId);
    Q_INVOKABLE void deleteVersion(const QString& versionId);
    Q_INVOKABLE void refreshVersionList();
    Q_INVOKABLE void refreshInstalled();
    Q_INVOKABLE void refreshVersionDetails();
    Q_INVOKABLE void installVersion(const QString& versionId);
    Q_INVOKABLE void cancelVersionInstall(const QString& versionId);
    Q_INVOKABLE void dismissCard(const QString& installId);
    Q_INVOKABLE void retryVersionInstall(const QString& installId);
    Q_INVOKABLE void launch(const QString& versionId, bool online);
    Q_INVOKABLE void cancelLaunch();
    /// 开发期安全演示（只画浮层，不启动游戏）：mode 0=失败，1=成功
    Q_INVOKABLE void demoLaunch(int mode);
    Q_INVOKABLE void stopDemo();
    /// launch() 后半段：auth 注入 + 启动（Java 自动安装完成由 LaunchBackend 状态机继续）
    void proceedLaunch(const QString& versionId, bool online, const QString& javaPath,
                       int maxMemory, const QString& jvmArgs, const QString& gameArgs,
                       bool highPerfGpu);
    Q_INVOKABLE void killGameProcess();
    // 仅用于开发核对「准备运行环境」卡片排版（--ui-demo-repair 也走这个）

    /// 下载基线自检（离线、无网络）：步骤词表一致性 + StepNode 状态机/百分比钳制。
    /// 返回 "PASS ..." 或 "FAIL: ..." 字符串；供 /eval 与人工验收使用。

    /// 源策略现状摘要（供人工验收）：四项下载设置当前值 + 版本清单实际会用的主源/兜底源。

    /// 下载探针（仅本地验证用，不参与业务路径）：
    /// 用真实 FileDownloader 下载一个 URL，返回 bytes/file/ms/平均 MBps。
    /// limitKBps<=0 表示不限速。用于验证限速、取消、失败语义是否真的生效。

    /// 取消验证：跑 cancelAfterMs 后 cancel()，再观察 600ms 字节是否继续增长。
    /// 期望：cancelled 后 bytes 不再变化（契约 §5：取消必须中止在途请求）。

    /// 多文件探针：同一 URL 下 count 个文件（不同落盘路径），用于验收 QNAM 复用
    /// （创建次数应 ≈ 线程数，而不是 ≈ 文件数）。

    /// 取消残留诊断：取消后统计"目标文件 / .shadow_temp 分片 / 目录"是否还留东西。
    /// 不自动删除，交给验收者看；用于证明"取消能否完全清干净"。
    Q_INVOKABLE void killGameByPid(qint64 pid);
    Q_INVOKABLE QVariantList runningGames();
    Q_INVOKABLE void searchModsEx(const QString& query, const QString& loader,
        const QString& category, const QString& gameVersion,
        const QString& environment, const QString& license,
        int offset, int limit, const QString& source = {});
    /// 池子运行时状态（诊断 / 分页 hasMore）：kind = mod | shader | resourcepack | modpack | datapack
    Q_INVOKABLE QVariantMap resourcePoolState(const QString& kind) const;
    // CurseForge 分类静态表（QML 叠加下拉用）
    Q_INVOKABLE void searchShadersEx(const QString& query, const QStringList& gameVersions,
        const QStringList& categories, const QStringList& performance,
        const QStringList& loader, int offset, int limit, const QString& source = {});
    // 翻页预取（只预热缓存，不产生聚合信号，与真实搜索物理隔离）
    Q_INVOKABLE void prefetchModsEx(const QString& query, const QString& loader,
        const QString& category, const QStringList& gameVersions,
        int offset, int limit, const QString& source = {});
    Q_INVOKABLE void prefetchShadersEx(const QString& query, const QStringList& gameVersions,
        const QStringList& categories, int offset, int limit, const QString& source = {});
    Q_INVOKABLE void prefetchResourcepacks(const QString& query, const QString& gameVersion,
        int offset, const QStringList& categories, const QString& source = {});
    // 整合包翻页预取（只预热缓存，不产生聚合信号）
    Q_INVOKABLE void prefetchModpacks(const QString& query, const QString& loader,
        const QString& category, const QStringList& gameVersions,
        int offset, int limit, const QString& source = {});
    // 数据包翻页预取（同构）
    Q_INVOKABLE void prefetchDatapacks(const QString& query, const QString& category,
        const QStringList& gameVersions, const QString& sort,
        int offset, int limit, const QString& source = {});
    Q_INVOKABLE void searchResourcepacks(const QString& query, const QString& gameVersion = {}, int offset = 0, const QStringList& categories = {}, const QString& source = {});
    // 整合包双源搜索（池子架构）
    Q_INVOKABLE void searchModpacksEx(const QString& query, const QString& loader,
        const QString& category, const QStringList& gameVersions,
        int offset, int limit, const QString& source = {});
    // 数据包双源搜索（Modrinth project_type:datapack + CF classId=6945）
    Q_INVOKABLE void searchDatapacksEx(const QString& query, const QString& category,
        const QStringList& gameVersions, const QString& sort,
        int offset, int limit, const QString& source = {});
    // 整合包详情版本列表（Modrinth slug / CF 数字 id 自动路由，复用 modVersionsPartial）
    Q_INVOKABLE void fetchModpackVersions(const QString& slug, const QString& gameVersion = {}, const QString& loader = {});
    /// 整合包压缩包下载：静默下载到 {gameDir}/downloads/，完成后自动走导入流程
    /// 返回 dlId（卡片通道 mod:N）；versionName=用户指定版本名（注册名），actualName=整合包实际名
    /// 整合包任务是否占用中（下载中 或 导入中）→ 同一时间只允许一个整合包任务（下载或导入）
    Q_INVOKABLE void fetchResourcepackVersions(const QStringList& slugs);  // batch-fetch game_versions
    Q_INVOKABLE void fetchModVersions(const QStringList& slugs);
    Q_INVOKABLE void fetchShaderVersions(const QStringList& slugs);
    // CurseForge 详情页版本（复用 modVersionsPartial 等信号）
    Q_INVOKABLE void fetchModVersionsCf(const QString& modId, const QString& gameVersion = {}, const QString& loader = {});
    Q_INVOKABLE void fetchShaderVersionsCf(const QString& modId, const QString& gameVersion = {}, const QString& loader = {});
    Q_INVOKABLE void fetchResourcepackVersionsCf(const QString& modId, const QString& gameVersion = {}, const QString& loader = {});
    /// CF 详情页前置依赖解析（Modrinth 优先映射），结果经 cfDependenciesResolved 回传
    /// 汉化反查：英文名 → 中文名（依赖卡用），转发 resource 层
    Q_INVOKABLE QString resolveModZh(const QString& title) const;
    /// 详情页「转到 XX / 复制链接」统一链接解析（转发 resource 层），返回 { mrUrl, cfUrl, mcmodUrl }

    // Mod file download
    Q_INVOKABLE int downloadModFile(const QString& url, const QString& savePath, const QString& displayName,
                                    qint64 expectedSize, const QString& sha1, qint64 receivedOffset = 0, int resumeId = -1);
    Q_INVOKABLE void cancelModFileDownload(int downloadId);
    Q_INVOKABLE void pauseModFileDownload(int downloadId);
    Q_INVOKABLE void resumeModFileDownload(int downloadId);
    Q_INVOKABLE void retryModFileDownload(int downloadId);
    /// 2026-08-15：版本级前置依赖（详情页悬停 tooltip）
    Q_INVOKABLE void fetchVersionDependencies(const QString& slug, const QString& versionId);
    /// 按 versionId 取该版本主文件信息（url/filename/size/sha1）——一键安装前置用
    Q_INVOKABLE void fetchVersionFile(const QString& versionId);

    // ═══ Wardrobe (衣帽间) ═══
    Q_INVOKABLE void browseSkin();  // File dialog
    Q_INVOKABLE void uploadSkin(const QString& skinPath, int modelType);  // Mojang API
    Q_INVOKABLE void saveWardrobeSettings(const QString& skinPath, const QString& capeId, int modelType);
    Q_INVOKABLE void saveSkinToFile();
    Q_INVOKABLE QVariantList availableCapes() const;
    QString selectedSkinPath() const { return m_selectedSkinPath; }
    bool isWardrobeBusy() const { return m_wardrobeBusy; }
    bool accountLoading() const;
    bool isScanningVersions() const { return m_isScanningVersions; }

    // ── Mod Loader version queries (BMCLAPI) ──
    Q_INVOKABLE void queryForgeVersions(const QString& mcVersion);
    Q_INVOKABLE void queryFabricVersions(const QString& mcVersion);
    Q_INVOKABLE void queryNeoForgeVersions(const QString& mcVersion);
    Q_INVOKABLE void queryOptifineVersions(const QString& mcVersion);
    Q_INVOKABLE void queryFabricApiVersions(const QString& mcVersion);

    // Cancel all in-flight mod-loader version queries (called when install starts)

    // Cache Forge installer SHA1 from version list (avoids extra network fetch for verification)
    QString getForgeInstallerSha1(const QString& mcVer, const QString& forgeVer) const;

    // Cache Forge Maven branch suffix (e.g. "1.10.0" for MC 1.10, "mc172" for MC 1.7.2)
    void cacheForgeInstallerBranch(const QString& mcVer, const QString& forgeVer, const QString& branch);
    QString getForgeInstallerBranch(const QString& mcVer, const QString& forgeVer) const;


    // Mod loader installation
    Q_INVOKABLE void installModLoader(const QString& mcVersion, const QString& loaderType,
                                       const QString& loaderVersion, const QString& installName,
                                       const QString& fabricApiVersion = QString(),
                                       const QString& fabricApiUrl = QString(),
                                       const QString& fabricApiSavePath = QString(),
                                       const QString& forgeInstallerSha1 = QString());
    Q_INVOKABLE void installOptifine(const QString& mcVersion, const QString& optifineVersion,
                                       const QString& forgeVersion, const QString& installName,
                                       const QString& bmclType = QString(), const QString& bmclPatch = QString());
    /// 转发到 VersionBackend::installOptifineJar（InstallPage 直接调 backend.xxx，曾断链）
    Q_INVOKABLE void installOptifineJar(const QString& mcVersion, const QString& optifineVersion,
                                        const QString& bmclType = QString(), const QString& bmclPatch = QString(),
                                        const QString& installName = QString());
    /// 整合包导入-用户数据迁移：转发到 VersionBackend（InstallPage 直接调 backend.xxx，曾断链）
    Q_INVOKABLE void setPendingUserDataImport(const QString& installId, const QString& archivePath);
    Q_INVOKABLE void cancelPendingUserDataImport(const QString& installId);
    Q_INVOKABLE void setSelectedVersion(const QString& versionId);
    Q_INVOKABLE void setTheme(const QString& theme);
    Q_INVOKABLE QVariantMap checkAll(const QString& versionId);
    Q_INVOKABLE int getAutoMemory();
    Q_INVOKABLE void setAutoMemoryEnabled(bool enabled);

    // Per-version memory override
    Q_INVOKABLE int versionMemoryMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionMemoryMode(const QString& versionId, int mode);
    Q_INVOKABLE int versionMemoryManualMB(const QString& versionId) const;
    Q_INVOKABLE void setVersionMemoryManualMB(const QString& versionId, int mb);
    int resolvedMemoryMB(const QString& versionId);

    // Per-version Java/launch overrides (0=follow global, 1=custom)
    Q_INVOKABLE int versionJavaMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionJavaMode(const QString& versionId, int mode);
    Q_INVOKABLE int versionJvmArgsMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionJvmArgsMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionJvmArgs(const QString& versionId) const;
    Q_INVOKABLE void setVersionJvmArgs(const QString& versionId, const QString& args);
    QString resolvedJvmArgs(const QString& versionId) const;

    Q_INVOKABLE int versionGameArgsMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionGameArgsMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionGameArgs(const QString& versionId) const;
    Q_INVOKABLE void setVersionGameArgs(const QString& versionId, const QString& args);
    QString resolvedGameArgs(const QString& versionId) const;

    Q_INVOKABLE int versionHighPerfGpuMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionHighPerfGpuMode(const QString& versionId, int mode);
    Q_INVOKABLE bool versionHighPerfGpu(const QString& versionId) const;
    Q_INVOKABLE void setVersionHighPerfGpu(const QString& versionId, bool v);
    bool resolvedHighPerfGpu(const QString& versionId) const;

    // Global setters
    Q_INVOKABLE void setJvmArgs(const QString& args);
    Q_INVOKABLE void setGameArgs(const QString& args);
    Q_INVOKABLE void setHighPerfGpu(bool v);
    Q_INVOKABLE void copyToClipboard(const QString& text);

    // ── Q_INVOKABLE versions of Q_PROPERTY-only getters ──

    // ── Path/document stubs ──
    Q_INVOKABLE void openJavaFileDialog() { browseJava(); }
    Q_INVOKABLE void deleteMod(const QString& filename, const QString& versionId = {});
    Q_INVOKABLE void setModEnabled(const QString& filename, const QString& versionId = {}, bool enabled = true);
    /// 全部启用/禁用（2026-08-11）：返回实际改动数，QML 刷新列表 + toast
    Q_INVOKABLE int setAllModsEnabled(const QString& versionId, bool enabled);
    /// 导出启动脚本（.bat）——转发 launchBackend（2026-08-07）
    Q_INVOKABLE QString exportLaunchScript(const QString& versionId, const QString& javaPath,
                                           int maxMemoryMB, const QString& jvmArgs = {},
                                           const QString& gameArgs = {}, bool highPerfGpu = false);
    /// 写文本文件（QML 侧无直接文件写 API，2026-08-07）
    Q_INVOKABLE bool saveTextFile(const QString& path, const QString& content);
    Q_INVOKABLE void deleteResourcePack(const QString& filename, const QString& versionId = {});
    Q_INVOKABLE bool importResourcePack(const QString& filePath, const QString& versionId = {});
    Q_INVOKABLE bool importMod(const QString& filePath, const QString& versionId = {});
    Q_INVOKABLE void deleteSave(const QString& saveName, const QString& versionId = {});
    Q_INVOKABLE void migrateVersion(const QString& versionId);
    Q_INVOKABLE void cancelQueuedDownload(const QString& versionId);
    Q_INVOKABLE void verifyVersion(const QString& versionId);
    Q_INVOKABLE void cleanCorruptVersion(const QString& versionId);
    Q_INVOKABLE bool renameVersion(const QString& oldId, const QString& newId);
    Q_INVOKABLE bool renameVersion(const QString& oldId);  // single-param stub (dialog handled in QML)
    Q_INVOKABLE bool cloneVersion(const QString& sourceId, const QString& newId);
    Q_INVOKABLE bool cloneVersion(const QString& sourceId);  // auto-generates "{name} (副本)"
    Q_INVOKABLE QString copyVersionPath(const QString& versionId);
    Q_INVOKABLE void repairVersion(const QString& versionId);
    Q_INVOKABLE void cancelVerify();
    Q_INVOKABLE void openVerifyReport();

    // ── Beta key gate ──
    Q_INVOKABLE void submitBetaKey(const QString& key);
    QString betaStatus() const { return m_betaStatus; }
    // 编译期内测开关：公测版（未定义 SHADOW_ENABLE_BETA_GATE）恒返回 false
    static bool betaGateEnabled();
    static QString loadBetaKey();
    static bool validateBetaKey(const QString& key, QString* outError = nullptr);
    static bool saveBetaKey(const QString& key);

    // ── Modpack Import ──
    QObject* modpackImporter() const { return m_modpackImporter; }
    QObject* modpackExporter() const { return m_modpackExporter; }

    // ── Update ──
    Q_INVOKABLE void checkForUpdate();
    Q_INVOKABLE void quitForUpdate();   // 2026-08-15：确认重启安装后退出进程（下次启动 PreInit 自动安装）
    bool updateChecking() const;
    int updateState() const;

signals:
    void betaVerified();
    void betaKeyInvalid(const QString& reason);
    void betaStatusChanged();

    // ── Update signals ──
    void updateCheckingChanged();
    void updateStateChanged();
    void toastMessage(const QString& message);
    void updateDownloadProgress(qint64 received, qint64 total);
    void updateChangelogAvailable(const QString& version, const QString& notes);
    /// 2026-08-15：更新包下载完成、可重启安装（转发自 UpdateManager::updateAvailableForInstall，
    /// QML 弹常驻 toast 引导用户重启）
    void updateReadyForRestart(const QString& version);
    void accountChanged();
    void accountsChanged();
    void microsoftLoginProgress(const QString& step, const QString& detail);
    void microsoftLoginSuccess(const QString& username, const QString& uuid);
    void microsoftLoginFailed(const QString& error);
    void microsoftLoginBusyChanged();
    void skinReady();
    void offlineSkinReady();
    void offlineHistoryChanged();
    void javaPathChanged();
    /// Java 扫描完整结束（设置-Java 刷新按钮 toast）
    void javaScanFinished();
    void javaReadyChanged();
    void memorySettingsChanged();
    void jvmArgsChanged();
    void gameArgsChanged();
    void highPerfGpuChanged();
    /// 启动细节设置变更（GC/优先级/全屏/自动进服/窗口标题/pre-post 命令）
    void launchDetailChanged();
    void versionLaunchSettingsChanged(const QString& versionId);
    void launchBlocked(const QString& reason);
    void generalSettingsChanged();
    void downloadSettingsChanged();
    void isolationChanged();
    void embeddedLoginChanged();
    void versionListReady();
    // 手动刷新版本列表的结果（QML 收尾提示用）：ok=是否成功，message=失败原因，count=版本数
    void versionRefreshFinished(bool ok, const QString& message, int count);
    void versionDetailsReady();
    void scanningChanged();
    void installedVersionsChanged();
    // 异步列表加载完成（worker 线程扫描后回主线程发信号）
    void modsListReady(const QString& versionId, const QVariantList& mods);
    void resourcePacksListReady(const QString& versionId, const QVariantList& packs);
    void savesListReady(const QString& versionId, const QVariantList& saves);
    void activeVersionNamesChanged();
    void selectedVersionChanged();
    void lastPlayedChanged();
    void selectedVersionClearedAfterDelete();
    void currentVersionSummaryChanged();
    void installStateChanged();
    void installPhaseChanged();
    void installFinished(bool success);
    void installComplete(const QString& installName);
    void launchProgressChanged(int progress, const QString& status);
    void launchStateChanged();
    void launchPipelineChanged();
    void launchRepairsChanged();
    void minecraftStarted();
    void minecraftStopped();
    // ── Crash detection ──
    void crashDetected(const QVariantMap& report);
    /// 启动失败 → 开始异步分析（QML 弹 toast）
    void crashReportChanged();
    void crashAnalyzingChanged();
    void crashAnalysisStarted();
    /// 异步分析完成（完整报告）
    void crashAnalysisReady(const QVariantMap& report);
    void isRunningChanged();
    void runningCountChanged();
    void resourceDownloadStateChanged();
    void resourcepackSearchCompleted(const QVariantList& results, int totalHits);
    void resourcepackSearchFailed(const QString& error);
    void resourcepackDownloadFinished(const QString& slug, bool success, const QString& filePath);
    void resourcepackVersionsLoaded(const QVariantMap& slugToVersions);
    void resourcepackVersionsPartial(const QString& slug, const QStringList& versions, const QVariantMap& details);
    void resourcepackVersionsProgress(int done, int total);

    void modVersionsLoaded(const QVariantMap& slugToVersions);
    void modVersionsPartial(const QString& slug, const QStringList& versions, const QVariantMap& details);
    void modVersionsProgress(int done, int total);

    // Fabric API signals
    void fabricApiVersionsReady(const QVariantList& versions);

    // Mod file download signals
    void modFileDownloadStarted(int downloadId, const QString& fileName, qint64 fileSize, const QString& displayName);
    void modFileDownloadProgress(int downloadId, qint64 received, qint64 total);
    void modFileDownloadFinished(int downloadId, bool success, const QString& filePath, const QString& displayName);
    void modFileDownloadFailed(int downloadId, const QString& errorDetail, const QString& displayName);
    /// 2026-08-15：用户主动取消文件下载（QML 弹"取消成功" toast）
    void modFileDownloadCancelled(int downloadId, const QString& displayName);
    /// 2026-08-15：版本级前置依赖（悬停 tooltip）
    void versionDependenciesResolved(const QString& versionId, const QVariantList& deps);
    void versionFileResolved(const QString& versionId, const QVariantMap& file);
    /// 2026-08-15：MC/加载器安装取消（转发自 VersionBackend，QML 弹 toast）
    void cancelNotification(const QString& installId, const QString& message);
    /// 整合包搜索完成（池子全量，QML 按页切片）
    void modpackSearchResultsReady(const QVariantList& results);
    /// 数据包搜索完成（池子全量，QML 按页切片）
    void datapackSearchResultsReady(const QVariantList& results);
    /// CF 前置依赖解析完成（QML 回填依赖卡片）
    void cfDependenciesResolved(const QString& modId, const QVariantList& deps);

    void shaderVersionsLoaded(const QVariantMap& slugToVersions);
    void shaderVersionsPartial(const QString& slug, const QStringList& versions, const QVariantMap& details);
    void shaderVersionsProgress(int done, int total);
    void resourceDownloadProgress(int completed, int total, const QString& fileName);
    void resourceDownloadDone(bool success);
    void verifyRunningChanged();
    void repairRunningChanged();
    void verifyCheckedChanged();
    void verifyTotalChanged();
    void verifyResultTextChanged();
    void downloadQueueChanged();
    void downloadQueueFull(const QString& displayName);
    void searchResultsReady(const QVariantList& results);  // deprecated
    void modSearchResultsReady(const QVariantList& results);
    void shaderSearchResultsReady(const QVariantList& results);
    void gameDirChanged();
    void themeChanged();
    void agreementAcceptedChanged();
    void loginModeChanged();
    void customBgChanged();
    void logMessage(const QString& msg);
    void skinChanged();
    void wardrobeBusyChanged();
    void accountLoadingChanged();
    void wardrobeError(const QString& error);

    // ── Mod loader version signals ──
    void forgeVersionsReady(const QVariantList& versions);
    void fabricVersionsReady(const QVariantList& versions);
    void neoforgeVersionsReady(const QVariantList& versions);
    void optifineVersionsReady(const QVariantList& versions);


    // ── Icon cache signal ──
    void iconCached(const QString& webpUrl, const QString& pngPath);
    // 资源拉取引擎（司南）图标就绪信号：QML 监听并更新 model 对应项
    void iconReady(const QString& url, const QString& localPath);

    // ── Auto-test navigation signal ──
    // pageIndex: 0=Launch, 1=Download, 2=Settings
    // subTab: for Download page → 0=MC, 1=Mod, 2=Shader, 3=RP; otherwise ignored
    void navigateToRequested(int pageIndex, int subTab);

    // ── Auto-test: open RP detail page ──
    void openRpDetailRequested(const QString& slug);
    void openModDetailRequested(const QString& slug);
    void openShaderDetailRequested(const QString& slug);
    void openPackDetailRequested(const QString& slug);

    // ── Auto-test: UI interaction signals ──
    void setRpShowPreReleases(bool show);
    void openRpVersionMenu();
    void expandRpDetailGroup(const QString& major);
    void selectRpDetailSubVer(const QString& version);

    // ── Verify signals ──
    void verifyStarted();
    void verifyProgress(int checked, int total);
    void verifyFinished(bool allPassed);
    void verifyFailedFiles(const QStringList& failedFiles);

    // ── Pre-launch check signals ──
    void launchCheckProgress(const QString& step);
    void launchCheckFailed(const QString& phase, const QString& details);
    void launchCheckMissingFiles(const QStringList& files);
    void launchCheckWarning(const QString& warning);

public:
    AppBackend* app() const { return m_app; }
    AccountBackend* account() const { return m_account; }
    QObject* yggdrasil() const { return m_yggdrasil; }
    Q_INVOKABLE SettingsBackend* settings() const { return m_settings; }
    // Auto-language mode helpers (bypass backend.settings.* QML chain issues in Loaders)
    // ── UI 一次性标记（QSettings 持久化；2026-08-24 v1.0.1 一次性启动公告 toast 用）──
    // 更新后首次启动判定（蓝色"更新内容"toast 仅更新用户弹出；一次性消费；2026-08-25）
    CheckBackend* check() const { return m_check; }
    VersionBackend* version() const { return m_version; }
    LaunchBackend* launchBackend() const { return m_launch; }
    QObject* launchPipeline() const;
    qreal launchOverallProgress() const;
    int launchStepCount() const;
    int launchStepNumber() const;
    QVariantList launchStepRows() const;
    bool launchFailed() const;
    QString launchFailReason() const;
    bool launchFinishedOk() const;
    QVariantList launchRepairs() const;
    ResourceBackend* resource() const { return m_resource; }
    // 注意：QML 暴露必须用 Q_PROPERTY(QObject*) 模式——Q_INVOKABLE 返回具体类型指针
    // 会报 "Unknown method return type"（2026-08-04 导出功能踩坑实锤）
    Q_PROPERTY(QObject* javaBackend READ javaBackend CONSTANT)
    Q_PROPERTY(QObject* userDataBackend READ userDataBackend CONSTANT)
    QObject* javaBackend() const { return m_java; }
    QObject* userDataBackend() const { return m_userData; }

    double totalGameHours() const;
    QObject* modManager() const;  // QML exposed (returns m_resource->modManager())
    QObject* multiplayer() const;
    QObject* mcFolder() const;  // 外部 .minecraft 选择/识别/读取（实现见 cpp，需完整类型转换）
    // 资源拉取引擎访问器（ResourceBackend 搜索接入用）
    ResourceFetchEngine* fetchEngine() const { return m_fetchEngine; }

    // ── Icon cache (QML-callable methods: mod / shader / rp) ──
    // 原生"选择文件夹"对话框（Win32 IFileOpenDialog + FOS_PICKFOLDERS）。
    // 为什么不用 Qt 的 FolderDialog：本程序未链接 QtWidgets，FolderDialog.open() 会静默失败，
    // 既不显示窗口、还会把后续的 SaveFile 对话框一起卡住。
    // 返回空串表示用户取消。
    Q_INVOKABLE QString pickFolder(const QString &initialDir = QString());

    Q_INVOKABLE QString resolveIconUrl(const QString &url);


private:
    int requiredJavaMajor(const QString& versionId);
    static int inferJavaByMcVersion(const QString& mcVersion);
    QString gameDirForVersion(const QString& versionId) const;
    bool isVersionInstalled(const QString& versionId) const;
    void syncPlayerName();
    void checkChangelog();
    void loadJavaRuntimeSettings();
    void saveJvmArgs();
    void saveGameArgs();
    void saveHighPerfGpu();

    // ── 外部 .minecraft 目录应用/回退（MinecraftFolderBackend 信号驱动）──
    void onApplyForeignFolder(const QString& root, int layout);
    void onRevertForeignFolder();

    AppBackend* m_app = nullptr;
    AccountBackend* m_account = nullptr;
    SettingsBackend* m_settings = nullptr;
    CheckBackend* m_check = nullptr;
    VersionBackend* m_version = nullptr;
    LaunchBackend* m_launch = nullptr;
    ResourceBackend* m_resource = nullptr;
    JavaBackend*    m_java = nullptr;
    QObject* m_yggdrasil = nullptr;
    UserDataBackend* m_userData = nullptr;
    IconCache* m_modIconCache = nullptr;
    IconCache* m_shaderIconCache = nullptr;
    IconCache* m_rpIconCache = nullptr;
    ResourceFetchEngine* m_fetchEngine = nullptr;
    MultiplayerManager* m_multiplayer = nullptr;
    LocalModManager* m_localMods = nullptr;
    class GeoIpService* m_geoIp = nullptr;
    QObject* m_modpackImporter = nullptr;
    QObject* m_modpackExporter = nullptr;
    MinecraftFolderBackend* m_mcFolder = nullptr;

    bool m_isolationEnabled = true;
    int m_lastLoginMode = 1;
    // versionId -> 上次真正起进程的 epoch 毫秒（dataDir/last-played.json）
    QHash<QString, qint64> m_lastPlayed;
    QString formatLastPlayed(qint64 epochMs) const;
    QString m_launchVersion;
    QString m_launchUsername;

    // ── Beta key ──
    QString m_betaStatus;

    // ── Translation hot-switch ──
    QTranslator* m_translator = nullptr;
    QQmlEngine* m_engine = nullptr;
    QString m_currentLang = QStringLiteral("zh_CN");
    QVariantMap m_lastCrash;
    bool m_crashAnalyzing = false;
    QString m_verifyReportPath;
    QString m_gameDir;
    QVariantList m_versionDetails;
    // 版本列表/日期表缓存（versionListReady 时失效）：避免 QML 序列逐项访问时反复重建
    mutable QVariantList m_versionListCache;
    mutable QVariantMap m_versionDateMapCache;
    mutable bool m_versionListCacheValid = false;
    QVariantMap m_currentVersionSummary;

    // ── Async version scanning state ──
    bool m_isScanningVersions = false;

    // ── Resource download progress tracking ──
    int m_resourceDlProgress = 0;
    int m_resourceDlTotal = 0;
    int m_resourceDlSpeed = 0;
    QString m_resourceDlFile;
    QMap<int, QString> m_modDownloadCards;  // dlId → cardId for mod file cards

    // 整合包压缩包下载 → 自动导入联动记录（dlId → 待导入信息）
    struct PackDownloadInfo {
        QString zipPath;       // 下载落盘路径（{gameDir}/downloads/xxx.mrpack|zip）
        QString versionName;   // 用户指定版本名（注册名）
        QString iconUrl;       // 整合包图标（搜索结果来源，传给导入卡片）
    };
    QMap<int, PackDownloadInfo> m_packDownloads;
    bool m_packDownloading = false;   // 整合包压缩包正在下载中（同一时间只允许一个整合包任务）

    // Mod-loader query tracking (for cancellation when install starts)
    QList<QPointer<QNetworkReply>> m_modLoaderReplies;
    bool m_modLoaderQueriesCancelled = false;

    // Forge installer SHA1 cache (populated from version list API)
    QMap<QString, QString> m_forgeInstallerSha1Cache;  // "mcVer-forgeVer" -> sha1
    QMap<QString, QString> m_forgeInstallerBranchCache; // "mcVer-forgeVer" -> branch (e.g. "1.10.0", "mc172")

    // ── Update ──
    UpdateManager* m_updateManager = nullptr;

    // ── Wardrobe cache ──
    QVariantList m_capeCache;
    void initCapeCache();
    QString m_selectedSkinPath;
    bool m_wardrobeBusy = false;

    // ── Verify results ──
    QString m_verifyResultText;
    bool m_verifyResultOk = true;
};
}
