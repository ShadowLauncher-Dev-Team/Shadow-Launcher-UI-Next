// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
//
// Asset-dedicated download engine v2 — speed-adaptive, multi-connection.
//
// Design:
//   - 2 persistent QNAMs (HTTP/1.1, 255 conn/host) avoid HTTP/2 stream limits
//   - Speed-based adaptive concurrency: monitor throughput, adjust inflight count
//   - Three-phase acceleration: burst → accelerate → steady
//   - SHA1+disk I/O offloaded to QThreadPool (non-blocking main thread)
//   - Per-host health tracking with consecutive-failure detection
//   - DNS pre-resolution with IP reliability scoring
//   - Sliding-window speed floor (85 % of weighted peak) prevents over-threading

#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QAtomicInt>
#include <QAtomicInteger>
#include <QElapsedTimer>
#include <QStringList>
#include <QVector>
#include <QQueue>
#include <QTimer>
#include <QThreadPool>
#include <QMutex>
#include <QMap>
#include <QSet>
#include <QHostInfo>

#include "utils/types.h"

// ────────────────────────────────────────────────────────────────────────────
class AssetDownloader : public QObject {
    Q_OBJECT
    Q_PROPERTY(int completedFiles READ completedFiles NOTIFY progressChanged)
    Q_PROPERTY(int totalFiles READ totalFiles NOTIFY progressChanged)
    Q_PROPERTY(qint64 downloadedBytes READ downloadedBytes NOTIFY progressChanged)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY progressChanged)

public:
    struct AssetTask {
        QString savePath;
        QString sha1;
        QStringList mirrors;   // download URLs, ordered by priority
        qint64 size = 0;
        // ── 阶段内重试（2026-11-14）──
        // 背景：所有镜像都失败时旧实现直接 finishDownload(false)，把文件丢给
        // 后面的「校验 + 自动修复」兜底 —— 实测 21 个资源文件就这样被放弃，
        // 安装多花 1.3 分钟重校验重下；而在这期间下载步骤的分母仍含这些字节，
        // 百分比永远到不了 100%，进度条死死停在 99%。
        // 现在在下载阶段内重试（多轮 + 退避 + 回退到完整镜像表）。
        int retryRound = 0;
        QStringList originalMirrors;   // 完整镜像表（镜像轮转时 mirrors 会被裁剪）
    };

    explicit AssetDownloader(QObject* parent = nullptr);
    ~AssetDownloader() override;

    void setMaxConcurrent(int n) { m_maxConcurrent = qBound(4, n, 256); }
    void setSpeedLimitMB(double mbps) { m_speedLimitMB = mbps; }
    /// 工作目录（merged 场景为 UUID 临时目录）——用于缓存 fallback 相对路径推导（2026-08-05）
    void setMinecraftDir(const QString& dir) { m_minecraftDir = dir; }
    /// If a file is not found in the working dir (tempDir), check this fallback
    /// dir (gameDir) for a matching SHA1 and copy it locally instead of re-downloading.
    void setFallbackCacheDir(const QString& dir) { m_fallbackCacheDir = dir; }

    void startDownload(const QVector<AssetTask>& tasks, int maxConcurrent = 16);
    /// 运行中追加任务（m_pendingQueue 追加，dispatch 循环会消费）。
    /// 用于：阶段 A 小库文件先启动，阶段 B assets 就绪后追加同引擎并行。
    void appendTasks(const QVector<AssetTask>& tasks);
    void cancel();
    bool isRunning() const { return m_state == Running; }

    // --- Stats ---
    int completedFiles() const { return m_completedFiles.loadRelaxed(); }
    int totalFiles() const { return m_totalFiles.loadRelaxed(); }
    qint64 downloadedBytes() const { return m_downloadedBytes.loadRelaxed(); }
    qint64 totalBytes() const { return m_totalBytes.loadRelaxed(); }
    /// Bytes from cache hits (excluded from speed calculation).
    qint64 cachedBytes() const { return m_cacheBytes.loadRelaxed(); }
    /// Network-only bytes (total - cache).
    qint64 networkBytes() const { return m_downloadedBytes.loadRelaxed() - m_cacheBytes.loadRelaxed(); }
    double currentSpeedMBps() const { return m_emaMbps; }
    /// 引擎当前速度（bytes/s）。单一来源：本引擎的 EMA 采样值（sampleSpeed 写入）。
    /// 上层只允许格式化显示，**不得再做二次平滑/相加/减半**（DOWNLOAD_CONTRACT §4）。
    qint64 currentSpeedBps() const { return m_emaBps.loadRelaxed(); }

signals:
    void progressChanged(int completedFiles, int totalFiles,
                         qint64 downloadedBytes, qint64 totalBytes);
    void fileCompleted(const QString& fileName, bool success);
    void fileProgress(const QString& url, const QString& fileName,
                      qint64 received, qint64 total,
                      const QString& savePath);
    void allFinished(bool success, int failedCount, const QStringList& failedFiles);
    void logMessage(const QString& msg);

private slots:
    void onReplyFinished(QNetworkReply* reply);

private:
    // ── Lifecycle ──
    void setupNam();
    void fireNext();
    void finishDownload(const AssetTask& task, bool success);
    /// 失败重试：还能重试就排队并返回 true；轮次用尽才真正判失败。
    bool retryOrFail(const AssetTask& task, const QString& why);
    void checkAllFinished();

    // ── Speed-adaptive scheduler (replaces old rampTick) ──
    void accelTick();                      // called by m_accelTimer
    void throttledTick();                  // called by m_throttleTimer（1s，轻量兜底）
    void watchdogTick();                   // called by m_watchdogTimer（2026-08-10）
    void schedulePhase();
    int  currentInflight() const;
    bool shouldThrottleSpeed() const;
    /// 缓存预检查（startDownload 与 appendTasks 共用，2026-08-05）：
    /// savePath 或 fallback 存在且大小匹配 → enqueuePreCheck，返回 true
    bool enqueueCachePreCheck(const AssetTask& task);

    // ── Per-host health ──
    struct HostStats {
        int  activeRequests = 0;
        int  consecutiveFails = 0;
        int  totalFails = 0;
        int  totalSuccess = 0;
        qint64 avgFirstByteMs = 15000;     // running average, start conservative
        bool  degraded = false;            // skip if too many fails
        qint64 degradedAtMs = 0;           // 降级时间戳（2026-08-05：超过 kDegradeRetryMs 自动恢复，防永久卡死）
        int  dynamicLimit = 4;             // current dynamic per-host limit
        // ── Range 支持（2026-11-17）──
        // 分片前必须先确认这个 host 认 Range。探测用 bytes=0-0（1 字节），
        // 只探一次。为什么必须探：服务器若不认 Range 会退化成 200 全文件，
        // 每条"分片"连接都会把整个文件下一遍 —— 用户明确要求不能出现这种
        // 多余流量，所以宁可在不确定时老老实实单连接。
        int  rangeOk = -1;                 // -1=未探测 0=不支持 1=支持
    };
    QString extractHost(const QString& url) const;
    bool hostCanAccept(const QString& host) const;
    void recordHostResult(const QString& host, bool ok, qint64 firstByteMs);
    /// Per-host connection limit — dynamically adjusted.
    /// BMCLAPI: separate limit; others use host-specific dynamic limit.
    int  getHostLimit(const QString& host) const;
    /// 同上，但要求调用方已持有 m_hostMutex（hostCanAccept 内部用，避免二次加锁死锁）
    int  hostLimitLocked(const QString& host) const;
    void adjustHostLimits();
    void logHostSummary();   // [主机] 每主机 成功/失败/首字均 —— 定量证据，不必再靠外部抓包              // called periodically to tune limits

    // ── 全源不可用冷却（2026-08-05）──
    // 所有镜像 degraded/限流时：fireNext 每 50ms 扫全队列无意义（锁竞争 + 无日志），
    // 改为冷却 kAllBlockedRetryMs 后重试；持续不可用超过 kAllBlockedFailMs 判定失败收尾。
    static constexpr qint64 kDegradeRetryMs = 30000;   // degraded 自动恢复周期（30s）
    static constexpr qint64 kAllBlockedRetryMs = 5000; // 全拒冷却后重试（5s）
    static constexpr qint64 kAllBlockedFailMs = 120000; // 全拒持续 120s → 剩余任务失败收尾
    qint64 m_blockedUntilMs = 0;           // 全拒冷却截止时间
    qint64 m_allBlockedSinceMs = 0;        // 首次全拒时间（持续超时用）
    qint64 m_lastBlockedLogMs = 0;         // 全拒日志节流

    // ── DNS + IP reliability ──
    struct IPInfo {
        QStringList addresses;             // resolved IPs
        QMap<QString, double> reliability; // IP → score (-1..+0.5)
        qint64 lastResolveMs = 0;
    };

    // ── Speed monitoring ──
    void sampleSpeed();
    void updateSpeedFloor();
    /// Reset speed baseline after burst cache-hits, so initial reading is correct
    void resetSpeedBaseline();

    // ── I/O offload (thread pool) ──
    struct IOTask {
        AssetTask task;
        QByteArray data;
    };
    void enqueueIO(const AssetTask& task, const QByteArray& data);

    // ── Cache fallback ──
    QString m_minecraftDir;        // 工作目录（tempDir for merged；2026-08-05）

    // ── Async SHA1 pre-check (offloaded to IO pool, avoids main-thread blocking) ──
    /// checkPath: path to verify SHA1 at (default: task.savePath).
    /// If checkPath != task.savePath and SHA1 matches, copies checkPath → savePath.
    void enqueuePreCheck(const AssetTask& task, const QString& checkPath = QString());
    struct PreCheckPending {
        AssetTask task;
        qint64 enqueueAtMs = 0;
    };
    QMap<QString, PreCheckPending> m_pendingPreCheck;  // sha1 → task
    void onPreCheckResult(const AssetTask& task, bool sha1Match, const QString& preCheckKey);

    // ════════════════════════════════════════════════════════════════════════
    // 空闲槽驱动的分片（2026-11-17）
    // ════════════════════════════════════════════════════════════════════════
    // 现象：assets 已按大小降序派发，但"最大的文件"若撞上慢连接，会成为收尾
    // 阶段仅剩的在途请求 —— 十几个槽位全空转，整体速度掉回单连接水平
    // （用户实测尾程 <1MB/s，与模组下载修复前完全同型）。
    //
    // 策略与模组下载（精卫）一致：不看"文件大不大"，只看"有没有空槽"。
    //   ① 派发时就有空闲槽且文件够大 → 直接按空闲槽数切段并发；
    //   ② 已经在下载的大文件遇到空闲槽 → 就地切分：已收字节作为第 0 段保留，
    //      剩余部分才发 Range —— 已收字节绝不重下。
    //
    // 三道"不多下一字节"的闸门：
    //   1) 先对 host 做 1 字节 Range 探测，只对确认回 206 的 host 开分片；
    //   2) 每个分片响应必须 206 且 Content-Range 起点等于请求起点，否则立即
    //      abort（此时代码还没开始收 body，浪费≈0），该 host 永久改为单连接；
    //   3) 合并后校验 SHA1，不匹配则整文件回退单连接重下，并把作废字节
    //      计入 m_wastedBytes —— 让"有没有偷流量"可测，不靠感觉。
    struct InFlight;   // 定义在下方"Task queues"区（handleShardReply 声明需要前置声明）

    struct ShardState {
        AssetTask task;
        qint64 total = -1;
        QVector<qint64> segStart;      // 每段起始偏移
        QVector<qint64> segLen;        // 每段长度
        QVector<qint64> segHave;       // 每段已收字节
        QVector<QByteArray> segData;   // 每段已收内容（assets ≤ 11MB，内存足够）
        QVector<int> segState;         // 0=待发 1=在途 2=完成
        int inflight = 0;
        int mirrorBase = 0;            // 选源起点（分片沿用主任务的源顺序）
        int segRetry = 0;              // 段级连续失败计数
        qint64 lastActiveMs = 0;       // 最近一次有段在跑/有进展的时刻（防"无源可派"下永久挂起）
    };
    QMap<QString, ShardState> m_shards;   // key = savePath|sha1（同 SHA1 可对应多条目，不能只用 sha1）
    QMap<QString, int> m_rangeProbe;      // host → -1 探测中 / 0 不支持 / 1 支持
    QAtomicInteger<qint64> m_wastedBytes{0};   // 分片作废字节（回退/校验失败时累计）

    /// 分片任务主键（与缓存预检查同规则：同一 SHA1 可对应多个 savePath）
    static QString shardKeyOf(const AssetTask& t) {
        return t.savePath + QLatin1Char('|') + t.sha1;
    }
    int  shardIdleSlots() const { return m_maxConcurrent - m_inFlight.size(); }
    /// 对候选 host 各发一次 1 字节 Range 探测（每 host 只探一次）
    void probeRangeSupport(const QVector<AssetTask>& tasks);
    /// 派发时判断该不该分片（够大 + 有空槽 + host 认 Range）
    bool tryStartShard(const AssetTask& task, int mirrorIndex);
    /// 把任务拆成分片并发；prefix 为已收前缀（就地切分时非空）
    bool startShardFromPrefix(const AssetTask& task, int mirrorIndex, const QByteArray& prefix);
    /// 派发某一段（续传该段剩余部分）
    void dispatchShardSeg(const QString& key, int segIndex);
    /// 分片响应收尾（onReplyFinished 分流入口）
    void handleShardReply(QNetworkReply* reply, const InFlight& ift);
    /// 全部段到齐 → 合并 → SHA1 → 落盘
    void finalizeShard(const QString& key);
    /// 放弃分片：作废已收字节（计入浪费），整文件回退单连接重下
    void abandonShard(const QString& key, const QString& why);
    /// 空闲槽补派分片段（watchdog / accel 调用）
    int  dispatchPendingShardSegs();
    /// 空闲槽驱动：把在途的单连接大文件就地切成多段
    void trySplitInFlight();

    // 分片阈值（2026-11-17 实测校准）
    // ≥2MB 才值得切：assets 最大约 11MB，2MB 以下切出来的段太小、握手开销占比高。
    // 每段 ≥512KB：Range 请求头开销可以忽略，且避免产生大量碎片段。
    // 分片门槛 2026-11-18：2MB → 8MB。实测资产/库绝大多数是 4KB–2MB，
    // 2MB 就切只会多出「探测 + 临时文件 + 合并」开销而无收益；
    // 真正需要并发的是几十 MB 的大文件。
    static constexpr qint64 kSegMinBytes    = 8LL * 1024 * 1024;
    static constexpr qint64 kMinShardPiece  = 512 * 1024;
    static constexpr int    kMaxShardPieces = 8;

    // ── Async DNS resolution ──
    struct DnsPending {
        QString host;
        int refCount = 0;
    };
    QMap<QString, DnsPending> m_dnsToResolve;  // host → pending state
    int  m_dnsPendingCount = 0;
    bool m_dnsAllResolved = false;
    void startAsyncDns();
    void checkAllDnsResolved();

    // ── State ──
    enum State { Idle, Running, Cancelled, Done };
    State m_state = Idle;
    int   m_totalTaskCount = 0;

    // ── Phase management ──
    enum Phase { PhaseInit, PhaseBurst, PhaseAccelerate, PhaseSteady, PhaseCooldown };
    Phase m_phase = PhaseInit;
    QTimer* m_accelTimer = nullptr;        // fires every 50ms during accel
    QTimer* m_watchdogTimer = nullptr;     // 挂起看门狗 1s（独立于 accelTick：队列空时 accelTick 会停）
    QTimer* m_throttleTimer = nullptr;     // 分片补派/唤醒兜底 1s（2026-11-17）
    // 周期性进度心跳 500ms（2026-11-17）：见 asset_downloader.cpp 里的说明。
    // 没有它，资源阶段的速度数字只在"有文件下完"时才更新 → 卡住时界面冻结。
    QTimer* m_emitTimer = nullptr;
    static constexpr int kEmitIntervalMs = 500;
    static constexpr int kAccelIntervalMs = 50;
    static constexpr int kWatchdogIntervalMs = 1000;
    static constexpr qint64 kInFlightStallMs = 30000;  // in-flight 无字节进展 30s → abort 换源

    // ── Concurrency ──
    int  m_maxConcurrent = 16;
    int  m_targetInflight = 0;             // computed by schedulePhase()
    int  m_burstSent = 0;                  // count of initial burst requests
    int  m_preCheckQueued = 0;             // count of async SHA1 pre-checks in flight
    static constexpr int kBurstSize = 4;   // immediate burst (reduced from 12, servers throttle >4)
    static constexpr int kAccelStep = 2;   // add per tick during accelerate (reduced from 4)
    static constexpr int kMaxPerHost = 4;  // max concurrent per host (reduced from 8)

    // ── Network managers (2 × HTTP/1.1 to avoid HTTP/2 stream limits) ──
    QNetworkAccessManager* m_nam[2] = {nullptr, nullptr};
    int  m_namRoundRobin = 0;              // simple round-robin

    // ── Task queues ──
    QQueue<AssetTask> m_pendingQueue;
    struct InFlight {
        AssetTask task;
        int  mirrorIndex = 0;
        int  namIndex = 0;                 // which QNAM handled it
        qint64 startMs = 0;                // for timing
        qint64 progressBytes = 0;          // bytes tracked via downloadProgress (增量)
        // 首字节时刻（2026-11-17）：第一个 downloadProgress 回调的耗时。
        // 用途：成功也要 recordHostResult(host, true, 首字ms)——旧实现只在失败时记录，
        //       导致 consecutiveFails 只增不减（见 recordHostResult 注释），
        //       累计 3 次失败就把整台主机打成 degraded，Download 随之冻结最多 30s。
        qint64 firstByteMs = -1;
        qint64 lastProgressMs = 0;         // 最近一次字节进展时刻（挂起看门狗用，2026-08-10）
        bool  watchdogAborted = false;     // 看门狗已 abort（跳过 host 失败记录，防误伤源）
        // ── 慢速拖流跟踪（2026-08-14）──
        // 背景：官方资源 CDN 对部分文件限速/拥塞时，请求持续有零星字节流
        // （几 KB/s），lastProgressMs 不断刷新 → 30s 无进展判定永不触发 →
        // 单个慢文件拖死整个下载（实测 assets 卡 97% 4 分钟）。
        // 策略：窗口内平均速率低于阈值且连续多窗口 → 判龟速 abort 换源。
        qint64 rateWindowStartMs = 0;      // 当前速率窗口起始时刻
        qint64 rateWindowBytes = 0;        // 窗口起始时的 progressBytes
        int    slowStreak = 0;             // 连续低速窗口计数

        // ── 分片（2026-11-17）──
        // 一条在途请求可能是「整文件要求」也可能是「某个分片段的 Range 请求」。
        // shardKey 非空即后者；segIndex 指向该段在 ShardState 里的下标。
        QString shardKey;
        int     segIndex = -1;
        qint64  rangeExpectStart = -1;     // 本次 Range 请求的起点（校验 Content-Range 用）
        QByteArray keepPrefix;             // 就地切分时保留的已收字节（abort 会清缓冲，必须先取）
        bool    converting = false;        // 正在从单连接转为分片
        bool    rangeBad = false;          // 服务器没按 Range 响应（非 206 / 起点不符）
    };
    QMap<QNetworkReply*, InFlight> m_inFlight;
    int  m_failedCount = 0;
    // 任务账务审计（2026-11-17）：总数 == 缓存命中 + 网络成功 + 失败 + 丢弃
    int  m_netOk = 0;          // 走网络且校验通过的文件数
    int  m_droppedTasks = 0;   // 因状态非 Running 被丢弃、既不算成功也不算失败的任务数
    QStringList m_failedFiles;
    int  m_cacheHitCount = 0;
    // 已排队但尚未入队重试的任务数：退避等待期间队列是空的，
    // 若不拦住 checkAllFinished 会误判「全部完成」（进度虚高到 100%）。
    int  m_retryScheduled = 0;
    static constexpr int kMaxRetryRounds = 3;   // 含首次共 3 轮

    // ── Stats ──
    QAtomicInt m_completedFiles{0};
    QAtomicInt m_totalFiles{0};
    QAtomicInteger<qint64> m_totalBytes{0};
    QAtomicInteger<qint64> m_downloadedBytes{0};
    qint64 m_lastSpeedLogBytes = 0;   // 吞吐心跳基线（2026-11-17）
    // ── 主线程开销 / 真实派发率实测（2026-11-17）──
    // 目的：定位"引擎吞吐远低于同并发 curl 实测"的原因，而不是继续猜。
    // m_mainThreadWorkUs 只统计 onReplyFinished 里 readAll + SHA1 + 投递的耗时，
    // 这段跑在主线程；若它占比高，就说明主线程被哈希/拷贝堵住，连接再多也没用。
    qint64 m_mainThreadWorkUs = 0;
    qint64 m_sha1Bytes = 0;
    // 单请求耗时分布（2026-11-17）：直接验证"连接是否被复用"。
    // 复用成功时小文件请求 ≈ TTFB(0.38s)；每次都重建连接则 ≈ 0.64s（外加 TCP+TLS）。
    // 平均值会被大文件拖偏，所以同时统计"快请求占比"，两者一起看才准。
    qint64 m_reqTotalMs = 0;
    int    m_reqCount = 0;
    int    m_reqFast = 0;      // < 500ms 的请求数
    int    m_replyFinishedCount = 0;
    int    m_dispatchCount = 0;
    QElapsedTimer m_hbTimer;          // 心跳专用时钟（不借用 sampleSpeed 的 50ms 周期）
    QAtomicInteger<qint64> m_lastSampleBytes{0};
    QAtomicInteger<qint64> m_cacheBytes{0};  // bytes from cache hits (excluded from speed calc)
    QString m_fallbackCacheDir;            // gameDir to check for existing files before downloading
    QElapsedTimer m_speedTimer;

    // ── Speed floor (adaptive, 85 % of weighted peak) ──
    static constexpr int   kMaxSpeedRecords = 20;
    static constexpr qint64 kMinSpeedFloorBps = 256LL * 1024;
    mutable QMutex m_speedMutex;
    QList<qint64> m_speedRecords;          // B/s, newest first
    QAtomicInteger<qint64> m_speedFloorBps{kMinSpeedFloorBps};
    double m_emaMbps = 0.0;                     // 展示用（MB/s）；保留给既有调用方
    QAtomicInteger<qint64> m_emaBps{0};         // 对外速度单值（bytes/s，EMA 同源；禁止上层二次平滑）
    double m_speedLimitMB = -1.0;

    // ── Per-host tracking ──
    mutable QMutex m_hostMutex;
    QMap<QString, HostStats> m_hostStats;

    // ── DNS / IP reliability (built-up async from lookupHost results) ──
    mutable QMutex m_dnsMutex;
    QMap<QString, IPInfo> m_dnsCache;
    static constexpr qint64 kDnsCacheMs = 300000;     // 5 min

    // ── I/O thread pool ──
    QThreadPool m_ioPool;
    static constexpr int  kMaxIOWorkers = 8;   // 2026-08-14 4→8：缓解写盘积压（配合 watchdog 完成兜底）

    // ── Throttle progress signals ──
    QElapsedTimer m_lastProgressEmit;
    static constexpr int kProgressThrottleMs = 150;

    // ── Detailed logging ──
    QElapsedTimer m_downloadTimer;
    void logState(const char* event);
    void logSpeed();  // rate-limited speed snapshot (1s interval)
    QElapsedTimer m_speedLogTimer;
};
