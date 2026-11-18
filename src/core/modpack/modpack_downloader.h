// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
//
// modpack_downloader.h — 整合包远端模组下载层（网络层 + 引擎适配层）。
//
// 参照 主流启动器 的 LoaderDownload 思路：
//   1. CurseForge：POST /v1/mods/files 批量换取真实下载地址（x-api-key 鉴权，
//      50 个 fileId/批），按 modules 判定资源类型（mods/resourcepacks/shaderpacks），
//      下载完成比对 API 返回的 fileLength。
//   2. Modrinth：直接使用 index.json 的 downloads[0]（+ 备用地址），
//      下载完成比对 sha1。
//   3. 镜像优先 + 官方兜底（MCIM 镜像 / CF·MR 官方端点，429/5xx/超时降级）。
//
// 下载执行复用独立模组引擎 ShadowDownloader::ModDownloadEngine（小文件批量专属，
// 与 MC 下载引擎 FileDownloader 物理隔离：线程/网络会话/队列互不争抢）
// 多源自动降级、SHA1/大小校验、主机健康、限速、EMA 网速），本类只承担：
//   - CF 批量地址解析（REST API，与文件下载正交，引擎不含）
//   - 可选文件跳过 / 落盘路径编排 / 覆盖备份与新建登记钩子（任务级事务语义）
//   - 引擎信号 → 任务层信号桥接（index 关联、队列进度折算、取消语义）
// 对外接口（start/cancel/signals）保持不变，任务层与 QML 无感。
//
// 说明：不修改既有网络底层（HttpClient 为既有稳定模块），仅通过其公开
// 异步 API 组装 CF API 请求；文件本体下载交给 ModDownloadEngine 引擎实例
// （每次 start 新建，任务结束/取消即释放，与 MC 下载引擎实例完全隔离）。

#pragma once

#include <QObject>
#include <QString>
#include <QList>
#include <QMap>
#include <QJsonObject>
#include <QNetworkReply>
#include <QPointer>
#include <QSet>

#include <atomic>
#include <functional>

#include "modpack_common.h"

class QTimer;

namespace ShadowDownloader { class ModDownloadEngine; }

namespace ShadowLauncher {

class HttpClient;

class ModpackDownloader : public QObject {
    static constexpr int kConcurrentStartup = 3;  // 每轮批量启动上限
    static constexpr int kCleanupDelayMs = 2000; // 取消后延迟清理（等 abort/worker 退出）
    static constexpr int kBatchRetryLimit = 2;    // 批次 API 失败重试次数（退避 1s/3s）
    // 下载阶段无字节进展判失败阈值（2026-11-05 验收调整：60s → 240s）
// 依据：引擎的文件级重试退避是 5+10+15+20=50s 纯退避，再叠加每轮失败的尝试耗时
// （多源 × 15~30s 空闲超时），可自愈的抖动零字节窗口约 230s。旧值 60s 会在引擎
// 仍按设计重试时把整包判死（failRemaining 一次性标 fail，丢掉剩余 4 轮预算）。
// 取 240s：略大于 horizon，且仍能在真正挂死时兜底（4 分钟内必有结论）。
static constexpr int kStallTimeoutMs = 240000;
    static constexpr int kStallCheckIntervalMs = 5000;
    Q_OBJECT
public:
    explicit ModpackDownloader(QObject* parent = nullptr);

    void setApiKey(const QString& key) { m_apiKey = key; }
    void setTargetDir(const QString& dir) { m_targetDir = dir; }
    void setFiles(QList<ModpackRemoteFile>* files) { m_files = files; }
    // 覆盖钩子：落盘前若目标已存在旧文件则回调（任务层用于回滚备份）
    void setOverwriteHook(const std::function<void(const QString& savePath)>& hook) { m_overwriteHook = hook; }
    // 新建文件钩子：成功落盘后回调（任务层登记回滚，失败/取消时清理）
    void setCreatedHook(const std::function<void(const QString& savePath)>& hook) { m_createdHook = hook; }

    // 启动：先解析 CF 下载地址，再经 ModDownloadEngine 引擎并发下载。
    // includeOptional=true 时连可选文件一起下。
    /// resumeFailedOnly=true 时跳过 status 已是 done/skipped 的文件（只补下失败的）。
    void start(bool includeOptional, bool resumeFailedOnly = false);
    void cancel();
    bool isRunning() const { return m_running; }
    /// 当前下载速度（MB/s）：转发动机全局 EMA（基于全局已下载字节，带平滑与衰减）。
    /// 任务层应以此为准，不要用单文件 received 瞬时差（分片/多文件切换时跳变，会虚高）。
    double currentSpeedMBps() const;
    /// 引擎当前速度（bytes/s），直接转发引擎窗口值。
    /// 上层只允许格式化显示，**不得再做二次平滑或"无数据减半"**（DOWNLOAD_CONTRACT §4）。
    qint64 currentSpeedBps() const;
    /// 引擎累计已下载字节（速度心跳用它算 2s 增量，区分"显示冻结"与"真停滞"）
    qint64 downloadedBytes() const;
    /// 在跑文件的字节比例之和（0..活动数）：任务层队列进度 = (完成 + 这个值)/总数。
    double currentPartialFraction() const;

signals:
    void statusChanged(const QString& text);          // 阶段文案（"正在解析下载地址…"）
    void fileProgress(int index, const QString& name, qint64 received, qint64 total);
    void fileFinished(int index, bool success, const QString& error);
    void queueProgress(int completed, int total, int failed);
    void allFinished(bool cancelled);
    void logLine(const QString& msg);

private:
    struct DlItem {
        int index = -1;
        QStringList urls;      // 尝试顺序：[镜像 CDN, 官方直链, 备用源…] → 引擎 orderedSources
        QString savePath;      // 最终路径
        QString fileName;
        bool finished = false;
        bool ok = false;
        QString error;
    };

    // ── 镜像优先 + 官方兜底请求（异步链式；4xx 除 429 外不降级）──
    void apiWithFallback(bool isPost,
                         const QString& mirrorUrl, const QString& officialUrl,
                         const QByteArray& body, const QString& apiKey,
                         const std::function<void(int, const QByteArray&)>& cb);

    // ── CF 地址解析（REST API 层，保留自研）──
    void resolveBatch(int startIndex);                 // 按 50 个/批发 POST /v1/mods/files
    void onResolveBatchDone(int startIndex, int status, const QByteArray& body);
    void processResolvedBatch(int startIndex, const QMap<int, QJsonObject>& byId,
                              const QSet<int>& officialOnly = {});
    // deterministic=true：确定性错误（401/403/4xx 等），重试无意义 → 直接整体失败；
    // false：网络/限流类瞬时错误 → 批次级重试 kBatchRetryLimit 次后退避 1s/3s。
    void onResolveBatchFailed(int startIndex, const QString& err, bool deterministic = false);
    // 是否已进入「不再推进」状态（用户取消 或 内部判失败）——所有异步回调统一用它早退。
    bool stopped() const { return m_cancelled || m_internalFailed; }
    void finishDownloadUrlResolve(int idx, bool ok, int status);
    void resolveDownloadUrls();                        // downloadUrl 缺失的条目逐个补解析
    void startDownloadUrlResolve(int idx);
    void failRemaining(const QString& err);            // 整体失败：把所有未完成条目标失败
    void releaseEngineDeferred();                      // 延迟释放引擎（abort 异步窗口，避免阻塞 UI）
    void checkStall();                                 // 下载阶段 60s 无字节进展 → 判失败

    // ── 引擎适配层（ShadowDownloader::ModDownloadEngine）──
    void startEngineDownloads();   // 地址就绪 → 构造引擎 + addFile 编排 + 启动
    int findIndexBySavePath(const QString& path) const;
    void onEngineProgress(int completed, int total, qint64 bytes, qint64 allBytes);
    void onEngineFileProgress(const QString& url, const QString& fileName,
                              qint64 received, qint64 total);
    void onEngineFileFinished(const QString& localPath, bool success);
    void onEngineAllFinished();

    static QString classifyCategory(const QString& fileName, const QJsonArray& modules);

    HttpClient* m_http = nullptr;
    QString m_apiKey;
    QString m_targetDir;
    QList<ModpackRemoteFile>* m_files = nullptr;       // 由任务层持有，运行期不做结构变更
    bool m_includeOptional = false;

    QList<DlItem> m_items;                             // 按 files 顺序展开（含跳过项占位）
    int m_total = 0;
    int m_failed = 0;          // 解析阶段失败计数（引擎失败用 fd->failedFiles()）
    int m_skippedCount = 0;    // 可选跳过 + 取消未开始 计数（并入 queueProgress completed）

    bool m_running = false;
    quint64 m_generation = 0;         // 任务代际（start 递增）：延迟定时器/旧回调据此失效
    bool m_cancelled = false;         // 仅表示「用户取消 / 主动中止」
    bool m_internalFailed = false;    // 内部判失败（批次重试耗尽、60s 停滞）：与用户取消语义分开
    QList<int> m_downloadUrlPending;   // 待补解析 download-url 的条目（镜像优先）
    QSet<int> m_downloadUrlInflight;   // 正在补解析的条目（取代旧实现拿 finished 当占用标记）
    QSet<int> m_officialOnlyFileIds;   // 官方补查救回的 fileId（镜像未同步：跳过镜像分片/镜像接口）
    int m_batchRetryStartIndex = -1;   // 批次重试计数绑定的批次起点
    int m_batchRetryCount = 0;         // 当前批次已重试次数
    QTimer* m_stallTimer = nullptr;    // 下载阶段停滞看门狗（5s 一扫，60s 无字节判失败）
    qint64 m_lastWatchdogBytes = -1;   // 上一次采样到的引擎累计字节
    qint64 m_lastWatchdogMs = 0;       // 最近一次字节增长时刻
    std::function<void(const QString&)> m_overwriteHook;   // 覆盖旧文件前的回调
    std::function<void(const QString&)> m_createdHook;     // 新建文件落盘后的回调（回滚登记）
    QList<QPointer<QNetworkReply>> m_inflight;   // CF API 在途请求（取消时 abort）

    ShadowDownloader::ModDownloadEngine* m_fd = nullptr;  // 引擎实例（每次 start 新建）
    QSet<QString> m_preExisting;   // addFile 前已存在的目标（覆盖场景，成功不登记新建）
    qint64 m_lastQueueEmitMs = 0;  // queueProgress 桥接限频（200ms）
    qint64 m_lastFileProgMs = 0;   // fileProgress 桥接限频（200ms）
    QString m_lastEngineError;     // 引擎最近一条失败/校验日志（失败详情透传卡片）
};

} // namespace ShadowLauncher
