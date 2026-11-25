// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "settings_backend.h"
#include "../core/region_utils.h"
#include "../utils/types.h"
#include "../core/version_isolation.h"
#include "../utils/logger.h"

#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFileDialog>
#include <QFileInfo>
#include <QImageReader>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QUrl>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>
#include <future>
#include <mutex>
#include <functional>
#include <algorithm>
#include <climits>

#ifdef Q_OS_WIN
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  include <windows.h>
#endif

namespace ShadowLauncher {

// ── 功能开关 ──────────────────────────────────────────────
// 白色配色方案暂时下线（2026-11-13 影：切过去发现大量不适配，先把入口收掉）。
// 恢复时改 true，并把 SetAppearancePane 里配色方案的 model 加回白色一项 —— 两处一起开。
static constexpr bool kEnableLightScheme = false;

// ============================================================
// Constants
// ============================================================

static const char* COMMON_JAVA_DIRS[] = {
    // Standard JDK install paths
    "C:\\Program Files\\Java",
    "C:\\Program Files\\Eclipse Adoptium",
    "C:\\Program Files\\Microsoft",
    "C:\\Program Files\\Eclipse Foundation",
    "C:\\Program Files\\Amazon Corretto",
    "C:\\Program Files\\Azul",
    "C:\\Program Files\\Zulu",
    "C:\\Program Files\\BellSoft",
    "C:\\Program Files\\GraalVM",
    "C:\\Program Files\\Semeru",
    "C:\\Program Files\\Liberica",
    "C:\\Program Files (x86)\\Java",
    "C:\\Program Files (x86)\\Eclipse Adoptium",
    "C:\\Program Files (x86)\\Microsoft",

    // Chocolatey
    "C:\\ProgramData\\chocolatey\\lib",

    // Launcher runtimes — Microsoft
    "C:\\Program Files (x86)\\Minecraft Launcher\\runtime",
    "C:\\Program Files (x86)\\Minecraft\\runtime",
    "C:\\XboxGames\\Minecraft Launcher\\Content\\runtime",
    "%LOCALAPPDATA%\\Packages\\Microsoft.4297127D64EC6_8wekyb3d8bbwe\\LocalCache\\Local\\runtime",

    // Launcher runtimes — other
    "%APPDATA%\\.hmcl\\java",
    "%APPDATA%\\.minecraft\\runtime",
    "%APPDATA%\\ATLauncher\\runtimes\\minecraft",
    "%APPDATA%\\ModrinthApp\\meta\\java_versions",
    "%APPDATA%\\PrismLauncher\\java",
    "%APPDATA%\\.ftba\\bin\\runtime",
    "%USERPROFILE%\\curseforge\\minecraft\\Install\\runtime",
    "%USERPROFILE%\\Documents\\Curse\\Minecraft\\Install\\runtime",

    // Development JDKs
    "%USERPROFILE%\\.jdks",
    "%USERPROFILE%\\.sdkman\\candidates\\java",

    // Package managers
    "%USERPROFILE%\\scoop\\apps",
    "%LOCALAPPDATA%\\Programs",
};

// ============================================================
// Constructor
// ============================================================

SettingsBackend::SettingsBackend(QObject* parent)
    : QObject(parent)
    , m_minMemoryMB(512)
    , m_maxMemoryMB(2048)
    
{
    // Create VersionIsolation (game dir set later)
    m_isolation = new VersionIsolation(this);
    connect(m_isolation, &VersionIsolation::isolationChanged,
            this, &SettingsBackend::isolationChanged);

    // Game dir is set later by ShadowBackend via setMinecraftDir()
    
    // Load persisted settings
    loadSettings();

    // Auto-detect Java asynchronously (defer to event loop)
    // This avoids blocking the UI during startup
    QTimer::singleShot(100, this, &SettingsBackend::doAutoDetect);
}

namespace {

// versionId 会被直接拼进 QSettings 键（"versionLaunch/<id>/..."）和文件系统路径
// （"<gameDir>/versions/<id>"）。只允许单段目录名：拒绝空、"." / ".."、路径分隔符。
// 少了这个校验，deleteVersion("..") 会递归删掉整个 gameDir（owner 2026-11-10 审计 F2）。
bool isSafeVersionId(const QString& id)
{
    if (id.isEmpty()) return false;
    if (id == QLatin1String(".") || id == QLatin1String("..")) return false;
    if (id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))) return false;
    if (id.contains(QLatin1String(".."))) return false;
    return true;
}

// 自动进服地址最终作为 "--server <addr>" 传给游戏。
// 只接受 host / host:port：拒绝空格、引号、"--" 等，
// 否则 "srv --username someone" 这类内容可以给游戏塞额外参数（审计 F8）。
bool isSafeServerAddress(const QString& v)
{
    if (v.isEmpty()) return false;
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9._:\\-]{1,255}$"));
    return re.match(v).hasMatch();
}

} // namespace

// ============================================================
// Settings persistence (QSettings)
// ============================================================

void SettingsBackend::loadSettings()
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());

    m_javaPath = s.value(QStringLiteral("java/path"), QString()).toString();
    m_javaVersion = s.value(QStringLiteral("java/version"), QString()).toString();
    m_javaMajor = s.value(QStringLiteral("java/major"), 0).toInt();
    m_javaReady = (m_javaMajor > 0);

    // 边界校验：QSettings 里的值可能来自旧版本、损坏数据或外部写入，
    // 不能假设它们经过 setter。这里统一夹一次，保证内存态永远合法
    // （否则 minMB=-5 会被读成 4294967291，min>max，启动参数直接非法）。
    m_minMemoryMB = qBound(256, s.value(QStringLiteral("memory/minMB"), 512).toInt(), 32768);
    m_maxMemoryMB = qBound(m_minMemoryMB, s.value(QStringLiteral("memory/maxMB"), 2048).toInt(), 32768);
    m_autoMemory = s.value(QStringLiteral("memory/autoMemory"), true).toBool();
    m_embeddedLoginEnabled = s.value(QStringLiteral("general/embeddedLogin"), false).toBool();
    // 0=简体 1=繁体(港澳) 2=繁体(台湾) 3=English；这四项都有词条。
    // 越界值一律夹进 0..3（负数→0、超大→3），否则 UI 下拉与后端语义会错位。
    // 注：main_release.cpp:514 读同一个键时也夹 0..3，两处必须一致。
    m_languageIndex = qBound(0, s.value(QStringLiteral("general/languageIndex"), 0).toInt(), 3);
    m_launchLanguageIndex = m_languageIndex;  // snapshot for restart detection
    m_lastLaunchedVersion = s.value(QStringLiteral("general/lastVersion"), QString()).toString();
    m_lastSelectedVersion = s.value(QStringLiteral("general/lastSelectedVersion"), QString()).toString();

    // Custom background
    m_sidebarOpacity = qBound(0.0, s.value(QStringLiteral("customBg/sidebarOpacity"), 0.90).toDouble(), 1.0);
    m_contentOpacity = qBound(0.0, s.value(QStringLiteral("customBg/contentOpacity"), 0.70).toDouble(), 1.0);
    m_backgroundBlur = qBound(0.0, s.value(QStringLiteral("customBg/blur"), 0.0).toDouble(), 1.0);

    // ── 背景图库 ──
    // 结构变了：以前是「一个路径 + 一套取景」，切回默认就把路径清了（图就丢了）。
    // 现在是图库：每张图各自带 path + zoom/cropX/cropY，切换只改 active。
    m_bgImages.clear();
    m_activeBgId.clear();
    {
        const QByteArray raw = s.value(QStringLiteral("customBg/library")).toString().toUtf8();
        if (!raw.isEmpty()) {
            const QJsonDocument doc = QJsonDocument::fromJson(raw);
            for (const QJsonValue& v : doc.array()) {
                const QJsonObject o = v.toObject();
                BgImage img;
                img.id      = o.value(QStringLiteral("id")).toString();
                img.name    = o.value(QStringLiteral("name")).toString();
                img.path    = o.value(QStringLiteral("path")).toString();
                img.builtin = o.value(QStringLiteral("builtin")).toBool();
                img.zoom    = qBound(1.0, o.value(QStringLiteral("zoom")).toDouble(1.0), 4.0);
                img.cropX   = qBound(0.0, o.value(QStringLiteral("cropX")).toDouble(0.5), 1.0);
                img.cropY   = qBound(0.0, o.value(QStringLiteral("cropY")).toDouble(0.5), 1.0);
                if (img.id.isEmpty()) continue;
                img.source = img.builtin
                        ? QStringLiteral("qrc:/ui/stage-aurora.jpg")
                        : QUrl::fromLocalFile(img.path).toString();
                // 文件已不在（用户手动删了数据目录）就跳过，别留一条裂图
                if (!img.builtin && !QFile::exists(img.path)) continue;
                m_bgImages.append(img);
            }
        }
        m_activeBgId = s.value(QStringLiteral("customBg/active"), QString()).toString();

        // 旧版本迁移：customBg/path 还是唯一真源时留下的值 → 变成图库里的一张。
        // id 必须用**文件内容**的 sha1（与 importBgFile 同一套规则），否则同一个文件会以
        // 「按路径算的 id」和「按内容算的 id」各存一份，图库里凭空多出一张重复图。
        // 迁完就把旧 key 清掉，避免每次启动都重算一遍 sha1。
        const QString legacyPath = s.value(QStringLiteral("customBg/path"), QString()).toString();
        if (!legacyPath.isEmpty()) {
            s.remove(QStringLiteral("customBg/path"));
            s.remove(QStringLiteral("customBg/cropX"));
            s.remove(QStringLiteral("customBg/cropY"));
            s.remove(QStringLiteral("customBg/zoom"));
        }
        if (!legacyPath.isEmpty() && QFile::exists(legacyPath)) {
            QByteArray legacyDigest;
            {
                QFile lf(legacyPath);
                if (lf.open(QIODevice::ReadOnly)) {
                    QCryptographicHash h(QCryptographicHash::Sha1);
                    h.addData(&lf);
                    legacyDigest = h.result();
                }
            }
            BgImage img;
            img.id      = QStringLiteral("u:") + QString::fromLatin1(legacyDigest.toHex());
            img.name    = QFileInfo(legacyPath).fileName();
            img.path    = legacyPath;
            img.source  = QUrl::fromLocalFile(legacyPath).toString();
            img.zoom    = qBound(1.0, s.value(QStringLiteral("customBg/zoom"), 1.0).toDouble(), 4.0);
            img.cropX   = qBound(0.0, s.value(QStringLiteral("customBg/cropX"), 0.5).toDouble(), 1.0);
            img.cropY   = qBound(0.0, s.value(QStringLiteral("customBg/cropY"), 0.5).toDouble(), 1.0);
            const int dup = indexOfBg(img.id);
            if (dup < 0) m_bgImages.append(img);
            if (m_activeBgId.isEmpty()) m_activeBgId = img.id;
        }
    }
    ensureBgLibrary();
    m_colorScheme = s.value(QStringLiteral("appearance/scheme"), QStringLiteral("dark")).toString();
    if (m_colorScheme != QStringLiteral("light")) m_colorScheme = QStringLiteral("dark");
    // 白色方案暂时下线（影：切过去发现大量不适配）。旧配置里如果是 light，这里直接归一到 dark，
    // 否则界面会停在白色但设置页只剩黑色卡，看起来像坏了。
    if (!kEnableLightScheme) m_colorScheme = QStringLiteral("dark");

    // Auto-language mode
    m_autoLangMode = qBound(0, s.value(QStringLiteral("general/autoLangMode"), 1).toInt(), 2);
    qCInfo(logApp) << QStringLiteral("[autoLang] loaded mode=%1 from QSettings").arg(m_autoLangMode);

    // ── 启动细节（低垂果实批，2026-08-08）──
    m_gcMode = qBound(0, s.value(QStringLiteral("launch/gcMode"), 0).toInt(), 3);
    m_processPriority = qBound(0, s.value(QStringLiteral("launch/processPriority"), 1).toInt(), 2);
    m_fullscreenEnabled = s.value(QStringLiteral("launch/fullscreen"), false).toBool();
    {
        // 历史值/外部写入的地址也要过一遍校验，非法则丢弃（返回空 = 不自动进服）
        const QString join = s.value(QStringLiteral("launch/autoJoinServer"), QString()).toString().trimmed();
        m_autoJoinServer = isSafeServerAddress(join) ? join : QString();
    }
    m_windowTitleOverride = s.value(QStringLiteral("launch/windowTitle"), QString()).toString();
    m_preLaunchCommand = s.value(QStringLiteral("launch/preLaunchCommand"), QString()).toString();
    m_postExitCommand = s.value(QStringLiteral("launch/postExitCommand"), QString()).toString();

    // Download settings
    // 注：全局源策略默认 PreferOfficial(1)——仅影响 MC 下载（夸父/山海经）。
    // 加载器（Forge/NeoForge/Fabric/OptiFine）的下载源在 version_backend /
    // mod_loader_installer 内独立处理（2026-08-15：加载器默认镜像优先，
    // 与全局 fileSource 解耦，避免影响 MC 下载）。
    // 2026-11-18（二次修正）：默认 AutoSwitch(2) = 官方优先 + 镜像兜底。
    // 早上那版让国内「自动」走镜像，是用单发 curl 数据定的；完整量测（5173 文件）
    // 推翻它：镜像优先 105.7s vs 官方优先 16.7s，镜像慢 6 倍。
    m_fileDownloadSource = qBound(0, s.value(QStringLiteral("download/fileSource"), 2).toInt(), 2);
    m_listDownloadSource = qBound(0, s.value(QStringLiteral("download/listSource"), 2).toInt(), 2);
    // 并发上限与引擎一致（审计 SET-01）：读注册表时就夹到 kMaxDownloadConcurrency。
    // 这里原先是 512，于是历史值 192/512 会被原样读进内存 → 设置页显示 192/512，
    // 而 VersionDownloader::setDownloadConfig 又夹到 24（version_downloader.cpp:192），
    // 用户看到的并发数从来不是引擎真正用的那个。
    m_maxDownloadThreads = qBound(1, s.value(QStringLiteral("download/threadLimit"), kMaxDownloadConcurrency).toInt(),
                                  kMaxDownloadConcurrency);

    // ── 一次性迁移（regionPolicyV1）──
    // 老版本把「官方优先(1)」写死成默认并存进了注册表，也把线程数写死成 16。
    // 这两条在国内都是明显吃亏的选择。这里只迁移**一次**（写了标记就不再动），
    // 用户之后手动改设置也不会被覆盖。
    //   源：1(官方优先) → 2(自动：官方优先 + 镜像兜底)
    //   线程：16(旧默认) → 核数×4（≤64）
    if (!s.value(QStringLiteral("download/regionPolicyV1"), false).toBool()) {
        const bool cn = RegionUtils::isChinaRegion();
        bool changed = false;
        if (m_fileDownloadSource == 1) { m_fileDownloadSource = 2; changed = true; }
        // 16 = 旧默认，64 = 2026-11-18 上午那版默认，>24 = 512 上限时代留下的历史值（192/512）。
        // 三者统一迁到上限本身。不再沿用 defaultDownloadConcurrency()：它仍是
        // 「核数×12 夹取 [32,192]」（types.h:65-69，契约 S1 之前的取值），照抄会把 192
        // 写回注册表并绕过上面的读时夹取，界面与引擎又分叉。
        if (m_maxDownloadThreads == 16 || m_maxDownloadThreads == 64 || m_maxDownloadThreads > kMaxDownloadConcurrency) {
            m_maxDownloadThreads = kMaxDownloadConcurrency; changed = true;
        }
        s.setValue(QStringLiteral("download/fileSource"), m_fileDownloadSource);
        s.setValue(QStringLiteral("download/threadLimit"), m_maxDownloadThreads);
        s.setValue(QStringLiteral("download/regionPolicyV1"), true);
        if (changed) {
            qCInfo(logApp) << QStringLiteral("[设置] 首次按区域调优下载策略 区域=%1 源策略=%2 并发=%3")
                .arg(cn ? QStringLiteral("中国") : QStringLiteral("其他"))
                .arg(m_fileDownloadSource).arg(m_maxDownloadThreads);
        }
    }
    // ── 一次性标记 v2（2026-11-18 下午，已改为「不再覆盖用户选择」）──
    // 原版在这里把 64 → 新默认、0(镜像优先) → 2(自动)，实际把影手动选的「镜像优先」改掉了。
    // 影的原话：覆盖配置用于测试没问题，但**不该悄悄改用户存的设置**。
    // 所以现在这段只写标记 + 记一行日志，一个值都不动。
    // 需要纠正的值只在「新装」（上面 default 生效）时纠正，老装一律尊重注册表。
    if (!s.value(QStringLiteral("download/regionPolicyV2"), false).toBool()) {
        s.setValue(QStringLiteral("download/regionPolicyV2"), true);
        qCInfo(logApp) << QStringLiteral("[设置] 下载策略沿用用户保存值 源策略=%1 并发=%2（v2 标记已写，不再覆盖）")
            .arg(m_fileDownloadSource).arg(m_maxDownloadThreads);
    }
    {
        const double lim = s.value(QStringLiteral("download/speedLimitMB"), -1.0).toDouble();
        m_downloadSpeedLimitMB = (lim <= 0.0) ? -1.0 : qBound(0.1, lim, 20.0);
    }
}

void SettingsBackend::saveSettings()
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());

    s.setValue(QStringLiteral("java/path"), m_javaPath);
    s.setValue(QStringLiteral("java/version"), m_javaVersion);
    s.setValue(QStringLiteral("java/major"), m_javaMajor);

    s.setValue(QStringLiteral("memory/minMB"), m_minMemoryMB);
    s.setValue(QStringLiteral("memory/maxMB"), m_maxMemoryMB);
    s.setValue(QStringLiteral("memory/autoMemory"), m_autoMemory);
    s.setValue(QStringLiteral("general/embeddedLogin"), m_embeddedLoginEnabled);
    s.setValue(QStringLiteral("general/languageIndex"), m_languageIndex);
    s.setValue(QStringLiteral("general/lastVersion"), m_lastLaunchedVersion);
    s.setValue(QStringLiteral("general/lastSelectedVersion"), m_lastSelectedVersion);

    // Custom background
    // 图库整体序列化（每项含自己的 zoom/crop）；旧的单值 key 不再写，
    // 但读的时候还认一次（迁移），所以老用户升级后自定义图不会丢。
    saveBgLibraryTo(s);
    s.setValue(QStringLiteral("customBg/sidebarOpacity"), m_sidebarOpacity);
    s.setValue(QStringLiteral("customBg/contentOpacity"), m_contentOpacity);
    s.setValue(QStringLiteral("customBg/blur"), m_backgroundBlur);
    s.setValue(QStringLiteral("appearance/scheme"), m_colorScheme);

    // Auto-language mode
    s.setValue(QStringLiteral("general/autoLangMode"), m_autoLangMode);

    // Download settings
    s.setValue(QStringLiteral("download/fileSource"), m_fileDownloadSource);
    s.setValue(QStringLiteral("download/listSource"), m_listDownloadSource);
    s.setValue(QStringLiteral("download/threadLimit"), m_maxDownloadThreads);
    s.setValue(QStringLiteral("download/speedLimitMB"), m_downloadSpeedLimitMB);

    // ── 启动细节（低垂果实批，2026-08-08）──
    s.setValue(QStringLiteral("launch/gcMode"), m_gcMode);
    s.setValue(QStringLiteral("launch/processPriority"), m_processPriority);
    s.setValue(QStringLiteral("launch/fullscreen"), m_fullscreenEnabled);
    s.setValue(QStringLiteral("launch/autoJoinServer"), m_autoJoinServer);
    s.setValue(QStringLiteral("launch/windowTitle"), m_windowTitleOverride);
    s.setValue(QStringLiteral("launch/preLaunchCommand"), m_preLaunchCommand);
    s.setValue(QStringLiteral("launch/postExitCommand"), m_postExitCommand);
}

// ============================================================
// Async Java auto-detect (called via QTimer after constructor)
// ============================================================

void SettingsBackend::doAutoDetect()
{
    // Load persisted Java list first (avoids full re-scan on every launch)
    loadJavaList();

    // Skip if we already have a valid Java from saved settings
    if (m_javaReady && QFileInfo::exists(m_javaPath)) {
        emit logMessage(tr("Java 已配置: %1 (版本 %2)")
                            .arg(m_javaPath, m_javaVersion));
        // Still scan in background to refresh the list
        scanJavaInstallations();
        return;
    }

    // No Java configured — start async scan; auto-select happens in scan completion
    emit logMessage(tr("正在后台自动检测 Java..."));
    scanJavaInstallations();
    saveSettings();
}

// ============================================================
// Properties
// ============================================================

void SettingsBackend::setJavaPath(const QString& path)
{
    QFileInfo fi(path);
    if (!fi.isFile()) {
        emit logMessage(tr("[失败] 路径不存在: %1").arg(path));
        return;
    }
    JavaInfo info = getJavaInfo(path);
    if (info.major == 0) {
        emit logMessage(tr("[失败] 无法获取 Java 版本: %1").arg(path));
        return;
    }
    m_javaPath = info.path;
    m_javaVersion = info.version;
    m_javaMajor = info.major;

    if (!m_javaReady) {
        m_javaReady = true;
        emit javaReadyChanged();
    }

    saveSettings();
    qCInfo(logUI) << QStringLiteral("Java路径: ") << path;
    emit logMessage(tr("[完成] Java 已设置: %1 (版本 %2)")
                        .arg(path, info.version));
    emit javaPathChanged();
}

// ============================================================
// Java Detection Slots
// ============================================================

const QVector<SettingsBackend::JavaInfo>& SettingsBackend::cachedJavaList()
{
    // Return cache immediately — no sync disk scan
    // Cache is populated by scanJavaInstallations() (async) or loadSettings()
    return m_cachedJavaList;
}

QVariantList SettingsBackend::scanJavaInstallations()
{
    if (m_javaScanning) {
        emit logMessage(tr("Java 扫描已在进行中..."));
        return {};
    }
    m_javaScanning = true;
    emit logMessage(tr("正在后台扫描 Java 安装..."));
    emit javaPathChanged();  // signal QML to show loading state

    // Use std::thread::detach() — NOT std::async whose future destructor blocks!
    std::thread([this]() {
        QVector<JavaInfo> results = findAllJava();
        // 优先候选目录中的 JDK，然后按与 Java 21 的接近程度排序
        std::sort(results.begin(), results.end(),
                  [this](const JavaInfo& a, const JavaInfo& b) {
                      bool aInCand = isPathInCandidateDir(QFileInfo(a.path).absolutePath());
                      bool bInCand = isPathInCandidateDir(QFileInfo(b.path).absolutePath());
                      if (aInCand != bInCand) return aInCand;
                      int aDist = qAbs(a.major - 21);
                      int bDist = qAbs(b.major - 21);
                      if (aDist != bDist) return aDist < bDist;
                      return a.major > b.major;
                  });
        // Persist scan results
        saveJavaList(results);

        QMetaObject::invokeMethod(this, [this, results]() {
            m_cachedJavaList = results;
            m_javaCacheValid = true;
            m_javaScanning = false;

            // 列表已更新：通知属性绑定刷新（javaPath/javaVersion 等）
            emit javaPathChanged();

            if (!results.isEmpty()) {
                emit logMessage(tr("找到 %1 个 Java 安装，最新: Java %2 (优先 Java 21)")
                                    .arg(results.size())
                                    .arg(results.first().major));
                if (!m_javaReady || !QFileInfo::exists(m_javaPath)) {
                    // 自动选中（内部会再 emit javaPathChanged 表示选中变化，属正常）
                    autoSelectJava();
                }
            } else {
                emit logMessage(tr("[警告] 未在系统中找到 Java 安装"));
            }

            // 扫描完整结束：专用信号（QML 弹 toast 只用它，避免开始/完成/选中多重通知）
            emit javaScanFinished();
        }, Qt::QueuedConnection);
    }).detach();

    return {};  // return immediately, results arrive via signal
}

QVariantList SettingsBackend::availableJavaList()
{
    // Return cached list immediately — no sync disk scan
    QVariantList list;
    for (const auto& j : m_cachedJavaList) {
        list.append(QVariantMap{
            { QStringLiteral("path"), j.path },
            { QStringLiteral("version"), j.version },
            { QStringLiteral("major"), j.major }
        });
    }
    return list;
}

void SettingsBackend::selectJavaByIndex(int index)
{
    const auto& results = cachedJavaList();
    if (index < 0 || index >= results.size()) {
        emit logMessage(tr("[失败] Java 索引无效: %1").arg(index));
        return;
    }
    const auto& info = results[index];
    m_javaPath = info.path;
    m_javaVersion = info.version;
    m_javaMajor = info.major;
    m_javaReady = true;
    saveSettings();
    emit logMessage(tr("[完成] 已切换 Java %1: %2")
                        .arg(info.major).arg(info.path));
    emit javaPathChanged();
    emit javaReadyChanged();
}

QString SettingsBackend::autoSelectJava()
{
    const auto& results = cachedJavaList();
    const JavaInfo* best = nullptr;
    for (const auto& j : results) {
        if (j.major >= 17) { best = &j; break; }
    }
    if (!best && !results.isEmpty()) best = &results.first();
    if (best) {
        m_javaPath = best->path;
        m_javaVersion = best->version;
        m_javaMajor = best->major;
        m_javaReady = true;
        saveSettings();
        emit logMessage(tr("[完成] 已选择 Java %1: %2")
                            .arg(best->major).arg(best->path));
        emit javaPathChanged();
        emit javaReadyChanged();
        return best->path;
    }
    emit logMessage(tr("[警告] 未找到合适的 Java，请手动指定"));
    return {};
}

void SettingsBackend::useAutoJava()
{
    if (m_javaPath.isEmpty() && !m_javaReady) return;
    // 清空手动指定：启动时 shadow_backend 的 resolve 逻辑会走 findJavaForVersion，
    // 按每个版本需要的 Java 主版本自动匹配（改这里之前 setJavaPath("") 是被拒绝的）。
    m_javaPath.clear();
    m_javaVersion.clear();
    m_javaMajor = 0;
    m_javaReady = false;
    saveSettings();
    emit javaPathChanged();
    emit javaReadyChanged();
    emit logMessage(tr("[完成] 已改为自动选择 Java（启动时按版本需求匹配）"));
}

QString SettingsBackend::findJavaForVersion(int requiredMajor, int maxMajor)
{
    // Searches cached Java list for best match to required major version.
    // Strategy:
    //   1. Exact match (== requiredMajor) → always preferred
    //   2. Closest higher match (>= requiredMajor, smallest diff) → compatible
    //   3. Java 8 special: must be exact (Java 9+ breaks pre-1.6 LaunchWrapper)
    //   4. maxMajor>0: 仅考虑 [requiredMajor, maxMajor] 区间（老版本 Mixin 兼容上限，
    //      如 1.17-1.20.x 的 Forge Mixin 不支持 >Java 21 的类格式）
    const auto& results = cachedJavaList();
    
    if (results.isEmpty()) {
        qCWarning(logLaunch) << QStringLiteral("[JAVA] 缓存中未找到Java安装，触发重新扫描...");
        // 异步重新扫描，结果在下次调用时准备就绪
        emit logMessage(tr("Java 列表为空，正在后台重新扫描..."));
        scanJavaInstallations();
        return {};
    }
    
    const JavaInfo* exactMatch = nullptr;
    const JavaInfo* closestHigher = nullptr;
    int closestDiff = INT_MAX;
    
    for (const auto& j : results) {
        if (maxMajor > 0 && j.major > maxMajor) continue;   // 超出兼容上限跳过
        if (j.major == requiredMajor) {
            exactMatch = &j;
            break; // exact match always wins, stop early
        }
        if (j.major >= requiredMajor) {
            int diff = j.major - requiredMajor;
            if (diff < closestDiff) {
                closestDiff = diff;
                closestHigher = &j;
            }
        }
    }
    
    const JavaInfo* best = exactMatch ? exactMatch : closestHigher;
    
    // Java 8: exact match mandatory (Java 9+ breaks LaunchWrapper for old versions)
    if (!exactMatch && requiredMajor == 8) {
        qCWarning(logLaunch) << QStringLiteral("[JAVA] 需要Java 8但未找到")
                             << "Java 9+ is incompatible with pre-1.6 Forge/LaunchWrapper";
        return {};
    }
    
    if (best) {
        qCInfo(logLaunch) << QStringLiteral("[JAVA] Requires Java %1 → matched Java %2%3 at %4")
                            .arg(requiredMajor).arg(best->major)
                            .arg(best == exactMatch ? QString()
                                 : QStringLiteral(" (+%1)").arg(best->major - requiredMajor))
                            .arg(best->path);
        return best->path;
    }
    
    qCWarning(logLaunch) << QStringLiteral("[JAVA] 缺少Java %1 未找到匹配").arg(requiredMajor)
                          << "but no compatible Java ≥" << requiredMajor << "found";
    return {};
}

QString SettingsBackend::detectJava() { return autoSelectJava(); }

QString SettingsBackend::openJavaFileDialog()
{
    // Use the QML engine's root object as parent to avoid modal issues
    QWidget* parentWidget = nullptr;
    QString path = QFileDialog::getOpenFileName(
        parentWidget, tr("选择 Java 可执行文件"),
        QStringLiteral("C:\\Program Files\\Java"),
        tr("Java 可执行文件 (java.exe javaw.exe);;所有文件 (*.*)"));
    if (!path.isEmpty()) {
        setJavaPath(path);
        return path;
    }
    return {};
}

QString SettingsBackend::browseJava() { return openJavaFileDialog(); }

// ============================================================
// Memory (Bug 6 fix: use int for QML compatibility)
// ============================================================

QVariantMap SettingsBackend::getMemoryStatus()
{
    QVariantMap map;
#ifdef Q_OS_WIN
    MEMORYSTATUSEX s;
    s.dwLength = sizeof(s);
    if (GlobalMemoryStatusEx(&s)) {
        int totalMB = static_cast<int>(s.ullTotalPhys / (1024 * 1024));
        int availMB = static_cast<int>(s.ullAvailPhys / (1024 * 1024));
        map[QStringLiteral("total")]       = totalMB;
        map[QStringLiteral("available")]   = availMB;
        map[QStringLiteral("percent")]     = static_cast<int>(s.dwMemoryLoad);
        // ── 2026-11-14：推荐值改以**总物理内存**为基准──
        // 原来用 availMB / 2：可用内存是瞬态值（浏览器/游戏自身都占），
        // 开着别的程序时会把推荐值压到很低；而且开机越久可用越少。
        // 现在按业界口径（GDLauncher）：取总量的一半，上限放宽到 12288
        // （ATM10 级大型整合包 8–12GB），并且硬性留出 4GB 给系统。
        int recommended = qMin(totalMB / 2, 12288);
        recommended = qMin(recommended, qMax(2048, totalMB - 4096));
        map[QStringLiteral("recommended")] = qBound(2048, recommended, 32768);
        return map;
    }
#endif
    // Fallback: round-trip estimate
    int totalMB = 8192;
    int percent = 50;
    map[QStringLiteral("total")]       = totalMB;
    map[QStringLiteral("available")]   = totalMB / 2;
    map[QStringLiteral("percent")]     = percent;
    map[QStringLiteral("recommended")] = 2048;
    return map;
}

void SettingsBackend::setMinMemory(int mb)
{
    m_minMemoryMB = qBound(256, mb, m_maxMemoryMB);
    saveSettings();
    emit memorySettingsChanged();
}

void SettingsBackend::setMaxMemory(int mb)
{
    m_maxMemoryMB = qBound(m_minMemoryMB, mb, 32768);
    saveSettings();
    // 打实际生效值而不是入参：入参可能被夹掉，日志打原始值会误导排查（审计 F11）
    qCInfo(logUI) << QStringLiteral("游戏内存: 请求=") << mb << QStringLiteral(" 生效=") << m_maxMemoryMB;
    emit memorySettingsChanged();
}

void SettingsBackend::setAutoMemoryEnabled(bool enabled)
{
    if (m_autoMemory == enabled) return;
    m_autoMemory = enabled;
    saveSettings();
    qCInfo(logUI) << QStringLiteral("自动内存分配: ") << (enabled ? QStringLiteral("开") : QStringLiteral("关"));
    emit memorySettingsChanged();
}

// ============================================================
// Per-Version Memory Override
// ============================================================

int SettingsBackend::versionMemoryMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionMemory/") + versionId + QStringLiteral("/mode"), 0).toInt();
}

void SettingsBackend::setVersionMemoryMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionMemory/") + versionId + QStringLiteral("/mode"), mode);
    s.sync();
    qCInfo(logUI) << QStringLiteral("版本内存模式: ") << versionId << QStringLiteral(" -> ") << mode;
}

int SettingsBackend::versionMemoryManualMB(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionMemory/") + versionId + QStringLiteral("/manualMB"), 2048).toInt();
}

void SettingsBackend::setVersionMemoryManualMB(const QString& versionId, int mb)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionMemory/") + versionId + QStringLiteral("/manualMB"), mb);
    s.sync();
    qCInfo(logUI) << QStringLiteral("版本内存: ") << versionId << QStringLiteral(" -> ") << mb << QStringLiteral("MB");
}

// ── Per-version Java/launch overrides ──

int SettingsBackend::versionJavaMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/javaMode"), 0).toInt();
}
void SettingsBackend::setVersionJavaMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/javaMode"), mode);
    s.sync();
}

int SettingsBackend::versionJvmArgsMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/jvmArgsMode"), 0).toInt();
}
void SettingsBackend::setVersionJvmArgsMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/jvmArgsMode"), mode);
    s.sync();
}
QString SettingsBackend::versionJvmArgs(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/jvmArgs"), QString()).toString();
}
void SettingsBackend::setVersionJvmArgs(const QString& versionId, const QString& args)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/jvmArgs"), args);
    s.sync();
}

int SettingsBackend::versionGameArgsMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/gameArgsMode"), 0).toInt();
}
void SettingsBackend::setVersionGameArgsMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/gameArgsMode"), mode);
    s.sync();
}
QString SettingsBackend::versionGameArgs(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/gameArgs"), QString()).toString();
}
void SettingsBackend::setVersionGameArgs(const QString& versionId, const QString& args)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/gameArgs"), args);
    s.sync();
}

int SettingsBackend::versionHighPerfGpuMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/highPerfGpuMode"), 0).toInt();
}
void SettingsBackend::setVersionHighPerfGpuMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/highPerfGpuMode"), mode);
    s.sync();
}
bool SettingsBackend::versionHighPerfGpu(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/highPerfGpu"), false).toBool();
}
void SettingsBackend::setVersionHighPerfGpu(const QString& versionId, bool v)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/highPerfGpu"), v);
    s.sync();
}

// ── 启动细节（版本级覆盖，2026-08-08：对齐主流启动器实现 VersionAdvanceGC/VersionServerEnter）──

int SettingsBackend::versionGcMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/gcMode"), 0).toInt();
}
void SettingsBackend::setVersionGcMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/gcMode"), mode);
    s.sync();
}
int SettingsBackend::versionProcessPriorityMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/priorityMode"), 0).toInt();
}
void SettingsBackend::setVersionProcessPriorityMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/priorityMode"), qBound(0, mode, 1));
    s.sync();
}
int SettingsBackend::versionProcessPriority(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return qBound(0, s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/priority"), 1).toInt(), 2);
}
void SettingsBackend::setVersionProcessPriority(const QString& versionId, int v)
{
    if (!isSafeVersionId(versionId)) return;
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/priority"), qBound(0, v, 2));
    s.sync();
}

QString SettingsBackend::versionAutoJoinServer(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/autoJoinServer"), QString()).toString();
}
void SettingsBackend::setVersionAutoJoinServer(const QString& versionId, const QString& addr)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/autoJoinServer"), addr);
    s.sync();
}

// ── 全屏/窗口标题/命令 版本级（mode 语义同 highPerfGpu：0=跟随全局 1=版本覆盖）──

int SettingsBackend::versionFullscreenMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/fullscreenMode"), 0).toInt();
}
void SettingsBackend::setVersionFullscreenMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/fullscreenMode"), mode);
    s.sync();
}
bool SettingsBackend::versionFullscreen(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/fullscreen"), false).toBool();
}
void SettingsBackend::setVersionFullscreen(const QString& versionId, bool v)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/fullscreen"), v);
    s.sync();
}
int SettingsBackend::versionWindowTitleMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/windowTitleMode"), 0).toInt();
}
void SettingsBackend::setVersionWindowTitleMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/windowTitleMode"), mode);
    s.sync();
}
QString SettingsBackend::versionWindowTitle(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/windowTitle"), QString()).toString();
}
void SettingsBackend::setVersionWindowTitle(const QString& versionId, const QString& v)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/windowTitle"), v);
    s.sync();
}
int SettingsBackend::versionPreLaunchMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/preLaunchMode"), 0).toInt();
}
void SettingsBackend::setVersionPreLaunchMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/preLaunchMode"), mode);
    s.sync();
}
QString SettingsBackend::versionPreLaunchCommand(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/preLaunchCommand"), QString()).toString();
}
void SettingsBackend::setVersionPreLaunchCommand(const QString& versionId, const QString& v)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/preLaunchCommand"), v);
    s.sync();
}
int SettingsBackend::versionPostExitMode(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/postExitMode"), 0).toInt();
}
void SettingsBackend::setVersionPostExitMode(const QString& versionId, int mode)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/postExitMode"), mode);
    s.sync();
}
QString SettingsBackend::versionPostExitCommand(const QString& versionId) const
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    return s.value(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/postExitCommand"), QString()).toString();
}
void SettingsBackend::setVersionPostExitCommand(const QString& versionId, const QString& v)
{
    if (!isSafeVersionId(versionId)) return;   // 防键空间污染 / 路径越界
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("versionLaunch/") + versionId + QStringLiteral("/postExitCommand"), v);
    s.sync();
}

// 设置导入导出（exportSettingsToFile / importSettingsFromFile / exportSettingsPreview）
// 已于 2026-11-10 整体删除：功能几乎不用，且导入路径是真实攻击面 ——
// 黑名单只过滤 token/secret/password/key/beta，launch/preLaunchCommand 会被原样写入 QSettings，
// 重启后由 Launcher::runPreLaunchCommand() 经 cmd.exe /c 执行（导入一份 .ini = 任意命令执行）。
// 需要迁移配置时另做「受控」方案。


// ============================================================
// ============================================================
void SettingsBackend::setAutoJoinServer(const QString& v)
{
    const QString t = v.trimmed();
    if (!t.isEmpty() && !isSafeServerAddress(t)) {
        // 拒绝而不是静默存下：该值会拼进游戏命令行 "--server <addr>"，
        // 允许空格/引号/-- 就等于允许给游戏塞额外参数。
        qCWarning(logUI) << QStringLiteral("[设置] 拒绝非法自动进服地址: ") << t;
        emit logMessage(QStringLiteral("\u26a0 自动进服地址只接受 host 或 host:port"));
        return;
    }
    if (m_autoJoinServer == t) return;
    m_autoJoinServer = t;
    saveSettings();
    emit launchDetailChanged();
}

void SettingsBackend::setEmbeddedLoginEnabled(bool v)
{
    if (m_embeddedLoginEnabled != v) {
        m_embeddedLoginEnabled = v;
        saveSettings();
        emit embeddedLoginChanged();
    }
}

// ============================================================
// Isolation (delegates to VersionManager later)
// ============================================================

void SettingsBackend::setMinecraftDir(const QString& dir)
{
    if (m_gameDir != dir && !dir.isEmpty()) {
        m_gameDir = dir;
        m_isolation->setGameDir(dir);
        QDir().mkpath(m_gameDir + QStringLiteral("/versions"));
        QDir().mkpath(m_gameDir + QStringLiteral("/libraries"));
        QDir().mkpath(m_gameDir + QStringLiteral("/assets"));
        emit gameDirChanged();
        emit logMessage(tr("游戏目录已设置: %1").arg(m_gameDir));
    }
}

void SettingsBackend::setIsolationEnabled(bool enabled)
{
    m_isolation->setEnabled(enabled);
    emit logMessage(enabled
        ? tr("版本隔离已开启 — 各版本拥有独立的存档/截图/配置")
        : tr("版本隔离已关闭 — 所有版本共享游戏目录"));
    // isolationChanged signal is emitted by VersionIsolation
}

void SettingsBackend::migrateVersionToIsolated(const QString& versionId)
{
    bool ok = m_isolation->migrateToIsolated(versionId);
    if (ok) {
        emit logMessage(tr("版本 %1 已迁移到隔离模式").arg(versionId));
    } else {
        emit logMessage(tr("版本 %1 迁移失败：未找到版本 JSON").arg(versionId));
    }
}

QString SettingsBackend::getVersionGameDir(const QString& versionId) const
{
    return m_isolation->getVersionGameDir(versionId);
}

bool SettingsBackend::isolationEnabled() const
{
    return m_isolation->isEnabled();
}

void SettingsBackend::setIsolationGameDir(const QString& dir)
{
    m_isolation->setGameDir(dir);
    // 与 setMinecraftDir 保持同一份目录：两处都会在启动时被调用，
    // 任意一处改了都要让 QML 的 gameDir 跟着变（设置页要显示这个路径）。
    if (!dir.isEmpty() && m_gameDir != dir) {
        m_gameDir = dir;
        emit gameDirChanged();
    }
}

// ============================================================
// Path Operations
// ============================================================

void SettingsBackend::openGameDir()
{
    QDir().mkpath(m_gameDir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(m_gameDir));
}

bool SettingsBackend::openVersionDir(const QString& versionId)
{
    const QString d = m_gameDir + QStringLiteral("/versions/") + versionId;
    // 版本不存在（无版本 JSON）时拒绝打开——不再 mkpath 自动创建空文件夹
    // （用户对不存在的版本点快捷入口会凭空生成垃圾目录）
    if (!QFileInfo::exists(d + QStringLiteral("/") + versionId + QStringLiteral(".json"))) {
        qCWarning(logApp) << "[openVersionDir] 版本不存在，拒绝打开/创建:" << d;
        return false;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(d));
    return true;
}

// 完整递归删除目录（带 Windows 文件占用重试 + 权限剥离回退）。
// 2026-08-19：从 deleteVersion 的 lambda 提取为文件级函数，供
// deleteVersion / deleteVersionFiles（外部目录非隔离版本专用）复用。
static bool forceRemoveDir(const QString& dirPath)
{
    for (int retry = 0; retry < 3; retry++) {
        if (retry > 0) QThread::msleep(500);
        QDir d(dirPath);
        if (!d.exists()) return true;
        bool ok = d.removeRecursively();
        if (ok && !QDir(dirPath).exists()) return true;

        // Manual cleanup: strip all permissions, then remove each file
        qWarning() << "[deleteVersion] retry" << (retry+1) << "manual cleanup for" << dirPath;
        for (const QFileInfo& fi : QDir(dirPath).entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries)) {
            if (fi.isDir()) {
                QDir(fi.absoluteFilePath()).removeRecursively();
            } else {
                QFile f(fi.absoluteFilePath());
                // Aggressively strip all restrictions before removal (Windows locked files)
                f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
                               | QFileDevice::ReadGroup | QFileDevice::WriteGroup
                               | QFileDevice::ReadOther | QFileDevice::WriteOther);
                if (!f.remove()) {
                    qWarning() << "[deleteVersion] cannot remove file:" << fi.absoluteFilePath();
                }
            }
        }
        if (!QDir(dirPath).exists()) return true;
    }
    qWarning() << "[deleteVersion] Failed to fully remove" << dirPath << "after 3 retries";
    return QDir().rmdir(dirPath);
}

void SettingsBackend::deleteVersion(const QString& versionId)
{
    // 必须先校验：verDir = "<gameDir>/versions/" + versionId 会直接交给 forceRemoveDir 递归删除。
    // versionId=".." 时目标变成整个 gameDir，"" 时是 versions 目录（审计 F2）。
    if (!isSafeVersionId(versionId)) {
        qCWarning(logApp) << QStringLiteral("[设置] 拒绝删除非法版本 id: ") << versionId;
        emit logMessage(QStringLiteral("\u26a0 版本 id 非法，已取消删除"));
        return;
    }
    int count = 0;

    // 1. Delete the vanilla version folder
    QString verDir = m_gameDir + QStringLiteral("/versions/") + versionId;
    {
        // 双保险：即使 id 通过了字符校验，也再确认最终路径确实落在 versions 目录下
        const QString versionsRoot = QDir::cleanPath(m_gameDir + QStringLiteral("/versions"));
        const QString cleaned = QDir::cleanPath(verDir);
        if (!cleaned.startsWith(versionsRoot + QLatin1Char('/')) || cleaned == versionsRoot) {
            qCWarning(logApp) << QStringLiteral("[设置] 拒绝越界删除: ") << cleaned;
            return;
        }
    }
    if (QDir(verDir).exists()) {
        if (forceRemoveDir(verDir)) count++;
    }
    // 2. Delete any mod-loader variant folders (e.g. "1.21.1-forge-65.0.0")
    QDir versionsRoot(m_gameDir + QStringLiteral("/versions"));
    if (versionsRoot.exists()) {
        QString prefix = versionId + QStringLiteral("-");
        QFileInfoList entries = versionsRoot.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& fi : entries) {
            if (fi.fileName() == versionId) continue;
            if (fi.fileName().startsWith(prefix)) {
                if (forceRemoveDir(fi.absoluteFilePath())) {
                    count++;
                    emit logMessage(QStringLiteral("\u5df2\u5220\u9664\u52a0\u8f7d\u5668\u7248\u672c: %1").arg(fi.fileName()));
                }
            }
        }
    }
    // 3. Check again & log if folder still exists
    if (QDir(verDir).exists()) {
        emit logMessage(QStringLiteral("\u26a0\ufe0f \u65e0\u6cd5\u5b8c\u5168\u5220\u9664\u76ee\u5f55: %1\uff0c\u8bf7\u624b\u52a8\u6e05\u7406").arg(verDir));
    }
    // 4. Delete the asset index file
    QString ai = m_gameDir + QStringLiteral("/assets/indexes/")
                 + versionId + QStringLiteral(".json");
    if (QFileInfo::exists(ai)) {
        QFile::remove(ai);
        count++;
    }
    emit logMessage(QStringLiteral("\u5df2\u5220\u9664\u7248\u672c: %1 \uff08\u5171\u6e05\u7406 %2 \u4e2a\u6587\u4ef6\u5939\uff09").arg(versionId).arg(count));
}

// ============================================================
// Private: findAllJava
// ============================================================

QVector<SettingsBackend::JavaInfo> SettingsBackend::findAllJava()
{
    QVector<JavaInfo> results;
    QSet<QString>     seenBinDirs;

    auto add = [&](const QString& p) { tryAddJavaResult(p, seenBinDirs, results); };

    // 1. JAVA_HOME + JDK_HOME
    QString javaHome = qEnvironmentVariable("JAVA_HOME");
    if (!javaHome.isEmpty()) add(findJavaInDir(javaHome));
    QString jdkHome = qEnvironmentVariable("JDK_HOME");
    if (!jdkHome.isEmpty() && jdkHome != javaHome) add(findJavaInDir(jdkHome));

    // 2. PATH ("where java")
    {
        QProcess proc;
        proc.start(QStringLiteral("where"), QStringList() << QStringLiteral("java"));
        proc.waitForFinished(5000);
        if (proc.exitCode() == 0) {
            QStringList lines = QString::fromLocal8Bit(
                proc.readAllStandardOutput()).split(QRegularExpression(QStringLiteral("[\\r\\n]")),
                                                    Qt::SkipEmptyParts);
            QSet<QString> seenPath;
            for (const auto& line : lines) {
                QString p = QDir::cleanPath(line.trimmed());
                if (p.isEmpty()) continue;
                QString dirLower = QDir::cleanPath(QFileInfo(p).absolutePath()).toLower();
                if (seenPath.contains(dirLower)) continue;
                seenPath.insert(dirLower);
                add(p);
            }
        }
    }

    // 2.5 启动器自带 java_cache（一键安装的便携 Java，用户应可在设置-Java 选用）
    {
        const QString cacheRoot = QCoreApplication::applicationDirPath() + QStringLiteral("/java_cache");
        QDir cacheDir(cacheRoot);
        if (cacheDir.exists()) {
            for (const QString& sub : cacheDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
                bool ok = false;
                sub.toInt(&ok);
                if (!ok) continue;
                const QString exe = cacheRoot + QStringLiteral("/") + sub + QStringLiteral("/bin/java.exe");
                if (QFile::exists(exe)) add(exe);
            }
        }
    }

    // 3. Scan common directories (recursive, up to 6 levels, parallel)
    {
        // Collect all valid root directories (expand env vars)
        QVector<QString> dirRoots;
        static const QRegularExpression varRe(QStringLiteral("%([^%]+)%"));
        for (const char* raw : COMMON_JAVA_DIRS) {
            QString searchDir = QString::fromLocal8Bit(raw);
            auto m = varRe.match(searchDir);
            if (m.hasMatch()) {
                QString val = qEnvironmentVariable(m.captured(1).toLocal8Bit());
                if (val.isEmpty()) continue;
                searchDir.replace(m.captured(0), val);
            }
            if (!QDir(searchDir).exists()) continue;
            dirRoots.append(searchDir);
        }

        // Parallel recursive scan (each root in its own thread)
        const int maxDepth = 6;
        std::mutex resultsMutex;
        std::vector<std::future<void>> dirFutures;
        for (const auto& root : dirRoots) {
            dirFutures.push_back(std::async(std::launch::async, [this, &root, &results, &seenBinDirs, &resultsMutex, maxDepth]() {
                QVector<JavaInfo> localResults;
                QSet<QString> localSeen;
                findJavaRecursive(root, maxDepth, 0, localSeen, localResults);
                if (!localResults.isEmpty()) {
                    std::lock_guard<std::mutex> lock(resultsMutex);
                    for (const auto& j : localResults) {
                        QString binDir = QDir::cleanPath(QFileInfo(j.path).absolutePath()).toLower();
                        if (seenBinDirs.contains(binDir)) continue;
                        seenBinDirs.insert(binDir);
                        results.append(j);
                    }
                }
            }));
        }
        for (auto& f : dirFutures) f.wait();
    }

    // 4. Windows Registry
#ifdef Q_OS_WIN
    const wchar_t* regPaths[] = {
        L"SOFTWARE\\JavaSoft\\JDK",
        L"SOFTWARE\\JavaSoft\\Java Runtime Environment",
        L"SOFTWARE\\Eclipse Adoptium\\JDK",
        L"SOFTWARE\\Eclipse Foundation\\JDK",
        L"SOFTWARE\\Microsoft\\JDK",
    };
    for (const auto* rp : regPaths) {
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, rp, 0,
                          KEY_READ | KEY_WOW64_64KEY, &hKey) != ERROR_SUCCESS)
            continue;
        DWORD idx = 0;
        wchar_t name[256];
        DWORD nameLen = 256;
        while (RegEnumKeyExW(hKey, idx, name, &nameLen,
                             nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS) {
            HKEY hSub;
            if (RegOpenKeyExW(hKey, name, 0, KEY_READ, &hSub) == ERROR_SUCCESS) {
                wchar_t home[512];
                DWORD sz = sizeof(home), type;
                if (RegQueryValueExW(hSub, L"JavaHome", nullptr, &type,
                                     reinterpret_cast<BYTE*>(home), &sz) == ERROR_SUCCESS
                    && type == REG_SZ) {
                    add(findJavaInDir(QString::fromWCharArray(home)));
                }
                RegCloseKey(hSub);
            }
            ++idx;
            nameLen = 256;
        }
        RegCloseKey(hKey);
    }
#endif

    // Filter out user-removed Java paths
    results.erase(std::remove_if(results.begin(), results.end(),
        [this](const JavaInfo& j) {
            return m_javaRemovedPaths.contains(QDir::cleanPath(QFileInfo(j.path).absolutePath()).toLower());
        }), results.end());

    return results;
}

// ============================================================
// Private Helpers
// ============================================================

QString SettingsBackend::findJavaInDir(const QString& dirPath)
{
    static const char* cands[] = { "bin/java.exe", "bin/javaw.exe", "java.exe", "javaw.exe" };
    for (const char* c : cands) {
        QString p = QDir::cleanPath(dirPath + QLatin1Char('/') + QString::fromLatin1(c));
        if (QFileInfo::exists(p)) return p;
    }
    return {};
}

bool SettingsBackend::tryAddJavaResult(const QString& exePath,
                                        QSet<QString>& seenBinDirs,
                                        QVector<JavaInfo>& out)
{
    if (exePath.isEmpty()) return false;
    QFileInfo fi(exePath);
    if (!fi.isFile()) return false;
    QString binDir = QDir::cleanPath(fi.absolutePath()).toLower();
    if (seenBinDirs.contains(binDir)) return false;
    JavaInfo info = getJavaInfo(exePath);
    if (info.major == 0) return false;
    seenBinDirs.insert(binDir);
    out.append(info);
    return true;
}

SettingsBackend::JavaInfo SettingsBackend::getJavaInfo(const QString& exePath)
{
    JavaInfo info;
    info.path = exePath;
    QProcess proc;
    proc.start(exePath, QStringList() << QStringLiteral("-version"));
    proc.waitForFinished(10000);
    QString output = QString::fromLocal8Bit(proc.readAllStandardError());
    if (output.isEmpty()) output = QString::fromLocal8Bit(proc.readAllStandardOutput());
    if (output.isEmpty()) return info;

    // 输出检查
    QString lower = output.toLower();
    if (lower.contains(QStringLiteral("/lib/ext exists"))) {
        qCWarning(logJava) << QStringLiteral("Java rejected (/lib/ext exists): %1").arg(exePath);
        return info;
    }
    if (lower.contains(QStringLiteral("a fatal error")) || lower.contains(QStringLiteral("error: "))) {
        qCWarning(logJava) << QStringLiteral("Java rejected (fatal error): %1").arg(exePath);
        return info;
    }
    // Reject 32-bit Java (MC needs 64-bit)
    if (!lower.contains(QStringLiteral("64-bit"))) {
        qCWarning(logJava) << QStringLiteral("Java rejected (not 64-bit): %1").arg(exePath);
        return info;
    }

    QRegularExpression re(QStringLiteral("version\\s+\"([^\"]+)\""));
    auto match = re.match(output);
    if (!match.hasMatch()) {
        QRegularExpression re2(QStringLiteral("version\\s+(\\S+)"));
        match = re2.match(output);
    }
    if (match.hasMatch()) {
        info.version = match.captured(1);
        info.major = parseMajorVersion(info.version);
    }
    return info;
}

int SettingsBackend::parseMajorVersion(const QString& versionStr)
{
    QString n = versionStr;
    n.replace(QLatin1Char('_'), QLatin1Char('.'));
    QStringList parts = n.split(QLatin1Char('.'));
    if (parts.isEmpty()) return 0;
    if (parts.size() >= 2 && parts[0] == QStringLiteral("1")) {
        bool ok; int v = parts[1].toInt(&ok); return ok ? v : 0;
    }
    bool ok; int v = parts[0].toInt(&ok); return ok ? v : 0;
}

int SettingsBackend::autoLangModeComboIndex() const
{
    int idx = m_autoLangMode == 0 ? 2 : (m_autoLangMode == 2 ? 1 : 0);
    qCInfo(logApp) << QStringLiteral("[autoLang] QML reads mode=%1 → comboIdx=%2").arg(m_autoLangMode).arg(idx);
    return idx;
}

void SettingsBackend::setAutoLangMode(int mode)
{
    if (mode < 0 || mode > 2) return;
    if (mode == m_autoLangMode) return;
    qCInfo(logApp) << QStringLiteral("[autoLang] saving mode=%1 (was %2)").arg(mode).arg(m_autoLangMode);
    m_autoLangMode = mode;
    saveSettings();
    emit autoLangModeChanged();
}

void SettingsBackend::setLanguageIndex(int idx)
{
    if (idx < 0 || idx > 3) return;
    if (idx == m_languageIndex) return;
    m_languageIndex = idx;
    saveSettings();
    emit languageChanged();
}

// ============================================================
// findJavaRecursive -- recursively search a directory tree for Java
// ============================================================

void SettingsBackend::findJavaRecursive(const QString& dirPath, int maxDepth,
                                         int currentDepth,
                                         QSet<QString>& seenBinDirs,
                                         QVector<JavaInfo>& results)
{
    if (currentDepth > maxDepth) return;
    QDir d(dirPath);
    if (!d.exists()) return;

    // Check current directory for java.exe/javaw.exe
    QString javaPath = findJavaInDir(dirPath);
    if (!javaPath.isEmpty()) {
        QFileInfo fi(javaPath);
        QString binDir = QDir::cleanPath(fi.absolutePath()).toLower();
        if (!isJavaSpecialPath(binDir)) {
            tryAddJavaResult(javaPath, seenBinDirs, results);
        }
    }

    // Recurse into subdirectories (skip reparse points / symlinks to avoid loops)
    const auto entries = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden);
    for (const auto& entry : entries) {
        if (entry.isSymLink() || entry.isShortcut()) continue;
        // Skip Windows special directories that won't contain Java
        QString lowerName = entry.fileName().toLower();
        if (lowerName == "system32" || lowerName == "syswow64" || lowerName == "windows") continue;
        findJavaRecursive(entry.absoluteFilePath(), maxDepth, currentDepth + 1,
                          seenBinDirs, results);
    }
}

// ============================================================
// isJavaSpecialPath -- filter out known bogus/dangling Java paths
// ============================================================

bool SettingsBackend::isJavaSpecialPath(const QString& binDir) const
{
    QString lower = binDir.toLower();
    return lower.contains("java8path_target_")
        || lower.contains("javapath_target_")
        || lower.contains("javatmp")
        || lower.contains("system32")
        || lower.contains("syswow64");
}

// ============================================================
// isPathInCandidateDir -- check if path is inside our known JDK dirs
// ============================================================

bool SettingsBackend::isPathInCandidateDir(const QString& binDir) const
{
    QString lower = binDir.toLower();
    static const QRegularExpression varRe(QStringLiteral("%([^%]+)%"));
    for (const char* raw : COMMON_JAVA_DIRS) {
        QString searchDir = QString::fromLocal8Bit(raw);
        auto m = varRe.match(searchDir);
        if (m.hasMatch()) {
            QString val = qEnvironmentVariable(m.captured(1).toLocal8Bit());
            if (val.isEmpty()) continue;
            searchDir.replace(m.captured(0), val);
        }
        if (lower.startsWith(searchDir.toLower())) {
            int sl = searchDir.length();
            if (lower.length() == sl || lower[sl] == QLatin1Char('\\') || lower[sl] == QLatin1Char('/'))
                return true;
        }
    }
    return false;
}

// ============================================================

// ============================================================
// persistedJavaList -- return persisted list (QML access)
// ============================================================

QVariantList SettingsBackend::persistedJavaList()
{
    return availableJavaList();
}

// ============================================================
// loadJavaList -- restore persisted Java list from QSettings
// ============================================================

void SettingsBackend::loadJavaList()
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());

    // Load removed paths
    QStringList removed = s.value(QStringLiteral("java/removedPaths")).toStringList();
    m_javaRemovedPaths.clear();
    for (const auto& p : removed) m_javaRemovedPaths.insert(p.toLower());

    // Load cached Java list
    int count = s.value(QStringLiteral("java/listCount"), 0).toInt();
    if (count > 0) {
        QVector<JavaInfo> loaded;
        for (int i = 0; i < count; ++i) {
            QString prefix = QStringLiteral("java/list/%1/").arg(i);
            JavaInfo j;
            j.path = s.value(prefix + QStringLiteral("path")).toString();
            j.version = s.value(prefix + QStringLiteral("version")).toString();
            j.major = s.value(prefix + QStringLiteral("major"), 0).toInt();
            if (!j.path.isEmpty() && QFileInfo::exists(j.path)) {
                loaded.append(j);
            }
        }
        if (!loaded.isEmpty()) {
            m_cachedJavaList = loaded;
            m_javaCacheValid = true;
        }
    }
}

// ============================================================
// saveJavaList -- persist Java list to QSettings
// ============================================================

void SettingsBackend::saveJavaList(const QVector<JavaInfo>& list)
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    s.setValue(QStringLiteral("java/listCount"), list.size());
    for (int i = 0; i < list.size(); ++i) {
        QString prefix = QStringLiteral("java/list/%1/").arg(i);
        s.setValue(prefix + QStringLiteral("path"), list[i].path);
        s.setValue(prefix + QStringLiteral("version"), list[i].version);
        s.setValue(prefix + QStringLiteral("major"), list[i].major);
    }
}

// ============================================================
// 外观页：启动页背景图库 + 配色方案（2026-11-13）
// ============================================================
// 设计要点：
//   • **图库模型**：内置默认图 + 每一张用户导入的图，各存一份 path 与取景
//     （zoom / cropX / cropY）。切换只是改 active，谁也不清空谁 ——
//     「导入一张新图 → 切回默认 → 再切回来」，图和取景都还在。
//     旧实现是「一个路径 + 一套取景」，切回默认就 clear() 掉路径，图就"丢"了（影报的 bug）。
//   • 导入的图复制进数据目录（custom_bg/bg_<sha1>.<ext>），原图被移动/删除也不影响。
//   • 内置图走 qrc，不占磁盘；customBg/path 等旧 key 只读一次做迁移。
//   • 取景公式在渲染侧（SBgImage）统一：cover × zoom，再把 crop 中心对齐到框内，
//     启动页与外观页预览共用，避免"预览和实际不一样"。
namespace {
constexpr const char* kDefaultBgId = "aurora";

// 随包发布的启动页背景（2026-11-14 影提供的一批）。
// 顺序 = 外观页里的展示顺序；第一项必须是默认极光（图库第 0 位、兜底都用它）。
// 名字用 QT_TR_NOOP 包起来，实际取值时才 tr() —— 这样 lupdate 能提取，切语言也能跟着变。
struct BuiltinBgDef {
    const char* id;
    const char* source;
    const char* name;
};
constexpr BuiltinBgDef kBuiltinBgs[] = {
    { "aurora",       "qrc:/ui/stage-aurora.jpg",      QT_TR_NOOP("极光（默认）") },
    { "fangcun",      "qrc:/ui/stage-fangcun.jpg",     QT_TR_NOOP("方寸") },
    { "shanhe",       "qrc:/ui/stage-shanhe.jpg",      QT_TR_NOOP("山河") },
    { "linlan",       "qrc:/ui/stage-linlan.jpg",      QT_TR_NOOP("林澜") },
    { "weijian-2",    "qrc:/ui/stage-weijian-2.jpg",   QT_TR_NOOP("未见 二") },
    { "weijian-4",    "qrc:/ui/stage-weijian-4.jpg",   QT_TR_NOOP("未见 四") },
    { "weijian-6",    "qrc:/ui/stage-weijian-6.jpg",   QT_TR_NOOP("未见 六") },
    { "jiguang",      "qrc:/ui/stage-jiguang.jpg",     QT_TR_NOOP("寂光") },
    { "yuwen-1",      "qrc:/ui/stage-yuwen-1.jpg",     QT_TR_NOOP("余温 一") },
    { "yuwen-2",      "qrc:/ui/stage-yuwen-2.jpg",     QT_TR_NOOP("余温 二") },
    { "city-2",       "qrc:/ui/stage-city-2.jpg",      QT_TR_NOOP("城市建筑 二") },
    { "city-4",       "qrc:/ui/stage-city-4.jpg",      QT_TR_NOOP("城市建筑 四") },
    { "citywalk-6",   "qrc:/ui/stage-citywalk-6.jpg",  QT_TR_NOOP("城市漫步 六") },
    { "jingmi",       "qrc:/ui/stage-jingmi.jpg",      QT_TR_NOOP("静谧") },
};
} // namespace

void SettingsBackend::saveBgLibraryTo(QSettings& s)
{
    QJsonArray arr;
    for (const BgImage& img : m_bgImages) {
        // 内置图不写 path（永远走 qrc），导入图必须带 path
        if (!img.builtin && !QFile::exists(img.path)) continue;
        QJsonObject o;
        o.insert(QStringLiteral("id"), img.id);
        o.insert(QStringLiteral("name"), img.name);
        o.insert(QStringLiteral("path"), img.builtin ? QString() : img.path);
        o.insert(QStringLiteral("builtin"), img.builtin);
        o.insert(QStringLiteral("zoom"), img.zoom);
        o.insert(QStringLiteral("cropX"), img.cropX);
        o.insert(QStringLiteral("cropY"), img.cropY);
        arr.append(o);
    }
    s.setValue(QStringLiteral("customBg/library"),
               QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact)));
    s.setValue(QStringLiteral("customBg/active"), m_activeBgId);
}

void SettingsBackend::saveBgLibrary()
{
    QSettings s(QCoreApplication::organizationName(),
                QCoreApplication::applicationName());
    saveBgLibraryTo(s);
}

int SettingsBackend::indexOfBg(const QString& id) const
{
    for (int i = 0; i < m_bgImages.size(); ++i)
        if (m_bgImages.at(i).id == id) return i;
    return -1;
}

void SettingsBackend::ensureBgLibrary()
{
    // 去重：同一个文件只保留一条。
    // 旧数据迁移用的 id 是「路径 sha1」，而 importBgFile 用的是「内容 sha1」，
    // 两者对同一张图会算出不同 id → 图库里会凭空多出一张一模一样的卡片（实测出现过）。
    // 这里按绝对路径归并，优先保留当前正在用的那一条。
    {
        QHash<QString, int> firstByPath;
        for (int i = 0; i < m_bgImages.size(); ) {
            if (m_bgImages.at(i).builtin) { ++i; continue; }
            const QString key = QFileInfo(m_bgImages.at(i).path).absoluteFilePath();
            if (!firstByPath.contains(key)) { firstByPath.insert(key, i); ++i; continue; }
            const int prev = firstByPath.value(key);
            if (m_bgImages.at(i).id == m_activeBgId) {
                m_bgImages.removeAt(prev);
                firstByPath[key] = i - 1;
            } else {
                m_bgImages.removeAt(i);
            }
        }
    }

    // ── 内置图库同步（2026-11-14）──
    // 随包发布的图都在 kBuiltinBgs 表里，这里按表把图库对齐：
    //   ① 缺的补上 —— 老用户升级后也能看到新图（图库存在 QSettings 里，不会自动出现）；
    //   ② 名字每次按当前语言重算 —— 不能沿用上次存进 JSON 的旧语言版本；
    //   ③ 表里已删除的图不再留死卡片。
    // 内置图永远排在最前、顺序与表一致；导入的图保持原顺序跟在后面。
    {
        QSet<QString> keep;
        for (const BuiltinBgDef& d : kBuiltinBgs) keep.insert(QString::fromLatin1(d.id));
        for (int i = m_bgImages.size() - 1; i >= 0; --i) {
            if (m_bgImages.at(i).builtin && !keep.contains(m_bgImages.at(i).id))
                m_bgImages.removeAt(i);
        }
        int slot = 0;
        for (const BuiltinBgDef& d : kBuiltinBgs) {
            const QString id = QString::fromLatin1(d.id);
            int at = indexOfBg(id);
            if (at < 0) {
                BgImage img;
                img.id = id;
                img.builtin = true;
                m_bgImages.insert(slot, img);   // 新图先插到位，随后统一填字段
                at = slot;
            }
            BgImage& img = m_bgImages[at];
            img.builtin = true;
            img.source  = QString::fromLatin1(d.source);
            img.name    = tr(d.name);
            if (at != slot) m_bgImages.move(at, slot);
            ++slot;
        }
    }

    if (m_activeBgId.isEmpty() || indexOfBg(m_activeBgId) < 0)
        m_activeBgId = m_bgImages.first().id;
}

SettingsBackend::BgImage SettingsBackend::activeBg() const
{
    const int i = indexOfBg(m_activeBgId);
    if (i >= 0) return m_bgImages.at(i);
    // 兜底：空图库也给一张内置默认（调用方拿到的永远是合法值，不会出现 zoom=0 之类的死状态）
    BgImage def;
    def.id      = QString::fromLatin1(kDefaultBgId);
    def.name    = tr("极光（默认）");
    def.source  = QStringLiteral("qrc:/ui/stage-aurora.jpg");
    def.builtin = true;
    return def;
}

void SettingsBackend::setActiveView(qreal zoom, qreal cx, qreal cy)
{
    const int i = indexOfBg(m_activeBgId);
    if (i < 0) return;
    BgImage& img = m_bgImages[i];
    img.zoom  = qBound(1.0, zoom, 4.0);
    img.cropX = qBound(0.0, cx, 1.0);
    img.cropY = qBound(0.0, cy, 1.0);
    saveBgLibrary();
    emit customBgChanged();
}

QString SettingsBackend::importBgFile(const QString& path)
{
    ensureBgLibrary();
    if (path.isEmpty()) return QString();

    const QFileInfo fi(path);
    if (!fi.exists() || !fi.isFile()) {
        qCWarning(logUI) << QStringLiteral("[外观] 背景图不存在: %1").arg(path);
        return QString();
    }
    // 只接受 Qt 能解码的图片（审计 SET-04）：图库条目会直接铺满整屏启动页，
    // 非图片文件（.txt / 压缩包 / 改错后缀）原先会被原样复制进 custom_bg 并设为当前图，
    // 结果是「导入成功」却得到一张永远解不出来的背景，启动日志刷
    // "QML QQuickImage: Error decoding ... Unsupported image format"，用户看不出哪里错了。
    {
        QImageReader probe(path);
        if (!probe.canRead()) {
            qCWarning(logUI) << QStringLiteral("[外观] 不是可解码的图片，拒绝导入: %1 (%2)")
                                    .arg(path, probe.errorString());
            return QString();
        }
    }

    // 已经导入过同一张图（按内容 sha1 判定）就直接激活它，不重复占磁盘
    QByteArray digest;
    {
        QFile f(path);
        if (f.open(QIODevice::ReadOnly)) {
            QCryptographicHash h(QCryptographicHash::Sha1);
            h.addData(&f);
            digest = h.result();
        }
    }
    const QString id = QStringLiteral("u:") + QString::fromLatin1(digest.toHex());
    const int dup = indexOfBg(id);
    if (dup >= 0) {
        m_activeBgId = id;
        saveBgLibrary();
        emit bgLibraryChanged();
        emit customBgChanged();
        qCInfo(logUI) << QStringLiteral("[外观] 复用已导入的背景: %1").arg(path);
        return id;
    }

    // 复制进数据目录，原图被移动/删除都不影响显示
    QString ext = fi.suffix().isEmpty() ? QStringLiteral("png") : fi.suffix().toLower();
    const QString destDir = m_bgStorageDir.isEmpty()
            ? (QCoreApplication::applicationDirPath() + QStringLiteral("/../data/custom_bg"))
            : m_bgStorageDir;
    QDir().mkpath(destDir);
    const QString dest = destDir + QStringLiteral("/bg_")
                         + (digest.isEmpty() ? QStringLiteral("x") : QString::fromLatin1(digest.toHex()))
                         + QStringLiteral(".") + ext;

    QString stored = path;
    if (QFile::exists(dest) || QFile::copy(path, dest)) {
        stored = dest;
    } else {
        // 复制失败就退回原路径：图还能显示，只是原图被移走会裂
        qCWarning(logUI) << QStringLiteral("[外观] 背景图复制失败，使用原路径: %1").arg(path);
    }

    BgImage img;
    img.id      = id;
    img.name    = fi.fileName();
    img.path    = stored;
    img.source  = QUrl::fromLocalFile(stored).toString();
    img.zoom    = 1.0;   // 新图默认 100%，不影响其它图已经调好的取景
    img.cropX   = 0.5;
    img.cropY   = 0.5;
    m_bgImages.append(img);
    m_activeBgId = id;
    saveBgLibrary();
    emit bgLibraryChanged();
    emit customBgChanged();
    qCInfo(logUI) << QStringLiteral("[外观] 导入背景: %1 -> %2").arg(path, stored);
    return id;
}

QVariantList SettingsBackend::bgPresets() const
{
    const_cast<SettingsBackend*>(this)->ensureBgLibrary();
    QVariantList out;
    for (const BgImage& img : m_bgImages) {
        out.append(QVariantMap{
            { QStringLiteral("id"),      img.id },
            { QStringLiteral("name"),    img.name },
            { QStringLiteral("source"),  img.source },
            { QStringLiteral("builtin"), img.builtin },
            { QStringLiteral("active"),  img.id == m_activeBgId },
            { QStringLiteral("zoom"),    img.zoom },
            { QStringLiteral("cropX"),   img.cropX },
            { QStringLiteral("cropY"),   img.cropY }
        });
    }
    return out;
}

void SettingsBackend::applyBgPreset(const QString& presetId)
{
    ensureBgLibrary();
    QString id = presetId;
    if (id.isEmpty() || indexOfBg(id) < 0) {
        qCWarning(logUI) << QStringLiteral("[外观] 未知背景 id: %1，回落到默认").arg(presetId);
        id = m_bgImages.first().id;
    }
    if (m_activeBgId == id) return;   // 已经是它：不动取景，也不惊动 UI
    // **只改 active**：不碰任何一张图的 path / 取景，所以切走再切回来还是原样
    m_activeBgId = id;
    saveBgLibrary();
    emit bgLibraryChanged();
    emit customBgChanged();
    qCInfo(logUI) << QStringLiteral("[外观] 切换背景 -> %1").arg(id);
}

bool SettingsBackend::chooseBgImage()
{
    const QString file = QFileDialog::getOpenFileName(
        nullptr, tr("选择启动页背景图片"), QString(),
        tr("图片 (*.png *.jpg *.jpeg *.webp *.bmp)"));
    if (file.isEmpty()) return false;
    return !importBgFile(file).isEmpty();
}

void SettingsBackend::restoreDefaultBg()
{
    ensureBgLibrary();
    // 只切回默认图，**不删任何导入的图**（它们的 path/取景都还留在图库里）
    applyBgPreset(m_bgImages.first().id);
}

void SettingsBackend::resetBgView()
{
    // 只复位「当前这张图」的取景，其它图的取景不动
    setActiveView(1.0, 0.5, 0.5);
}

void SettingsBackend::removeBgImage(const QString& id)
{
    ensureBgLibrary();
    const int i = indexOfBg(id);
    if (i < 0 || m_bgImages.at(i).builtin) return;   // 内置图不可删

    const BgImage img = m_bgImages.at(i);
    m_bgImages.removeAt(i);

    // 只删我们自己复制进数据目录的副本，绝不碰用户原图
    const QString dirPath = m_bgStorageDir.isEmpty()
            ? (QCoreApplication::applicationDirPath() + QStringLiteral("/../data/custom_bg"))
            : m_bgStorageDir;
    const QString dirCanonical = QFileInfo(dirPath).canonicalFilePath();
    const QString fileCanonical = QFileInfo(img.path).canonicalFilePath();
    if (!fileCanonical.isEmpty() && !dirCanonical.isEmpty()
        && fileCanonical.startsWith(dirCanonical)) {
        QFile::remove(fileCanonical);
    }

    if (m_activeBgId == id) m_activeBgId = m_bgImages.first().id;
    saveBgLibrary();
    emit bgLibraryChanged();
    emit customBgChanged();
    qCInfo(logUI) << QStringLiteral("[外观] 移除背景: %1").arg(id);
}

void SettingsBackend::setColorScheme(const QString& scheme)
{
    QString next = (scheme == QStringLiteral("light")) ? QStringLiteral("light")
                                                         : QStringLiteral("dark");
    // 白色方案暂时下线：即使 QML/外部传了 light 也只落到 dark（单一入口，避免绕过）
    if (!kEnableLightScheme) next = QStringLiteral("dark");
    if (m_colorScheme == next) return;
    m_colorScheme = next;
    saveSettings();
    emit colorSchemeChanged();
    qCInfo(logUI) << QStringLiteral("[外观] 配色方案 = %1").arg(m_colorScheme);
}

} // namespace ShadowLauncher

