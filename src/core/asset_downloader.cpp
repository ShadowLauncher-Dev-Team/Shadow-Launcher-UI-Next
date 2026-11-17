// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
//
// Asset-dedicated download engine v2 (performance-tuned 2026-07-29).
//
// Performance fixes:
//   - Async SHA1 pre-check (IO pool instead of blocking main thread)
//   - Async DNS resolution (QHostInfo::lookupHost instead of fromName)
//   - Fixed cache-hit speed spike corrupting speed floor
//   - Reduced default concurrency (burst 12, max 32, per-host 8)
//   - Added detailed logging for diagnostics
//
// Design:
//   1. Init: async DNS pre-resolution, brief size-based cache check
//   2. Burst: fire ~12 requests immediately
//   3. Accelerate: every 50ms, check throughput. If speed < floor → add 4 more.
//      Speed floor starts at 256KB/s, rises to 85% of weighted peak.
//   4. Steady: when speed >= floor, stop adding. Replace finished requests.
//   5. Cooldown: if speed drops sharply, reduce inflight to avoid congestion.

#include "asset_downloader.h"
#include "../utils/hash_utils.h"
#include "engine_identity.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QCryptographicHash>
#include <QUrl>
#include <QLoggingCategory>
#include <QRunnable>
#include <QNetworkRequest>
#include <QHttp1Configuration>
#include <QDateTime>
#include <QPointer>
#include <QHostInfo>
#include <algorithm>

Q_LOGGING_CATEGORY(logAsset, "ShadowDownloader.Asset")

namespace {
    QString fmtSize(qint64 bytes) {
        if (bytes < 1024)       return QStringLiteral("%1 B").arg(bytes);
        if (bytes < 1024*1024)  return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
        return QStringLiteral("%1 MB").arg(bytes / (1024.0*1024.0), 0, 'f', 1);
    }
} // anonymous

// ── 慢速拖流看门狗常量（2026-08-14）──
// 官方资源 CDN 限速/拥塞时单文件持续零星字节（绕过 30s 无进展判定），
// 需按"窗口平均速率"判龟速。参考夸父慢速分片（2s 采样 <256KB 判龟速）。
namespace {
    constexpr int    kRateWindowMs     = 4000;   // 速率窗口 4s
    constexpr qint64 kMinRateBps       = 64 * 1024;  // 窗口内平均 < 64KB/s 判低速
    constexpr int    kMaxSlowStreak    = 5;      // 连续 5 窗口（20s）低速 → abort
}

// ═════════════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ═════════════════════════════════════════════════════════════════════════════

AssetDownloader::AssetDownloader(QObject* parent)
    : QObject(parent)
{
    // Acceleration timer — fires frequently during the accelerate phase
    m_accelTimer = new QTimer(this);
    m_accelTimer->setSingleShot(false);
    m_accelTimer->setInterval(kAccelIntervalMs);
    connect(m_accelTimer, &QTimer::timeout, this, &AssetDownloader::accelTick);

    // Hang watchdog — 1s independent of accelTick (2026-08-10)
    // accelTick stops when the queue is empty; a stalled in-flight request
    // (transferTimeout never fires when the server trickles data) would then
    // hang completion forever at 99%. Watchdog aborts stalled requests.
    m_watchdogTimer = new QTimer(this);
    m_watchdogTimer->setSingleShot(false);
    m_watchdogTimer->setInterval(kWatchdogIntervalMs);
    connect(m_watchdogTimer, &QTimer::timeout, this, &AssetDownloader::watchdogTick);

    // 分片补派 / accelTimer 唤醒兜底（2026-11-17）：1s 节拍，轻量。
    // 与 watchdog 分开是因为 watchdog 里还有 abort 逻辑，语义不同，
    // 混在一起以后改一处会误伤另一处。
    m_throttleTimer = new QTimer(this);
    m_throttleTimer->setSingleShot(false);
    m_throttleTimer->setInterval(1000);
    connect(m_throttleTimer, &QTimer::timeout, this, &AssetDownloader::throttledTick);

    // I/O thread pool: 4 workers for SHA1 + disk writes
    m_ioPool.setMaxThreadCount(kMaxIOWorkers);

    setupNam();
}

AssetDownloader::~AssetDownloader()
{
    cancel();
}

// ═════════════════════════════════════════════════════════════════════════════
// Network manager setup
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::setupNam()
{
    m_accelTimer->stop();
    m_watchdogTimer->stop();
    m_burstSent = 0;
    m_targetInflight = 0;
    m_phase = PhaseInit;

    // ── 2026-11-18：QNAM 数量从 2 提到 32 ──
    // Qt 的 QHttpNetworkConnection 每个连接对象默认 6 条 channel，
    // 所以「单主机真实并发 = 6 × QNAM 数」。之前 2 个 QNAM = 12 条真实连接，
    // 与我们声明的 192 并发差 16 倍：日志里在途=192 却只有 114 文件/s、请求均 1653ms
    // （参考引擎同样 192 并发是 309 文件/s、190ms）。
    // 32 × 6 = 192，与目标并发对齐。每个 QNAM 自带一条网络线程，32 个线程可接受。
    // 仍然逐请求 Http2AllowedAttribute=false（HTTP/2 单连接复用会把 192 请求挤到少数流上）。
    for (int i = 0; i < kNamCount; ++i) {
        if (m_nam[i]) {
            m_nam[i]->disconnect();
            m_nam[i]->deleteLater();
            m_nam[i] = nullptr;
        }
        m_nam[i] = new QNetworkAccessManager(this);
    }

    qCInfo(logAsset) << QStringLiteral("[山海经] %1× QNAM 就绪（单主机真实并发 ≈ %2）")
        .arg(kNamCount).arg(kNamCount * 6);
}

// ═════════════════════════════════════════════════════════════════════════════
// Entry point
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::startDownload(const QVector<AssetTask>& tasks, int maxConcurrent)
{
    if (m_state == Running) {
        qCWarning(logAsset) << QStringLiteral("[山海经] 已在运行，忽略重复的 startDownload()");
        return;
    }

    m_maxConcurrent = qBound(4, maxConcurrent, 256);
    m_targetInflight = 0;
    m_phase = PhaseInit;
    m_burstSent = 0;
    m_cacheHitCount = 0;
    m_netOk = 0;
    m_droppedTasks = 0;
    m_preCheckQueued = 0;
    m_cacheBytes.storeRelaxed(0);
    m_dnsPendingCount = 0;
    m_dnsAllResolved = false;
    m_pendingPreCheck.clear();
    m_dnsToResolve.clear();
    m_hostStats.clear();  // Clear stale degradation from previous runs

    m_pendingQueue.clear();
    m_inFlight.clear();
    m_failedFiles.clear();
    m_failedCount = 0;
    // 全源不可用冷却状态重置（2026-08-05）
    m_blockedUntilMs = 0;
    m_allBlockedSinceMs = 0;
    m_lastBlockedLogMs = 0;
    m_completedFiles.storeRelaxed(0);
    m_downloadedBytes.storeRelaxed(0);
    m_totalTaskCount = tasks.size();

    qint64 totalEst = 0;
    for (const auto& t : tasks)
        totalEst += t.size;
    m_totalBytes.storeRelaxed(totalEst);
    m_totalFiles.storeRelaxed(tasks.size());

    // 大小降序（2026-08-05）：大文件先下（前期高并发/多连接竞争），
    // 后期全小文件（每个 0.1s）——避免哈希序尾部碰巧集中大文件（音乐 ogg
    // 11MB）→ 收尾阶段单连接慢（用户实测：90% 后停摆 48 秒）
    QVector<AssetTask> sorted = tasks;
    std::sort(sorted.begin(), sorted.end(),
              [](const AssetTask& a, const AssetTask& b) {
                  return a.size > b.size;
              });

    for (auto t : sorted) {
        if (t.originalMirrors.isEmpty()) t.originalMirrors = t.mirrors;
        m_pendingQueue.enqueue(t);
    }

    m_state = Running;
    m_lastProgressEmit.start();
    m_downloadTimer.start();
    m_speedLogTimer.start();
    m_hbTimer.start();
    m_lastSpeedLogBytes = 0;
    m_mainThreadWorkUs = 0;
    m_sha1Bytes = 0;
    m_replyFinishedCount = 0;
    m_dispatchCount = 0;
    m_reqTotalMs = 0;
    m_reqCount = 0;
    m_reqFast = 0;
    m_watchdogTimer->start();
    m_throttleTimer->start();

    // ── 周期性进度心跳（2026-11-17）──
    // 背景：本引擎原本只在 finishDownload() 里发 progressChanged（150ms 节流），
    // 也就是说"没有文件下完 = 界面完全收不到进度"。上层 VersionBackend 的速度是
    // 由 progressChanged 驱动的（netDelta/衰减都在里面算），没事件就既不更新也不衰减
    // —— 用户看到的"卡在 0.1 MB/s 很久不动"就是这么来的（实测截图 16:37）。
    // 对比：夸父（FileDownloader）有 100ms 的 speedTick 一直在发，所以库阶段不会冻结。
    // 这里补上同一个节拍，代价是每秒 2 次信号，可忽略。
    if (!m_emitTimer) {
        m_emitTimer = new QTimer(this);
        m_emitTimer->setSingleShot(false);
        m_emitTimer->setInterval(kEmitIntervalMs);
        connect(m_emitTimer, &QTimer::timeout, this, [this]() {
            if (m_state != Running) return;
            emit progressChanged(m_completedFiles.loadRelaxed(),
                                 m_totalFiles.loadRelaxed(),
                                 m_downloadedBytes.loadRelaxed(),
                                 m_totalBytes.loadRelaxed());
        });
    }
    m_emitTimer->start();

    // Log the first few task's mirror sources to verify which source is being used
    if (!tasks.isEmpty()) {
        const auto& first = tasks.first();
        QString sampleUrls;
        for (int i = 0; i < qMin(first.mirrors.size(), 4); ++i) {
            if (i > 0) sampleUrls += QStringLiteral(" | ");
            sampleUrls += first.mirrors[i];
        }
        qCInfo(logAsset) << engineBanner("shanhai");
    emit logMessage(engineBanner("shanhai"));
    emit logMessage(QStringLiteral("[山海经] 开始下载资源文件 共 %1 个 (%2)")
                            .arg(tasks.size()).arg(fmtSize(totalEst)));
        emit logMessage(QStringLiteral("[山海经]   镜像源示例: %1").arg(sampleUrls));
    } else {
        emit logMessage(QStringLiteral("[山海经] 开始下载资源文件 共 0 个"));
    }
    emit progressChanged(0, tasks.size(), 0, totalEst);

    // ════════════════════════════════════════════════════════════════
    // Phase Init: async DNS + pre-check already-cached files
    // ════════════════════════════════════════════════════════════════
    // Collect unique hosts for async DNS resolution
    QSet<QString> hosts;
    for (const auto& t : tasks) {
        for (const auto& m : t.mirrors)
            hosts.insert(extractHost(m));
    }
    // Store them for async resolution
    for (const auto& h : hosts) {
        DnsPending dp;
        dp.host = h;
        dp.refCount = 0;
        m_dnsToResolve.insert(h, dp);
    }
    m_dnsPendingCount = m_dnsToResolve.size();

    if (!m_dnsToResolve.isEmpty()) {
        emit logMessage(QStringLiteral("[山海经] 正在解析 %1 个域名...").arg(m_dnsToResolve.size()));
        startAsyncDns();
    } else {
        m_dnsAllResolved = true;
    }

    // Pre-scan for cache hits: quick file-exists + size check (no SHA1 I/O).
    // Dispatch async SHA1 pre-check for files that pass the fast check.
    int fastCacheHits = 0;
    QQueue<AssetTask> downloadQueue;
    while (!m_pendingQueue.isEmpty()) {
        AssetTask task = m_pendingQueue.dequeue();
        if (enqueueCachePreCheck(task)) {
            fastCacheHits++;
            continue;
        }
        // Needs download
        downloadQueue.enqueue(task);
    }
    m_pendingQueue = downloadQueue;

    if (fastCacheHits > 0) {
        emit logMessage(QStringLiteral("[山海经] 预检查: %1 个文件进入异步 SHA1 校验").arg(fastCacheHits));
    }

    // ── Range 支持探测（2026-11-17）──
    // 每个 host 一次 1 字节请求。探测结果决定后面能不能对它分片：
    // 未探测/不支持 → 永远走单连接，绝不冒"多下一遍整个文件"的风险。
    probeRangeSupport(tasks);

    // ── Phase 1: Burst — fire kBurstSize immediately ──
    // (Only for files that definitely need downloading, pre-checks run in parallel)
    m_phase = PhaseBurst;
    int burst = qMin(kBurstSize, m_pendingQueue.size());
    burst = qMin(burst, m_maxConcurrent);
    if (burst > 0) {
        emit logMessage(QStringLiteral("[山海经] 突发请求: 发送 %1 个请求 (待下载=%2, 预检查=%3)")
                            .arg(burst).arg(m_pendingQueue.size()).arg(m_pendingPreCheck.size()));
        for (int i = 0; i < burst && !m_pendingQueue.isEmpty(); ++i) {
            fireNext();
            m_burstSent++;
        }
    }

    // Initialize speed baseline AFTER counting pre-check cache hits
    resetSpeedBaseline();

    if (m_inFlight.size() < m_maxConcurrent && (!m_pendingQueue.isEmpty() || !m_pendingPreCheck.isEmpty()))
        m_accelTimer->start();

    logState("startDownload complete");
}

bool AssetDownloader::enqueueCachePreCheck(const AssetTask& task)
{
    // 快速检查（无 SHA1 I/O）：savePath 或 fallback 存在且大小匹配 → 异步 SHA1 预检。
    // 2026-08-05 抽出供 startDownload/appendTasks 共用：旧实现 appendTasks 无预检，
    // 阶段 B assets 每次都全量重下（578MB）；fallback 路径旧写死 assets/objects，
    // 对 libs 任务查错路径、merged tempDir 场景也无法命中真实 gameDir。
    if (task.sha1.isEmpty()) return false;
    // Check 1: working dir（纯 MC=gameDir；merged=tempDir）
    QFileInfo fi(task.savePath);
    if (fi.exists() && fi.size() > 0) {
        if (task.size <= 0 || fi.size() == task.size) {
            enqueuePreCheck(task, task.savePath);
            return true;
        }
    }
    // Check 2: fallback cache dir（真实 gameDir）——按相对路径推导
    if (!m_fallbackCacheDir.isEmpty()) {
        QString fallbackPath;
        if (!m_minecraftDir.isEmpty() && task.savePath.startsWith(m_minecraftDir))
            fallbackPath = m_fallbackCacheDir + task.savePath.mid(m_minecraftDir.length());
        else
            fallbackPath = m_fallbackCacheDir + QStringLiteral("/assets/objects/")
                + task.sha1.left(2) + QStringLiteral("/") + task.sha1;
        QFileInfo ffi(fallbackPath);
        if (ffi.exists() && ffi.size() > 0) {
            if (task.size <= 0 || ffi.size() == task.size) {
                enqueuePreCheck(task, fallbackPath);
                return true;
            }
        }
    }
    return false;
}

void AssetDownloader::appendTasks(const QVector<AssetTask>& tasks)
{
    if (tasks.isEmpty()) return;
    if (m_state != Running) {
        // 未在运行（阶段 A 没启动）：直接走 startDownload
        startDownload(tasks, m_maxConcurrent);
        return;
    }
    // 运行中追加：入队 + 更新内部总量统计；DNS/precheck 新 host 由 fireNext 惰性处理
    // m_pendingQueue 仅主线程访问（fireNext/dispatch 由 timer 触发）→ 无需加锁
    // m_totalFiles/m_totalBytes 是山海经内部计数（progressChanged 数据源），
    // 追加必须同步增加；VersionDownloader 侧的 m_totalFiles 由调用方（阶段 A/B）负责。
    // 大小降序（与 startDownload 一致）：大文件先下，避免收尾阶段单连接慢
    QVector<AssetTask> sorted = tasks;
    std::sort(sorted.begin(), sorted.end(),
              [](const AssetTask& a, const AssetTask& b) {
                  return a.size > b.size;
              });
    // ── 缓存预检查（2026-08-05 修复）──
    // 旧实现：appendTasks 直接全部入队下载、无预检查 → 阶段 B assets 每次都全量
    // 重下（实测 3643 文件 578MB 只命中 7 个，缓存形同虚设）。现在与 startDownload
    // 共用 enqueueCachePreCheck：命中者走异步 SHA1 校验（onPreCheckResult 处理）。
    // 追加批次同样要探 Range：assets（阶段 B）走的就是这条路径，
    // 只在 startDownload 里探会导致大文件所在的 host 永远是"未探测"→ 永不分片。
    probeRangeSupport(sorted);

    int preCheckAdded = 0;
    for (auto t : sorted) {
        if (t.originalMirrors.isEmpty()) t.originalMirrors = t.mirrors;
        if (enqueueCachePreCheck(t)) {
            preCheckAdded++;
        } else {
            m_pendingQueue.enqueue(t);
        }
        m_totalTaskCount++;
        m_totalFiles.fetchAndAddRelaxed(1);
        m_totalBytes.fetchAndAddRelaxed(t.size);
    }
    qCInfo(logAsset) << QStringLiteral("[山海经] 追加 %1 个任务（运行中），%2 个进入缓存预检查")
        .arg(tasks.size()).arg(preCheckAdded);
    if (preCheckAdded > 0)
        emit logMessage(QStringLiteral("[山海经] 追加 %1 个任务，%2 个进入缓存预检查")
                            .arg(tasks.size()).arg(preCheckAdded));
    if (m_inFlight.size() < m_maxConcurrent)
        fireNext();
}

// ═════════════════════════════════════════════════════════════════════════════
// Cancel
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::cancel()
{
    if (m_state != Running) return;
    m_state = Cancelled;
    m_accelTimer->stop();
    m_watchdogTimer->stop();
    if (m_throttleTimer) m_throttleTimer->stop();
    if (m_emitTimer) m_emitTimer->stop();
    m_emaBps.storeRelaxed(0);   // 取消即报 0，避免上层读到停表前的陈旧速度

    QList<QNetworkReply*> toAbort;
    for (auto it = m_inFlight.cbegin(); it != m_inFlight.cend(); ++it)
        toAbort.append(it.key());
    m_inFlight.clear();
    m_pendingQueue.clear();
    m_pendingPreCheck.clear();
    m_shards.clear();          // 分片状态一并丢弃（在途段随 replies abort 失效）

    for (auto* reply : toAbort) {
        reply->abort();
        reply->deleteLater();
    }

    m_ioPool.clear();

    emit logMessage(QStringLiteral("[山海经] 下载已取消"));
    logState("cancelled");
    emit allFinished(false, m_failedCount, m_failedFiles);
}

// ═════════════════════════════════════════════════════════════════════════════
// Fire next pending request
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::fireNext()
{
    if (m_state != Running || m_pendingQueue.isEmpty()) return;

    // Scan the queue to find a file whose host can accept.
    // Previously we only checked the first file — if it was blocked
    // by per-host limits, it would be prepended and block ALL files
    // behind it, causing the pipeline to stall at ~90% completion.
    // Now we move blocked files to the back of the queue and try
    // the next file, ensuring dispatch doesn't stall.
    AssetTask dispatchTask;
    int selectedMirror = -1;
    int totalTried = 0;
    while (totalTried < m_pendingQueue.size()) {
        dispatchTask = m_pendingQueue.dequeue();
        totalTried++;

        if (dispatchTask.mirrors.isEmpty()) {
            QTimer::singleShot(0, this, [this, dispatchTask]() {
                finishDownload(dispatchTask, false);
            });
            continue;
        }

        // Pick source: skip degraded hosts, respect per-host limits
        // ── 主流启动器 GetSource 语义（2026-08-04）：从源 0 开始顺序找第一个可用源。
        // 源列表 = [首选组(官方或镜像按设置)..., 备选组...]——首选组用完/被
        // 禁用才轮到备选组；不做多源混合分流（哈希 65/35 已废除）。
        selectedMirror = -1;
        for (int i = 0; i < dispatchTask.mirrors.size(); ++i) {
            QString host = extractHost(dispatchTask.mirrors[i]);
            if (hostCanAccept(host)) {
                selectedMirror = i;
                break;
            }
        }
        if (selectedMirror < 0) {
            // All mirrors at capacity — move to back and try next file
            m_pendingQueue.enqueue(dispatchTask);
            continue;
        }
        break;  // found a dispatchable file
    }

    if (selectedMirror < 0) {
        // ── 全源不可用（2026-08-05）──
        // 所有镜像 degraded/限流：冷却 kAllBlockedRetryMs 后重试，避免每 50ms
        // 扫全队列（锁竞争 + 静默空转，用户感知为卡死）。
        // 持续不可用超时由 accelTick 兜底失败收尾（kAllBlockedFailMs）。
        const qint64 nowB = QDateTime::currentMSecsSinceEpoch();
        if (m_allBlockedSinceMs == 0)
            m_allBlockedSinceMs = nowB;   // 记录全拒持续时长起点
        m_blockedUntilMs = nowB + kAllBlockedRetryMs;
        // 节流日志：每 10s 一条，让用户看到引擎仍活着而非死锁
        if (nowB - m_lastBlockedLogMs >= 10000) {
            m_lastBlockedLogMs = nowB;
            qCWarning(logAsset) << QStringLiteral("  [山海经] 所有镜像源暂不可用（degraded/限流），待下载=%1，%2s 后自动重试（已持续 %3s）")
                .arg(m_pendingQueue.size())
                .arg(kAllBlockedRetryMs / 1000)
                .arg((nowB - m_allBlockedSinceMs) / 1000);
        }
        if (!m_accelTimer->isActive())
            m_accelTimer->start();
        return;
    }

    // 成功派发 → 清零全拒持续计时（2026-08-05）
    m_allBlockedSinceMs = 0;

    // ── 空闲槽驱动分片：够大 + 有空槽 + host 认 Range → 直接切段并发 ──
    // 放在这里而不是"收尾阶段"才做，是因为空槽出现在任何时刻：
    // 大文件先派发（大小降序），只要它还没下完而队列已经空/变短，
    // 空槽就该立刻喂给它，而不是干等它单连接爬完。
    if (tryStartShard(dispatchTask, selectedMirror))
        return;

    // ── Dispatch the found file ──
    // 目录创建走缓存：同一个 objects/xx/ 目录会被上千个文件共享，
    // 每个文件都调一次 QDir().mkpath() 是纯浪费（见 m_createdDirs 注释）。
    {
        const QString dir = QFileInfo(dispatchTask.savePath).absolutePath();
        if (!m_createdDirs.contains(dir)) {
            QDir().mkpath(dir);
            m_createdDirs.insert(dir);
        }
    }
    const QString& url = dispatchTask.mirrors[selectedMirror];
    // ── Source selection log (throttled: every 5s or on fallback) ──
    {
        static int logCounter = 0;
        if (++logCounter % 100 == 1 || selectedMirror > 0) {
            QString host = extractHost(url);
            QString srcLabel = selectedMirror == 0
                ? QStringLiteral("primary")
                : QStringLiteral("fallback[%1]").arg(selectedMirror);
            qCInfo(logAsset) << QStringLiteral("  [山海经] 源=%1 主机=%2 SHA1=%3...").arg(srcLabel, host, dispatchTask.sha1.left(12));
        }
    }
    QUrl qurl(url);
    QNetworkRequest req(qurl);
    req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    // Disable HTTP/2 — BMCLAPI and Mojang CDN send RST_STREAM under
    // concurrent HTTP/2 streams. HTTP/1.1 with multiple connections is
    // more reliable for asset downloads.
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    // Per-request HTTP/1.1 config: 255 connections per host per QNAM
    {
        QHttp1Configuration h1cfg;
        h1cfg.setNumberOfConnectionsPerHost(128);
        req.setHttp1Configuration(h1cfg);
    }
    // Per-source adaptive timeout（主流启动器语义）:
    //   min(max(avg_first_byte, 15s) × (1+fails), 30s)
    // 15s 下限避免快网络误杀慢连接；avg_first_byte 增长上限 30s。
    {
        QString host = extractHost(url);
        QMutexLocker lock(&m_hostMutex);
        auto it = m_hostStats.find(host);
        int fails = (it != m_hostStats.end()) ? it->consecutiveFails : 0;
        // 2026-11-18：基线 15s→6s、上限 30s→12s。
        // 实测官方源首字节 p90 仅 160ms；这里给 6s 起步已经非常宽松，
        // 而坏节点（镜像池里的跨境小节点）必须在秒级被放弃 —— 一个 20s 超时
        // 就吃掉整轮 1/4 时间（27MB jar 卡了 19s 才重试）。
        qint64 base = (it != m_hostStats.end())
            ? qBound(6000LL, it->avgFirstByteMs * 3, 12000LL)
            : 6000;
        qint64 timeoutMs = qMin(base * (1 + qMin(fails, 3)), 12000LL);
        req.setTransferTimeout(static_cast<int>(timeoutMs));
        it->activeRequests++;
    }

    // Round-robin across 2 QNAMs
    int namIdx = m_namRoundRobin;
    m_namRoundRobin = (m_namRoundRobin + 1) % kNamCount;

    QNetworkReply* reply = m_nam[namIdx]->get(req);
    ++m_dispatchCount;

    InFlight ift;
    ift.task = dispatchTask;
    ift.mirrorIndex = selectedMirror;
    ift.namIndex = namIdx;
    ift.startMs = QDateTime::currentMSecsSinceEpoch();
    m_inFlight.insert(reply, ift);

    // 增量跟踪下载字节，避免在 onReplyFinished 中整批累加导致测速尖峰
    connect(reply, &QNetworkReply::downloadProgress, this,
            [this, reply](qint64 received, qint64) {
        auto it = m_inFlight.find(reply);
        if (it == m_inFlight.end()) return;
        qint64 delta = received - it->progressBytes;
        if (delta > 0) {
            m_downloadedBytes.fetchAndAddRelaxed(delta);
            it->progressBytes = received;
            const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
            it->lastProgressMs = nowMs;
            if (it->firstByteMs < 0)
                it->firstByteMs = qMax<qint64>(0, nowMs - it->startMs);
        }
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onReplyFinished(reply);
    });
}

// ═════════════════════════════════════════════════════════════════════════════
// Reply handler
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::onReplyFinished(QNetworkReply* reply)
{
    // Defer deletion so we can read reply data first
    reply->deleteLater();

    auto it = m_inFlight.find(reply);
    if (it == m_inFlight.end()) return;

    InFlight ift = it.value();
    m_inFlight.erase(it);

    // Decrement active-request count for the host
    {
        QString host = extractHost(ift.task.mirrors.value(ift.mirrorIndex));
        QMutexLocker lock(&m_hostMutex);
        auto hit = m_hostStats.find(host);
        if (hit != m_hostStats.end())
            hit->activeRequests--;
    }

    if (m_state == Cancelled) {
        checkAllFinished();
        return;
    }

    const AssetTask& task = ift.task;
    qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - ift.startMs;

    // ── 就地切分收尾（2026-11-17）──
    // 这条请求是被 trySplitInFlight() abort 掉的：已收字节存在 keepPrefix 里，
    // 剩余部分改由多个 Range 段并发拉。已收部分不重下 → 零浪费。
    if (ift.converting) {
        if (m_state == Running && ift.keepPrefix.size() > 0) {
            startShardFromPrefix(ift.task, ift.mirrorIndex, ift.keepPrefix);
        } else {
            // 前缀为空或已取消：老路重下（这种情况下没有可复用的进度）
            m_pendingQueue.prepend(ift.task);
            if (m_state == Running && !m_accelTimer->isActive())
                m_accelTimer->start();
        }
        checkAllFinished();
        return;
    }

    // ── 分片段收尾（2026-11-17）──
    if (!ift.shardKey.isEmpty()) {
        handleShardReply(reply, ift);
        checkAllFinished();
        return;
    }

    if (reply->error() != QNetworkReply::NoError) {
        QString host = extractHost(ift.task.mirrors.value(ift.mirrorIndex));
        // 挂起看门狗 abort 是本地超时，不代表源故障——不计 host 失败（防误伤官方源）
        if (!ift.watchdogAborted)
            recordHostResult(host, false, elapsed);

        int nextIdx = ift.mirrorIndex + 1;
        if (nextIdx < task.mirrors.size()) {
            // Retry with next mirror
            AssetTask retryTask = task;
            retryTask.mirrors = task.mirrors.mid(nextIdx);
            m_pendingQueue.prepend(retryTask);
            fireNext();
        } else {
            qCWarning(logAsset) << QStringLiteral("  [山海经] 下载失败 %1 所有镜像已耗尽 (%2)").arg(task.sha1, reply->errorString());
            retryOrFail(task, reply->errorString());
        }
        return;
    }

    // ── 主线程开销计时（2026-11-17）──
    // 从 readAll 起算到 enqueueIO 投递完成：其中包括一次全量拷贝 + 一次完整 SHA1。
    // 这段是主线程的串行成本，直接决定"每秒能完成几个文件"的上限。
    QElapsedTimer mainWork;
    mainWork.start();
    ++m_replyFinishedCount;

    // 单请求总耗时（从发起到收完）：用于判断连接是否被复用。
    // ift.startMs 在 fireNext/dispatchShardSeg 里打过，这里取差值。
    {
        const qint64 durMs = qMax<qint64>(0,
            QDateTime::currentMSecsSinceEpoch() - ift.startMs);
        m_reqTotalMs += durMs;
        ++m_reqCount;
        if (durMs < 500) ++m_reqFast;
    }

    QByteArray data = reply->readAll();

    // DNS IP reliability reward
    {
        QString url = ift.task.mirrors.value(ift.mirrorIndex);
        QString host = extractHost(url);
        // We connected successfully — reward the IP we used
        QMutexLocker lock(&m_dnsMutex);
        auto ipIt = m_dnsCache.find(host);
        if (ipIt != m_dnsCache.end() && !ipIt->addresses.isEmpty()) {
            // The QNAM chose an IP; we approximate by rewarding all resolved IPs
            // equally since Qt doesn't expose which IP was actually connected.
            for (const QString& ip : ipIt->addresses)
                ipIt->reliability[ip] = qBound(-1.0,
                    ipIt->reliability.value(ip, 0.0) * 0.5 + 0.3, 0.5);
        }
    }

    // SHA1 verification — must pass before any I/O or counting.
    // This is the definitive SHA1 check. The I/O worker only writes to disk.
    if (!task.sha1.isEmpty()) {
        const QString hash = ShadowLauncher::sha1Hex(data);
        if (hash != task.sha1) {
            int nextIdx = ift.mirrorIndex + 1;
            if (nextIdx < task.mirrors.size()) {
                qCWarning(logAsset) << QStringLiteral("  [山海经] SHA1 校验失败 %1，切换到镜像[%2]").arg(task.sha1).arg(nextIdx);
                QString host = extractHost(ift.task.mirrors.value(ift.mirrorIndex));
                recordHostResult(host, false, elapsed);

                AssetTask retryTask = task;
                retryTask.mirrors = task.mirrors.mid(nextIdx);
                m_pendingQueue.prepend(retryTask);
                fireNext();
            } else {
                qCWarning(logAsset) << QStringLiteral("  [山海经] SHA1 校验失败 %1（所有镜像均不匹配）").arg(task.sha1);
                retryOrFail(task, QStringLiteral("SHA1 不匹配"));
            }
            return;
        }
    }

    // ── 成功也要记主机健康（2026-11-17 修）──
    // 旧实现只在失败 / 校验失败时调 recordHostResult(false)，成功一次都不记 →
    // st.consecutiveFails 只增不减（"连续 3 次成功即恢复"永远等不到），
    // 于是整轮下载里累计 3 次任意失败，该主机就被打成 degraded →
    // hostCanAccept() 直接拒发 → 单源时整个下载冻结到 kDegradeRetryMs 后，
    // 再攒 3 次失败又冻。表现正是"前面快、后面越来越慢、最后卡住不动"。
    // 放在 SHA1 校验通过之后：校验不通过（数据坏）不算主机成功。
    {
        const QString hostOk = extractHost(ift.task.mirrors.value(ift.mirrorIndex));
        const qint64 fb = (ift.firstByteMs >= 0) ? ift.firstByteMs : elapsed;
        recordHostResult(hostOk, true, fb);
        ++m_netOk;
    }

    // 字节已在 downloadProgress 增量累加，这里不再重复累加。
    // onReplyFinished 只负责 I/O（写盘、SHA1 校验）。

    // I/O offload: SHA1 + disk write in thread pool
    enqueueIO(task, data);

    // 主线程串行成本累计（含 SHA1）
    m_mainThreadWorkUs += mainWork.nsecsElapsed() / 1000;
    if (!task.sha1.isEmpty()) m_sha1Bytes += data.size();
}

// ═════════════════════════════════════════════════════════════════════════════
// 空闲槽驱动的分片（2026-11-17）
// ═════════════════════════════════════════════════════════════════════════════
// 与模组下载（精卫）同一思路：判断依据不是"文件大不大"，而是"有没有空槽"。
// 尾程只剩一两个大文件时，十几个槽位空转 —— 此时把大文件切开喂满槽位，
// 聚合速度才上得来。
//
// 零多余流量是硬约束（用户明确要求）。为此：
//   1. 分片前对 host 做 1 字节 Range 探测，只对确认 206 的 host 分片；
//   2. 每段响应必须 206 且 Content-Range 起点与请求一致，否则立刻 abort
//      （此时还没收 body，浪费≈0），该 host 永久降级为单连接；
//   3. 就地切分时已收字节整段保留，只对剩余部分发 Range；
//   4. 合并后校验 SHA1，失败则整文件回退单连接，并把作废字节计入 m_wastedBytes。

void AssetDownloader::probeRangeSupport(const QVector<AssetTask>& tasks)
{
    QMap<QString, QString> sampleUrl;   // host → 一条可用的真实 URL
    for (const auto& t : tasks) {
        if (t.size < kSegMinBytes || t.sha1.isEmpty() || t.mirrors.isEmpty()) continue;
        const QString url = t.mirrors.first();
        const QString host = extractHost(url);
        if (m_rangeProbe.contains(host) || sampleUrl.contains(host)) continue;
        sampleUrl.insert(host, url);
    }
    for (auto it = sampleUrl.begin(); it != sampleUrl.end(); ++it) {
        const QString host = it.key();
        m_rangeProbe.insert(host, -1);   // 探测中：期间该 host 一律单连接

        QNetworkRequest req{QUrl(it.value())};
        req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
        req.setRawHeader("Range", "bytes=0-0");     // 只要 1 字节
        req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
        req.setTransferTimeout(8000);   // 2026-11-18：20s → 8s
        // 2026-11-18（卡顿/吞吐）：探测请求原先**没有**设 Http1Configuration，
        // 于是它是该 host 在此 QNAM 上的第一条请求 → 连接按默认 6 条 channel 建好并缓存，
        // 后面所有真实请求复用这条「6 通道」连接，per-host 128 形同虚设，
        // 而且连接缓存 key 不含配置，永远不会自愈。这里补上同样配置。
        {
            QHttp1Configuration h1cfg;
            h1cfg.setNumberOfConnectionsPerHost(128);
            req.setHttp1Configuration(h1cfg);
        }

        const int namIdx = m_namRoundRobin;
        m_namRoundRobin = (m_namRoundRobin + 1) % kNamCount;
        QNetworkReply* reply = m_nam[namIdx]->get(req);

        // 不等 body：响应头一到就能判定。不支持 Range 时立刻 abort，避免为探测
        // 白下整个文件（这正是"多余流量"最容易漏掉的地方）。
        connect(reply, &QNetworkReply::metaDataChanged, this, [this, reply, host]() {
            const int code = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (code == 0 || (code >= 300 && code < 400)) return;   // 中间态/重定向
            if (code != 206) {
                m_rangeProbe.insert(host, 0);
                reply->abort();
            }
        });
        connect(reply, &QNetworkReply::finished, this, [this, reply, host]() {
            const int code = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray cr = reply->rawHeader("Content-Range");
            const bool ok = (code == 206 && cr.startsWith("bytes 0-0/"));
            if (m_rangeProbe.value(host, -1) != 0)
                m_rangeProbe.insert(host, ok ? 1 : 0);
            qCInfo(logAsset) << QStringLiteral("  [山海经] [分片探测] %1 %2 (HTTP %3)")
                .arg(host,
                     ok ? QStringLiteral("支持 Range") : QStringLiteral("不支持 Range，走单连接"))
                .arg(code);
            reply->deleteLater();
        });
    }
}

bool AssetDownloader::tryStartShard(const AssetTask& task, int mirrorIndex)
{
    if (m_state != Running) return false;
    if (task.size < kSegMinBytes || task.sha1.isEmpty()) return false;
    if (m_shards.contains(shardKeyOf(task))) return false;
    const QString host = extractHost(task.mirrors.value(mirrorIndex));
    const int rk = m_rangeProbe.value(host, -2);
    if (rk != 1) {
        // 从未探测过 → 顺手补一次探测（下个候选文件就能用上）。
        // 探测失败/不支持都只会让它继续走单连接，不会多下字节。
        if (rk == -2) probeRangeSupport({task});
        return false;                                      // 未确认支持 → 老老实实单连接
    }
    if (shardIdleSlots() < 2) return false;                // 没空槽，切了只是抢口粮
    return startShardFromPrefix(task, mirrorIndex, QByteArray());
}

bool AssetDownloader::startShardFromPrefix(const AssetTask& task, int mirrorIndex,
                                          const QByteArray& prefix)
{
    const QString key = shardKeyOf(task);
    if (m_shards.contains(key)) return false;

    const qint64 total = task.size;
    const qint64 have = prefix.size();
    if (total <= 0 || have >= total) return false;

    // 段数 = 空闲槽数（上限 kMaxShardPieces），且每段 ≥ kMinShardPiece。
    // 空闲槽少 → 切得少；这正是"按需切片"，不是固定 4 段/8 段。
    const qint64 remain = total - have;
    int pieces = qMin(kMaxShardPieces, qMax(2, shardIdleSlots()));
    pieces = static_cast<int>(qMin<qint64>(pieces, remain / kMinShardPiece));
    if (pieces < 2) return false;

    ShardState st;
    st.task = task;
    st.total = total;
    st.mirrorBase = mirrorIndex;
    st.lastActiveMs = QDateTime::currentMSecsSinceEpoch();

    if (have > 0) {
        // 已收前缀原样保留为第 0 段（不再占用连接、也不会重下）
        st.segStart.append(0);
        st.segLen.append(have);
        st.segHave.append(have);
        st.segData.append(prefix);
        st.segState.append(2);
    }
    const qint64 len = remain / pieces;
    for (int i = 0; i < pieces; ++i) {
        const qint64 segBegin = have + i * len;
        const qint64 segEnd = (i == pieces - 1) ? total : (have + (i + 1) * len);
        st.segStart.append(segBegin);
        st.segLen.append(segEnd - segBegin);
        st.segHave.append(0);
        st.segData.append(QByteArray());
        st.segState.append(0);
    }

    QDir().mkpath(QFileInfo(task.savePath).absolutePath());
    m_shards.insert(key, st);
    qCInfo(logAsset) << QStringLiteral("  [山海经] [分片] %1 切 %2 段（总 %3，已收前缀 %4，空闲槽 %5）")
        .arg(task.sha1.left(12)).arg(pieces).arg(fmtSize(total))
        .arg(fmtSize(have)).arg(shardIdleSlots());

    for (int i = 0; i < pieces; ++i)
        dispatchShardSeg(key, i);
    return true;
}

void AssetDownloader::dispatchShardSeg(const QString& key, int segIndex)
{
    auto it = m_shards.find(key);
    if (it == m_shards.end()) return;
    ShardState& st = it.value();
    if (segIndex < 0 || segIndex >= st.segState.size()) return;
    if (st.segState[segIndex] != 0) return;
    if (m_state != Running) return;

    const qint64 segBegin = st.segStart[segIndex] + st.segHave[segIndex];
    const qint64 segEnd = st.segStart[segIndex] + st.segLen[segIndex] - 1;
    if (segEnd < segBegin) { st.segState[segIndex] = 2; return; }

    // 选源：沿用主任务的源顺序，跳过不可用的 host
    int mi = -1;
    for (int k = st.mirrorBase; k < st.task.mirrors.size(); ++k) {
        if (hostCanAccept(extractHost(st.task.mirrors[k]))) { mi = k; break; }
    }
    if (mi < 0) return;   // 稍后由 watchdog / accelTick 补派

    const QString url = st.task.mirrors[mi];
    const QString host = extractHost(url);

    QNetworkRequest req{QUrl(url)};
    req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
    req.setRawHeader("Range", QStringLiteral("bytes=%1-%2").arg(segBegin).arg(segEnd).toUtf8());
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    {
        QHttp1Configuration h1cfg;
        h1cfg.setNumberOfConnectionsPerHost(128);
        req.setHttp1Configuration(h1cfg);
    }
    {
        QMutexLocker lock(&m_hostMutex);
        auto hit = m_hostStats.find(host);
        // 2026-11-18：这段是分片区间请求的超时，原先 cap 在 30s。
        // 实测 libraries.minecraft.net 首字节 30s 时，5 个分片一起卡在这里，
        // 资源下完 18.3s 之后还要再等 21s 才收尾。改为 12s 上限、6s 起步。
        const qint64 base = (hit != m_hostStats.end())
            ? qMax(hit->avgFirstByteMs, 6000LL) : 6000;
        const int fails = (hit != m_hostStats.end()) ? hit->consecutiveFails : 0;
        req.setTransferTimeout(static_cast<int>(qMin(base * (1 + qMin(fails, 2)), 12000LL)));
        m_hostStats[host].activeRequests++;
    }

    const int namIdx = m_namRoundRobin;
    m_namRoundRobin = (m_namRoundRobin + 1) % kNamCount;
    QNetworkReply* reply = m_nam[namIdx]->get(req);
    ++m_dispatchCount;

    InFlight ift;
    ift.task = st.task;
    ift.mirrorIndex = mi;
    ift.namIndex = namIdx;
    ift.startMs = QDateTime::currentMSecsSinceEpoch();
    ift.shardKey = key;
    ift.segIndex = segIndex;
    ift.rangeExpectStart = segBegin;
    m_inFlight.insert(reply, ift);

    st.segState[segIndex] = 1;
    st.inflight++;
    st.lastActiveMs = QDateTime::currentMSecsSinceEpoch();

    connect(reply, &QNetworkReply::downloadProgress, this, [this, reply](qint64 received, qint64) {
        auto i2 = m_inFlight.find(reply);
        if (i2 == m_inFlight.end()) return;
        const qint64 delta = received - i2->progressBytes;
        if (delta > 0) {
            m_downloadedBytes.fetchAndAddRelaxed(delta);
            i2->progressBytes = received;
            i2->lastProgressMs = QDateTime::currentMSecsSinceEpoch();
        }
    });
    // 响应头阶段就校验 Range：此时还没开始收 body，判定失败立刻 abort = 零浪费
    connect(reply, &QNetworkReply::metaDataChanged, this, [this, reply]() {
        auto i2 = m_inFlight.find(reply);
        if (i2 == m_inFlight.end()) return;
        InFlight& w = i2.value();
        const int code = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (code == 0 || (code >= 300 && code < 400)) return;   // 中间态：重定向交给 Qt
        if (code == 200) { w.rangeBad = true; reply->abort(); return; }  // 无视 Range
        if (code != 206) return;                                        // 其它错误交 finished
        const QByteArray want = QStringLiteral("bytes %1-").arg(w.rangeExpectStart).toUtf8();
        if (!reply->rawHeader("Content-Range").startsWith(want)) {
            w.rangeBad = true;      // 起点不符 = 拿到的是错位数据，绝不能收
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { onReplyFinished(reply); });
}

void AssetDownloader::handleShardReply(QNetworkReply* reply, const InFlight& ift)
{
    auto it = m_shards.find(ift.shardKey);
    if (it == m_shards.end()) return;     // 已被放弃/取消
    ShardState& st = it.value();
    if (st.inflight > 0) st.inflight--;
    if (ift.segIndex < 0 || ift.segIndex >= st.segState.size()) return;

    const QString host = extractHost(st.task.mirrors.value(ift.mirrorIndex));

    if (ift.rangeBad) {
        // 探测说支持、实际却不按 Range 回：这个 host 以后永远单连接
        m_rangeProbe.insert(host, 0);
        abandonShard(ift.shardKey, QStringLiteral("服务器未按 Range 响应"));
        return;
    }
    if (m_state == Cancelled) return;

    const bool netErr = (reply->error() != QNetworkReply::NoError);
    if (netErr) {
        recordHostResult(host, false, 0);
        st.segState[ift.segIndex] = 0;
        if (++st.segRetry > 8) {
            abandonShard(ift.shardKey, QStringLiteral("分片连续失败"));
            return;
        }
        dispatchShardSeg(ift.shardKey, ift.segIndex);
        return;
    }

    recordHostResult(host, true, 0);
    st.segRetry = 0;

    QByteArray data = reply->readAll();
    const qint64 want = st.segLen[ift.segIndex] - st.segHave[ift.segIndex];
    if (want > 0 && data.size() > want) {
        // 本段范围内的数据已够：多的部分直接丢（不写盘、也不会用），
        // 正常情况下不会发生（Range 精确到字节），发生即说明服务器超发。
        qCWarning(logAsset) << QStringLiteral("  [山海经] [分片] %1 段%2 超发 %3 字节，截断")
            .arg(st.task.sha1.left(12)).arg(ift.segIndex).arg(data.size() - want);
        data.truncate(static_cast<int>(want));
    }
    st.segData[ift.segIndex].append(data);
    st.segHave[ift.segIndex] += data.size();

    if (st.segHave[ift.segIndex] >= st.segLen[ift.segIndex]) {
        st.segState[ift.segIndex] = 2;
    } else {
        // 没收满：只补拉剩下的那截（已收字节保留）——绝不从头重下
        st.segState[ift.segIndex] = 0;
        dispatchShardSeg(ift.shardKey, ift.segIndex);
        return;
    }

    for (int s2 : st.segState) {
        if (s2 != 2) return;      // 还有段没收完
    }
    finalizeShard(ift.shardKey);
}

void AssetDownloader::finalizeShard(const QString& key)
{
    auto it = m_shards.find(key);
    if (it == m_shards.end()) return;
    ShardState st = it.value();
    m_shards.erase(it);

    QByteArray whole;
    whole.reserve(static_cast<int>(st.total));
    for (const auto& seg : st.segData)
        whole.append(seg);

    if (whole.size() != st.total) {
        m_wastedBytes.fetchAndAddRelaxed(whole.size());
        qCWarning(logAsset) << QStringLiteral("  [山海经] [分片] %1 合并尺寸不符 %2/%3，回退单连接重下")
            .arg(st.task.sha1.left(12)).arg(whole.size()).arg(st.total);
        AssetTask t = st.task;
        m_pendingQueue.prepend(t);
        if (!m_accelTimer->isActive()) m_accelTimer->start();
        return;
    }
    if (!st.task.sha1.isEmpty() && ShadowLauncher::sha1Hex(whole) != st.task.sha1) {
        m_wastedBytes.fetchAndAddRelaxed(whole.size());
        qCWarning(logAsset) << QStringLiteral("  [山海经] [分片] %1 SHA1 校验失败（浪费 %2），回退单连接重下")
            .arg(st.task.sha1.left(12)).arg(fmtSize(whole.size()));
        AssetTask t = st.task;
        m_pendingQueue.prepend(t);
        if (!m_accelTimer->isActive()) m_accelTimer->start();
        return;
    }

    qCInfo(logAsset) << QStringLiteral("  [山海经] [分片] %1 合并完成 %2 段 %3（SHA1 通过）")
        .arg(st.task.sha1.left(12)).arg(st.segData.size()).arg(fmtSize(whole.size()));
    // 2026-11-18 记账修正：分片路径的完成不经过 onReplyFinished，
    // 所以从来没累加过 m_netOk，审计就永远「差 1 个任务」。
    // 分片只是传输手段不同，本质仍是一次网络成功，这里补记。
    ++m_netOk;
    enqueueIO(st.task, whole);
}

void AssetDownloader::abandonShard(const QString& key, const QString& why)
{
    auto it = m_shards.find(key);
    if (it == m_shards.end()) return;
    AssetTask task = it->task;
    qint64 got = 0;
    for (const auto& d : it->segData) got += d.size();
    m_shards.erase(it);

    m_wastedBytes.fetchAndAddRelaxed(got);
    qCWarning(logAsset) << QStringLiteral("  [山海经] [分片] %1 放弃（%2），已收 %3 作废，整文件回退单连接")
        .arg(task.sha1.left(12), why).arg(fmtSize(got));

    if (!task.originalMirrors.isEmpty()) task.mirrors = task.originalMirrors;
    m_pendingQueue.prepend(task);
    if (m_state == Running && !m_accelTimer->isActive())
        m_accelTimer->start();
}

int AssetDownloader::dispatchPendingShardSegs()
{
    if (m_state != Running || m_shards.isEmpty()) return 0;
    QList<QPair<QString, int>> pending;
    for (auto it = m_shards.begin(); it != m_shards.end(); ++it) {
        for (int i = 0; i < it->segState.size(); ++i)
            if (it->segState[i] == 0) pending.append(qMakePair(it.key(), i));
    }
    int fired = 0;
    for (const auto& pr : pending) {
        if (shardIdleSlots() <= 0) break;
        dispatchShardSeg(pr.first, pr.second);
        ++fired;
    }
    return fired;
}

void AssetDownloader::trySplitInFlight()
{
    if (m_state != Running) return;
    if (shardIdleSlots() < 2) return;      // 没空槽：不切（切了只是抢后面文件的口粮）

    QList<QNetworkReply*> cand;
    for (auto it = m_inFlight.begin(); it != m_inFlight.end(); ++it) {
        const InFlight& w = it.value();
        if (!w.shardKey.isEmpty() || w.converting) continue;   // 已经是分片段/正在转
        if (w.task.size < kSegMinBytes || w.task.sha1.isEmpty()) continue;
        if (w.progressBytes <= 0) continue;                    // 一个字节都还没到：交给预派发切片更省事
        if (w.task.size - w.progressBytes < 2 * kMinShardPiece) continue;  // 剩下的不够切
        const QString host = extractHost(w.task.mirrors.value(w.mirrorIndex));
        if (m_rangeProbe.value(host, -1) != 1) continue;
        cand.append(it.key());
    }
    for (auto* reply : cand) {
        if (shardIdleSlots() < 2) break;
        auto it = m_inFlight.find(reply);
        if (it == m_inFlight.end() || it->converting) continue;
        // abort() 会清空未读缓冲：必须在 abort 之前把已收字节取走，
        // 否则这部分数据白下载 —— 正是用户要求杜绝的"多余数据"。
        it->keepPrefix = reply->readAll();
        it->converting = true;
        qCInfo(logAsset) << QStringLiteral("  [山海经] [分片] %1 就地切分（已收 %2，空闲槽 %3）")
            .arg(it->task.sha1.left(12)).arg(fmtSize(it->keepPrefix.size())).arg(shardIdleSlots());
        reply->abort();
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Speed-adaptive scheduler (replaces the old rampTick)
// ═════════════════════════════════════════════════════════════════════════════

// ═════════════════════════════════════════════════════════════════════════════
// In-flight hang watchdog（2026-08-10）
// ═════════════════════════════════════════════════════════════════════════════
// 背景：transferTimeout 是"无活动"超时——服务器限流挂起/持续小包时永不触发，
// 请求永远 pending → checkAllFinished 永不满足 → 安装进度永久卡 99%（实测
// 26.2-forge 下载 assets 阶段 17:06:51 后静默无任何完成/超时/失败日志）。
// 独立于 accelTick：队列派发完时 accelTick 会 stop，挂起恰恰发生在那之后。
// 策略：in-flight 请求连续 kInFlightStallMs（30s）无字节进展 → abort →
// onReplyFinished 走 error 分支换下一个镜像；镜像耗尽 → 失败收尾（不卡死）。
// abort 不计 host 失败（本地超时不代表源故障，防误伤官方源；镜像有限，
// 每个镜像最多再挂 30s 即失败收尾，不会无限循环）。
void AssetDownloader::watchdogTick()
{
    if (m_state != Running) {
        m_watchdogTimer->stop();
        return;
    }
    const qint64 nowW = QDateTime::currentMSecsSinceEpoch();
    QList<QNetworkReply*> toAbort;
    for (auto wit = m_inFlight.begin(); wit != m_inFlight.end(); ++wit) {
        InFlight& w = wit.value();
        if (w.lastProgressMs <= 0) w.lastProgressMs = w.startMs;
        if (w.watchdogAborted) continue;   // 已 abort，等 finished 到达
        if (nowW - w.lastProgressMs >= kInFlightStallMs) {
            w.watchdogAborted = true;
            toAbort.append(wit.key());
            qCWarning(logAsset) << QStringLiteral("  [山海经] 挂起看门狗: %1 无进展 %2s，中止换源（镜像[%3]）")
                .arg(w.task.sha1).arg((nowW - w.lastProgressMs) / 1000).arg(w.mirrorIndex + 1);
            continue;
        }

        // ── 慢速拖流看门狗（2026-08-14）──
        // 背景：资源 CDN 限速/拥塞时单文件持续零星字节流（几 KB/s），
        // 上面的"30s 无进展"判定被不断刷新的 lastProgressMs 绕过 → 单个慢
        // 文件拖死整个下载（实测 assets 卡 97% 4 分钟，日志无更新）。
        // 策略：按窗口平均速率判龟速——窗口内增量 < 64KB/s 计一次低速，
        // 连续 5 个窗口（20s）低速 → abort 换镜像（有字节流但太慢照样换）。
        if (w.rateWindowStartMs == 0) {
            w.rateWindowStartMs = nowW;
            w.rateWindowBytes = w.progressBytes;
        } else if (nowW - w.rateWindowStartMs >= kRateWindowMs) {
            qint64 windowBytes = w.progressBytes - w.rateWindowBytes;
            qint64 windowMs = nowW - w.rateWindowStartMs;
            qint64 avgBps = (windowMs > 0) ? (windowBytes * 1000 / windowMs) : 0;
            w.rateWindowStartMs = nowW;
            w.rateWindowBytes = w.progressBytes;
            if (avgBps < kMinRateBps) {
                w.slowStreak++;
                if (w.slowStreak >= kMaxSlowStreak) {
                    w.watchdogAborted = true;
                    toAbort.append(wit.key());
                    qCWarning(logAsset) << QStringLiteral("  [山海经] 慢速拖流看门狗: %1 窗口均速 %2 KB/s 持续低速，中止换源（镜像[%3]）")
                        .arg(w.task.sha1).arg(avgBps / 1024.0, 0, 'f', 0).arg(w.mirrorIndex + 1);
                }
            } else {
                w.slowStreak = 0;
            }
        }
    }
    for (auto* reply : toAbort) {
        reply->abort();
    }

    // ── 空闲槽驱动分片（2026-11-17）──
    // 放在看门狗里而不是只放 accelTick：队列派空后 accelTick 会 stop，
    // 而"尾程只剩一两个大文件、十几个槽空转"恰恰发生在队列派空之后。
    trySplitInFlight();
    dispatchPendingShardSegs();

    // 分片僵死兜底（2026-11-17）：段全部待发却派不出去（host 全降级/限流）时，
    // 不能因为 m_shards 非空就一直挡住 checkAllFinished —— 20s 无任何推进就放弃分片，
    // 整文件回退单连接（宁可慢，不能挂）。
    if (!m_shards.isEmpty()) {
        const qint64 nowS = QDateTime::currentMSecsSinceEpoch();
        QStringList stale;
        for (auto sit = m_shards.begin(); sit != m_shards.end(); ++sit) {
            if (sit->inflight > 0) continue;
            if (sit->lastActiveMs > 0 && nowS - sit->lastActiveMs < 8000) continue;
            stale.append(sit.key());
        }
        for (const QString& k : stale)
            abandonShard(k, QStringLiteral("分片长时间无法推进"));
    }

    // ── 完成兜底（2026-08-14 修复：assets 卡 92% 数分钟）──
    // 背景：最后文件网络下载完成后走 enqueueIO 异步写盘（IO 线程池），
    // 写盘回调经 QueuedConnection 回主线程调 finishDownload → checkAllFinished。
    // 若主线程事件循环被其他同步操作（如驿道下载的 QEventLoop 等待）长时间
    // 占用，或 IO 写盘在途，checkAllFinished 的条件（inFlight/pending/preCheck
    // 全空 + preCheckQueued==0）暂时不满足；此后若没有新事件再触发
    // checkAllFinished，下载永远停在 92%（实测 3948/3948 文件完成但 allFinished
    // 迟到 200s，期间进度条静止、速度不跳——用户观感"卡死"）。
    // 修复：watchdog 每秒兜底调用一次 checkAllFinished（条件不满足时是空操作，
    // 写盘完成后下一次 tick 自然放行）。
    checkAllFinished();
}

void AssetDownloader::accelTick()
{
    if (m_state != Running) {
        m_accelTimer->stop();
        return;
    }

    // Wait for DNS to finish before accelerating
    if (!m_dnsAllResolved) {
        return;
    }

    // ── degraded 过期自动恢复（2026-08-05）──
    // 旧逻辑：degraded 后需 3 次成功才恢复，但 degraded 后不再派发新请求 →
    // 所有源全 degraded 时永久卡死（实测：镜像批量失败后 3 分钟静默无日志）。
    // 现在：降级超 kDegradeRetryMs 自动解除，镜像恢复后自动续传。
    {
        QMutexLocker lock(&m_hostMutex);
        const qint64 nowR = QDateTime::currentMSecsSinceEpoch();
        for (auto hit = m_hostStats.begin(); hit != m_hostStats.end(); ++hit) {
            if (hit->degraded && hit->degradedAtMs > 0
                && nowR - hit->degradedAtMs >= kDegradeRetryMs) {
                qCInfo(logAsset) << QStringLiteral("  [山海经] 主机恢复探测 %1 (降级已超 %2s，重新尝试)")
                    .arg(hit.key()).arg(kDegradeRetryMs / 1000);
                hit->degraded = false;
                hit->consecutiveFails = 0;
            }
        }
    }

    // ── 全源不可用冷却（2026-08-05）──
    // fireNext 全拒后设置冷却：冷却期内不扫描派发（避免 50ms 空转扫全队列），
    // 冷却结束自动重试（degraded 超 30s 的 host 会由 hostCanAccept 自动恢复）。
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (nowMs < m_blockedUntilMs) {
        // 全拒持续超时 → 剩余任务失败收尾（终局兜底，防无限卡死）
        if (m_allBlockedSinceMs > 0
            && nowMs - m_allBlockedSinceMs >= kAllBlockedFailMs) {
            qCWarning(logAsset) << QStringLiteral("  [山海经] 所有镜像源持续不可用 %1s，剩余 %2 个任务判定失败收尾")
                .arg((nowMs - m_allBlockedSinceMs) / 1000).arg(m_pendingQueue.size());
            while (!m_pendingQueue.isEmpty()) {
                AssetTask t = m_pendingQueue.dequeue();
                finishDownload(t, false);
            }
            m_allBlockedSinceMs = 0;
            m_blockedUntilMs = 0;
        }
        return;
    }
    m_allBlockedSinceMs = 0;   // 成功派发（fireNext 找到可用源）后由 fireNext 清零；这里保留累计
    // 2026-08-10 修：原实现冷却结束即清零 → 持续全拒时每 5s 重新计时 →
    // kAllBlockedFailMs（120s）失败收尾永不触发 → 永久卡死（配合换镜像被拒场景实锤）

    // Sample speed every tick
    sampleSpeed();
    updateSpeedFloor();

    // Log speed once per second regardless of dispatch state
    logSpeed();

    // Speed limit gate: if user set a limit and we're at/above it, don't add more
    if (m_speedLimitMB > 0.0 && m_emaMbps >= m_speedLimitMB) {
        return;
    }

    schedulePhase();

    int inflight = currentInflight();
    int target = m_targetInflight;

    // Keep timer running even when full — logSpeed() + adjustHostLimits()
    // need to fire periodically to increase per-host limits.
    // Only stop when there's genuinely no work left.
    // 分片任务还没收尾时不能停表：否则队列派空后没人补派剩余段（2026-11-17）
    if (m_pendingQueue.isEmpty() && m_pendingPreCheck.isEmpty() && m_shards.isEmpty()) {
        m_accelTimer->stop();
        return;
    }
    if (inflight >= target) {
        dispatchPendingShardSegs();   // 目标并发未满时先把分片的剩余段喂满
        return;  // at capacity, but keep timer for limit adjustment
    }

    // Fire more requests up to target
    // 2026-11-18：不再按 kAccelStep 限速派发 —— 有槽就填满（fireNext 内部仍有主机级限流兜底）
    int toSend = qMin(target - inflight, kDispatchPerTick);
    for (int i = 0; i < toSend && !m_pendingQueue.isEmpty(); ++i)
        fireNext();
    dispatchPendingShardSegs();

    // accelTick: debug-level (every 50ms would flood log file)
    // Enable with: setFilterRules(\"ShadowDownloader.Asset.debug=true\")
    // and remove the 'if (type == QtDebugMsg) return;' in shadowMessageHandler
    qCDebug(logAsset) << QStringLiteral("  [山海经] 加速: phase=%1 inflight=%2 target=%3 floor=%4/s pending=%5 preCheck=%6")
        .arg(m_phase).arg(inflight).arg(target)
        .arg(fmtSize(m_speedFloorBps.loadRelaxed()))
        .arg(m_pendingQueue.size())
        .arg(m_pendingPreCheck.size());
}

void AssetDownloader::schedulePhase()
{
    qint64 floor = m_speedFloorBps.loadRelaxed();
    qint64 speed = 0;
    {
        QMutexLocker lock(&m_speedMutex);
        if (!m_speedRecords.isEmpty())
            speed = m_speedRecords.first();
    }

    int inflight = currentInflight();
    int pending = m_pendingQueue.size();
    int preChecking = m_pendingPreCheck.size();
    bool hasWork = (pending > 0 || preChecking > 0);

    switch (m_phase) {

    case PhaseInit:
        // Should not normally reach here; handled in startDownload
        m_phase = PhaseBurst;
        m_targetInflight = qMin(kBurstSize, m_maxConcurrent);
        break;

    case PhaseBurst:
        // After burst sent, immediately go to accelerate
        m_phase = PhaseAccelerate;
        m_targetInflight = qMin(m_burstSent + kAccelStep, m_maxConcurrent);
        break;

    case PhaseAccelerate:
        if (inflight >= m_maxConcurrent || !hasWork) {
            m_phase = PhaseSteady;
            m_targetInflight = qMin(inflight, m_maxConcurrent);
        } else if (speed >= floor && inflight > 0) {
            // Saturated — stop adding, let speed floor catch up
            m_phase = PhaseSteady;
            m_targetInflight = inflight;
        } else {
            // Speed < floor — add more (but keep some headroom for I/O)
            m_targetInflight = qMin(inflight + kAccelStep, m_maxConcurrent);
        }
        break;

    case PhaseSteady:
        if (!hasWork) {
            m_targetInflight = inflight;
        } else if (inflight > 0 && speed == 0 && inflight >= 4 && pending > 4) {
            // Complete stall — reduce inflight to avoid congestion collapse
            // 仅当大量任务排队且完全无速度时才冷却（小文件间隙速度归零
            // 是正常的，不能误触发冷却 → 并发砍半 → 后期暴跌）
            m_phase = PhaseCooldown;
            m_targetInflight = qMax(4, inflight / 2);
        } else if (speed < floor && inflight < m_maxConcurrent && pending > 0) {
            // Speed dropped below floor — try adding more
            m_phase = PhaseAccelerate;
            m_targetInflight = qMin(inflight + kAccelStep, m_maxConcurrent);
        } else if (pending > 0) {
            // Steady state: keep ramping toward maxConcurrent regardless of
            // speed floor——floor 只增不减，后期速度自然下降（小文件阶段）时
            // speed<floor 恒成立但并发已满；这里保证剩余任务持续派发
            m_targetInflight = qMin(m_maxConcurrent, inflight + 1);
        }
        break;

    case PhaseCooldown:
        if (speed > 0) {
            m_phase = PhaseAccelerate;
            m_targetInflight = qMin(inflight + kAccelStep, m_maxConcurrent);
        } else if (inflight <= 4 || !hasWork) {
            m_phase = PhaseSteady;
            m_targetInflight = qMin(8, m_maxConcurrent);
        }
        break;
    }

    // ── 2026-11-18：队列还长时，目标并发直接拉满，不做「每 tick 加一点」的爬坡 ──
    // 实测（32 QNAM / 192 并发）爬坡期在途长期只有 83~107，4048 个资源跑了 17.6s；
    // 参考引擎同并发跑 5059 个（含库）只用 16.4s，差别就是「有没有一直在满并发」。
    // 爬坡本来是给慢速网络做自适应的，但队列里还有几千个小文件时它只有害处。
    if (pending > 64 && m_phase != PhaseCooldown
        && inflight < m_maxConcurrent) {
        m_targetInflight = m_maxConcurrent;
        m_phase = PhaseAccelerate;
    }
}

int AssetDownloader::currentInflight() const
{
    return m_inFlight.size();
}

// ═════════════════════════════════════════════════════════════════════════════
// Speed monitoring
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::sampleSpeed()
{
    qint64 elapsed = m_speedTimer.elapsed();
    if (elapsed < 50) return;

    // Exclude cache-hit bytes from speed calculation
    qint64 now = m_downloadedBytes.loadRelaxed();
    qint64 cacheNow = m_cacheBytes.loadRelaxed();
    qint64 base = m_lastSampleBytes.loadRelaxed();
    qint64 netBytes = (now - cacheNow) - base;

    if (netBytes < 0) {
        // Safety: if cache count caught up after reset baseline, re-sync
        m_lastSampleBytes.storeRelaxed(now - cacheNow);
        netBytes = 0;
    }

    m_lastSampleBytes.storeRelaxed(now - cacheNow);
    m_speedTimer.restart();

    qint64 bps = netBytes * 1000 / qMax(elapsed, 1LL);

    {
        QMutexLocker lock(&m_speedMutex);
        m_speedRecords.prepend(bps);
        if (m_speedRecords.size() > kMaxSpeedRecords)
            m_speedRecords.removeLast();
    }

    // Update EMA
    double mbps = bps / (1024.0 * 1024.0);
    m_emaMbps = m_emaMbps * 0.5 + mbps * 0.5;
    // 对外单值：与展示值同源（bytes/s），上层直接读，禁止再平滑
    m_emaBps.storeRelaxed(static_cast<qint64>(m_emaMbps * 1024.0 * 1024.0));
}

void AssetDownloader::updateSpeedFloor()
{
    // Weighted average: newer samples count more
    qint64 weightedSum = 0;
    int weightDiv = 0;
    {
        QMutexLocker lock(&m_speedMutex);
        int w = m_speedRecords.size();
        for (auto rec : m_speedRecords) {
            weightedSum += rec * w;
            weightDiv += w;
            w--;
        }
    }
    qint64 avgBps = (weightDiv > 0) ? (weightedSum / weightDiv) : 0;
    if (avgBps < kMinSpeedFloorBps) return;

    // Floor = 85% of weighted average (architecture unchanged)
    qint64 newFloor = static_cast<qint64>(avgBps * 0.85);
    qint64 currentFloor = m_speedFloorBps.loadRelaxed();
    if (newFloor > currentFloor) {
        m_speedFloorBps.storeRelaxed(newFloor);
        // 只在跨过整 MB 时打日志（避免每次微增刷屏）
        if (newFloor / (1024 * 1024) > currentFloor / (1024 * 1024)) {
            qCDebug(logAsset) << QStringLiteral("[山海经] 速度下限 %1 M").arg(newFloor / (1024.0 * 1024.0), 0, 'f', 2);
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Finish tracking for one task
// ═════════════════════════════════════════════════════════════════════════════

// 失败重试（2026-11-14）：不再把失败文件丢给上层的「校验 + 自动修复」兜底。
//   理由：兜底那趟要多花 1.3 分钟重校验重下（实测 21 个资源文件），而且期间
//   下载步骤的分母仍含这些字节 → 百分比永远到不了 100% → 进度条卡在 99%。
//   在下载阶段内重试，分母能真正被填满，进度条也就自然走到 100%。
//   轮次用尽仍失败才判失败（此时才轮到上层兜底，这是安全网而不是常规路径）。
bool AssetDownloader::retryOrFail(const AssetTask& task, const QString& why)
{
    if (task.retryRound + 1 >= kMaxRetryRounds) {
        qCWarning(logAsset) << QStringLiteral("  [山海经] 重试 %1 轮仍失败，交出：%2（%3）")
            .arg(task.retryRound + 1).arg(task.sha1, why);
        finishDownload(task, false);
        return false;
    }

    AssetTask t = task;
    t.retryRound++;
    // 回到**完整**镜像表：任务在换源过程中 mirrors 被逐段裁剪，只剩最后一个源；
    // 直接复用会让第 2 轮只试那个已经失败的源（等于没重试）。
    if (!t.originalMirrors.isEmpty()) t.mirrors = t.originalMirrors;

    // 退避：第 2 轮立即，第 3 轮等一会儿（抖动/限流时立刻重试大概率还失败）
    const int delay = (t.retryRound <= 1) ? 0 : 2000;
    m_retryScheduled++;
    qCWarning(logAsset) << QStringLiteral("  [山海经] 重试第 %1 轮：%2（%3）待下载=%4")
        .arg(t.retryRound).arg(t.sha1.left(12), why).arg(m_pendingQueue.size());

    QTimer::singleShot(delay, this, [this, t]() {
        if (m_retryScheduled > 0) m_retryScheduled--;
        if (m_state != Running) return;
        m_pendingQueue.enqueue(t);
        if (!m_accelTimer->isActive()) m_accelTimer->start();
        fireNext();
        checkAllFinished();
    });
    return true;
}

void AssetDownloader::finishDownload(const AssetTask& task, bool success)
{
    // NOTE: downloadedBytes are counted in onReplyFinished() or the cache-hit
    // path in fireNext(). We do NOT count them here to avoid double-counting.
    if (success) {
        m_completedFiles.fetchAndAddRelaxed(1);
    } else {
        // 失败不计入完成数（契约 §0.3 / §3）：分母 m_totalFiles 不变，
        // 结果仍由 checkAllFinished() 按 m_failedCount>0 判 failed；
        // 进度上限停在“成功数/总数”，不再出现“有失败却 100%”。
        m_failedCount++;
        m_failedFiles.append(task.sha1);
    }

    // Throttled progress emit
    qint64 now = m_lastProgressEmit.elapsed();
    if (now >= kProgressThrottleMs) {
        m_lastProgressEmit.start();
        emit progressChanged(m_completedFiles.loadRelaxed(),
                             m_totalFiles.loadRelaxed(),
                             m_downloadedBytes.loadRelaxed(),
                             m_totalBytes.loadRelaxed());
    }

    emit fileCompleted(task.sha1, success);

    // 只有成功才报"满字节"。旧实现对失败文件也发 size/size，
    // 上层按 received 聚合出来的字节数会被失败文件虚报满额（进度/速度失真的一个来源）。
    if (success && !task.mirrors.isEmpty()) {
        emit fileProgress(task.mirrors.first(), task.sha1,
                          task.size, task.size, task.savePath);
    }

    // Adjust per-host limits on every file completion so the dynamic
    // limit can ramp up even when accelTick is busy dispatching.
    // (Was only called from logSpeed() which stops if accelTimer is off.)
    adjustHostLimits();

    // Don't fireNext directly if at capacity — let accelTick pace requests.
    // This prevents inflight from growing unboundedly when finishDownload
    // fires faster than the server can handle, which caused RST_STREAM on
    // BMCLAPI / Mojang CDN when 5000+ files were all dispatched at once.
    if (m_inFlight.size() < m_maxConcurrent) {
        fireNext();
    } else if (!m_accelTimer->isActive()) {
        m_accelTimer->start();  // re-activate to dispatch when slots free
    }
    checkAllFinished();
}

// ═════════════════════════════════════════════════════════════════════════════
// Check completion
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::checkAllFinished()
{
    if (m_state != Running && m_state != Cancelled) return;
    if (!m_pendingQueue.isEmpty() || !m_inFlight.isEmpty() || !m_pendingPreCheck.isEmpty()) return;
    if (m_preCheckQueued > 0) return;
    if (m_retryScheduled > 0) return;   // 还有重试在退避等待中（2026-11-14）
    if (!m_shards.isEmpty()) return;    // 还有分片任务没收尾（2026-11-17）

    m_accelTimer->stop();
    m_state = (m_state == Cancelled) ? Cancelled : Done;
    m_watchdogTimer->stop();
    if (m_throttleTimer) m_throttleTimer->stop();
    if (m_emitTimer) m_emitTimer->stop();

    emit progressChanged(m_completedFiles.loadRelaxed(),
                         m_totalFiles.loadRelaxed(),
                         m_downloadedBytes.loadRelaxed(),
                         m_totalBytes.loadRelaxed());

    logHostSummary();

    if (m_state == Cancelled) {
        emit logMessage(QStringLiteral("[山海经] 下载已取消"));
        emit allFinished(false, m_failedCount, m_failedFiles);
    } else {
        bool ok = (m_failedCount == 0);
        // 对账：总数 == 缓存命中 + 网络成功 + 失败 + 丢弃，否则说明有任务漏账
        {
            const qint64 accounted = qint64(m_cacheHitCount) + m_netOk + m_failedCount + m_droppedTasks;
            qCInfo(logAsset) << QStringLiteral("  [山海经] [审计] 总数=%1 缓存命中=%2 网络成功=%3 失败=%4 丢弃=%5 完成计数器=%6")
                .arg(m_totalFiles.loadRelaxed())
                .arg(m_cacheHitCount).arg(m_netOk).arg(m_failedCount).arg(m_droppedTasks)
                .arg(m_completedFiles.loadRelaxed());
            if (accounted != m_totalFiles.loadRelaxed()) {
                qCWarning(logAsset) << QStringLiteral("  [山海经] [审计] 账不平！差 %1 个任务（合计 %2 / 总数 %3）")
                    .arg(m_totalFiles.loadRelaxed() - accounted).arg(accounted)
                    .arg(m_totalFiles.loadRelaxed());
            }
        }
        emit logMessage(QStringLiteral("[山海经] 资源文件下载完成 总数=%1 缓存命中=%2 失败=%3 峰值=%4 MB/s")
                            .arg(m_totalTaskCount)
                            .arg(m_cacheHitCount)
                            .arg(m_failedCount)
                            .arg(m_emaMbps, 0, 'f', 1));
        emit allFinished(ok, m_failedCount, m_failedFiles);
        logState("all done");
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Dynamic per-host limit adjustment (TCP slow-start style)
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::adjustHostLimits()
{
    // Slight lock risk — keep it quick
    QMutexLocker lock(&m_hostMutex);
    for (auto it = m_hostStats.begin(); it != m_hostStats.end(); ++it) {
        if (it.key().contains(QStringLiteral("bmclapi")))
            continue;  // BMCLAPI uses fixed limit
        auto& st = it.value();
        if (st.consecutiveFails > 0)
            continue;  // recent failure — don't increase
        if (st.totalSuccess < 1)
            continue;  // need at least 1 success
        // If we consistently fill the current limit, try increasing
        if (st.activeRequests >= st.dynamicLimit * 0.8) {
            int oldLimit = st.dynamicLimit;
            st.dynamicLimit = qMin(st.dynamicLimit + 1, 32);
            // Per-host limit increase: debug-only (too verbose at info level)
            if (st.dynamicLimit != oldLimit)
                qCDebug(logAsset) << QStringLiteral("  [山海经] 限制 %1 ↑ %2 → %3 (良好)").arg(it.key()).arg(oldLimit).arg(st.dynamicLimit);
        }
    }
}

// ── 每主机定量摘要（2026-11-17）──
// 目的：把「哪个源快、快多少」变成日志里的数字，不再依赖外部抓包或猜测。
// avgFirstByteMs 只统计成功请求（recordHostResult 里是 3:1 的滑动均值）。
void AssetDownloader::logHostSummary()
{
    struct Row { QString host; int ok; int fail; qint64 firstByte; int limit; bool degraded; };
    QVector<Row> rows;
    {
        QMutexLocker lock(&m_hostMutex);
        for (auto it = m_hostStats.begin(); it != m_hostStats.end(); ++it) {
            rows.append({ it.key(), it->totalSuccess, it->totalFails,
                          static_cast<qint64>(it->avgFirstByteMs), hostLimitLocked(it.key()), it->degraded });
        }
    }
    if (rows.isEmpty()) return;

    std::sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) {
        return a.firstByte < b.firstByte;   // 快的排前面
    });
    for (const Row& r : rows) {
        qCInfo(logAsset) << QStringLiteral("  [山海经] [主机] %1 成功=%2 失败=%3 首字均=%4ms 并发上限=%5%6")
            .arg(r.host)
            .arg(r.ok).arg(r.fail)
            .arg(r.firstByte)
            .arg(r.limit)
            .arg(r.degraded ? QStringLiteral(" [已降级]") : QString());
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Per-host health
// ═════════════════════════════════════════════════════════════════════════════

QString AssetDownloader::extractHost(const QString& url) const
{
    QUrl qurl(url);
    return qurl.host().toLower();
}

int AssetDownloader::getHostLimit(const QString& host) const
{
    // 固定档位不碰锁，先判掉（hostCanAccept 会在持锁状态下调 hostLimitLocked，
    // 这里如果无条件加锁就会自锁 —— 旧实现正是这样，只是恰好只走固定档位才没炸）。
    if (host.contains(QStringLiteral("bmclapi"))
        || host.contains(QStringLiteral("resources.download.minecraft.net"))
        || host.contains(QStringLiteral("libraries.minecraft.net"))
        || host.contains(QStringLiteral("piston-data.mojang.com"))
        || host.contains(QStringLiteral("launcher.mojang.com"))) {
        return hostLimitLocked(host);
    }
    QMutexLocker lock(&m_hostMutex);
    return hostLimitLocked(host);
}

int AssetDownloader::hostLimitLocked(const QString& host) const
{

    // 2026-11-18：单主机上限不再写死 8/16，而是跟随总并发（上限 64）。
    // 理由：一次安装是几千个小文件，耗时 ≈ 文件数 × 单请求延迟 ÷ 并发，
    // 延迟主导；把总并发抬到 64 却让单主机卡在 16，等于只抬了一半。
    // 仍低于总并发一点（-2），给双引擎（夸父+山海经）叠加留余量。
    const int hostCap = qMax(4, m_maxConcurrent);
    if (host.contains(QStringLiteral("bmclapi")))
        return qMin(hostCap, 32);
    if (host.contains(QStringLiteral("resources.download.minecraft.net"))
        || host.contains(QStringLiteral("libraries.minecraft.net"))
        || host.contains(QStringLiteral("piston-data.mojang.com"))
        || host.contains(QStringLiteral("launcher.mojang.com"))) {
        return hostCap;
    }
    auto it = m_hostStats.find(host);
    if (it == m_hostStats.end()) return 4;  // start conservative for unknown hosts
    return qBound(2, it->dynamicLimit, 32);
}

bool AssetDownloader::hostCanAccept(const QString& host) const
{
    QMutexLocker lock(&m_hostMutex);
    auto it = m_hostStats.find(host);
    if (it == m_hostStats.end()) return true;  // unknown = accept
    // degraded 过期自动恢复由 accelTick 定期执行（2026-08-05，本方法 const 只读）
    if (it->degraded) return false;
    if (it->activeRequests >= hostLimitLocked(host)) return false;   // 已持锁，走无锁版本
    return true;
}

void AssetDownloader::recordHostResult(const QString& host, bool ok, qint64 firstByteMs)
{
    QMutexLocker lock(&m_hostMutex);
    auto& st = m_hostStats[host];
    if (ok) {
        st.consecutiveFails = 0;
        st.totalSuccess++;
        // Update running average (first-byte time)
        st.avgFirstByteMs = (st.avgFirstByteMs * 3 + firstByteMs) / 4;
        // Recover from degraded state after 3 consecutive successes
        if (st.degraded && st.consecutiveFails == 0 && st.totalSuccess >= 3)
            st.degraded = false;
    } else {
        st.consecutiveFails++;
        st.totalFails++;
        // Degrade after 3 consecutive failures
        if (st.consecutiveFails >= 3 && !st.degraded) {
            st.degraded = true;
            st.degradedAtMs = QDateTime::currentMSecsSinceEpoch();
        }
        // Increase timeout estimate (host is slow)
        st.avgFirstByteMs = qMin(st.avgFirstByteMs * 2, 30000LL);
        // Failure → reduce dynamic limit (TCP congestion control style)
        int oldLimit = st.dynamicLimit;
        st.dynamicLimit = qMax(2, st.dynamicLimit / 2);
        // Per-host limit decrease: debug-only
        if (st.dynamicLimit != oldLimit)
            qCDebug(logAsset) << QStringLiteral("  [山海经] 限制 %1 ↓ %2 → %3 (失败)").arg(host).arg(oldLimit).arg(st.dynamicLimit);
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Async DNS resolution — uses QHostInfo::lookupHost() instead of blocking fromName()
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::startAsyncDns()
{
    if (m_dnsToResolve.isEmpty()) {
        m_dnsAllResolved = true;
        return;
    }

    for (auto it = m_dnsToResolve.begin(); it != m_dnsToResolve.end(); ++it) {
        const QString& host = it.key();
        qint64 now = QDateTime::currentMSecsSinceEpoch();

        // Check cache
        {
            QMutexLocker lock(&m_dnsMutex);
            auto cacheIt = m_dnsCache.find(host);
            if (cacheIt != m_dnsCache.end()) {
                if (now - cacheIt->lastResolveMs < kDnsCacheMs) {
                    // Cache hit — count as resolved immediately
                    qCInfo(logAsset) << QStringLiteral("  [山海经] DNS 缓存命中: %1 %2").arg(host, cacheIt->addresses.join(", "));
                    m_dnsPendingCount--;
                    checkAllDnsResolved();
                    continue;
                }
            }
        }

        // Async lookup
        QHostInfo::lookupHost(host, this, [this, host](const QHostInfo& info) {
            if (m_state != Running && m_state != Idle) return;

            QMutexLocker lock(&m_dnsMutex);
            IPInfo& ipi = m_dnsCache[host];
            ipi.lastResolveMs = QDateTime::currentMSecsSinceEpoch();

            if (info.error() != QHostInfo::NoError) {
                qCWarning(logAsset) << QStringLiteral("  [山海经] DNS 解析失败: %1 (%2)").arg(host, info.errorString());
                ipi.addresses.clear();
            } else {
                QStringList ipv4, ipv6;
                for (const auto& addr : info.addresses()) {
                    if (addr.protocol() == QAbstractSocket::IPv4Protocol)
                        ipv4.append(addr.toString());
                    else
                        ipv6.append(addr.toString());
                }
                auto sortByReliability = [&](QStringList& list) {
                    std::sort(list.begin(), list.end(), [&](const QString& a, const QString& b) {
                        return ipi.reliability.value(a, 0.0) > ipi.reliability.value(b, 0.0);
                    });
                };
                sortByReliability(ipv4);
                sortByReliability(ipv6);
                ipi.addresses = ipv4 + ipv6;
                qCInfo(logAsset) << QStringLiteral("  [山海经] DNS %1 → %2").arg(host, ipi.addresses.join(", "));
            }
            lock.unlock();

            m_dnsPendingCount--;
            checkAllDnsResolved();
        });
    }
}

void AssetDownloader::checkAllDnsResolved()
{
    if (!m_dnsAllResolved && m_dnsPendingCount <= 0) {
        m_dnsAllResolved = true;
        qCInfo(logAsset) << QStringLiteral("  [山海经] DNS 所有主机解析完成");
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// I/O offload — SHA1 verification + disk write in thread pool
// ═════════════════════════════════════════════════════════════════════════════

class IOWorker : public QRunnable {
public:
    AssetDownloader::AssetTask task;
    QByteArray data;
    std::function<void(const AssetDownloader::AssetTask&, bool)> callback;

    void run() override {
        // SHA1 already verified in onReplyFinished().
        // This worker only writes verified data to disk.
        bool writeOk = false;
        {
            QFile f(task.savePath);
            if (f.open(QIODevice::WriteOnly)) {
                f.write(data);
                f.close();
                // Write results are logged via finishDownload signal; keep lightweight here.
        // qCDebug is available for per-file debugging.
                writeOk = true;
            } else {
                qCWarning(logAsset) << QStringLiteral("  [山海经] 写入失败 %1: %2").arg(task.sha1, f.errorString());
            }
        }

        if (callback)
            callback(task, writeOk);
    }
};

void AssetDownloader::enqueueIO(const AssetTask& task, const QByteArray& data)
{
    auto* worker = new IOWorker();
    worker->task = task;
    worker->data = data;

    QPointer<AssetDownloader> self(this);
    worker->callback = [self](const AssetDownloader::AssetTask& t, bool ok) {
        if (self) {
            QMetaObject::invokeMethod(self, [self, t, ok]() {
                if (self->m_state == AssetDownloader::Cancelled) return;
                self->finishDownload(t, ok);
            });
        }
    };

    m_ioPool.start(worker);
}

// ═════════════════════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════════════════════
// Async SHA1 pre-check — offloaded to IO thread pool to avoid blocking main thread.
// ═════════════════════════════════════════════════════════════════════════════

class PreCheckWorker : public QRunnable {
public:
    AssetDownloader::AssetTask task;
    QString checkPath;              // path to check SHA1 at; empty = use task.savePath
    bool copyOnHit = false;         // if SHA1 matches and copyOnHit, copy checkPath → task.savePath
    std::function<void(const AssetDownloader::AssetTask&, bool)> callback;

    void run() override {
        qint64 t0 = QDateTime::currentMSecsSinceEpoch();
        const QString targetPath = checkPath.isEmpty() ? task.savePath : checkPath;
        bool sha1Match = false;
        {
            // ── 存在 + 尺寸匹配即视为命中（2026-11-18）──
            // 依据：文件路径本身就是内容哈希（assets/objects/xx/<sha1>），
            // 尺寸也对得上 → 再整文件算一遍 SHA1 只是白读盘。
            // 一次冷装 4000 个文件时这部分开销被放大；HMCL 的资产检查也只做
            // Files.isRegularFile（FileDownloadTask 的 caching 分支）。
            // 注意：**下载完成后的 SHA1 校验不变**（onReplyFinished 里那一层还在），
            // 所以首次下载的数据完整性不受影响，这里省掉的是「已存在文件」的重校验。
            const QFileInfo fi(targetPath);
            if (fi.exists() && fi.isFile() && task.size > 0 && fi.size() == task.size) {
                sha1Match = true;
            } else {
            QFile f(targetPath);
            if (f.open(QIODevice::ReadOnly)) {
                QCryptographicHash hash(QCryptographicHash::Sha1);
                hash.addData(&f);
                f.close();
                if (hash.result().toHex() == task.sha1) {
                    sha1Match = true;
                }
            }
            }
        }
        // If hit came from a fallback cache path, copy to working dir
        if (sha1Match && copyOnHit && targetPath != task.savePath) {
            QDir().mkpath(QFileInfo(task.savePath).absolutePath());
            if (!QFile::copy(targetPath, task.savePath)) {
                // Copy can fail if destination already exists (duplicate SHA1 task
                // from a different asset index entry — same content, same hash).
                if (QFileInfo::exists(task.savePath)) {
                    // Verify existing file has the right content
                    QFile f(task.savePath);
                    if (f.open(QIODevice::ReadOnly)) {
                        QCryptographicHash h(QCryptographicHash::Sha1);
                        h.addData(&f);
                        f.close();
                        if (h.result().toHex() == task.sha1) {
                            sha1Match = true;  // already there, count as hit
                        } else {
                            qCWarning(logAsset) << QStringLiteral("  [山海经] 缓存复制失败（冲突）: %1").arg(task.sha1.left(12));
                            sha1Match = false;
                        }
                    } else {
                        qCWarning(logAsset) << QStringLiteral("  [山海经] 缓存复制失败（无法验证）: %1").arg(task.sha1.left(12));
                        sha1Match = false;
                    }
                } else {
                    qCWarning(logAsset) << QStringLiteral("  [山海经] 缓存复制失败（目标不存在）: %1 %2").arg(task.sha1.left(12), targetPath);
                    sha1Match = false;
                }
            }
        }
        qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - t0;
        // Per-file pre-check result: debug-only (too verbose at info level when 5000+ files)
        if (elapsed > 50) {
            qCDebug(logAsset) << QStringLiteral("  [山海经] 预检查 %1 %2 %3 用时 %4ms").arg(task.sha1, sha1Match ? QStringLiteral("命中") : QStringLiteral("不匹配"), fmtSize(task.size)).arg(elapsed);
        }
        if (callback)
            callback(task, sha1Match);
    }
};

void AssetDownloader::enqueuePreCheck(const AssetTask& task, const QString& checkPath)
{
    // NOTE: Deliberately NOT de-duplicating by SHA1 here. Multiple asset index entries
    // CAN share the same SHA1 (different virtual paths, identical content). The first
    // PreCheckWorker that hits copies the file to savePath; subsequent workers for the
    // same SHA1 will find the file already there and count as cache hit via the
    // copy-fallback logic below. Removing dedup avoids the silent-drop bug.

    PreCheckPending pcp;
    pcp.task = task;
    pcp.enqueueAtMs = QDateTime::currentMSecsSinceEpoch();
    // 唯一 key：savePath + sha1（同一 SHA1 可对应多个条目，2026-08-14 修复——
    // 旧实现用 sha1 作 key，同一 sha1 重复任务时 map 覆盖但 m_preCheckQueued
    // 计数 +2，回调只 remove 一次 → 计数泄漏 → checkAllFinished 永被
    // "m_preCheckQueued > 0" 挡住 → assets 卡 92% 数分钟）
    // 2026-11-17 修：key 里加自增序号。
    // 上一版用 savePath|sha1，如果同一个任务被投递两次（初版 4041 条 + appendTasks
    // 又追加 76 条，两个来源可能包含同一 savePath|sha1），insert 会覆盖前一条，
    // 但两条 IO 都会跑、onPreCheckResult 也都会回调 → map 里只剩一条 →
    // 总任务数 +2、完成数 +2、但 map 只少 1：结果是"总 4117 / 完成 4116"，
    // 进度永远差 1 个到不了 100%（实测 17:09:36 这一次）。加序号后每条互不覆盖。
    static QAtomicInteger<quint64> s_preCheckSeq{0};
    const QString preCheckKey = task.savePath + QLatin1Char('|') + task.sha1
                              + QLatin1Char('#') + QString::number(s_preCheckSeq.fetchAndAddRelaxed(1));
    m_pendingPreCheck.insert(preCheckKey, pcp);
    m_preCheckQueued++;

    auto* worker = new PreCheckWorker();
    worker->task = task;
    worker->checkPath = checkPath.isEmpty() ? task.savePath : checkPath;
    worker->copyOnHit = !checkPath.isEmpty() && checkPath != task.savePath;

    QPointer<AssetDownloader> self(this);
    worker->callback = [self, preCheckKey](const AssetDownloader::AssetTask& t, bool sha1Match) {
        if (self) {
            QMetaObject::invokeMethod(self, [self, t, sha1Match, preCheckKey]() {
                if (self->m_state == AssetDownloader::Cancelled) return;
                self->onPreCheckResult(t, sha1Match, preCheckKey);
            });
        }
    };

    m_ioPool.start(worker);
}

void AssetDownloader::onPreCheckResult(const AssetTask& task, bool sha1Match, const QString& preCheckKey)
{
    // key 由 enqueuePreCheck 生成并随 lambda 带过来（含自增序号，见那里的说明）
    m_pendingPreCheck.remove(preCheckKey);
    m_preCheckQueued--;

    // 丢任务审计（2026-11-17）：这里要是 return，这个任务既不算完成也不算失败，
    // 分母已经加过 → 进度永远差 1 个。记账，让 "总数 = 缓存命中+网络+失败+丢弃" 可核对。
    if (m_state != Running) {
        ++m_droppedTasks;
        qCWarning(logAsset) << QStringLiteral("  [山海经] [审计] 预检查结果到达时状态非 Running，任务被丢弃：%1")
            .arg(task.sha1.left(12));
        return;
    }

    if (sha1Match) {
        // Cache hit: count bytes, finish, and fire next
        m_cacheHitCount++;
        m_downloadedBytes.fetchAndAddRelaxed(task.size);
        m_cacheBytes.fetchAndAddRelaxed(task.size);
        finishDownload(task, true);
    } else {
        // Size matched but SHA1 didn't: must download
        m_pendingQueue.prepend(task);
        if (m_inFlight.size() < m_maxConcurrent) {
            fireNext();
        } else {
            // If all slots full, re-activate timer to dispatch when slots free up
            if (!m_accelTimer->isActive())
                m_accelTimer->start();
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Reset speed baseline — called after burst is sent to avoid cache-hit spike.
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::resetSpeedBaseline()
{
    m_speedTimer.restart();
    // Subtract cache-hit bytes so the first speed reading reflects only network I/O
    m_lastSampleBytes.storeRelaxed(
        m_downloadedBytes.loadRelaxed() - m_cacheBytes.loadRelaxed());
    m_emaMbps = 0.0;
    m_emaBps.storeRelaxed(0);
    {
        QMutexLocker lock(&m_speedMutex);
        m_speedRecords.clear();
    }
    m_speedFloorBps.storeRelaxed(kMinSpeedFloorBps);
}

// ═════════════════════════════════════════════════════════════════════════════
// Detailed logging
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::logState(const char* event)
{
    qint64 elapsed = m_downloadTimer.elapsed();
    int inflight = m_inFlight.size();
    int pending = m_pendingQueue.size();
    int preCheckLeft = m_pendingPreCheck.size();
    int done = m_completedFiles.loadRelaxed();
    int total = m_totalFiles.loadRelaxed();
    qint64 bytes = m_downloadedBytes.loadRelaxed();
    double speed = m_emaMbps;

    // State transitions always go to info-level (visible in log file)
    qCInfo(logAsset) << QStringLiteral("[山海经] [状态] %1 用时=%2ms phase=%3 inflight=%4 pending=%5 预检查=%6 进度=%7/%8 已下载=%9 速度=%10 MB/s 阈值=%11/s 缓存命中=%12")
        .arg(QString::fromLatin1(event))
        .arg(elapsed).arg(m_phase).arg(inflight).arg(pending).arg(preCheckLeft)
        .arg(done).arg(total)
        .arg(fmtSize(bytes))
        .arg(QString::number(speed, 'f', 1))
        .arg(fmtSize(m_speedFloorBps.loadRelaxed()))
        .arg(m_cacheHitCount)
        + QStringLiteral(" 分片任务=%1 分片作废=%2")
              .arg(m_shards.size()).arg(fmtSize(m_wastedBytes.loadRelaxed()));
}

// ═════════════════════════════════════════════════════════════════════════════
// Periodic speed logging — 1-second interval, info-level (visible in log file)
// ═════════════════════════════════════════════════════════════════════════════

void AssetDownloader::logSpeed()
{
    // 周期性调整每主机限速 + 吞吐心跳（2026-11-17）
    // 诊断价值：assets 尾程的"龟速/静止"以前在日志里完全看不见 —— 没有速度行，
    // 只能从下一条 dispatch 日志的间隔反推，实测因此多花了两轮排查。
    // 现在每 5s 打一行吞吐，静止多久、还剩多少、有多少在途，一行就能看出来。
    if (m_speedLogTimer.elapsed() < 5000)
        return;
    m_speedLogTimer.restart();

    adjustHostLimits();

    // ⚠ 必须用自己的时钟：m_speedTimer 被 sampleSpeed() 每 50ms restart 一次，
    // 借用它算出来的"5 秒吞吐"其实是 50ms 窗口 → 输出过 226929 MB/s 这种荒谬数字。
    const qint64 elapsed = qMax<qint64>(1, m_hbTimer.restart());
    const qint64 now = m_downloadedBytes.loadRelaxed() - m_cacheBytes.loadRelaxed();
    const qint64 delta = now - m_lastSpeedLogBytes;
    m_lastSpeedLogBytes = now;
    const qint64 bps = delta * 1000 / elapsed;

    // 剩下多少大文件
    int bigLeft = 0;
    for (int i = 0; i < m_pendingQueue.size(); ++i) {
        if (m_pendingQueue.at(i).size >= kSegMinBytes) ++bigLeft;
    }

    // 主线程占比：这段跑在主线程（拷贝 + SHA1），是"每秒能完成几个文件"的硬上限来源
    const qint64 totalMs = m_downloadTimer.elapsed();
    const double mainPct = (totalMs > 0)
        ? (m_mainThreadWorkUs / 1000.0) * 100.0 / totalMs : 0.0;
    const double avgMainMs = (m_replyFinishedCount > 0)
        ? (m_mainThreadWorkUs / 1000.0) / m_replyFinishedCount : 0.0;

    // ⚠ 这里必须"先各自 arg 完再拼接"。
    // 直接写 A + B + C 会让 .arg() 链只作用在最后一个操作数上 ——
    // 实测出现过 "完成=%1 派发=%2 ..." 占位符原样漏进日志（诊断数据全废）的情况。
    const QString head =
        QStringLiteral("[山海经] [吞吐] %1/s 在途=%2 待下载=%3 大文件剩余=%4 分片任务=%5 作废=%6")
            .arg(fmtSize(bps))
            .arg(m_inFlight.size())
            .arg(m_pendingQueue.size())
            .arg(bigLeft)
            .arg(m_shards.size())
            .arg(fmtSize(m_wastedBytes.loadRelaxed()));
    const QString tail =
        QStringLiteral(" | 完成=%1 派发=%2 主线程=%3ms(占比%4% 均%5ms/个) SHA1=%6 请求均=%7ms 快请求%8%")
            .arg(m_replyFinishedCount)
            .arg(m_dispatchCount)
            .arg(qRound64(m_mainThreadWorkUs / 1000.0))
            .arg(QString::number(mainPct, 'f', 1))
            .arg(QString::number(avgMainMs, 'f', 2))
            .arg(fmtSize(m_sha1Bytes))
            .arg(m_reqCount > 0 ? qRound64((double)m_reqTotalMs / m_reqCount) : 0)
            .arg(m_reqCount > 0 ? qRound(100.0 * m_reqFast / m_reqCount) : 0);
    qCInfo(logAsset) << (head + tail);
}

// ═════════════════════════════════════════════════════════════════════════════
// Throttled tick（2026-11-17）
// ═════════════════════════════════════════════════════════════════════════════
// 背景：accelTick 在「队列派空」或「inflight >= target」时会 stop 定时器。
// 分片引入后，"inflight == target" 不再等于"没有工作"——target 是按
// schedulePhase 用旧的 inflight 算出来的，分片段完成一个就少一个 in-flight，
// 此时若没有人再调 dispatchPendingShardSegs，剩下的段就一直待发，
// 表现为「前段很快、后段莫名静止 30 秒」（实测 new3 10:43:47→10:44:39 空档）。
// 所以必须有一张每秒都还在的表。它只做三件轻量的事，不参与派发节奏。
void AssetDownloader::throttledTick()
{
    if (m_state != Running) return;

    // 分片段补派：完成一段就让出槽位，槽位立刻还给分片
    if (!m_shards.isEmpty()) {
        dispatchPendingShardSegs();
        trySplitInFlight();
    }

    // 队列还在 → 别让 accelTimer 停摆（停摆期间没人派发，等于空转）
    bool hasWork = !m_pendingQueue.isEmpty() || !m_pendingPreCheck.isEmpty() || !m_shards.isEmpty();
    if (hasWork && !m_accelTimer->isActive())
        m_accelTimer->start();

    checkAllFinished();
}
