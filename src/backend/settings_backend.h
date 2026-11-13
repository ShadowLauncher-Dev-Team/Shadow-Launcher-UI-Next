// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once
#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>
#include <QTimer>

namespace ShadowLauncher {

class VersionIsolation;

class SettingsBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString javaPath READ javaPath WRITE setJavaPath NOTIFY javaPathChanged)
    Q_PROPERTY(QString javaVersion READ javaVersion NOTIFY javaPathChanged)
    Q_PROPERTY(int javaMajor READ javaMajor NOTIFY javaPathChanged)
    Q_PROPERTY(int minMemoryMB READ minMemoryMB NOTIFY memorySettingsChanged)
    Q_PROPERTY(int maxMemoryMB READ maxMemoryMB NOTIFY memorySettingsChanged)
    Q_PROPERTY(bool autoMemoryEnabled READ autoMemoryEnabled WRITE setAutoMemoryEnabled NOTIFY memorySettingsChanged)
    Q_PROPERTY(bool javaReady READ isJavaReady NOTIFY javaPathChanged)
    Q_PROPERTY(bool isolationEnabled READ isolationEnabled NOTIFY isolationChanged)
    Q_PROPERTY(bool embeddedLoginEnabled READ embeddedLoginEnabled WRITE setEmbeddedLoginEnabled NOTIFY embeddedLoginChanged)
    Q_PROPERTY(int languageIndex READ languageIndex WRITE setLanguageIndex NOTIFY languageChanged)
    Q_PROPERTY(bool languageChanged READ isLanguageChanged NOTIFY languageChanged)
    Q_PROPERTY(QString customBgPath READ customBgPath WRITE setCustomBgPath NOTIFY customBgChanged)
    Q_PROPERTY(qreal sidebarOpacity READ sidebarOpacity WRITE setSidebarOpacity NOTIFY customBgChanged)
    Q_PROPERTY(qreal contentOpacity READ contentOpacity WRITE setContentOpacity NOTIFY customBgChanged)
    Q_PROPERTY(qreal backgroundBlur READ backgroundBlur WRITE setBackgroundBlur NOTIFY customBgChanged)
    Q_PROPERTY(qreal cropX READ cropX WRITE setCropX NOTIFY customBgChanged)
    Q_PROPERTY(qreal cropY READ cropY WRITE setCropY NOTIFY customBgChanged)
    // 2026-11-13 外观页：背景图缩放倍率（1.0 = 恰好铺满；>1 放大后可在框内拖动取景）
    Q_PROPERTY(qreal bgZoom READ bgZoom WRITE setBgZoom NOTIFY customBgChanged)
    // 配色方案："dark"（黑，默认）/ "light"（白）
    Q_PROPERTY(QString colorScheme READ colorScheme WRITE setColorScheme NOTIFY colorSchemeChanged)
    Q_PROPERTY(int fileDownloadSource READ fileDownloadSource WRITE setFileDownloadSource NOTIFY downloadSettingsChanged)
    Q_PROPERTY(int listDownloadSource READ listDownloadSource WRITE setListDownloadSource NOTIFY downloadSettingsChanged)
    Q_PROPERTY(int maxDownloadThreads READ maxDownloadThreads WRITE setMaxDownloadThreads NOTIFY downloadSettingsChanged)
    Q_PROPERTY(double downloadSpeedLimitMB READ downloadSpeedLimitMB WRITE setDownloadSpeedLimitMB NOTIFY downloadSettingsChanged)
    Q_PROPERTY(int autoLangMode READ autoLangMode WRITE setAutoLangMode NOTIFY autoLangModeChanged)
    // 游戏目录（只读）：设置页「高级」要显示绝对路径
    Q_PROPERTY(QString gameDir READ gameDir NOTIFY gameDirChanged)
    // ── 启动细节（低垂果实批，2026-08-08：对齐 主流启动器/主流启动器）──
    Q_PROPERTY(int gcMode READ gcMode WRITE setGcMode NOTIFY launchDetailChanged)
    Q_PROPERTY(int processPriority READ processPriority WRITE setProcessPriority NOTIFY launchDetailChanged)
    Q_PROPERTY(bool fullscreenEnabled READ fullscreenEnabled WRITE setFullscreenEnabled NOTIFY launchDetailChanged)
    Q_PROPERTY(QString autoJoinServer READ autoJoinServer WRITE setAutoJoinServer NOTIFY launchDetailChanged)
    Q_PROPERTY(QString windowTitleOverride READ windowTitleOverride WRITE setWindowTitleOverride NOTIFY launchDetailChanged)
    Q_PROPERTY(QString preLaunchCommand READ preLaunchCommand WRITE setPreLaunchCommand NOTIFY launchDetailChanged)
    Q_PROPERTY(QString postExitCommand READ postExitCommand WRITE setPostExitCommand NOTIFY launchDetailChanged)

public:
    explicit SettingsBackend(QObject* parent = nullptr);

    QString javaPath() const { return m_javaPath; }
    QString javaVersion() const { return m_javaVersion; }
    int javaMajor() const { return m_javaMajor; }
    int minMemoryMB() const { return m_minMemoryMB; }
    int maxMemoryMB() const { return m_maxMemoryMB; }
    bool autoMemoryEnabled() const { return m_autoMemory; }
    QString lastLaunchedVersion() const { return m_lastLaunchedVersion; }
    void setLastLaunchedVersion(const QString& v) {
        m_lastLaunchedVersion = v;
        saveSettings();
    }
    QString lastSelectedVersion() const { return m_lastSelectedVersion; }
    void setLastSelectedVersion(const QString& v) {
        m_lastSelectedVersion = v;
        saveSettings();
    }
    bool isJavaReady() const { return m_javaReady; }

    void setJavaPath(const QString& path);

    // ---- Slots ----
    Q_INVOKABLE QVariantList scanJavaInstallations();
    Q_INVOKABLE bool isJavaScanning() const { return m_javaScanning; }
    Q_INVOKABLE QString autoSelectJava();
    /// 回到「由启动器按版本需求自动挑 Java」：清掉手动指定。
    /// 不能复用 setJavaPath("") —— 它会因为 isFile() 失败而拒绝。
    Q_INVOKABLE void useAutoJava();
    Q_INVOKABLE QString detectJava();         // QML alias
    Q_INVOKABLE QVariantMap getMemoryStatus();
    Q_INVOKABLE void setMinMemory(int mb);
    Q_INVOKABLE void setMaxMemory(int mb);
    Q_INVOKABLE void setAutoMemoryEnabled(bool enabled);

    // Per-version memory override
    Q_INVOKABLE int versionMemoryMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionMemoryMode(const QString& versionId, int mode);
    Q_INVOKABLE int versionMemoryManualMB(const QString& versionId) const;
    Q_INVOKABLE void setVersionMemoryManualMB(const QString& versionId, int mb);

    // ── Per-version Java/launch overrides ──
    Q_INVOKABLE int versionJavaMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionJavaMode(const QString& versionId, int mode);
    Q_INVOKABLE int versionJvmArgsMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionJvmArgsMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionJvmArgs(const QString& versionId) const;
    Q_INVOKABLE void setVersionJvmArgs(const QString& versionId, const QString& args);

    Q_INVOKABLE int versionGameArgsMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionGameArgsMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionGameArgs(const QString& versionId) const;
    Q_INVOKABLE void setVersionGameArgs(const QString& versionId, const QString& args);

    Q_INVOKABLE int versionHighPerfGpuMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionHighPerfGpuMode(const QString& versionId, int mode);
    Q_INVOKABLE bool versionHighPerfGpu(const QString& versionId) const;
    Q_INVOKABLE void setVersionHighPerfGpu(const QString& versionId, bool v);

    // ── 启动细节（版本级覆盖，对齐主流启动器实现 VersionAdvanceGC/VersionServerEnter）──
    Q_INVOKABLE int versionGcMode(const QString& versionId) const;      // 0=跟随全局 1-3=覆盖
    // 进程优先级版本级覆盖：mode 0=跟随全局 1=覆盖（0..2 见 launcher.cpp SetPriorityClass）
    Q_INVOKABLE int versionProcessPriorityMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionProcessPriorityMode(const QString& versionId, int mode);
    Q_INVOKABLE int versionProcessPriority(const QString& versionId) const;
    Q_INVOKABLE void setVersionProcessPriority(const QString& versionId, int v);
    Q_INVOKABLE void setVersionGcMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionAutoJoinServer(const QString& versionId) const;  // 空=跟随全局
    Q_INVOKABLE void setVersionAutoJoinServer(const QString& versionId, const QString& addr);
    // 全屏/窗口标题/命令：mode 语义同 highPerfGpu（0=跟随全局 1=版本覆盖）
    Q_INVOKABLE int versionFullscreenMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionFullscreenMode(const QString& versionId, int mode);
    Q_INVOKABLE bool versionFullscreen(const QString& versionId) const;
    Q_INVOKABLE void setVersionFullscreen(const QString& versionId, bool v);
    Q_INVOKABLE int versionWindowTitleMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionWindowTitleMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionWindowTitle(const QString& versionId) const;
    Q_INVOKABLE void setVersionWindowTitle(const QString& versionId, const QString& v);
    Q_INVOKABLE int versionPreLaunchMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionPreLaunchMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionPreLaunchCommand(const QString& versionId) const;
    Q_INVOKABLE void setVersionPreLaunchCommand(const QString& versionId, const QString& v);
    Q_INVOKABLE int versionPostExitMode(const QString& versionId) const;
    Q_INVOKABLE void setVersionPostExitMode(const QString& versionId, int mode);
    Q_INVOKABLE QString versionPostExitCommand(const QString& versionId) const;
    Q_INVOKABLE void setVersionPostExitCommand(const QString& versionId, const QString& v);

    Q_INVOKABLE QVariantList availableJavaList();
    Q_INVOKABLE void selectJavaByIndex(int index);
    Q_INVOKABLE QVariantList persistedJavaList();
    Q_INVOKABLE QString findJavaForVersion(int requiredMajor, int maxMajor = 0);
    // maxMajor>0 时限制在 [requiredMajor, maxMajor] 区间（老版本 Mixin 兼容上限）
    Q_INVOKABLE QString openJavaFileDialog();
    Q_INVOKABLE QString browseJava();          // QML alias
    // ── 设置导入导出（2026-08-08：主流启动器 CacheExportConfig 对齐）──
    /// 导出全部启动器设置到指定文件（ini 格式），成功返回 true

    /// 从文件导入设置（合并，覆盖已有值），成功返回 true

    /// 导出的设置内容预览（供 QML 确认弹窗展示）

    void setMinecraftDir(const QString& dir);
    Q_INVOKABLE void setIsolationEnabled(bool enabled);
    Q_INVOKABLE void migrateVersionToIsolated(const QString& versionId);
    Q_INVOKABLE QString getVersionGameDir(const QString& versionId) const;
    Q_INVOKABLE bool isolationEnabled() const;
    Q_INVOKABLE void openGameDir();
    Q_INVOKABLE bool openVersionDir(const QString& versionId);
    Q_INVOKABLE void deleteVersion(const QString& versionId);
    bool embeddedLoginEnabled() const { return m_embeddedLoginEnabled; }
    Q_INVOKABLE void setEmbeddedLoginEnabled(bool v);
    // ── 2026-08-15：版本悬停前置依赖 tooltip（实验性，可能卡顿/信息有误）──
    int languageIndex() const { return m_languageIndex; }
    Q_INVOKABLE void setLanguageIndex(int idx);
    bool isLanguageChanged() const { return m_languageIndex != m_launchLanguageIndex; }

    // ── 启动细节 getter/setter（全局）──
    int gcMode() const { return m_gcMode; }
    // GC 模式：0=自动 1=分代ZGC 2=仅G1GC 3=不指定（见 launcher.cpp collectGcArgs）
    void setGcMode(int v) { m_gcMode = qBound(0, v, 3); saveSettings(); emit launchDetailChanged(); }
    int processPriority() const { return m_processPriority; }
    // 进程优先级：0=AboveNormal 1=默认 2=BelowNormal（见 launcher.cpp setProcessPriority）
    void setProcessPriority(int v) { m_processPriority = qBound(0, v, 2); saveSettings(); emit launchDetailChanged(); }
    bool fullscreenEnabled() const { return m_fullscreenEnabled; }
    void setFullscreenEnabled(bool v) { m_fullscreenEnabled = v; saveSettings(); emit launchDetailChanged(); }
    QString autoJoinServer() const { return m_autoJoinServer; }
    // 实现见 cpp：只接受 host[:port]，拒绝会污染 --server 后续参数的内容
    void setAutoJoinServer(const QString& v);
    QString windowTitleOverride() const { return m_windowTitleOverride; }
    void setWindowTitleOverride(const QString& v) { m_windowTitleOverride = v; saveSettings(); emit launchDetailChanged(); }
    QString preLaunchCommand() const { return m_preLaunchCommand; }
    void setPreLaunchCommand(const QString& v) { m_preLaunchCommand = v; saveSettings(); emit launchDetailChanged(); }
    QString postExitCommand() const { return m_postExitCommand; }
    void setPostExitCommand(const QString& v) { m_postExitCommand = v; saveSettings(); emit launchDetailChanged(); }

    // Custom background
    QString customBgPath() const { return activeBgPath(); }
    // 兼容旧接口：把某个本地路径直接当成「一张新导入的图」加进图库并激活
    void setCustomBgPath(const QString& path) { importBgFile(path); }
    qreal sidebarOpacity() const { return m_sidebarOpacity; }
    void setSidebarOpacity(qreal v) { m_sidebarOpacity = qBound(0.0, v, 1.0); saveSettings(); emit customBgChanged(); }
    qreal contentOpacity() const { return m_contentOpacity; }
    void setContentOpacity(qreal v) { m_contentOpacity = qBound(0.0, v, 1.0); saveSettings(); emit customBgChanged(); }
    qreal backgroundBlur() const { return m_backgroundBlur; }
    void setBackgroundBlur(qreal v) { m_backgroundBlur = qBound(0.0, v, 1.0); saveSettings(); emit customBgChanged(); }
    qreal cropX() const { return activeBg().cropX; }
    void setCropX(qreal v) { setActiveView(activeBg().zoom, qBound(0.0, v, 1.0), activeBg().cropY); }
    Q_INVOKABLE void updateCrop(qreal x, qreal y) {
        setActiveView(activeBg().zoom, qBound(0.0, x, 1.0), qBound(0.0, y, 1.0));
    }
    qreal cropY() const { return activeBg().cropY; }
    void setCropY(qreal v) { setActiveView(activeBg().zoom, activeBg().cropX, qBound(0.0, v, 1.0)); }

    // ── 启动页背景（外观页）──────────────────────────────────
    qreal bgZoom() const { return activeBg().zoom; }
    void setBgZoom(qreal v) { setActiveView(qBound(1.0, v, 4.0), activeBg().cropX, activeBg().cropY); }

    // ── 背景图库 ────────────────────────────────────────────
    // 每张图（内置 / 每张导入的）各自保存 path + zoom + cropX + cropY。
    // 切换只是改 active，谁也不清空谁 —— 「切回默认后再切回来」图和取景都还在。
    struct BgImage {
        QString id;      // 内置用固定 id；导入的用 "u:<sha1>"
        QString name;    // 展示名（导入的是文件名）
        QString path;    // 本地绝对路径；内置为空（走 qrc）
        QString source;  // 可直接喂给 Image 的 URL（qrc:/ 或 file:///）
        bool builtin = false;
        qreal zoom = 1.0;
        qreal cropX = 0.5;
        qreal cropY = 0.5;
    };
    /// 图库列表（内置在前，导入的按加入顺序）；每项带 active 标记
    Q_INVOKABLE QVariantList bgPresets() const;
    /// 切换当前使用的图（未知 id → 回落到默认极光）
    Q_INVOKABLE void applyBgPreset(const QString& presetId);
    /// 选择本地图片：复制进数据目录、追加到图库并激活；返回是否成功
    Q_INVOKABLE bool chooseBgImage();
    /// 恢复默认背景（= 切回内置极光，**不删任何已导入的图**）
    Q_INVOKABLE void restoreDefaultBg();
    /// 只把当前图的取景复位（缩放 1.0、居中），不换图
    Q_INVOKABLE void resetBgView();
    /// 从图库移除一张导入的图（删数据目录副本）；内置图不可删
    Q_INVOKABLE void removeBgImage(const QString& id);
    /// 导入一张本地图片进图库并激活；返回新条目 id（空 = 失败）。
    /// 会复制到 setBgStorageDir() 指定的目录，原图后续被移动/删除都不影响。
    QString importBgFile(const QString& path);
    /// 指定导入图片的存放目录（由 ShadowBackend 注入 dataDir/custom_bg）
    void setBgStorageDir(const QString& dir) { m_bgStorageDir = dir; }
    /// 当前图的本地路径（内置返回空）
    QString activeBgPath() const { return activeBg().path; }
    /// 当前图的显示 URL（内置返回 qrc，导入返回 file:///）
    QString activeBgSource() const { return activeBg().source; }

    // ── 配色方案 ─────────────────────────────────────────────
    QString colorScheme() const { return m_colorScheme; }
    void setColorScheme(const QString& scheme);

    // ── Auto-language mode ──
    int autoLangMode() const { return m_autoLangMode; }
    // Returns combo box index for QML (mode → idx mapping: 0→2, 1→0, 2→1)
    int autoLangModeComboIndex() const;
    Q_INVOKABLE void setAutoLangMode(int mode);
    // Window resolution

    // Download settings
    int fileDownloadSource() const { return m_fileDownloadSource; }
    // DownloadSourcePolicy：0=镜像优先 1=官方优先 2=自动切换（utils/types.h）
    void setFileDownloadSource(int v) { m_fileDownloadSource = qBound(0, v, 2); saveSettings(); emit downloadSettingsChanged(); }
    int listDownloadSource() const { return m_listDownloadSource; }
    void setListDownloadSource(int v) { m_listDownloadSource = qBound(0, v, 2); saveSettings(); emit downloadSettingsChanged(); }
    int maxDownloadThreads() const { return m_maxDownloadThreads; }
    /// 并发上限 1..24：默认 16。64 是旧值 —— BMCLAPI/CF 在 64 并发下会 429/饿死连接，
    /// 且 64 个 worker 各自持有 QNAM，连接数与内存都失控（契约 S1）。
    void setMaxDownloadThreads(int v) { m_maxDownloadThreads = qBound(1, v, 24); saveSettings(); emit downloadSettingsChanged(); }
    double downloadSpeedLimitMB() const { return m_downloadSpeedLimitMB; }
    // 限速：<=0 一律表示不限速（-1）。
    // 旧实现用 v<0，导致 UI 拖到 0 想表示"不限速"时被夹成 0.1MB/s（几乎断网）。
    void setDownloadSpeedLimitMB(double v) { m_downloadSpeedLimitMB = (v <= 0) ? -1.0 : qBound(0.1, v, 20.0); saveSettings(); emit downloadSettingsChanged(); }
    void setIsolationGameDir(const QString& dir);
    VersionIsolation* isolation() const { return m_isolation; }
    QString gameDir() const { return m_gameDir; }
    // 设置页要显示「游戏目录」的绝对路径。原来只有 C++ 方法、没暴露给 QML，
    // QML 里读 s.gameDir 会拿到 undefined（日志：Unable to assign [undefined] to QString）。


signals:
    void javaPathChanged();
    /// 一次 Java 扫描完整结束（刷新按钮/自动检测完成后弹 toast）
    void javaScanFinished();
    void javaReadyChanged();
    void memorySettingsChanged();
    void generalSettingsChanged();
    void gameDirChanged();
    void isolationChanged();
    void embeddedLoginChanged();

    void languageChanged();
    void customBgChanged();
    void colorSchemeChanged();
    void downloadSettingsChanged();
    void autoLangModeChanged();
    /// 启动细节设置变更（GC/优先级/全屏/自动进服/窗口标题/pre-post 命令）
    void launchDetailChanged();
    void windowSettingsChanged();
    void logMessage(const QString& msg);

private:
    struct JavaInfo {
        QString path;
        QString version;
        int major = 0;
    };

    void loadSettings();
    void saveSettings();
    void doAutoDetect();
    const QVector<JavaInfo>& cachedJavaList();
    void loadJavaList();
    void saveJavaList(const QVector<JavaInfo>& list);
    bool isPathInCandidateDir(const QString& binDir) const;

    QVector<JavaInfo> findAllJava();
    JavaInfo getJavaInfo(const QString& exePath);
    int parseMajorVersion(const QString& versionStr);
    bool tryAddJavaResult(const QString& exePath, QSet<QString>& seenBinDirs,
                          QVector<JavaInfo>& out);
    QString findJavaInDir(const QString& dirPath);
    void findJavaRecursive(const QString& dirPath, int maxDepth, int currentDepth,
                           QSet<QString>& seenBinDirs,
                           QVector<JavaInfo>& results);
    bool isJavaSpecialPath(const QString& binDir) const;

    QString m_javaPath;
    QString m_javaVersion;
    int m_javaMajor = 0;
    int m_minMemoryMB = 512;
    int m_maxMemoryMB = 2048;
    bool m_autoMemory = true;
    QString m_lastLaunchedVersion;
    QString m_lastSelectedVersion;
    bool m_javaReady = false;
    QString m_gameDir;
    bool m_embeddedLoginEnabled = false;

    int m_languageIndex = 0;
    int m_launchLanguageIndex = 0;
    VersionIsolation* m_isolation = nullptr;

    // Custom background
    QVector<BgImage> m_bgImages;      // 图库（第 0 项永远是内置默认图）
    QString m_activeBgId;             // 当前使用哪一项
    QString m_bgStorageDir;           // 导入图的存放目录（空 = 相对 exe 的 data/custom_bg）
    qreal m_sidebarOpacity = 0.90;
    qreal m_contentOpacity = 0.70;
    qreal m_backgroundBlur = 0.0;

    // ── 图库内部 ──
    void ensureBgLibrary();                       // 首次访问时初始化 + 迁移旧 customBg/path
    int indexOfBg(const QString& id) const;
    BgImage activeBg() const;                     // 空图库时返回内置默认值（不会崩）
    void setActiveView(qreal zoom, qreal cx, qreal cy);
    void saveBgLibrary();
    void saveBgLibraryTo(QSettings& s);
    QString m_colorScheme = QStringLiteral("dark");

    // Download settings
    // 全局源策略默认 PreferOfficial(1)——仅影响 MC 下载；加载器下载源独立
    // 于 version_backend / mod_loader_installer（默认镜像优先，2026-08-15）
    int m_fileDownloadSource = 1;      // 0=PreferMirror, 1=PreferOfficial, 2=AutoSwitch
    int m_listDownloadSource = 1;
    int m_maxDownloadThreads = 16;
    double m_downloadSpeedLimitMB = -1; // -1 = unlimited

    int m_autoLangMode = 1;  // 0=off, 1=system locale, 2=IP region
    int m_windowWidth = 854;
    int m_windowHeight = 480;

    // ── 启动细节（低垂果实批，2026-08-08）──
    int m_gcMode = 0;                 // 0=自动 1=分代ZGC优先 2=仅G1GC 3=不指定
    int m_processPriority = 1;        // 0=高 1=中 2=低（主流启动器 LaunchArgumentPriority）
    bool m_fullscreenEnabled = false; // --fullscreen
    QString m_autoJoinServer;         // 自动进服 host[:port]
    QString m_windowTitleOverride;    // 游戏窗口标题覆盖
    QString m_preLaunchCommand;       // 启动前命令
    QString m_postExitCommand;        // 退出后命令

    // Cache for Java scan results (expensive operation)
    QVector<JavaInfo> m_cachedJavaList;
    bool m_javaCacheValid = false;
    bool m_javaScanning = false;
    QSet<QString> m_javaRemovedPaths;
};

} // namespace ShadowLauncher
