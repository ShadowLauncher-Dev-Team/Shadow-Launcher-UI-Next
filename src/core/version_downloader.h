// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QJsonObject>
#include <QJsonArray>
#include <QVector>
#include <QMap>
#include <QAtomicInt>
#include <functional>
#include "utils/types.h"
// Forward-declare (see version_downloader.cpp for full include)
namespace ShadowDownloader { class FileDownloader; }
class AssetDownloader;

namespace ShadowLauncher {

// ============================================================
// Mirror source configuration
// ============================================================

struct MirrorSource {
    QString name;
    QString desc;
    QString manifestUrl;
    QString versionMetaHost;
    QString resourceBase;
    QString libraryBase;
    QString jarHost;
    bool isDefault = false;

    // BMCLAPI 协议合规相关
    QString healthCheckUrl;     // 用于镜像健康检测的探测 URL
    QString attribution;        // 使用协议标注文案（BMCLAPI 必须标注来源）
    bool isAvailable = true;    // 运行时可用状态

    static MirrorSource bmclapi();
    static MirrorSource mojang();
    static QVector<MirrorSource> allMirrors();
};

// BMCLAPI 协议合规公告（下载页面必须展示）
constexpr const char* kBMCLAPIComplianceNotice =
    "[下载] 下载加速由 BMCLAPI / MCBBS 镜像提供\n"
    "文件归源站点 (Mojang/Fabric/Forge 等) 所有\n"
    "Shadow Launcher 不对镜像文件内容承担责任";

// ============================================================
// VersionDownloader — Minecraft version install pipeline
// ============================================================

class VersionDownloader : public QObject {
    Q_OBJECT
    Q_PROPERTY(int completedFiles READ completedFiles NOTIFY progressChanged)
    Q_PROPERTY(int totalFiles READ totalFiles NOTIFY progressChanged)
    Q_PROPERTY(qint64 downloadedBytes READ downloadedBytes NOTIFY progressChanged)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY progressChanged)
    Q_PROPERTY(QString state READ stateStr NOTIFY stateChanged)

public:
    explicit VersionDownloader(QObject* parent = nullptr);
    ~VersionDownloader() override;

    // Configuration
    void setMirror(const MirrorSource& mirror);
    void setMinecraftDir(const QString& dir);
    void setCacheFallbackDir(const QString& dir);
    void setDownloadConfig(const DownloadConfig& config);

    // Main entry: download a Minecraft version
    void downloadVersion(const QJsonObject& versionJson, const QString& versionId);

    // Lifecycle
    void pause();
    void resume();
    void cancel();

    // State queries
    int completedFiles() const;
    int totalFiles() const;
    qint64 downloadedBytes() const;
    qint64 totalBytes() const;
    /// Bytes from cache hits (excluded from speed calculation).
    qint64 cachedBytes() const;
    /// Network-only bytes (total - cache).
    qint64 networkBytes() const { return m_downloadedBytes.loadRelaxed() - cachedBytes(); }
    QString stateStr() const;
    bool isRunning() const;

    // Per-category total bytes (pre-computed from task list)
    qint64 categoryTotalBytes(int cat) const { return m_categoryTotalBytes[cat]; }
    // Per-file category for savePath. Returns -1 if unknown (not in task list).
    int fileCategory(const QString& savePath) const { return m_fileCategory.value(savePath, -1); }

signals:
    void progressChanged(int completedFiles, int totalFiles,
                         qint64 downloadedBytes, qint64 totalBytes);
    void fileProgress(const QString& url, const QString& fileName, qint64 received, qint64 total, const QString& savePath = QString());

    /// Emitted during integrity verification phase only.
    /// Does NOT overlap with downloadProgress — verify has its own signal.
    void verifyProgressChanged(int checked, int total);
    /// 校验判坏后走「换镜像重下」的修复阶段进度（done/total = 本轮重下的文件数）。
    /// 2026-11-20：修复期间上层步骤原本停在 99% 一动不动（实测 105 秒），
    /// 用户以为卡死；有这个信号就能显示「修复中 x/y」并在跑完时收尾。
    void repairProgress(int done, int total);

    void logMessage(const QString& msg);
    void downloadFinished(bool success, const QString& errorMsg);
    void stateChanged();

    /// Emitted when files fail to download (all mirrors exhausted).
    /// QML can use this to show a retry UI or display missing file lists.
    void downloadFailedFiles(const QStringList& failedFiles);

private slots:
    void onAllFinishedV2();  // FileDownloader (v8) wrapper

private:
    // --- Pipeline steps ---
    QMap<QString, QJsonObject> parseAssetIndex(const QJsonObject& assetIdx);
    void downloadAssetIndexRace(const QString& idxUrl, const QString& idxPath,
                                std::function<void()> done);   // 双源竞速（镜像+官方）
    void collectTasks(const QJsonObject& versionJson, const QString& versionId,    
                      const QMap<QString, QJsonObject>& assetObjects,
                      QVector<DownloadTask>& tasks);
    bool shouldDownloadLibrary(const QJsonObject& lib) const;
    void addLibraryTasks(const QJsonObject& lib, QVector<DownloadTask>& tasks);
    QString buildMirrorUrl(const QString& originalUrl, const QString& kind) const;

    // --- Verify phase (SHA1 scan) ---
    struct VerifyItem {
        QString fullPath;
        QString expectedSha1;
        QString label;
    };
    QVector<VerifyItem> collectVerifyItems(const QJsonObject& versionJson,
                                            const QString& versionId);
    void startAsyncVerify(const QVector<VerifyItem>& items);
    void onVerifyFinished(bool allPassed, const QStringList& missed,
                          const QStringList& missedPaths);

    // --- Helpers ---
    static bool verifySha1(const QString& filePath, const QString& expected);
    static QString formatSize(qint64 bytes);

    // --- Mirror fallback ---
    /// badPaths：完整性校验明确判坏（缺失 / SHA1 不符）的文件。
    /// 切镜像重下时据此清掉这些 assets，否则 AssetDownloader 的缓存预检查
    /// 会按「存在 + 尺寸一致」判命中，坏文件永远不会被重新拉取（2026-11-20）。
    void retryWithNextMirror(const QStringList& badPaths = QStringList());

    // --- Cross-downloader coordination ---
    void checkBothDownloadersDone();

    // --- Members ---
    MirrorSource m_mirror;
    QString m_minecraftDir;
    QString m_cacheFallbackDir;  // real gameDir for cache lookups (used when m_minecraftDir is a tempDir)
    DownloadConfig m_downloadCfg;
    int m_maxWorkers = 16;  // 与设置默认一致，上限 24

    // Mirror fallback: tracks current position in fallback chain
    QVector<MirrorSource> m_fallbackChain;
    int m_fallbackIndex = 0;
    static constexpr double kFallbackThreshold = 0.3;
    static constexpr int kRaceTimeoutMs = 20000;    // 双源竞速请求超时

    ShadowDownloader::FileDownloader* m_downloader = nullptr;
    AssetDownloader* m_assetDownloader = nullptr;

    QAtomicInt m_completedFiles{0};
    QAtomicInt m_totalFiles{0};
    QAtomicInteger<qint64> m_totalBytes{0};
    QAtomicInteger<qint64> m_downloadedBytes{0};

    // Cross-downloader completion tracking
    bool m_libTasksDone = false;
    bool m_assetTasksDone = false;

    enum State { Idle, Running, Paused, Cancelled, Verifying, Done, Failed };
    State m_state = Idle;

    // ── 资源索引临时文件（取消时必须清掉，否则 assets/indexes 留下 .part.* 残片）──
    QStringList m_indexTempFiles;                  // idx.part.0 / .1 / …
    QString m_indexFinalPath;                      // 索引最终 json 路径
    bool m_indexCommitted = false;                 // 索引已成功落盘

    QString m_currentVersionId;

    // Cached for integrity verification
    QMap<QString, QJsonObject> m_assetObjects;
    QJsonObject m_currentVersionJson;
    QStringList m_taskDestPaths;

    // Per-category total bytes (pre-computed from all tasks)
    qint64 m_categoryTotalBytes[3] = {0, 0, 0};
    // Per-file category mapping (savePath → cat). Populated by collectTasks().
    // Used by VersionBackend::updateDownloadFile() to classify files by task group
    // instead of runtime path matching (which can mismatch with task-group totals).
    QMap<QString, int> m_fileCategory;

    // Async verify worker (thread-based, replaces QTimer batching)
    class AsyncVerifyWorker;
    QThread* m_verifyThread = nullptr;
    AsyncVerifyWorker* m_verifyWorkerObj = nullptr;
    int m_downloadFailedCount = 0;  // stored for logging after async verify
};

// ═══════════════════════════════════════════════════════════
// AsyncVerifyWorker — background SHA1 verification
// ═══════════════════════════════════════════════════════════

class VersionDownloader::AsyncVerifyWorker : public QObject {
    Q_OBJECT
public:
    explicit AsyncVerifyWorker(QObject* parent = nullptr) : QObject(parent) {}

    void setItems(const QVector<VerifyItem>& items) { m_items = items; }
    void cancel() { m_cancelled.storeRelease(1); }

public slots:
    void process();

signals:
        void progressChecked(int checked, int total);
    /// 校验判坏后走「换镜像重下」的修复阶段进度（done/total = 本轮重下的文件数）。
    /// 2026-11-20：修复期间上层步骤原本停在 99% 一动不动（实测 105 秒），
    /// 用户以为卡死；有这个信号就能显示「修复中 x/y」并在跑完时收尾。
    void cancelled(int checked, int total);
    void finished(bool allPassed, const QStringList& missedLabels,
                  const QStringList& missedPaths);

private:
    static QString sha1FileFast(const QString& filePath);
    QVector<VerifyItem> m_items;
    QAtomicInt m_cancelled = 0;
    int m_failed = 0;
    QStringList m_failedLabels;
    QStringList m_failedPaths;
};

} // namespace ShadowLauncher
