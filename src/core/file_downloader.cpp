// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
//
// Per-file download engine v9 — thread-pool based, phased acceleration.
//
// Key improvements over v8:
//   - QThreadPool instead of QThread::create (avoids OS thread thrash)
//   - 2 shared QNAMs with per-request HTTP/1.1 config (connection pooling)
//   - DNS pre-resolution + IP reliability scoring
//   - Per-host health tracking (consecutive failures, degraded hosts)
//   - Phased acceleration: first-thread-for-all → speed-floor-thread-split
//   - Removed QThread::msleep(50) BMCLAPI serial bottleneck
//   - Removed static s_lastProgressEmitMs race condition

#include "core/file_downloader.h"
#include "download_accept.h"
#include "../utils/hash_utils.h"
#include "core/engine_identity.h"
#include "utils/logger.h"
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QHttp1Configuration>
#include <QThread>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QCryptographicHash>
#include <QEventLoop>
#include <QTimer>
#include <QRunnable>
#include <QHostInfo>
#include <QDateTime>
#include <QPointer>
#include <algorithm>

namespace ShadowDownloader {
using namespace ShadowLauncher;

// ═════════════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ═════════════════════════════════════════════════════════════════════════════

FileDownloader::FileDownloader(QObject* parent) : QObject(parent)
{
    qCInfo(logDownload) << QStringLiteral("[夸父] 下载引擎 v9 初始化");

    m_speedTimer.start();

    // Thread pool: max 128 concurrent workers
    m_threadPool.setMaxThreadCount(128);

    m_managerTimer = new QTimer(this);
    m_managerTimer->setTimerType(Qt::PreciseTimer);
    connect(m_managerTimer, &QTimer::timeout, this, &FileDownloader::managerTick);

    m_speedTimer2 = new QTimer(this);
    m_speedTimer2->setTimerType(Qt::PreciseTimer);
    connect(m_speedTimer2, &QTimer::timeout, this, &FileDownloader::speedTick);
}

FileDownloader::~FileDownloader()
{
    cancel();
    m_threadPool.clear(); // prevent new jobs from starting
    m_threadPool.waitForDone(10000);
}

// ═════════════════════════════════════════════════════════════════════════════
// addFile — enqueue a file for download
// ═════════════════════════════════════════════════════════════════════════════

void FileDownloader::addFile(const QString& localPath, const QString& localName,
                              const QStringList& sources, qint64 expectedSize,
                              const QByteArray& sha1, bool jarStrip, bool skipCacheCheck)
{
    qCInfo(logDownload) << QStringLiteral("[夸父] 添加下载任务 名称=%1 大小=%2").arg(localName, formatSize(expectedSize));

    // Pre-check SHA1 cache hit in working dir (tempDir for merged installs)
    // skipCacheCheck=true：调用方已后台预检过缓存（未命中），跳过重复读盘 SHA1
    if (!sha1.isEmpty() && !skipCacheCheck) {
        QFileInfo fi(localPath);
        if (fi.exists() && fi.size() > 0) {
            QFile f(localPath);
            if (f.open(QIODevice::ReadOnly)) {
                QCryptographicHash hash(QCryptographicHash::Sha1);
                hash.addData(&f);
                f.close();
                if (hash.result().toHex() == sha1) {
                    // 缓存命中：本地文件 SHA1 完全匹配 → 直接复用，跳过网络请求。
                    // 计数延迟到 start() 统一入账（m_cacheHits）——否则 addFile 阶段
                    // completed 提前涨高，进度条从高完成度开始；全命中时 completed==total
                    // 但无 worker → allFinished 永不触发 → 下载流程卡死（问题 1/2 根因）。
                    m_cacheHits.fetchAndAddRelaxed(1);
                    m_cacheBytes.fetchAndAddRelaxed(fi.size());
                    emit logMessage(QString::fromUtf8("[夸父] 缓存命中｜文件名:%1，直接复用本地文件，跳过网络请求")
                                        .arg(localName));
                    qCInfo(logDownload) << QStringLiteral("[夸父] 缓存命中｜文件名:%1，直接复用本地文件，跳过网络请求")
                                           .arg(localName);
                    // 不发 fileProgress：缓存命中不是网络下载，不应驱动上层 catBytesDl
                    // （否则缓存全命中时 catBytesDl 立即满 → 卡片提前绿色完成态）
                    emit fileFinished(localPath, true);
                    return;
                }
            }
        }

        // Fallback cache check: if file not in working dir, check gameDir cache
        if (!m_cacheFallbackDir.isEmpty() && !m_minecraftDir.isEmpty()
            && localPath.startsWith(m_minecraftDir)) {
            QString relative = localPath.mid(m_minecraftDir.length());
            QString fallbackPath = m_cacheFallbackDir + relative;
            QFileInfo ffi(fallbackPath);
            if (ffi.exists() && ffi.size() > 0) {
                QFile f(fallbackPath);
                if (f.open(QIODevice::ReadOnly)) {
                    QCryptographicHash hash(QCryptographicHash::Sha1);
                    hash.addData(&f);
                    f.close();
                    if (hash.result().toHex() == sha1) {
                        // Cache hit from gameDir! Copy to working dir.
                        // 计数延迟到 start() 统一入账（m_cacheHits），同工作目录缓存命中
                        QDir().mkpath(QFileInfo(localPath).absolutePath());
                        if (QFile::copy(fallbackPath, localPath)) {
                            m_cacheHits.fetchAndAddRelaxed(1);
                            m_cacheBytes.fetchAndAddRelaxed(ffi.size());
                            emit logMessage(QString::fromUtf8("[夸父] 缓存命中｜文件名:%1，直接复用本地文件，跳过网络请求")
                                                .arg(localName));
                            qCInfo(logDownload) << QStringLiteral("[夸父] 缓存命中｜文件名:%1，直接复用本地文件，跳过网络请求")
                                                   .arg(localName);
                            // 不发 fileProgress（同工作目录缓存命中）：避免驱动上层 catBytesDl 提前满
                            emit fileFinished(localPath, true);
                            return;
                        } else {
                            qCWarning(logDownload) << QStringLiteral("[夸父] [缓存] 复制失败 %1 → %2")
                                .arg(fallbackPath).arg(localPath);
                        }
                    }
                }
            }
        }
    }

    auto file = std::make_shared<FileDownload>();
    file->localPath = localPath;
    file->localName = localName;
    file->orderedSources = sources;
    file->sourceFailCounts.fill(0, sources.size());
    file->expectedSha1 = sha1;
    file->needsJarStrip = jarStrip;
    file->fileSize = expectedSize;
    file->isUnknownSize = (expectedSize <= 0);
    // 主流启动器 IsNoSplit 语义：<1MB 不分片（FileSize < 1024*1024）——
    // 1MB 以上可分片（配合速度门限防并发爆炸）；镜像源在 tryAddThread 拦截
    file->isNoSplit = (!file->isUnknownSize
                       && file->fileSize < 1LL * 1024 * 1024);

    QMutexLocker lock(&m_filesMutex);
    m_files.append(file);
    m_totalFiles.fetchAndAddRelaxed(1);
    if (file->fileSize > 0) m_totalBytes.fetchAndAddRelaxed(file->fileSize);

    qCInfo(logDownload) << QStringLiteral("[夸父] 任务已排队 名称=%1 队列总数=%2").arg(localName).arg(m_files.size());
}

void FileDownloader::notifyCacheHit(const QString& localPath, qint64 size)
{
    // 调用方已后台预检确认 SHA1 命中：直接计入完成（completed/total/cacheHits），
    // 不读盘不排队——避免主线程批量读盘 hash 卡 UI。
    // 发 fileProgress 让上层分类字节（catBytesDl）计入缓存命中——否则子步骤进度
    // （如“下载支持库”）不含缓存文件，进度到 42% 突然跳完成。
    m_cacheHits.fetchAndAddRelaxed(1);
    m_cacheBytes.fetchAndAddRelaxed(size);
    // ── 命中日志（2026-08-05 补）──
    // 后台预检命中走本路径；旧实现无任何日志，用户无法确认缓存复用是否生效
    //（addFile 同步分支的“缓存命中”日志因 skipCacheCheck=true 已不再执行）。
    // 节流：每 20 个打一条明细，避免几千个文件刷屏。
    const int hitTotal = m_cacheHits.loadRelaxed();
    if ((++m_cacheHitLogCtr % 20) == 1 || hitTotal <= 1) {
        qCInfo(logDownload) << QStringLiteral("[夸父] 缓存命中｜文件名:%1 大小:%2KB（累计 %3 个）")
            .arg(localPath.section(QLatin1Char('/'), -1)).arg(size / 1024).arg(hitTotal);
    }
    const QString name = localPath.section(QLatin1Char('/'), -1);
    emit fileProgress(localPath, name, size, size, localPath);
    emit fileFinished(localPath, true);
}

// ═════════════════════════════════════════════════════════════════════════════
// Lifecycle
// ═════════════════════════════════════════════════════════════════════════════

void FileDownloader::start()
{
    if (m_state == Running) return;
    m_state = Running;
    m_cancelled.storeRelaxed(0);
    m_paused.storeRelaxed(0);
    m_phase = PhaseFirstThread;

    // 限速虚拟时钟按“下次任务生效”重置（限速设置本身在 start 前已由调用方写入）
    {
        QMutexLocker lock(&m_limitMutex);
        m_limitNextSlotUs = 0;
    }

    m_speedTimer.start();
    // 初始化 lastSpeedBytes 为当前网络字节：m_downloadedBytes 仅累加真实网络 IO
    // （缓存命中分支已剔除字节累加），避免首次 speedTick 将缓存文件计入瞬时速度
    m_lastSpeedBytes = m_downloadedBytes.loadRelaxed();
    m_speedFloorBps.storeRelaxed(kMinSpeedFloorBps);
    m_speedRecords.clear();

    // ── 缓存命中统一入账（addFile 阶段只累计 m_cacheHits，start 时再补计数）──
    // 修复：之前 addFile 阶段就 completed++/total++，进度条从高完成度开始；
    // 缓存全命中时 completed==total 但无 worker → allFinished 永不触发 → 下载卡死。
    {
        const int hits = m_cacheHits.fetchAndStoreRelaxed(0);
        m_cacheHitBase += hits;   // 留基数给收尾汇总（m_cacheHits 已被清零）
        if (hits > 0) {
            m_completedFiles.fetchAndAddRelaxed(hits);
            m_totalFiles.fetchAndAddRelaxed(hits);
            // 缓存字节并入总字节（进度条字节显示完整）
            const qint64 cb = m_cacheBytes.fetchAndStoreRelaxed(0);
            m_totalBytes.fetchAndAddRelaxed(cb);
        }
    }

    // ── 无网络任务（全缓存命中）：无 worker 可跑，立即完成 ──
    if (m_files.isEmpty()) {
        qCInfo(logDownload) << QStringLiteral("[夸父] 无待下载文件（全部缓存命中或空任务），直接完成");
        emit logMessage(QStringLiteral("[夸父] 无待下载文件，直接完成"));
        m_state = Idle;
        const int done = m_completedFiles.loadRelaxed();
        const int total = m_totalFiles.loadRelaxed();
        emit progressChanged(done, total,
                              m_downloadedBytes.loadRelaxed(),
                              m_totalBytes.loadRelaxed());
        emit allFinished();
        return;
    }

    // Clear thread pool from any previous runs
    m_threadPool.clear();

    m_managerTimer->start(kManagerTickMs);
    m_speedTimer2->start(kSpeedTickMs);

    emit progressChanged(m_completedFiles.loadRelaxed(), m_totalFiles.loadRelaxed(),
                          m_downloadedBytes.loadRelaxed(), m_totalBytes.loadRelaxed());

    qCInfo(logDownload) << engineBanner("kuafu");
    emit logMessage(engineBanner("kuafu"));
    emit logMessage(QStringLiteral("[夸父] 引擎启动 文件数=%1 最大线程=%2").arg(m_files.size()).arg(m_maxThreads));
}

void FileDownloader::pause()
{
    if (m_state != Running) return;
    m_state = Paused;
    m_paused.storeRelaxed(1);
    m_currentSpeedBps.storeRelaxed(0);   // 暂停即报 0，避免上层显示“停着的速度”
    m_managerTimer->stop();
    m_speedTimer2->stop();

    // ── 真暂停（契约 §5）──
    // 旧实现只停定时器：在途 worker 仍在收字节并累加 m_downloadedBytes（假暂停）。
    // 现在排队 abort 所有在途 reply；worker 退出等待循环后看到 m_paused →
    // 丢弃本 attempt 数据并等待 resume（不消耗重试次数），恢复后整段重下。
    abortInFlightReplies();

    emit logMessage(QString::fromUtf8("[夸父] [暂停] 下载已暂停（已在途请求已中止并等待恢复）"));
}

void FileDownloader::resume()
{
    if (m_state != Paused) return;
    m_paused.storeRelaxed(0);
    m_state = Running;
    m_speedTimer.restart();
    m_lastSpeedBytes = m_downloadedBytes.loadRelaxed();   // 网络字节口径（缓存已剔除）
    // 暂停期间不累计限速账：恢复后重新起算，避免“欠账”一次性补睡
    {
        QMutexLocker lock(&m_limitMutex);
        m_limitNextSlotUs = 0;
    }
    m_managerTimer->start(kManagerTickMs);
    m_speedTimer2->start(kSpeedTickMs);
    emit logMessage(QStringLiteral("[夸父] 下载已恢复"));
}

void FileDownloader::cancel()
{
    m_cancelled.storeRelaxed(1);
    m_paused.storeRelaxed(0);   // 取消优先：暂停等待循环看到 cancelled 立即退出
    m_state = Cancelled;
    m_currentSpeedBps.storeRelaxed(0);
    m_managerTimer->stop();
    m_speedTimer2->stop();
    m_threadPool.clear();

    // Abort ALL in-flight HTTP replies immediately.
    // IMPORTANT: QNetworkReply::abort() is only thread-safe when called from the
    // thread that owns the reply. Workers run in QThreadPool threads, so we MUST
    // invoke abort() on the worker's event loop via QueuedConnection.
    // Direct reply->abort() from the main thread is UNDEFINED BEHAVIOR.
    abortInFlightReplies();
    {
        QMutexLocker lock(&m_inflightMutex);
        m_inflightReplies.clear();
    }

    // ── 清理分片临时文件（.shadow_temp/dl_*.tmp）+ 未提交的目标文件 ──
    // 实测（2026-11-05）：取消后目标文件可能残留**满尺寸**（isNoSplit 直写最终路径，
    // 写完整数据后才被取消），也可能残留半截（写文件中途取消）。
    // 规则：只删"本次写过、但没走到成功收尾"的目标文件；已提交的一律保留。
    QStringList tempDirs;
    {
        QMutexLocker lock(&m_filesMutex);
        for (auto& f : m_files) {
            for (auto& t : f->threads) {
                if (!t->tempPath.isEmpty()) {
                    tempDirs.append(QFileInfo(t->tempPath).absolutePath());
                    QFile::remove(t->tempPath);
                    t->tempPath.clear();
                }
            }
            if (f->targetWritten && !f->committed) {
                if (QFile::remove(f->localPath))
                    qCInfo(logDownload) << QStringLiteral("[夸父] 取消清理未完成文件 %1").arg(f->localPath);
            }
        }
    }

    // 空壳目录（.shadow_temp/）不留在磁盘上
    tempDirs.removeDuplicates();
    for (const QString& d : tempDirs) {
        if (QDir(d).exists() && QDir(d).isEmpty())
            QDir().rmdir(d);
    }

    emit logMessage(QString::fromUtf8("[夸父] [失败] 下载已取消"));
}

// ═════════════════════════════════════════════════════════════════════════════

// ── In-flight reply tracking (for immediate abort on cancel) ──
void FileDownloader::addInFlightReply(QNetworkReply* reply) {
    QMutexLocker lock(&m_inflightMutex);
    m_inflightReplies.append(reply);
}

void FileDownloader::removeInFlightReply(QNetworkReply* reply) {
    QMutexLocker lock(&m_inflightMutex);
    m_inflightReplies.removeOne(reply);
}

// ── 线程局部 QNAM（见 runWorker 注释）──
// 计数用于验收：下载 N 个文件时 QNAM 创建次数应 ≈ 线程数，而不是 ≈ 文件数。
static QAtomicInt g_qnamCreatedCount{0};

int FileDownloader::qnamCreatedTotal() { return g_qnamCreatedCount.loadRelaxed(); }

static QNetworkAccessManager* workerQnam()
{
    static thread_local QNetworkAccessManager* nam = nullptr;
    if (!nam) {
        nam = new QNetworkAccessManager();   // 进程级生命周期（线程池线程复用）
        g_qnamCreatedCount.fetchAndAddRelaxed(1);
    }
    return nam;
}

// ── 429/503：解析 Retry-After（秒数；HTTP 日期形式忽略，退化为默认值）──
static int retryAfterSeconds(QNetworkReply* reply, int fallbackSec)
{
    const QByteArray ra = reply->rawHeader("Retry-After").trimmed();
    bool ok = false;
    const int sec = ra.toInt(&ok);
    if (ok && sec > 0) return sec;
    return fallbackSec;
}

// ── 取消/暂停：对全部在途 reply 排队 abort ──
// 必须持锁遍历：worker 在 removeInFlightReply() 之后才 deleteLater()，
// 持锁期间对象不会被移除/释放；abort() 由 reply 所属 worker 线程的事件循环执行。
void FileDownloader::abortInFlightReplies()
{
    QMutexLocker lock(&m_inflightMutex);
    for (auto* reply : m_inflightReplies) {
        if (reply)
            QMetaObject::invokeMethod(reply, "abort", Qt::QueuedConnection);
    }
}

// ── 暂停等待（worker 线程内调用）──
// QThreadPool worker 允许 sleep；分片轮询保证 cancel 能立刻打断等待。
void FileDownloader::waitWhilePaused()
{
    while (m_paused.loadRelaxed() && !m_cancelled.loadRelaxed())
        QThread::msleep(static_cast<unsigned long>(kPausePollMs));
}

// ── 限速：全局虚拟时钟（所有 worker 共享一条时间线）──
// 速率 = m_speedLimitBps（bytes/s）。每收到 delta 字节，在锁内把“允许完成时刻”
// 往后推 delta/limit 秒，并 sleep 到该时刻。
// 关键：预约在锁内串行累加 → N 个 worker 不会各自按 limit 并行（那样实际吞吐 = N×limit）；
// 聚合吞吐收敛到 limit。
// sleep 在 worker 线程的读取回调里，阻塞事件循环 → TCP 反压，是真正的传输层限速。
void FileDownloader::applySpeedLimit(qint64 deltaBytes, const QAtomicInt* abortFlag)
{
    const qint64 limitBps = m_speedLimitBps.loadRelaxed();
    if (limitBps <= 0 || deltaBytes <= 0) return;   // <=0：未设置限速

    qint64 waitUs = 0;
    {
        QMutexLocker lock(&m_limitMutex);
        // 用 µs 计账：1KB @ 20MB/s ≈ 48µs，ms 粒度会把整数余量吃掉导致限速失效
        const qint64 nowUs = getElapsedMs() * 1000;
        if (m_limitNextSlotUs < nowUs)
            m_limitNextSlotUs = nowUs;   // 空闲后不补睡，重新起算
        m_limitNextSlotUs += deltaBytes * 1000000 / limitBps;
        waitUs = m_limitNextSlotUs - nowUs;
    }

    // ── 攒账再睡（2026-11-05 实测修正）──
    // 逐块 sleep 会被 Windows 的 sleep 粒度（1–15ms，通常 15.6ms 一档）吃掉吞吐：
    // 实测 1MB/s 档只跑到 0.64MB/s、4MB/s 档只跑到 2.52MB/s。
    // 现在小欠账不睡（先跑快一点点把额度攒起来），攒到 4ms 以上才进入等待循环；
    // 循环里每次用"真实时间"重算剩余（而不是账面减法），sleep 粒度带来的过冲会被
    // 下一轮自动扣回，长期平均收敛到 limit。
    if (waitUs < kSpeedLimitMinSleepUs) return;

    while (true) {
        if (m_cancelled.loadRelaxed() || m_paused.loadRelaxed())
            return;   // 取消/暂停立即放弃本次限速等待
        // 范围被切分缩小：立刻停等，让调用方去 abort（少睡 = 少囤数据）
        if (abortFlag && abortFlag->loadRelaxed())
            return;
        const qint64 nowUs = getElapsedMs() * 1000;
        qint64 remain = 0;
        {
            QMutexLocker lock(&m_limitMutex);
            remain = m_limitNextSlotUs - nowUs;
        }
        if (remain <= 1500) return;   // 剩余不足 1.5ms：直接放行，避免过度睡
        QThread::usleep(static_cast<unsigned long>(
            qMin<qint64>(remain - 1000, kSpeedLimitSleepSliceUs)));
    }
}

// Manager tick — 分阶段调度
// ═════════════════════════════════════════════════════════════════════════════

void FileDownloader::managerTick()
{
    // 2026-11-18（修界面卡顿）：managerTick 跑在 GUI 线程上，50ms 一次。
    // 卡顿探针抓到 1.5 秒级停顿，但日志/日志缓冲都排除了 → 要证明是哪个 tick 占住的。
    QElapsedTimer tickClock;
    tickClock.start();
    struct TickWatch {
        QElapsedTimer& t; FileDownloader* self;
        ~TickWatch() {
            const qint64 ms = t.elapsed();
            if (ms > 200)
                qCWarning(logDownload) << QStringLiteral("[夸父] managerTick 占用 GUI 线程 %1ms").arg(ms);
        }
    } tickWatch{tickClock, this};
    if (m_state != Running || m_cancelled.loadRelaxed()) return;

    int active = m_activeThreads.loadRelaxed();
    int maxThreads = m_maxThreads;
    if (active >= maxThreads) return;

    QMutexLocker lock(&m_filesMutex);

    // Phase 1: ensure every file has at least one thread started
    if (m_phase == PhaseFirstThread) {
        bool allStarted = true;
        for (auto& f : m_files) {
            if (f->state == 5 || f->state == 4) continue; // failed or finished
            if (f->state == 0) {
                if (active >= maxThreads) { allStarted = false; break; }
                auto th = tryStartFirstThread(f);
                if (th) {
                    active++;
                } else if (m_modpackMode) {
                    // 模组专项：host 暂时满/降级被拒 → 文件保持 state 0，
                    // 强制留在 Phase1 下轮重试——否则 allStarted=true 进入 Phase2 后
                    // state 0 文件永不被调度（Phase2 只给已有线程的文件加片）
                    allStarted = false;
                }
            }
        }
        if (allStarted) {
            m_phase = PhaseAccelerate;
            qCInfo(logDownload) << QStringLiteral("[夸父] [调度] 所有文件已启动首线程，进入加速阶段");
        }
        lock.unlock();
        return;
    }

    // Phase 2-3: speed-based thread splitting
    // ── 速度门限（主流启动器语义，2026-08-04 恢复）──
    // 全局下载速度 ≥256KB/s 就不追加分片线程：并发受控，避免把 CDN
    // 打到限流（实测 14 个大文件全开分片 → 官方 CDN 限流 → 集体超时）。
    // 速度不足时才加分片加速——主流启动器 NetTaskSpeedLimitLow=256KB/s。
    // 注意：速度门限只挡“给已有线程的文件加分片”，不挡“无线程文件的
    // 首线程补启动”（主流启动器 StartManager：等待文件启动不受速度门限限制）。
    const bool speedEnough = (m_instantBps >= kSpeedLimitLowBps);

    // Add threads to files with large remaining chunks
    for (auto& f : m_files) {
        if (active >= maxThreads) break;
        if (f->state >= 3 || f->state == 5) continue; // merging/finished/failed
        if (m_modpackMode && f->threads.isEmpty() && f->state == 0) {
            // 模组专项双保险：Phase1 已退出但仍有 state 0 文件（极端时序）→ 补启动首线程
            auto th = tryStartFirstThread(f);
            if (th) { active++; continue; }
        }
        // 小文件补启动：Phase1 因线程上限未启动的文件在此补首线程（主流启动器：
        // 等待文件循环持续启动直到线程满；这里每 tick 继续补）。
        // 不受速度门限限制（主流启动器语义：等待文件无条件启动首线程）。
        if (f->threads.isEmpty() && f->state == 0) {
            auto th = tryStartFirstThread(f);
            if (th) { active++; }
            continue;
        }
        if (f->isNoSplit && !f->threads.isEmpty()) continue; // single-thread files, already started

        // 速度门限：速度足够时不再给已有线程的文件加分片（主流启动器语义）
        // ⚠️ 2026-11-18（尾部慢的真凶）：这个门限看的是**整机**速度，不是本文件速度。
        // 冷装时 415MB 资源由山海经跑出 33MB/s，于是"速度足够"恒成立 →
        // 夸父这 9 个文件（共 74MB）永远停在 1~2 条连接上，平均只有 3.8MB/s，
        // 结果「资源 15.8 秒下完，安装却要等到 19.2 秒」。
        // 例外：本文件线程数少于 4 时无条件加分片 —— 大文件本来就该多连接。
        //
        // ── 2026-11-20（再次校正：4 条/文件把库下载压在 6.5MB/s）──
        // 冷装实测：126MB 库文件 15.4 秒（6.5MB/s），而同一主机
        // 4 条并发 Range 实测 11.3MB/s、6 条整文件 GET 实测 33MB/s —— 对端不缺带宽，
        // 是连接给少了。每文件上限改为「按剩余大小给，每 ~6MB 一条，最多 16 条」；
        // 全局速度门限只用来挡「已经 4 条以上、且本文件已经很宽裕」的情况。
        // 速度门限：全局速度足够时不再给已有线程的文件加分片（主流启动器语义）。
        // ⚠️ 2026-11-18（尾部慢的真凶）：这个门限看的是**整机**速度，不是本文件速度。
        // 冷装时资源由山海经跑出 33MB/s，于是"速度足够"恒成立 →
        // 夸父这 9 个文件永远停在 1~2 条连接上，平均只有 3.8MB/s。
        // 例外：本文件线程数少于 4 时无条件加分片 —— 大文件本来就该多连接。
        //
        // ── 2026-11-20 实测定稿 ──
        // 「只有库要下」的场景（资源全在缓存，链路闲着）连测两轮：
        //   4 条上限：4.6s / 38.3s（一条慢连接就能把文件拖死，结果呈双峰）
        //   按剩余大小放到 12 条：4.28s / 4.39s（稳定）
        // 而冷装（资源与库同时抢链路）时多开连接会把活塞 CDN 的 client.jar 打到
        // 超时/连接被取消（那个失败在 4 条上限下同样出现，与线程数无关）。
        // 因此判据取「整机链路是否闲着」：闲（<8MB/s）才给单文件多开连接，
        // 忙时保持 4 条，避免把对端打到超时。
        const qint64 undoneForFile = qMax<qint64>(0, f->fileSize - f->totalDone());
        int perFileCap = 4;
        if (!f->isUnknownSize) {
            perFileCap = static_cast<int>(
                qBound<qint64>(4LL, undoneForFile / (6LL * 1024 * 1024), 12LL));
        }
        const bool linkIdle = (m_instantBps < kLinkIdleBps);
        if (f->threads.size() >= perFileCap) continue;
        if (!linkIdle && f->threads.size() >= 4) continue;

        // Check if preparing threads outnumber downloading threads
        int prep = 0, dl = 0;
        for (auto& t : f->threads) {
            if (t->state < 2) prep++;
            else if (t->state == 2) dl++;
        }
        if (prep > dl) continue;

        auto th = tryAddThread(f);
        if (th) active++;
    }

    // ── 尾程加速：慢速分片检测（2026-08-05）──
    // 大文件收尾阶段只剩 1-2 个分片在跑，若碰上慢速连接（CDN 边缘抖动，
    // 实测 16KB/s），整批下载被拖到龟速。检测持续慢速的分片线程，
    // 将其剩余范围一分为二并开新连接——老分片保留进度不丢，新线程新连接
    // 有机会命中更快边缘；多次切分后尾部多连接并跑，聚合速度成倍提升
    // （并发上限 maxThreads，镜像源不分片、小于 32KB 不再切）。
    const qint64 scanNow = getElapsedMs();
    if (scanNow - m_lastSlowScanMs >= kSlowScanMs) {
        m_lastSlowScanMs = scanNow;
        for (auto& f : m_files) {
            if (active >= maxThreads) break;
            if (f->state >= 3 || f->state == 5) continue;
            // ⚠️ 必须下标遍历：trySplitSlowThread 会 append 新分片到 f->threads，
            // Qt6 QList 连续存储 append 扩容会使引用/迭代器失效（实测崩溃）
            for (int ti = 0; ti < f->threads.size(); ++ti) {
                // 取原始指针而非引用：trySplitSlowThread 可能 append 扩容 QList，
                // 引用会悬垂；DownloadThread 对象由 shared_ptr 持有不随扩容移动
                DownloadThread* t = f->threads[ti].get();
                if (active >= maxThreads) break;
                if (t->state != 2) { t->slowBaseMs = 0; t->slowStreak = 0; continue; }
                if (t->downloadUndone() < kMinSplitPieceBytes) { t->slowBaseMs = 0; t->slowStreak = 0; continue; }
                if (t->slowBaseMs == 0) { t->slowBaseMs = scanNow; t->slowBaseBytes = t->downloadDone; continue; }
                const qint64 dt = scanNow - t->slowBaseMs;
                const qint64 gained = t->downloadDone - t->slowBaseBytes;
                if (dt >= kSlowScanMs) {
                    const qint64 bps = gained * 1000 / qMax<qint64>(1, dt);
                    if (bps < kSlowSegBps) {
                        t->slowStreak++;
                        if (t->slowStreak >= kSlowStreakLimit) {
                            t->slowStreak = 0;
                            // 现取 shared_ptr 按值传（append 后引用失效，原始指针 t 仍有效）
                            if (trySplitSlowThread(f, f->threads[ti])) active++;
                        }
                    } else {
                        t->slowStreak = 0;
                    }
                    // 滚动基线（~500ms 滑动窗口）
                    t->slowBaseMs = scanNow;
                    t->slowBaseBytes = t->downloadDone;
                }
            }
        }
    }
    lock.unlock();
}

// ═════════════════════════════════════════════════════════════════════════════
// Thread management — tryStartFirstThread / tryAddThread
// ═════════════════════════════════════════════════════════════════════════════

std::shared_ptr<DownloadThread> FileDownloader::tryStartFirstThread(
    std::shared_ptr<FileDownload> file)
{
    if (file->orderedSources.isEmpty()) return nullptr;
    if (file->fileSize <= 0 && !file->isUnknownSize) {
        // 未知大小的占位值：只为让分片逻辑有分母，**不能**用于完整性判定
        file->fileSize = 10LL * 1024 * 1024;
        file->sizeIsPlaceholder = true;
    }
    if (file->fileSize <= 0) { file->isUnknownSize = true; file->isNoSplit = true; }

    // Pick a healthy source
    // ── 主流启动器 GetSource 语义（2026-08-04）：从源 0 开始顺序找第一个可用源。
    // 源列表 = [首选组(官方或镜像按设置)..., 备选组...]——首选组用完/被禁用
    // 才轮到备选组；不做多源混合分流（哈希 65/35 已废除）。
    int sourceIdx = 0;
    int srcLabel = 0;
    bool allDisabled = true;
    for (int i = 0; i < file->orderedSources.size(); ++i) {
        // 主流启动器 GetSource：跳过已禁用源（per-file FailCount>=5 → IsFailed）
        if (i < file->sourceFailCounts.size() && file->sourceFailCounts[i] >= 5)
            continue;
        allDisabled = false;
        QString host = extractHost(file->orderedSources[i]);
        if (hostCanAccept(host)) { sourceIdx = i; srcLabel = (i == 0) ? 0 : i; break; }
        if (i == file->orderedSources.size() - 1) { sourceIdx = i; srcLabel = i; } // last resort
    }
    // 主流启动器 Retried 语义：所有源均被禁用（连续失败）→ 重置失败计数重试一轮
    //（主流启动器: SourcesOnce 全部重新标记，逐个重新尝试下载；Retried 只允许一次）
    if (allDisabled && !file->retriedOnce) {
        qCInfo(logDownload) << QStringLiteral("[夸父] 全部源被禁用，重置失败计数重试 文件=%1").arg(file->localName);
        file->retriedOnce = true;
        file->sourceFailCounts.fill(0);
        sourceIdx = 0;
        srcLabel = 0;
    } else if (allDisabled) {
        return nullptr;   // 已重试过仍全禁用 → 无法启动首线程（等上层失败处理）
    }

    // Source selection log (sampled)
    static int s_srcLogCtr = 0;
    if (srcLabel > 0 || (++s_srcLogCtr % 20 == 0)) {
        qCInfo(logDownload) << QStringLiteral("[夸父] [调度] 首源选择 host=%1 file=%2")
            .arg(extractHost(file->orderedSources[sourceIdx]), file->localName);
    }

    auto th = std::make_shared<DownloadThread>();
    th->uuid = m_nextUuid.fetchAndAddRelaxed(1);
    th->downloadStart = 0;
    th->downloadEnd = file->isUnknownSize ? 0 : file->fileSize;
    th->sourceUrl = file->orderedSources[sourceIdx];
    file->threads.append(th);
    file->state = 1;
    m_activeThreads.fetchAndAddRelaxed(1);

    // Track host active request count
    {
        QString host = extractHost(th->sourceUrl);
        QMutexLocker lock(&m_hostMutex);
        m_hostStats[host].activeRequests++;
    }

    emit logMessage(QStringLiteral("[夸父] 启动线程 文件=%1 范围=[%2-%3] 源=%4")
                        .arg(file->localName)
                        .arg(th->downloadStart).arg(th->downloadEnd)
                        .arg(th->sourceUrl));

    launchWorker(th, file);
    return th;
}

std::shared_ptr<DownloadThread> FileDownloader::tryAddThread(
    std::shared_ptr<FileDownload> file)
{
    if (file->fileSize <= 0 || file->isNoSplit || file->threads.isEmpty()) return nullptr;

    std::shared_ptr<DownloadThread> maxPiece;
    qint64 maxUndone = 0;
    for (auto& t : file->threads) {
        if (t->state >= 3) continue;
        qint64 u = t->downloadUndone();
        if (u > maxUndone) { maxUndone = u; maxPiece = t; }
    }
    if (!maxPiece || maxUndone < 256 * 1024) return nullptr;   // 主流启动器 FilePieceLimit=256KB

    qint64 splitPoint = maxPiece->downloadEnd - static_cast<qint64>(maxUndone * 0.4);
    // 只能在「尚未发出的请求」区间里切（2026-11-17）：
    // requestedEnd 之后才是还没下发的字节，切到这里新线程与在途请求零重叠。
    {
        // 本函数由 managerTick 调用，而 managerTick 全程持有 m_filesMutex ——
        // 这里再加锁就是同一线程二次加锁（非递归 QMutex）= 死锁。
        const qint64 reqEnd = maxPiece->requestedEnd.loadRelaxed();
        // requestedEnd 还是 0 = 该线程**还没发出第一个请求**：此刻切它没有任何安全点
        //（切完它才发请求，请求终点就可能越过新边界 → 又是多余字节）。
        // 直接放弃本次切分，下一拍（50ms）worker 已登记后再切。
        // 实测：不加这条会出现一次 8MB 满窗口的超额（1.21.4.jar 超额 4,141,056）。
        if (reqEnd <= maxPiece->downloadStart) return nullptr;
        if (splitPoint < reqEnd) splitPoint = reqEnd;
        // 未请求尾部太小就不切（等下次；宁可少一个线程，也不下多余字节）
        if (maxPiece->downloadEnd - splitPoint < kMinSplitPieceBytes) return nullptr;
    }

    // Pick a healthy source
    // ── 主流启动器语义：顺序 fallback（源 0 起）+ 镜像禁止分片 ──
    // BMCLAPI 等镜像：主流启动器 明确不分片（TryBeginThread 对 bmclapi 返回 Nothing），
    // 镜像单连接下载 + 限速请求频率（防镜像限流）。分片仅限官方源。
    int sourceIdx = 0;
    for (int i = 0; i < file->orderedSources.size(); ++i) {
        // 主流启动器 GetSource：跳过已禁用源（per-file FailCount>=5）
        if (i < file->sourceFailCounts.size() && file->sourceFailCounts[i] >= 5)
            continue;
        QString host = extractHost(file->orderedSources[i]);
        if (hostCanAccept(host)) { sourceIdx = i; break; }
        if (i == file->orderedSources.size() - 1) { sourceIdx = i; } // last resort
    }
    // 镜像禁止分片（主流启动器：当前选中源是镜像则不分片）——在选中源之后判断
    if (isMirrorUrl(file->orderedSources[sourceIdx]))
        return nullptr;

    // Source selection log (sampled per 20 addition threads)
    static int s_addSrcLogCtr = 0;
    if (sourceIdx > 0 || (++s_addSrcLogCtr % 20 == 0)) {
        qCInfo(logDownload) << QStringLiteral("[夸父] [调度] 附加源选择 file=%1 host=%2")
            .arg(file->localName, extractHost(file->orderedSources[sourceIdx]));
    }

    auto th = std::make_shared<DownloadThread>();
    th->uuid = m_nextUuid.fetchAndAddRelaxed(1);
    th->downloadStart = splitPoint;
    th->downloadEnd = maxPiece->downloadEnd;
    th->sourceUrl = file->orderedSources[sourceIdx];
    maxPiece->downloadEnd = splitPoint;
    // 关键（2026-11-17）：上面只改了内存里的终点，**已经发出去的 HTTP 请求改不了**。
    // 不改就等服务器把旧范围发完 → 超出新范围的那段被丢弃，同时新线程又下一遍
    //（实测 icu4j 15.1MB 被下了 22.6MB = 1.49 倍，见日志「截断多余数据 / 超额止损」）。
    // 置位后 worker 会立刻 abort 在途请求，用缩小后的 Range 重发，已收字节不重下。
    maxPiece->rangeShrunk.storeRelaxed(1);

    // 分片细节：一次下载可能几百个分片，逐条 Info 会把日志刷爆（实测 8000 行/日）
    qCDebug(logDownload) << QStringLiteral("[夸父] 附加线程 线程号=%1 文件=%2 偏移=%3")
                            .arg(th->uuid).arg(file->localName).arg(splitPoint);

    file->threads.append(th);
    m_activeThreads.fetchAndAddRelaxed(1);

    {
        QString host = extractHost(th->sourceUrl);
        QMutexLocker lock(&m_hostMutex);
        m_hostStats[host].activeRequests++;
    }

    launchWorker(th, file);
    return th;
}

// ═════════════════════════════════════════════════════════════════════════════
// trySplitSlowThread — 尾程慢速分片（2026-08-05）
// ═════════════════════════════════════════════════════════════════════════════

std::shared_ptr<DownloadThread> FileDownloader::trySplitSlowThread(
    std::shared_ptr<FileDownload> file, std::shared_ptr<DownloadThread> th)
{
    if (file->fileSize <= 0 || file->isNoSplit || file->threads.isEmpty()) return nullptr;
    if (th->state != 2) return nullptr;
    const qint64 undone = th->downloadUndone();
    // 剩余不足两倍最小粒度（32KB×2）不再切——保证切出的两半都 ≥32KB，
    // 避免无限细分产生碎片分片
    if (undone < 2 * kMinSplitPieceBytes) return nullptr;
    // ── 2026-11-20：慢速切分的最低粒度提到 512KB ──
    // 现场：client.jar 被切出 55,733 字节的碎片片（[8429568-8485301]），
    // 紧接着原连接被 abort → 「Operation canceled」→ 该文件判失败 → 触发整轮修复。
    // 32KB 的粒度对「慢速切分」太小：切出来的碎片本身没有下载价值，
    // 只是把一条能用的连接干掉。大文件切分至少留 512KB 才有意义。
    if (undone < 2 * 512 * 1024) return nullptr;
    if (m_activeThreads.loadRelaxed() >= m_maxThreads) return nullptr;

    // 源选择（同 tryAddThread：顺序 fallback + 镜像禁止分片）
    int sourceIdx = 0;
    for (int i = 0; i < file->orderedSources.size(); ++i) {
        if (i < file->sourceFailCounts.size() && file->sourceFailCounts[i] >= 5)
            continue;
        QString host = extractHost(file->orderedSources[i]);
        if (hostCanAccept(host)) { sourceIdx = i; break; }
        if (i == file->orderedSources.size() - 1) sourceIdx = i; // last resort
    }
    if (isMirrorUrl(file->orderedSources[sourceIdx]))
        return nullptr;

    // 中点切分，但同样只能落在「已发出请求的终点之后」：
    // 在途请求改不了，切到它前面就是白下再丢。
    qint64 splitPoint = th->downloadEnd - undone / 2;
    {
        const qint64 reqEnd = th->requestedEnd.loadRelaxed();
        if (reqEnd <= th->downloadStart) return nullptr;   // 首个请求还没登记
        if (splitPoint < reqEnd) splitPoint = reqEnd;
        if (th->downloadEnd - splitPoint < kMinSplitPieceBytes) return nullptr;
    }
    if (splitPoint <= th->downloadStart) return nullptr;

    auto nth = std::make_shared<DownloadThread>();
    nth->uuid = m_nextUuid.fetchAndAddRelaxed(1);
    nth->downloadStart = splitPoint;
    nth->downloadEnd = th->downloadEnd;
    nth->sourceUrl = file->orderedSources[sourceIdx];
    th->downloadEnd = splitPoint;

    file->threads.append(nth);
    m_activeThreads.fetchAndAddRelaxed(1);

    {
        QString host = extractHost(nth->sourceUrl);
        QMutexLocker lock(&m_hostMutex);
        m_hostStats[host].activeRequests++;
    }

    qCInfo(logDownload) << QStringLiteral("[夸父] 慢速分片 文件=%1 线程=%2 剩余=%3 切分点=%4 新片=[%5-%6] 源=%7")
        .arg(file->localName).arg(th->uuid).arg(undone).arg(splitPoint)
        .arg(nth->downloadStart).arg(nth->downloadEnd)
        .arg(extractHost(nth->sourceUrl));

    launchWorker(nth, file);

    // 中止老分片连接：原请求还在按旧 range 龟速流（不中止则分片白切——
    // 老线程要等整条旧响应流完才截断）。置标志由 worker 轮询自己 abort，
    // 重试时以缩小后的范围换新连接（有机会命中快边缘）。预算防止 attempt
    // 耗尽（每线程最多 kMaxWatchdogAborts 次）。
    if (th->watchdogAbortCount < kMaxWatchdogAborts) {
        th->watchdogAbortCount++;
        th->watchdogAbort.storeRelaxed(1);
    }
    return nth;
}

class DownloadWorker : public QRunnable {
public:
    FileDownloader* self = nullptr;
    std::shared_ptr<DownloadThread> th;
    std::shared_ptr<FileDownload> file;

    void run() override {
        if (!self) return;
        self->runWorker(th, file);
    }
};

void FileDownloader::launchWorker(std::shared_ptr<DownloadThread> th,
                                   std::shared_ptr<FileDownload> file)
{
    auto* worker = new DownloadWorker();
    worker->setAutoDelete(true);
    worker->self = this;
    worker->th = th;
    worker->file = file;
    m_threadPool.start(worker);
}

void FileDownloader::runWorker(std::shared_ptr<DownloadThread> th,
                                std::shared_ptr<FileDownload> file)
{
    th->state = 1;
    th->lastReceiveTime = getElapsedMs();

    // URL 必须是最后一个 arg：QString::arg 对替换文本中的 %N 递归处理，
    // URL 含 %2B 等编码时会被后续 .arg() 破坏（2026-08-02 实测日志错乱）
    qCDebug(logDownload) << QStringLiteral("[夸父] 开始下载 文件=%2 偏移=%3 URL=%1")
                            .arg(file->localName).arg(th->downloadStart).arg(th->sourceUrl);

    if (!ShadowLauncher::suppressUrlLog())
        emit logMessage(QStringLiteral("[夸父] 开始下载 %1 源=%2").arg(file->localName).arg(th->sourceUrl));

    // ── 线程局部 QNAM（契约 S1：传输层收敛）──
    // QNetworkAccessManager 是"可重入但不线程安全"的：不能跨线程共享一个实例。
    // 但旧实现是"每个 worker 每次 runWorker（= 每个文件）新建一个" ——
    // 连接池、DNS 缓存、Cookie、代理配置全部随之作废，同一线程下连续下载 N 个文件
    // 就要重建 N 次 TCP/TLS 握手（这是"十几兆/s 却慢"的隐性来源之一）。
    // 现在改成 thread_local：每个 QThreadPool 线程一个、跨文件复用；线程安全边界不变。
    QNetworkAccessManager& mgr = *workerQnam();

    bool sourceOk = false;
    bool modRetriedOnce = false;   // 模组专项：全部源耗尽后重置源列表整体重试一轮（PCL Retried 同款）
    for (int sourceIdx = 0; sourceIdx < file->orderedSources.size() && !sourceOk; ++sourceIdx) {
        if (m_cancelled.loadRelaxed()) goto cleanup;
        waitWhilePaused();   // 暂停中不发起新请求；cancel 可打断等待
        if (m_cancelled.loadRelaxed()) goto cleanup;

        QString url = file->orderedSources[sourceIdx];
        th->sourceUrl = url;

        if (sourceIdx > 0)
            qCInfo(logDownload) << QStringLiteral("[夸父] 切换到镜像%1 URL=%2").arg(sourceIdx + 1).arg(url);

        sourceOk = false;
        qint64 startTimeMs = getElapsedMs();
        // 镜像限速（主流启动器语义）：只要是 BMCLAPI 等镜像源就限速 100ms
        //（无论是否为首选源——镜像优先设置时源 0 也是镜像），
        // 防镜像源高频请求限流（403/429）。主流启动器: TryBeginThread 对
        // bmclapi sleep 100ms。
        if (isMirrorUrl(url))
            QThread::msleep(100);
        // 模组专项：重置重试轮每源仅 1 次尝试（PCL「逐个重新尝试下载」语义）
        const int attemptLimit = modRetriedOnce ? 1 : 6;
        int rateLimitHits = 0;   // 本源 429/503 命中次数（上限 5，防止"永远 429"把线程锁死）
        bool prevWatchdogAbort = false;   // 上一次尝试是否因看门狗中止（跳过快速失败守卫）
        // 连续「超时且零字节进展」次数（2026-11-19）：用于快速换源，
        // 见下方守卫注释（旧守卫要求 elapsed<5500，而一次超时就有 12s，永不成立）。
        int consecutiveTimeouts = 0;
        int slowAbortCount = 0;   // 本线程「龟速」放弃次数（2026-11-20）
        for (int attempt = 0; attempt < attemptLimit && !sourceOk; ++attempt) {
            if (m_cancelled.loadRelaxed()) goto cleanup;
            waitWhilePaused();
            if (m_cancelled.loadRelaxed()) goto cleanup;
            bool watchdogAbortedThisAttempt = false;   // 本次尝试被看门狗中止
            bool rangeFilled = false;                    // 本线程范围已收满（超额止损 abort，数据完整）
            QByteArray rangeData;                        // 止损前 readAll 保存的已接收数据（abort 会清空缓冲！）

            int timeoutMs;
            // ── 自适应超时（主流启动器语义）──
            // 主流启动器: Timeout = min(max(ConnectAverage,15000)×(1+FailCount), 30000)
            // 基础 12s（官方 CDN 正常 1-2s 首字节），连续失败次数越多超时越长
            // （上限 30s）——避免死等也避免误杀慢速但存活的连接。
            // setTransferTimeout 是“无数据超时”，持续下载的文件不受影响。
            const bool isOfficialUrl = url.contains("mojang.com") || url.contains("minecraft.net");
            {
                QString host = extractHost(url);
                int fails = 0;
                {
                    QMutexLocker hlock(&m_hostMutex);
                    auto it = m_hostStats.find(host);
                    if (it != m_hostStats.end())
                        fails = it->consecutiveFails;
                }
                const qint64 base = isOfficialUrl ? 12000 : 15000;
                timeoutMs = static_cast<int>(qMin(base * (1 + qMin(fails, 3)), 12000LL));
            }
            // ── 2026-11-19 修正「快速失败守卫形同虚设」──
            // 旧条件要求 (elapsed < 5500ms)，但单次超时本身就有 12s，
            // 所以 attempt 到 2/5 时 elapsed 恒 >12000 → 两个守卫永不成立 →
            // 同一个源被死磕满 5 次（=60s）。现场：jna-platform-5.17.0.jar
            // 连续 5 次 12.5s 超时，白付 43 秒，用户看到「卡 99%」。
            // 现在：只要「本次是超时、且没有任何字节进展」，连续 2 次就直接换源。
            if (consecutiveTimeouts >= 2 && !prevWatchdogAbort) {
                qCWarning(logDownload) << QStringLiteral("[夸父] 连续 %1 次超时且零进展，放弃本源换源 文件=%2")
                    .arg(consecutiveTimeouts).arg(file->localName);
                if (sourceIdx < file->sourceFailCounts.size())
                    file->sourceFailCounts[sourceIdx] = 5;   // 触发换源判定
                break;
            }
            if (attempt > 0) QThread::msleep(kRetryBackoffMs);

            QNetworkRequest req{QUrl(url)};
            req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
            if (m_modpackMode) {
                // 模组专项：禁 H2（MCIM 镜像对 QNAM H2 连接不稳定，实测 Connection closed）；
                // 请求原始编码（Qt QNAM 无自动 gzip 解压，发 gzip 头会致 SHA1 不符）
                req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
                req.setRawHeader("Accept-Encoding", "identity");
            }
            req.setTransferTimeout(timeoutMs);
            req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                             QNetworkRequest::NoLessSafeRedirectPolicy);
            // HTTP/1.1 connection pooling
            {
                QHttp1Configuration h1cfg;
                h1cfg.setNumberOfConnectionsPerHost(255);
                req.setHttp1Configuration(h1cfg);
            }

            // 本次尝试的续传基线：downloadDone 已是「线程内已落盘/已收」的字节数。
            // 服务器对每个 reply 的 received 都从 0 起算，所以进度回调里要加回这个基线，
            // 否则断点重发会被算成"负增量"，把 downloadDone 冲小（旧代码不支持续传的根因）。
            const qint64 attemptBase = th->downloadDone;
            // 本轮已把范围缩小过（切分）：先清标志，本次用缩小后的终点
            th->rangeShrunk.storeRelaxed(0);

            if (!file->isUnknownSize && !file->isNoSplit) {
                const qint64 start = th->downloadStart + attemptBase;
                // ── 有界窗口（2026-11-17）──
                // 关键：一次只请求「窗口」这么多，而不是整个剩余区间。
                // 这样「还没请求的尾部」始终存在，切分可以在那里安全进行，
                // 永远不会出现「已发出请求的终点被改小 → 多余字节被丢弃」。
                qint64 reqEndExcl = th->downloadEnd;
                const qint64 cap = start + DownloadThread::kRequestWindowBytes;
                if (reqEndExcl > cap) reqEndExcl = cap;
                // ⚠ 这里绝不能锁 m_filesMutex：managerTick 在切分时**全程持有**该锁，
                // 且 worker 是它启动的 —— 再取一次就是自锁/互锁（实测：日志停在
                // 「所有文件已启动首线程」后 47 秒零输出，jar 全部没落地）。
                // requestedEnd 是原子量，登记即生效；万一登记与切分交错，
                // rangeShrunk 兜底会中止重发，最多损失一个突发。
                if (reqEndExcl > th->downloadEnd) reqEndExcl = th->downloadEnd;
                th->requestedEnd.storeRelaxed(reqEndExcl);
                const qint64 end = reqEndExcl - 1;
                req.setRawHeader("Range", QString("bytes=%1-%2").arg(start).arg(end).toUtf8());
            }

            // ── 2026-11-20：单次尝试的「最低吞吐」兜底计时 ──
            // 现场：修复阶段从 bmclapi 下 client.jar，单次 attempt 跑了 129 秒只收
            // 1.5MB（11KB/s），另一次 145 秒收 0 字节才超时。原因是空闲超时
            // （QTimer 与 Qt 的 transferTimeout）都被 readyRead 续命——
            // 只要对端偶发滴一个字节，就永远不会判超时；而镜像源在
            // trySplitSlowThread 里被显式排除（isMirrorUrl → return nullptr），
            // 连尾程看门狗都不会来救。结果就是「看起来卡死、其实在龟速滴」。
            const qint64 attStart = getElapsedMs();
            bool slowAbort = false;
            QNetworkReply* reply = mgr.get(req);

            QEventLoop loop;
            QTimer timeout;
            timeout.setSingleShot(true);
            bool timedOut = false;
            // ── 2026-11-19：超时归因（只做诊断，不改行为）──
            // 现场：jna-platform-5.17.0.jar（1.3MB）连续 5 次「12s 超时」，
            // 而同一 URL 用 curl 三次全部 1.4~1.7s 下完 —— 说明对端没问题，
            // 是我们的请求在某处被卡住。要区分「请求没被服务端处理」和
            // 「有响应头但没 body」，必须在超时那一刻记录这两个事实。
            bool metaSeen = false;
            qint64 bytesSeen = 0;
            connect(reply, &QNetworkReply::metaDataChanged,
                    [&metaSeen]() { metaSeen = true; });

            connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
            connect(&timeout, &QTimer::timeout, [&]() { timedOut = true; loop.quit(); });
            // ── 无数据超时（主流启动器语义，2026-08-05 修正）──
            // 所有模式统一：每次收到数据包重置超时计时器——有数据持续传输的
            // 大文件不被固定超时误杀（主流启动器: 传输阶段取消固定超时，靠速度监控；
            // 无数据超过 Timeout 才断开）。旧实现 MC 模式 QTimer 不随数据重置，
            // 大文件下载中 12s 必被掐断（严重 bug）。
            if (m_modpackMode) {
                // 模组专项：空闲无数据超时——每次收到数据包重置，连续 30s 无数据才断
                timeout.start(kChunkTimeoutMs);
                connect(reply, &QNetworkReply::readyRead, &timeout,
                        [&timeout]() { timeout.start(kChunkTimeoutMs); });
            } else {
                timeout.start(timeoutMs);
                connect(reply, &QNetworkReply::readyRead, &timeout,
                        [&timeout, timeoutMs]() { timeout.start(timeoutMs); });
            }

            qint64 lastProgressEmitMs = getElapsedMs();

            connect(reply, &QNetworkReply::downloadProgress,
                    [&](qint64 received, qint64 total) {
                // 取消/暂停后不得再计字节、发进度（契约 §5：回调早退）
                if (m_cancelled.loadRelaxed() || m_paused.loadRelaxed()) return;
                // 线程内绝对已收 = 本次尝试续传基线 + 本 reply 收到的字节
                bytesSeen = received;
                const qint64 absReceived = attemptBase + received;
                qint64 delta = absReceived - th->downloadDone;
                if (delta > 0) {
                    // 限速真正作用于传输层：阻塞本 worker 读取 → TCP 反压
                    applySpeedLimit(delta, &th->rangeShrunk);
                    // 限速 sleep 期间可能被取消/暂停打断：醒来后再确认一次，绝不写统计
                    if (m_cancelled.loadRelaxed() || m_paused.loadRelaxed()) return;
                    // 限速 sleep 会阻塞本线程事件循环：醒来后重置空闲超时，避免被自己的限速误杀
                    timeout.start(m_modpackMode ? kChunkTimeoutMs : timeoutMs);
                    // 首包数据到达 → 线程进入 downloading（state 2）。
                    // 分片调度（managerTick Phase2）以 state<2=prep / state==2=dl 判断
                    // 是否可加片——6129062 基线仅模组模式置 state=2，MC 模式 prep>dl 恒成立
                    // 导致 MC >50MB 文件分片永不触发（分片机制对 MC 是死代码）。
                    // 豁免保留：放开为通用；模组路径行为与基线一致（基线模组本就置 state=2）。
                    if (th->state == 1) th->state = 2;
                    // 封顶到线程范围：服务器返回超范围数据（200 全文件/超大 206）时，
                    // received 会超过线程的 downloadEnd——downloadDone 若虚高，
                    // file->totalDone() 也会虚高 → 步骤进度提前满（用户实测：MC 未
                    // 下载完子步骤就显示 completed）。封顶后进度只反映真实分片部分。
                    const qint64 thMax = th->downloadEnd - th->downloadStart;
                    qint64 realDelta = delta;
                    if (thMax > 0 && th->downloadDone + delta > thMax)
                        realDelta = qMax<qint64>(0, thMax - th->downloadDone);
                    m_downloadedBytes.fetchAndAddRelaxed(realDelta);
                    th->downloadDone = qMin(absReceived, thMax > 0 ? thMax : absReceived);
                    // 主流启动器语义：收到数据重置源失败计数（FailCount=0）——
                    // 偶发失败不累计，避免误伤正常源
                    if (sourceIdx < file->sourceFailCounts.size())
                        file->sourceFailCounts[sourceIdx] = 0;
                }
                th->lastReceiveTime = getElapsedMs();
                qint64 now = getElapsedMs();
                if (now - lastProgressEmitMs >= kProgressEmitThrottleMs) {
                    lastProgressEmitMs = now;
                    emit progressChanged(m_completedFiles.loadRelaxed(), m_totalFiles.loadRelaxed(),
                                          m_downloadedBytes.loadRelaxed(), m_totalBytes.loadRelaxed());
                    // 与 progressChanged 同节奏节流：高并发（模组 12 路 + MC 64 路）下
                    // 每个数据包都跨线程 emit 会灌爆主线程事件队列 → UI 卡死无响应。
                    // ── 文件总进度（2026-08-05 修复）──
                    // 多分片文件：received 是“该分片线程的接收量”（从 Range 起始算），
                    // 多个分片各自报 received —— 上层按 savePath 去重只累计第一个分片
                    // → 大文件进度缺失（用户实测：支持库 40% 后失真）。
                    // 改为上报文件级总进度：received=所有分片累计下载量，total=文件大小。
                    const qint64 fileDone = file->totalDone();
                    const qint64 fileTotal = (file->fileSize > 0) ? file->fileSize : total;
                    emit fileProgress(th->sourceUrl, file->localName, fileDone, fileTotal, file->localPath);
                }

                // ── 超额止损（2026-08-07）──
                // 根因：tryAddThread 加速切分只缩小 th->downloadEnd，in-flight 请求仍按
                // 旧 range 拉数据（首线程请求全文件被切分后服务器仍发完整文件）→
                // worker 等整条旧响应收完再截断，超额浪费实测 178%（1261MB/707MB）。
                // 主流启动器 对照（ModNet.vb）：流式边收边写，DownloadUndone=0 即 Exit While
                // 断开连接——收满即停，不多收一字节。此处 206 响应已收满本线程范围
                // （received >= downloadEnd-downloadStart）→ 立即 abort 止损；
                // 数据前缀完整（截断写盘逻辑会裁剪到范围），不丢进度、不需重试。
                // 200 全文件响应（isFullFile 优化）不触发：respStatus==200 走整文件逻辑。
                // 条件用严格大于（received > thRange）：正常未切分的 206 响应 received 恰好
                // == thRange（收满即自然结束），不应走 abort 路径；只有服务器按旧 range
                // 超发（received 超出当前范围）才止损（2026-08-07 复查修正）。
                // ⚠️ 关键：必须在 abort 前 readAll 保存数据——实测 QNetworkReply::abort()
                // 会清空未读缓冲，abort 后 readAll() 返回 0（慢速分块场景实测 FAIL，
                // 2026-08-07 本地 FDTest 只合并出 916KB/12MB 的根因）；abort 前 readAll
                // 能拿到全部已接收字节（== received，实测 PASS）。
                const int respStatus206 = reply->attribute(
                    QNetworkRequest::HttpStatusCodeAttribute).toInt();
                if (!rangeFilled && respStatus206 == 206
                    && !file->isUnknownSize && !file->isNoSplit) {
                    const qint64 thRange = th->downloadEnd - th->downloadStart;
                    // ── 范围被主线程切分缩小（2026-11-17）──
                    // 立刻停手：把已收的前缀留下，用缩小后的 Range 重发。
                    // 这样「旧范围多出来的那段」一个字节都不会落到网卡上。
                    if (th->rangeShrunk.loadRelaxed()) {
                        rangeFilled = true;
                        rangeData = reply->readAll();
                        qCInfo(logDownload) << QStringLiteral("[夸父] 范围缩小，重发 文件=%1 新段=%2..%3 已收=%4")
                            .arg(file->localName).arg(th->downloadStart + attemptBase)
                            .arg(th->downloadStart + thRange).arg(rangeData.size());
                        reply->abort();
                        loop.quit();
                    } else if (thRange > 0 && absReceived > thRange) {
                        rangeFilled = true;
                        rangeData = reply->readAll();   // abort 前先取出已收数据
                        qCInfo(logDownload)
                            << QStringLiteral("[夸父] 超额止损 文件=%1 起始=%2 范围=%3 已收=%4 已读=%5")
                                   .arg(file->localName).arg(th->downloadStart).arg(thRange)
                                   .arg(absReceived).arg(rangeData.size());
                        reply->abort();
                        loop.quit();
                    }
                }
            });

            // ── 尾程看门狗轮询（2026-08-05）──
            // 主线程慢速扫描可能置 th->watchdogAbort 请求中止当前连接：
            // 切分后让本线程以缩小后的范围重试（换新连接，有机会命中快边缘）。
            // worker 自己 abort 自己的 reply（线程安全），不跨线程碰 QNetworkReply。
            QTimer watchdogPoll;
            watchdogPoll.setSingleShot(true);
            connect(&watchdogPoll, &QTimer::timeout, [&]() {
                if (th->watchdogAbort.fetchAndStoreRelaxed(0)) {
                    watchdogAbortedThisAttempt = true;
                    reply->abort();
                    loop.quit();
                    return;
                }
                // ── 2026-11-20：单次尝试的最低吞吐兜底 ──
                // 必须挂在**定时器**上，不能挂在 downloadProgress 里：
                // 现场 fastutil-8.5.18.jar 静默 115 秒（11:18:48 → 11:20:43）才完成，
                // 期间既没有超时也没有进度回调——挂在数据回调上的检查永远不会被触发。
                // 判据：本次尝试已过 20 秒且平均 < 24KB/s → 放弃这次连接。
                // 这样「偶发滴一个字节续命空闲超时」的连接也会被掐掉换源。
                const qint64 el = getElapsedMs() - attStart;
                // 只统计**本次尝试**已收到的字节（reply 未读缓冲单调增长，
                // 不掺 downloadDone，避免跨 attempt 记账污染判据）
                const qint64 gotNow = reply->bytesAvailable();
                // ① 起步就停：20 秒还没收到 4MB 且均值 <24KB/s → 掐掉换连接。
                //    4MB 门槛保证「慢但真在跑」的连接（1MB/s 时 20s 已有 20MB）不被误杀。
                //    ⚠️ 现场：bmclapi 的 client.jar 单次 attempt 跑到 141 秒、已收 0B，
                //    空闲超时被 302 重定向的 readyRead 反复续命 → 必须有这条兜底。
                const bool stalledStart = (el >= kSlowAttemptWindowMs
                                           && gotNow < 4LL * 1024 * 1024
                                           && gotNow * 1000 / qMax<qint64>(1, el) < kSlowAttemptMinBps);
                // ② 单次尝试硬上限：超过 45 秒一律放弃（我们有续传，重来不亏）
                const bool overWall = (el >= kMaxAttemptWallMs);
                if (stalledStart || overWall) {
                    slowAbort = true;
                    qCWarning(logDownload)
                        << QStringLiteral("[夸父] 放弃本次尝试（%1）文件=%2 收=%3B 用时=%4ms")
                               .arg(overWall ? QStringLiteral("超过单次上限") : QStringLiteral("龟速"))
                               .arg(file->localName).arg(gotNow).arg(el);
                    reply->abort();
                    loop.quit();
                    return;
                }
                watchdogPoll.start(500);
            });
            watchdogPoll.start(500);

            // Register reply for thread-safe abort on cancel
            // QMetaObject::invokeMethod("abort", QueuedConnection) from the main
            // thread triggers reply->abort() on THIS worker thread (the owner).
            addInFlightReply(reply);
            // 注册与 cancel/pause 的竞态兜底：若旗标已置位，排队中止。
            // 必须走 QueuedConnection：abort() 可能同步 emit finished()，
            // 若在 loop.exec() 之前同步触发，quit() 会丢失 → 卡到超时。
            if (m_cancelled.loadRelaxed() || m_paused.loadRelaxed())
                QMetaObject::invokeMethod(reply, "abort", Qt::QueuedConnection);

            // NOTE: QTimer cancelGuard is NOT used here — QThreadPool threads
            // have no event dispatcher, so QTimer never fires. Instead we rely on:
            //   1. addInFlightReply() + cancel() queuing abort() to this thread
            //   2. loop.exec() returning when reply finishes (naturally or aborted)
            //   3. The m_cancelled check below to discard data if cancelled

            loop.exec();

            removeInFlightReply(reply);

            // Cancel check: discard data immediately if cancelled
            if (m_cancelled.loadRelaxed()) {
                reply->abort();
                reply->deleteLater();
                goto cleanup;
            }

            // ── 暂停：在途请求已被 pause() abort → 丢弃本 attempt 数据，原地等待恢复后整段重下 ──
            // 数据只在成功收尾时写盘，本 attempt 尚未写盘；恢复后从 downloadStart 重下该范围。
            // 暂停不消耗重试次数（--attempt 后循环 ++ 回到同一 attempt）。
            if (m_paused.loadRelaxed() && !rangeFilled
                && reply->error() != QNetworkReply::NoError) {
                reply->abort();
                reply->deleteLater();
                th->downloadDone = 0;
                th->state = 0;            // 回到等待态：恢复后重新计下载量
                waitWhilePaused();
                if (m_cancelled.loadRelaxed()) goto cleanup;
                // 暂停不计入快速失败窗口：恢复后重新起算
                startTimeMs = getElapsedMs();
                // 回到同一 attempt（0 → -1 → 循环 ++ 仍为 0）
                --attempt;
                continue;
            }

            // ── 429 / 503：服务端限流（契约 §6 第三层：按 Retry-After 退避）──
            // 旧实现完全不看 HTTP 状态：429 被当成普通失败，退避固定 500ms，且计入
            // 源失败次数 → 越重试越被禁用（实测镜像在高峰期的"越下越慢/越下越死"）。
            if (!rangeFilled) {
                const int httpStatus = reply->attribute(
                    QNetworkRequest::HttpStatusCodeAttribute).toInt();
                if (httpStatus == 429 || httpStatus == 503) {
                    const int waitSec = qBound(1, retryAfterSeconds(reply, httpStatus == 429 ? 2 : 1), 10);
                    qCWarning(logDownload)
                        << QStringLiteral("[夸父] 服务端限流 %1 URL=%2 Retry-After=%3s（本源退避后重试，不计失败）")
                               .arg(httpStatus).arg(url).arg(waitSec);
                    reply->abort();
                    reply->deleteLater();
                    th->downloadDone = 0;
                    // 退避等待（分片 100ms，取消/暂停可打断）
                    for (int slice = 0; slice < waitSec * 10; ++slice) {
                        if (m_cancelled.loadRelaxed()) goto cleanup;
                        if (m_paused.loadRelaxed()) break;   // 暂停：跳出退避，交给暂停路径
                        QThread::msleep(100);
                    }
                    if (m_cancelled.loadRelaxed()) goto cleanup;
                    // 上限保护：某源连续 5 次限流 → 视为该源不可用，换下一个源；
                    // 否则"永远 429"会让 --attempt 无限循环（线程永不返回）。
                    if (++rateLimitHits > 5) {
                        qCWarning(logDownload)
                            << QStringLiteral("[夸父] 源持续限流，放弃本源 URL=%1（已退避 5 次）").arg(url);
                        if (sourceIdx < file->sourceFailCounts.size())
                            file->sourceFailCounts[sourceIdx]++;
                        th->downloadDone = 0;
                        break;
                    }
                    if (m_paused.loadRelaxed()) { --attempt; continue; }
                    --attempt;   // 限流不消耗尝试次数（否则高峰期 6 次重试全打在限流上）
                    continue;
                }
            }

            // 慢速中止：不算对端失败，但每次消耗预算；超预算直接换源（否则
            // 「滴 bytes」的源会把整个下载拖成几分钟）。
            if (slowAbort && !rangeFilled) {
                reply->abort();
                reply->deleteLater();
                th->downloadDone = 0;
                if (++slowAbortCount > kMaxSlowAborts) {
                    qCWarning(logDownload) << QStringLiteral("[夸父] 源持续龟速，放弃本源 文件=%1")
                        .arg(file->localName);
                    if (sourceIdx < file->sourceFailCounts.size())
                        file->sourceFailCounts[sourceIdx] = 5;
                    break;
                }
                continue;
            }

            // 超额止损（2026-08-07）：主动 abort 不算失败——数据已收满本线程范围，
            // 跳过失败分支直接进入成功收尾（rangeData 是 abort 前 readAll 保存的缓冲，
            // 截断写盘逻辑会裁剪到当前范围）。
            if (rangeFilled) {
                // 数据完整（>= 本线程范围），不重试、不计 FailCount
            } else if (timedOut || reply->error() != QNetworkReply::NoError) {
                qCWarning(logDownload) << QStringLiteral("[夸父] 请求失败 URL=%1 错误=%2 重试=%3 | 归因: 响应头=%4 已收=%5B 耗时=%6ms 状态=%7")
                    .arg(url, timedOut ? QStringLiteral("超时") : reply->errorString())
                    .arg(attempt + 1)
                    .arg(metaSeen ? QStringLiteral("有") : QStringLiteral("无"))
                    .arg(bytesSeen)
                    .arg(getElapsedMs() - startTimeMs)
                    .arg(reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt());
                if (timedOut && bytesSeen == 0) ++consecutiveTimeouts;
                else consecutiveTimeouts = 0;
                reply->abort();
                reply->deleteLater();
                // ── 2026-11-19：超时且连响应头都没收到 → 清掉该线程 QNAM 的连接缓存 ──
                // 现场证据（4 轮定向复现，第 2 轮）：同一个 1.3MB 小文件连续 5 次
                // 「12s 超时」，归因显示**响应头=无、已收=0B**；而同一 URL 用 curl
                // 连发 3 次全部 200、1.4~1.7 秒下完（含 8 条并发 Range 也全 206）。
                // 既然对端正常、我们却连响应头都拿不到，最可能就是这条 QNAM 的连接池里
                // 躺着一条「半死」连接（对端已关、本地未感知），请求全排上去干等。
                // workerQnam() 是 thread_local 跨文件复用，重试又落回同一线程 → 同一条坏连接。
                // 超时时清缓存，强制下一条请求重新建连。
                if (timedOut && !metaSeen) {
                    mgr.clearConnectionCache();
                    qCWarning(logDownload) << QStringLiteral("[夸父] 超时无响应头，已清空连接缓存（强制重建连接） 文件=%1")
                        .arg(file->localName);
                }
                // ── 看门狗中止（2026-08-05）──
                // 慢速分片后的策略性换连接：不算失败（不累计 FailCount）、
                // 跳过快速失败守卫，直接以缩小后的范围换新连接重试。
                if (watchdogAbortedThisAttempt) {
                    watchdogAbortedThisAttempt = false;
                    prevWatchdogAbort = true;
                    // ── 2026-11-19：中止前把已收字节救回来 ──
                    // 旧代码直接 downloadDone = 0：本次 attempt 收的几 MB 全部丢掉，
                    // 下次从 downloadStart 重新下。慢速连接被看门狗切分后，
                    // 「切一次丢一次、丢了再慢」互为因果 —— 越切越慢。
                    // 现在保持 downloadDone（它就是续传基线：请求从
                    // downloadStart + attemptBase 起发），切分只缩小终点，前缀不重下。
                    continue;
                }
                prevWatchdogAbort = false;
                // ── 主流启动器 SourceFail 语义 ──
                // 同一源失败累计（FailCount）达标（≥5 且无下载进度）才禁用该源换下一个；
                // 未达标则同源继续重试（主流启动器: FailCount ≥ min(ThreadLimit,5~30) 且
                // DownloadDone<1 → IsFailed）。模组模式：网络错误立即换源（历史实测）。
                if (sourceIdx < file->sourceFailCounts.size())
                    file->sourceFailCounts[sourceIdx]++;
                if (m_modpackMode) {
                    th->downloadDone = 0;
                    break;
                }
                const bool hasProgress = (th->downloadDone > 0);
                const int failCount = (sourceIdx < file->sourceFailCounts.size())
                    ? file->sourceFailCounts[sourceIdx] : attempt + 1;
                // 主流启动器: FailCount ≥ 5 且无进度 → 禁用此源，换下一个
                if (!hasProgress && failCount >= 5) {
                    qCInfo(logDownload) << QStringLiteral("[夸父] 源禁用(连续失败) 文件=%1 源=%2 URL=%3")
                        .arg(file->localName).arg(sourceIdx).arg(url);
                    break;
                }
                // 有 SHA1 校验的整文件下载（非分片），重试上限内同源继续
                if (attempt >= 6) break;
                th->downloadDone = 0;
                continue;
            }

            sourceOk = true;
            // 超额止损场景：数据已在 abort 前 readAll 保存到 rangeData（abort 后
            // readAll 返回空——2026-08-07 实测），主流程统一用 rangeData。
            QByteArray data = rangeFilled ? rangeData : reply->readAll();
            qint64 contentLen = reply->rawHeader("Content-Length").toLongLong();
            // 优先用服务器返回的 Content-Length 做预期判断（它才是实际响应体大小）
            // file->fileSize 是 API 解析值，可能偏大（如清华镜像 API 195.6MB 实际 195.0MB）
            qint64 expectedSize = contentLen > 0 ? contentLen : (file->fileSize > 0 ? file->fileSize : 0);
            // 超额止损场景：data 是旧 range 响应的前缀（>= 本线程范围），
            // Content-Length 是旧 range 长度（更大）——跳过完整性检查，
            // 截断写盘逻辑会裁剪到当前范围（2026-08-07）。
            if (!rangeFilled && expectedSize > 0 && data.size() < expectedSize) {
                qCWarning(logDownload) << QStringLiteral("[夸父] 下载数据不完整 URL=%1 预期=%2(Content-Length) 实际=%3")
                    .arg(url).arg(expectedSize).arg(data.size());
                sourceOk = false;
                reply->deleteLater();
                th->downloadDone = 0;
                continue;
            }
            reply->deleteLater();

            // Determine file size on first thread
            // 始终以实际 Content-Length（或收到的数据大小）为准，
            // 修正 addFile 时传入的 expectedSize 可能偏小的问题。
            // 2026-08-02 实测修复：仅响应完整（data.size() >= contentLen）时才更新
            // fileSize/isNoSplit——Modrinth 高峰下首线程可能拿到 404/截断响应
            // （contentLen 偏小），旧逻辑据此把 isNoSplit 翻转为 true → 分片作废
            // + 全量 SHA1 风暴 → 必失败。
            if (th->downloadStart == 0 && data.size() > 0
                && (contentLen <= 0 || data.size() >= contentLen)) {
                qint64 actualSize = contentLen > 0 ? contentLen : data.size();
                // 只允许补差（actualSize > fileSize），不允许缩小：
                // 首线程 split 后响应是分片（206，contentLen=分片大小）——
                // 若用它更新会把 fileSize 缩成分片大小（实测：26.2.jar 39MB
                // 首线程分片 5MB → fileSize 被改成 5MB → 分片/合并混乱 + 后续
                // 请求误判 isNoSplit 无 Range → 全文件 200 超额下载）
                if (actualSize > 0 && actualSize > file->fileSize) {
                    if (file->fileSize > 0) {
                        // API 提供的 expectedSize 小于实际大小，补差
                        m_totalBytes.fetchAndAddRelaxed(actualSize - file->fileSize);
                    } else {
                        // 未知大小的文件，首次发现大小
                        m_totalBytes.fetchAndAddRelaxed(actualSize);
                    }
                    file->fileSize = actualSize;
                    file->isUnknownSize = false;
                    file->isNoSplit = (actualSize < 1LL * 1024 * 1024);   // 主流启动器: <1MB 不分片
                    th->downloadEnd = actualSize;
                } else if (file->fileSize <= 0) {
                    // 未知大小且本次拿到完整响应（200）→ 采用
                    file->fileSize = actualSize;
                    file->isUnknownSize = false;
                    file->isNoSplit = (actualSize < 1LL * 1024 * 1024);
                    th->downloadEnd = actualSize;
                }
            }

            // SHA1 verification for full-download files（只对非分片，放锁外避免长持锁）
            bool isFullDownload = file->isNoSplit || file->isUnknownSize;
            if (isFullDownload && !file->expectedSha1.isEmpty()) {
                const QString dlHash = sha1Hex(data);
                if (dlHash != QString::fromLatin1(file->expectedSha1)) {
                    qCWarning(logDownload) << QStringLiteral("[夸父] SHA1不匹配 URL=%1 预期=%2 实际=%3 (第%4次)")
                        .arg(url).arg(QString::fromLatin1(file->expectedSha1)).arg(dlHash)
                        .arg(attempt + 1);
                    sourceOk = false;
                    th->downloadDone = 0;   // 防续传错位：重试必须从头（2026-08-02 实测修复）
                    if (attempt >= 5) break;
                    continue;
                }
            }

            // ── 截断 + 写盘 + state 更新（与主线程切分互斥）──
            // 竞态修复（2026-08-02 本地 20MB 分片实测发现）：managerTick（主线程）在锁内
            // 切分下载中线程的 downloadEnd，worker 线程此前无锁读 downloadEnd 截断写盘 →
            // 切分与写盘交错时 tempPath 数据基于旧 range，合并后文件缺块/错位。
            // 现整体加 m_filesMutex：锁内读最新 downloadEnd 截断 + 写盘 + state=3。
            bool needMoreData = false;   // 只收到范围的一部分（切分后缩小）→ 续传
            {
                QMutexLocker lock(&m_filesMutex);
                if (!file->isUnknownSize && !file->isNoSplit) {
                    const qint64 threadRange = th->downloadEnd - th->downloadStart;
                    const int respStatusNow = reply->attribute(
                        QNetworkRequest::HttpStatusCodeAttribute).toInt();
                    // 续传基线下本线程还缺多少：data 只含 attemptBase 之后的字节
                    const qint64 want = (threadRange > attemptBase) ? (threadRange - attemptBase) : 0;
                    if (respStatusNow == 200 && file->fileSize > 0 && data.size() >= file->fileSize) {
                        // 服务器忽略 Range 返回全文件（200）：直接用整文件（主流启动器语义）
                        qCInfo(logDownload) << QStringLiteral("[夸父] 服务器返回全文件(忽略Range)，整文件使用 文件=%1 大小=%2")
                            .arg(file->localName).arg(data.size());
                        th->downloadDone = data.size();
                        th->isFullFile = true;
                    } else if (want > 0 && data.size() > want) {
                        const qint64 excess = data.size() - want;
                        const qint64 counted = th->downloadDone;
                        const int respStatus = respStatusNow;
                        qCInfo(logDownload) << QStringLiteral("[夸父] 截断多余数据 文件=%1 起始=%2 预期=%3 实际=%4 超额=%5 状态=%6")
                            .arg(file->localName).arg(th->downloadStart + attemptBase).arg(want).arg(data.size()).arg(excess).arg(respStatus);
                        data = data.left(want);
                        th->downloadDone = attemptBase + data.size();
                consecutiveTimeouts = 0;   // 本 attempt 有数据 → 链路正常，清零（2026-11-19）
                        const qint64 finalDone = th->downloadDone;
                        if (counted > finalDone)
                            m_downloadedBytes.fetchAndAddRelaxed(-(counted - finalDone));
                    } else {
                        th->downloadDone = attemptBase + data.size();
                consecutiveTimeouts = 0;   // 本 attempt 有数据 → 链路正常，清零（2026-11-19）
                    }
                    if (!th->isFullFile && threadRange > 0 && th->downloadDone < threadRange)
                        needMoreData = true;
                }

                if (needMoreData) {
                    // 续传：已收字节写到临时文件的正确偏移，保留给下一次尝试。
                    // 必须 ReadWrite（WriteOnly 会截断，把前面已落盘的进度清掉）。
                    QString tmpDir = QFileInfo(file->localPath).absolutePath() + "/.shadow_temp/";
                    QDir().mkpath(tmpDir);
                    th->tempPath = tmpDir + QString("dl_%1_%2.tmp").arg(file->localName).arg(th->uuid);
                    QFile f(th->tempPath);
                    if (f.open(QIODevice::ReadWrite)) {
                        f.seek(attemptBase);
                        f.write(data);
                        f.close();
                    }
                    th->state = 2;   // 仍在下载，不置 3
                } else {
                    // Write data
                    if (file->isNoSplit) {
                        QFile f(file->localPath);
                        QDir().mkpath(QFileInfo(file->localPath).absolutePath());
                        file->targetWritten = true;   // 直写最终路径：取消后必须删
                        if (f.open(QIODevice::WriteOnly)) { f.write(data); f.close(); }
                    } else {
                        QString tmpDir = QFileInfo(file->localPath).absolutePath() + "/.shadow_temp/";
                        QDir().mkpath(tmpDir);
                        th->tempPath = tmpDir + QString("dl_%1_%2.tmp").arg(file->localName).arg(th->uuid);
                        QFile f(th->tempPath);
                        // 分片线程的临时文件里只放「本线程范围」的字节，从 0 开始写；
                        // 续传场景前面已有 attemptBase 字节，必须 ReadWrite + seek 保留
                        if (f.open(QIODevice::ReadWrite)) {
                            f.seek(attemptBase);
                            f.write(data);
                            f.close();
                        }
                    }
                    th->state = 3;
                }
            }
            if (needMoreData) {
                // 窗口链（本次请求正常结束但线程范围未满）：不占重试预算。
                // 只有「确实收到了新字节」才回退计数，避免服务器返回空包时死循环。
                if (th->downloadDone > attemptBase) { --attempt; }
                // ⚠ 必须把 sourceOk 归零：for 循环条件是 !sourceOk，而上面成功收尾
                // 时已置 true —— 不清掉的话 continue 直接退出整个尝试循环，
                // 线程带着「只下了一个窗口」的数据就结束 → 文件永久不完整
                //（实测：窗口化后校验报 2 个文件缺失/校验失败）。
                sourceOk = false;
                rangeFilled = false;
                rangeData.clear();
                continue;
            }
            goto worker_done;
        }

        // 模组专项：全部源耗尽后，重置源列表整体重试一轮（PCL Retried 同款）。
        // 第二轮每源仅 1 次尝试（attemptLimit 已按 modRetriedOnce 收窄）。
        if (!sourceOk && m_modpackMode && !modRetriedOnce) {
            modRetriedOnce = true;
            sourceIdx = -1;   // for 循环 ++ 后回到 0，重走全部源
            qCInfo(logDownload) << QStringLiteral("[夸父] 全部源失败，重置源列表整体重试一轮: %1")
                                   .arg(file->localName);
            continue;
        }
    }

    // Last resort retry（主流启动器 SourcesOnce 语义：全部源重新逐个尝试一轮，
    // 每源 1 次——兼容多源中部分源返回错误/部分源多线程下抽风的情况）
    // 模组专项已用 modRetriedOnce 覆盖，跳过
    // 2026-11-05：以前这里还要求 expectedSha1 非空 —— CurseForge 的文件大多没有 sha1，
    // 于是一旦常规尝试耗尽就再也不会被兜底救回（"失败后永远不恢复"的直接原因之一）。
    // 现在按"有 sha1 用 sha1，没 sha1 用大小"接受数据（见 download_accept.h）。
    if (!sourceOk && !m_modpackMode && file->orderedSources.size() > 0) {
        qCInfo(logDownload) << QStringLiteral("[夸父] 最终兜底：全部源逐个重试一轮 %1").arg(file->localName);
        for (int si = 0; si < file->orderedSources.size() && !sourceOk; ++si) {
            const QString url = file->orderedSources[si];
            qCInfo(logDownload) << QStringLiteral("[夸父] 最终兜底重试 URL=%1").arg(url);
        for (int attempt = 0; attempt < 3 && !sourceOk; ++attempt) {
            if (m_cancelled.loadRelaxed()) goto cleanup;
            waitWhilePaused();
            if (m_cancelled.loadRelaxed()) goto cleanup;
            if (attempt > 0) QThread::msleep(kRetryBackoffMs);

            QUrl qurl2(url); QNetworkRequest req(qurl2);
            qint64 lastProgressEmitMs = getElapsedMs();
            req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
            req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                             QNetworkRequest::NoLessSafeRedirectPolicy);
            {
                    QHttp1Configuration h1cfg;
                h1cfg.setNumberOfConnectionsPerHost(255);
                req.setHttp1Configuration(h1cfg);
            }
            QNetworkReply* reply = mgr.get(req);

            QEventLoop loop;
            QTimer timeout;
            timeout.setSingleShot(true);
            bool timedOut = false;
            connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
            connect(&timeout, &QTimer::timeout, [&]() { timedOut = true; loop.quit(); });
            if (m_modpackMode) {
                timeout.start(kChunkTimeoutMs);
                connect(reply, &QNetworkReply::readyRead, &timeout,
                        [&timeout]() { timeout.start(kChunkTimeoutMs); });
            } else {
                // 无数据超时（主流启动器语义）：有数据持续传输不掐断（2026-08-05 修正）
                int timeoutMs = (attempt == 0) ? kFirstAttemptTimeoutMs : kChunkTimeoutMs;
                timeout.start(timeoutMs);
                connect(reply, &QNetworkReply::readyRead, &timeout,
                        [&timeout, timeoutMs]() { timeout.start(timeoutMs); });
            }

            connect(reply, &QNetworkReply::downloadProgress,
                    [&](qint64 received, qint64 total) {
                // 取消/暂停后不得再计字节、发进度（契约 §5：回调早退）
                if (m_cancelled.loadRelaxed() || m_paused.loadRelaxed()) return;
                qint64 delta = received - th->downloadDone;
                if (delta > 0) {
                    applySpeedLimit(delta);
                    // 限速 sleep 期间可能被取消/暂停打断：醒来后再确认一次，绝不写统计
                    if (m_cancelled.loadRelaxed() || m_paused.loadRelaxed()) return;
                    // 兜底路径同主路径：醒来后重置空闲超时，避免被限速 sleep 误判超时
                    timeout.start(m_modpackMode ? kChunkTimeoutMs
                                                : (attempt == 0 ? kFirstAttemptTimeoutMs : kChunkTimeoutMs));
                    m_downloadedBytes.fetchAndAddRelaxed(delta);
                    th->downloadDone = received;
                }
                th->lastReceiveTime = getElapsedMs();
                qint64 now = getElapsedMs();
                if (now - lastProgressEmitMs >= kProgressEmitThrottleMs) {
                    lastProgressEmitMs = now;
                    emit progressChanged(m_completedFiles.loadRelaxed(), m_totalFiles.loadRelaxed(),
                                          m_downloadedBytes.loadRelaxed(), m_totalBytes.loadRelaxed());
                    // 同主请求：150ms 节流，避免跨线程信号风暴
                    emit fileProgress(th->sourceUrl, file->localName, received, total, file->localPath);
                }
            });

            // Register reply for thread-safe abort on cancel
            addInFlightReply(reply);
            // 注册与 cancel/pause 的竞态兜底：排队中止（理由同主请求：避免 quit() 丢失）
            if (m_cancelled.loadRelaxed() || m_paused.loadRelaxed())
                QMetaObject::invokeMethod(reply, "abort", Qt::QueuedConnection);

            loop.exec();

            removeInFlightReply(reply);

            // Cancel check: discard data immediately if cancelled
            if (m_cancelled.loadRelaxed()) {
                reply->abort();
                reply->deleteLater();
                goto cleanup;
            }

            // ── 暂停：abort 在途请求后原地等待恢复（不消耗重试次数）──
            if (m_paused.loadRelaxed() && reply->error() != QNetworkReply::NoError) {
                reply->abort();
                reply->deleteLater();
                th->downloadDone = 0;
                th->state = 0;
                waitWhilePaused();
                if (m_cancelled.loadRelaxed()) goto cleanup;
                // 回到同一 attempt（0 → -1 → 循环 ++ 仍为 0）
                --attempt;
                continue;
            }

            if (timedOut || reply->error() != QNetworkReply::NoError) {
                reply->abort();
                reply->deleteLater();
                continue;
            }

            QByteArray data = reply->readAll();
            reply->deleteLater();

            // ── Truncate data if thread was split mid-download (retry path) ──
            {
                qint64 threadRange = th->downloadEnd - th->downloadStart;
                if (threadRange > 0 && data.size() > threadRange) {
                    qint64 excess = data.size() - threadRange;
                    qCInfo(logDownload) << QStringLiteral("[夸父] 截断多余数据(重试) 文件=%1 起始=%2 预期=%3 实际=%4 超额=%5")
                        .arg(file->localName).arg(th->downloadStart).arg(threadRange).arg(data.size()).arg(excess);
                    data = data.mid(th->downloadStart, threadRange);
                    th->downloadDone = threadRange;
                    m_downloadedBytes.fetchAndAddRelaxed(-excess);
                }
            }

            bool isFullDownload = file->isNoSplit || file->isUnknownSize;
            if (isFullDownload) {
                const bool hasSha1 = !file->expectedSha1.isEmpty();
                const bool sha1Match = hasSha1
                    && (sha1Hex(data) == QString::fromLatin1(file->expectedSha1));
                // 占位大小（10MB 假值）不得当作"期望大小"，否则真实 2MB 的数据会被判不合格
                const qint64 expectedForCheck = file->sizeIsPlaceholder ? -1 : file->fileSize;
                const bool unknownForCheck = file->isUnknownSize || file->sizeIsPlaceholder;
                if (!acceptFallbackPayload(hasSha1, sha1Match, expectedForCheck,
                                           data.size(), unknownForCheck)) {
                    qCWarning(logDownload)
                        << QStringLiteral("[夸父] 最终兜底数据不合格 URL=%1 大小=%2 期望=%3 有SHA1=%4")
                               .arg(url).arg(data.size()).arg(file->fileSize).arg(hasSha1);
                    sourceOk = false;
                    continue;
                }
                if (hasSha1 && sha1Match) {
                    qCInfo(logDownload) << QStringLiteral("[夸父] 最终兜底 SHA1匹配 URL=%1").arg(url);
                } else {
                    qCInfo(logDownload) << QStringLiteral("[夸父] 最终兜底 大小匹配，信任数据 URL=%1 (SHA1=%2)")
                                               .arg(url, hasSha1 ? QStringLiteral("不匹配") : QStringLiteral("缺失"));
                }
                sourceOk = true;
                if (file->isNoSplit) {
                    QFile f(file->localPath);
                    QDir().mkpath(QFileInfo(file->localPath).absolutePath());
                    file->targetWritten = true;   // 直写最终路径：取消后必须删
                    if (f.open(QIODevice::WriteOnly)) { f.write(data); f.close(); }
                } else {
                    QString tmpDir = QFileInfo(file->localPath).absolutePath() + "/.shadow_temp/";
                    QDir().mkpath(tmpDir);
                    th->tempPath = tmpDir + QString("dl_%1_%2.tmp").arg(file->localName).arg(th->uuid);
                    QFile f(th->tempPath);
                    if (f.open(QIODevice::WriteOnly)) { f.write(data); f.close(); }
                }
                th->state = 3;
                // 兜底成功也要发一次进度：否则 UI 上这个文件"一声不响地完成"
                // （实测：兜底救回的文件 lastRecv 一直是 0）。
                emit progressChanged(m_completedFiles.loadRelaxed(), m_totalFiles.loadRelaxed(),
                                     m_downloadedBytes.loadRelaxed(), m_totalBytes.loadRelaxed());
                emit fileProgress(url, file->localName, data.size(), data.size(), file->localPath);
                goto worker_done;
            }
            }
        }
    }

    th->state = 4; // failed
    emit logMessage(QStringLiteral("[夸父] 所有源均失败 %1").arg(file->localName));

worker_done:
cleanup:
    m_activeThreads.fetchAndAddRelaxed(-1);

    // Decrement host active request count
    {
        QString host = extractHost(th->sourceUrl);
        QMutexLocker lock(&m_hostMutex);
        auto it = m_hostStats.find(host);
        if (it != m_hostStats.end()) it->activeRequests--;
    }

    qCDebug(logDownload) << QStringLiteral("[夸父] 线程完成 文件=%1 字节=%2")
        .arg(file->localName).arg(th->downloadDone);

    // ── 取消幂等（契约 §5）：cancel() 之后不得再合并写盘 / 发 fileFinished / 改统计 ──
    if (m_cancelled.loadRelaxed())
        return;

    // ── Merge on worker thread (avoid main thread disk I/O) ──
    bool allDone = false, anyFailed = false;
    {
        QMutexLocker lock(&m_filesMutex);
        allDone = true;
        for (auto& t : file->threads) {
            if (t.get() == th.get()) continue; // skip self (state may not be set yet)
            if (t->state < 3 && t->state != 4) { allDone = false; break; }
            if (t->state == 4) anyFailed = true;
        }
        // Only the LAST worker checks: all others done + self just finished
        if (allDone && th->state != 4) {
            // Count self as done (its state was set above before goto)
        }
        allDone = allDone && file->state < 3;
    }

    if (allDone) {
        // 模组专项：失败分片重下（PCL「丢弃失败分片重下」语义）——
        // 24 路并发下单片网络抖动不应导致整个大文件报废：
        // 失败分片（state=4 且未重试过）重置后重新下载其 range，
        // allDone 会因 state=0 重新计算，重试完成后再进入合并/终判。
        if (m_modpackMode && anyFailed) {
            bool launchedRetry = false;
            {
                QMutexLocker lock(&m_filesMutex);
                for (auto& t : file->threads) {
                    if (t->state == 4 && !t->retried) {
                        t->retried = true;
                        t->state = 0;
                        t->downloadDone = 0;
                        if (!t->tempPath.isEmpty()) QFile::remove(t->tempPath);
                        t->tempPath.clear();
                        launchedRetry = true;
                        m_activeThreads.fetchAndAddRelaxed(1);
                        launchWorker(t, file);   // 重新下载该分片 range（源会重新选择）
                    }
                }
            }
            if (launchedRetry) {
                qCInfo(logDownload) << QStringLiteral("[夸父] 分片失败重下 %1").arg(file->localName);
                return;   // 等重试分片完成
            }
        }

        bool ok = false;
        if (!anyFailed && th->state != 4) {
            file->state = 3;
            ok = mergeFile(file);
            file->state = ok ? 4 : 5;
        } else {
            file->state = 5;
        }

        // Signal completion to main thread (stats + signal emission)
        QPointer<FileDownloader> self(this);
        QMetaObject::invokeMethod(this, [self, file, ok, anyFailed]() {
            if (!self) return;
            if (!self) return;
            // 取消后在途完成的排队回调也不得改统计/发进度（契约 §5）
            if (self->m_cancelled.loadRelaxed()) return;
            if (anyFailed || !ok) {
                self->m_failedFiles.fetchAndAddRelaxed(1);
                for (const auto& s : file->orderedSources)
                    self->recordHostResult(QUrl(s).host().toLower(), false);
                self->logMessage(QString::fromUtf8("[夸父] [失败] 下载失败: %1 (所有源均失败)").arg(file->localName));
                self->fileFinished(file->localPath, false);
            } else {
                file->committed = true;   // 已提交：取消不再删该文件
                self->m_completedFiles.fetchAndAddRelaxed(1);
                for (const auto& t : file->threads)
                    self->recordHostResult(QUrl(t->sourceUrl).host().toLower(), true);
                // 文件完成补发 fileProgress（满字节）——合并完成后不再有
                // 下载中帧（received≈fileSize 差最后几 KB），补一帧让上层
                // 进度精确到 100%（避免“永远差一点到 100%”）。
                const qint64 fs = (file->fileSize > 0) ? file->fileSize : 0;
                if (fs > 0)
                    emit self->fileProgress(file->orderedSources.isEmpty() ? QString() : file->orderedSources.first(),
                                            file->localName, fs, fs, file->localPath);
                self->fileFinished(file->localPath, true);
            }
            self->updateStats();
        }, Qt::QueuedConnection);
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// mergeFile — combine multi-thread parts into final file
// ═════════════════════════════════════════════════════════════════════════════

bool FileDownloader::mergeFile(std::shared_ptr<FileDownload> file)
{
    if (file->isNoSplit) {
        if (!file->expectedSha1.isEmpty()) {
            QFile f(file->localPath);
            if (!f.open(QIODevice::ReadOnly)) return false;
            QCryptographicHash h(QCryptographicHash::Sha1);
            h.addData(&f); f.close();
            if (h.result().toHex() != file->expectedSha1) {
                emit logMessage(QString("[夸父] SHA1校验失败: %1").arg(file->localName));
                return false;
            }
        }
        return true;
    }

    qCInfo(logDownload) << QStringLiteral("[夸父] 开始合并文件 路径=%1 分段数=%2")
        .arg(file->localPath).arg(file->threads.size());

    QDir().mkpath(QFileInfo(file->localPath).absolutePath());
    // ── temp + rename（2026-11-05 验收 P2-F）──
    // 旧实现直接 open(localPath) 顺序写：分片打不开 / SHA1 失败 / 进程被杀
    // 都会在最终路径留下半截或脏文件（且没人清理）。改为写 .shadow_merge，
    // 校验通过再 rename；失败分支一律删临时文件。
    const QString mergeTmp = file->localPath + QStringLiteral(".shadow_merge");
    QFile::remove(mergeTmp);
    QFile out(mergeTmp);
    file->targetWritten = true;   // 写过（临时）文件：取消后必须删
    if (!out.open(QIODevice::WriteOnly)) {
        emit logMessage(QString("[夸父] 无法写入: %1").arg(mergeTmp));
        return false;
    }

    // 提交器：close + SHA1 校验 + rename。返回 false 时调用方负责删除 mergeTmp。
    auto commitTmp = [&]() -> bool {
        out.close();
        if (!file->expectedSha1.isEmpty()) {
            QFile chk(mergeTmp);
            if (!chk.open(QIODevice::ReadOnly)) return false;
            QCryptographicHash h(QCryptographicHash::Sha1);
            h.addData(&chk);
            chk.close();
            if (h.result().toHex() != file->expectedSha1) {
                emit logMessage(QString("[夸父] SHA1合并校验失败: %1").arg(file->localName));
                return false;
            }
        }
        QFile::remove(file->localPath);   // rename 前先清掉旧文件（Windows rename 不覆盖）
        if (!QFile::rename(mergeTmp, file->localPath)) {
            emit logMessage(QString("[夸父] 合并文件改名失败: %1").arg(file->localPath));
            return false;
        }
        return true;
    };

    // 服务器返回全文件（忽略 Range）的线程：其 temp 是完整文件，直接复制为
    // 最终文件（跳过其他分片——它们只是部分数据，完整数据已具备）
    for (auto& th : file->threads) {
        if (th->isFullFile && !th->tempPath.isEmpty()) {
            QFile tf(th->tempPath);
            if (tf.open(QIODevice::ReadOnly)) {
                out.write(tf.readAll());
                tf.close();
                tf.remove();
                if (!commitTmp()) {
                    qCWarning(logDownload) << QStringLiteral("[夸父] 全文件提交失败，已丢弃临时文件 %1").arg(file->localName);
                    out.close();
                    QFile::remove(mergeTmp);
                    return false;
                }
                qCInfo(logDownload) << QStringLiteral("[夸父] 合并使用全文件数据 %1").arg(file->localName);
                // 清理其余分片 temp
                for (auto& o : file->threads) {
                    if (o != th && !o->tempPath.isEmpty()) QFile::remove(o->tempPath);
                }
                return true;
            }
        }
    }

    // 按偏移排序合并——不能用 uuid（创建顺序）：tryAddThread 从"最大未完成片"切分，
    // 创建顺序 ≠ 偏移顺序，按 uuid 合并会乱序损坏文件（此路径 MC 下载从未触发，
    // 只有 modpackMode 1MB 阈值下真实大文件才暴露，2026-08-02 本地 20MB 实测发现）
    auto sorted = file->threads;
    std::sort(sorted.begin(), sorted.end(), [](auto& a, auto& b) { return a->downloadStart < b->downloadStart; });

    // ── 2026-11-20：合并层补长度校验 ──
    // 现场（本地坏镜像 /partshort：声明 8MB 只发 4MB 就断）**没有**复现「短分片被
    // 合进正式文件」——下载层重试到上限后直接判失败，mergeFile 根本没被调用。
    // 但这一层的不变量确实没人检查：这里只把每个分片 temp 原样 readAll 后追加，
    // 不比对「分片实际长度 vs 它负责的区间」，rename 前也只靠 SHA1（没有 sha1 的文件
    // 就没人管）。也就是说，只要哪一天某条路径让一个短分片「成功」返回，
    // 合并就会安静地生成一个短文件。补上校验，代价是每个文件一次 stat。
    qint64 expectedBytes = 0;
    for (auto& th : sorted) {
        if (th->tempPath.isEmpty()) continue;
        QFile tf(th->tempPath);
        if (!tf.open(QIODevice::ReadOnly)) {
            out.close();
            QFile::remove(mergeTmp);   // 半截合并文件不留在最终路径
            return false;
        }
        // 注意：downloadEnd 是**排他**上界（实测区间 0..16777216 实际写 16777216 字节），
        // 所以这里不按区间重算期望长度，只累加分片实际长度，最后与声明的文件大小比对。
        expectedBytes += tf.size();
        out.write(tf.readAll());
        tf.close();
        tf.remove();
    }
    // 与声明大小比对：这是唯一与分片区间约定无关的不变量。
    // 分片全收但总长偏短，只可能是某片被静默丢弃；没有 sha1 的文件全靠这道闸。
    const qint64 declared = (file->isUnknownSize || file->sizeIsPlaceholder) ? -1 : file->fileSize;
    if (expectedBytes > 0 && out.size() != expectedBytes) {
        qCWarning(logDownload) << QStringLiteral("[夸父] 合并总长不符，丢弃 文件=%1 累计=%2 落盘=%3")
            .arg(file->localName).arg(expectedBytes).arg(out.size());
        out.close();
        QFile::remove(mergeTmp);
        return false;
    }
    if (declared > 0 && out.size() != declared) {
        qCWarning(logDownload) << QStringLiteral("[夸父] 合并后大小与声明不符，丢弃 文件=%1 声明=%2 实际=%3")
            .arg(file->localName).arg(declared).arg(out.size());
        out.close();
        QFile::remove(mergeTmp);
        return false;
    }
    if (!commitTmp()) {
        QFile::remove(mergeTmp);
        return false;
    }

    qCInfo(logDownload) << QStringLiteral("[夸父] 合并完成 文件=%1 SHA1校验=通过").arg(file->localName);
    return true;
}

// ═════════════════════════════════════════════════════════════════════════════
// Speed tracking
// ═════════════════════════════════════════════════════════════════════════════

void FileDownloader::speedTick()
{
    if (m_state != Running) return;

    qint64 elapsed = m_speedTimer.elapsed();
    if (elapsed < 100) return;

    // 速度口径：仅真实网络收发字节。缓存命中分支不累加 m_downloadedBytes（也不累加
    // m_cacheBytes），本地文件读取/缓存标记数据不参与速度统计；m_cacheBytes 保持 0。
    qint64 now = m_downloadedBytes.loadRelaxed();
    if (now < 0) now = 0;   // 分片重下/截断修正时瞬时回退 → 钳零
    qint64 bytes = now - m_lastSpeedBytes;
    if (bytes < 0) bytes = 0;   // 分片重下/截断修正时 m_downloadedBytes 瞬时回退 → 钳零，避免负速度
    m_lastSpeedBytes = now;
    m_speedTimer.restart();

    qint64 actualBps = bytes * 1000 / elapsed;
    m_instantBps = actualBps;   // 主流启动器 Speed 语义：瞬时差分（速度门限用，响应快）

    {
        QMutexLocker lock(&m_speedMutex);
        m_speedRecords.prepend(actualBps);
        if (m_speedRecords.size() > kMaxSpeedRecords) m_speedRecords.removeLast();
    }

    qint64 weightedSum = 0;
    int weightDiv = 0;
    {
        QMutexLocker lock(&m_speedMutex);
        int w = m_speedRecords.size();
        for (auto rec : m_speedRecords) { weightedSum += rec * w; weightDiv += w; w--; }
    }
    qint64 currentBps = (weightDiv > 0) ? (weightedSum / weightDiv) : actualBps;
    // 对外单值（契约 §4：整个程序只读这一处；上层禁止二次平滑）
    m_currentSpeedBps.storeRelaxed(currentBps);

    // 展示速度 = 滑动窗口线性加权值（30 条 × 100ms ≈ 3s 窗口）：
    // 停流时窗口内连续 0 采样 → 数值 ~3s 内自然滑落归零（PCL 同款语义），
    // 不再叠加 EMA 混合（0.5/0.5 在 100ms 节拍下衰减过陡、观感像跳变）。
    m_emaMbps = currentBps / (1024.0 * 1024.0);

    // ── Speed floor: up on growth, decay on stagnation ──
    qint64 floorLimit = static_cast<qint64>(currentBps * kFloorRatio);
    qint64 currentFloor = m_speedFloorBps.loadRelaxed();
    const qint64 nowMs = getElapsedMs();
    if (currentBps >= kMinSpeedFloorBps && floorLimit > currentFloor) {
        m_speedFloorBps.storeRelaxed(floorLimit);
        m_lastFloorIncreaseMs = nowMs;
        // 只在跨过整 MB 时打日志（避免每次微增刷屏）
        if (floorLimit / (1024 * 1024) > currentFloor / (1024 * 1024)) {
            qCDebug(logDownload) << QStringLiteral("[夸父] 速度下限 %1 M").arg(floorLimit / (1024.0 * 1024.0), 0, 'f', 2);
        }
    } else if (nowMs - m_lastFloorIncreaseMs > kFloorDecayMs && currentFloor > kMinSpeedFloorBps) {
        // 5s without growth: decay floor by 50%
        qint64 newFloor = qMax(kMinSpeedFloorBps, currentFloor / 2);
        m_speedFloorBps.storeRelaxed(newFloor);
        m_lastFloorIncreaseMs = nowMs;
    }

    emit progressChanged(m_completedFiles.loadRelaxed(), m_totalFiles.loadRelaxed(),
                          m_downloadedBytes.loadRelaxed(), m_totalBytes.loadRelaxed());
}

// ═════════════════════════════════════════════════════════════════════════════
// updateStats
// ═════════════════════════════════════════════════════════════════════════════

void FileDownloader::updateStats()
{
    int done = m_completedFiles.loadRelaxed();
    int total = m_totalFiles.loadRelaxed();
    int fails = m_failedFiles.loadRelaxed();

    emit progressChanged(done, total,
                          m_downloadedBytes.loadRelaxed(),
                          m_totalBytes.loadRelaxed());

    if (done + fails >= total && total > 0) {
        m_managerTimer->stop();
        m_speedTimer2->stop();
        m_currentSpeedBps.storeRelaxed(0);   // 任务结束：对外速度归零，避免上层读到陈旧值
        m_state = Idle;
        const qint64 totalDl = m_totalBytes.loadRelaxed();
        // 完成汇总带缓存命中数（2026-08-05 补：缓存复用可见）
        const int cacheHits = m_cacheHitBase + m_cacheHits.loadRelaxed();   // 2026-11-19：补上 start() 清零前的基础数
        emit logMessage(QString::fromUtf8("[夸父] [完成] 下载完成: %1/%2 文件, %3, 速度 %4 MB/s, 缓存命中 %5")
                            .arg(done).arg(total)
                            .arg(formatSize(totalDl))
                            .arg(m_emaMbps, 0, 'f', 1)
                            .arg(cacheHits));
        qCInfo(logDownload) << QStringLiteral("[夸父] [完成] 下载完成: %1/%2 文件, %3, 速度 %4 MB/s, 缓存命中 %5")
            .arg(done).arg(total)
            .arg(formatSize(totalDl))
            .arg(m_emaMbps, 0, 'f', 1)
            .arg(cacheHits);
        emit allFinished();
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Per-host health
// ═════════════════════════════════════════════════════════════════════════════

QString FileDownloader::extractHost(const QString& url)
{
    return QUrl(url).host().toLower();
}

bool FileDownloader::isMirrorUrl(const QString& url)
{
    // 镜像判定（主流启动器语义）：BMCLAPI 及各类镜像站不分片、限速请求
    const QString u = url.toLower();
    return u.contains(QStringLiteral("bmclapi"))
        || u.contains(QStringLiteral("bangbang93"))
        || u.contains(QStringLiteral("mcimirror"))
        || u.contains(QStringLiteral("mcbbs"))
        || u.contains(QStringLiteral("tuna"))
        || u.contains(QStringLiteral("ustc"))
        || u.contains(QStringLiteral("aliyun"))
        || u.contains(QStringLiteral("tencent"))
        || u.contains(QStringLiteral("huawei"));
}


bool FileDownloader::hostCanAccept(const QString& host) const
{
    QMutexLocker lock(&m_hostMutex);
    auto it = m_hostStats.find(host);
    if (it == m_hostStats.end()) return true;
    // 模组专项：单镜像 host 场景跳过 degraded 拦截——短时连续失败若标记降级，
    // 会导致后续所有文件无法启动、整队列卡死（实测 129 文件尾部大文件全部拒启）；
    // MC 多源场景保留 degraded 源隔离（降级源不参与新连接）
    // 2026-11-19：降级带时限（见 HostStats::degradedUntilMs）。到期即放行，
    // 否则「拒发新请求 → 永远没有成功 3 次 → 永远降级」会死锁一整个进程。
    if (it->degraded && !m_modpackMode) {
        if (getElapsedMs() < it->degradedUntilMs) return false;
        // 到期：解除封锁，允许一条新连接去试探
        const_cast<HostStats&>(*it).degraded = false;
        const_cast<HostStats&>(*it).consecutiveFails = 0;
    }
    // ── per-host 并发上限（2026-11-19）──
    // 旧值：非模组 = m_maxThreads（192）。夸父开的是**长连接 Range 请求**，
    // 76 个库文件 × 最多 4 分片 → 可以把近 200 条长连接同时压到
    // libraries.minecraft.net 一台主机上。
    // 现场日志（26.3 安装）：126MB 花了 72 秒，其中 icu4j 与 26.3.jar 两个文件
    // 反复「超时」重试（每次间隔正好 12 秒 = 空闲超时），说明**部分连接被饿死**，
    // 而其余连接正常跑完 —— 典型的单主机连接数过多被对端限流。
    // 而且速度门限是 4MB/s：低于它就一直加分片，于是「越慢 → 连接越多 →
    // 越容易被限流 → 更慢」构成正反馈。
    // 现在给单主机一个温和上限（64）：仍够 76 个文件几乎并行，但不再把 200 条
    // 长连接压在一台机器上。模组专项保持 12（MCIM 镜像 16+ 会限流）。
    const int limit = m_modpackMode ? 12 : qBound(8, m_maxThreads, 64);
    if (it->activeRequests >= limit) return false;
    return true;
}

void FileDownloader::recordHostResult(const QString& host, bool ok)
{
    QMutexLocker lock(&m_hostMutex);
    auto& st = m_hostStats[host];
    if (ok) {
        st.consecutiveFails = 0;
        st.totalSuccess++;
        if (st.degraded && st.totalSuccess >= 3)
            st.degraded = false;
    } else {
        st.consecutiveFails++;
        st.totalFails++;
        // ── 全局降级阈值（2026-08-05 修正）──
        // 主流启动器 是 per-file 源禁用（FailCount>=5 只影响该文件）；我们的 host
        // 降级是全局的（影响所有文件）——阈值必须足够高，接近“官方完全停摆”
        // 才全局降级，避免偶发失败（3 次）就把官方全局拉黑 → 全部切镜像 →
        // 镜像负载暴增限流（“官方优先”设置被架空）。10 次连续失败 ≈ 源真挂。
        if (st.consecutiveFails >= 10) {
            st.degraded = true;
            st.degradedUntilMs = getElapsedMs() + kDegradeHoldMs;
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// DNS + IP reliability
// ═════════════════════════════════════════════════════════════════════════════

// ═════════════════════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════════════════════

double FileDownloader::currentSpeedMBps() const { return m_emaMbps; }

qint64 FileDownloader::currentSpeedBps() const { return m_currentSpeedBps.loadRelaxed(); }

QString FileDownloader::formatSize(qint64 bytes)
{
    if (bytes < 1024) return QString::number(bytes) + " B";
    if (bytes < 1048576) return QString::number(bytes / 1024.0, 'f', 1) + " KB";
    if (bytes < 1073741824LL) return QString::number(bytes / 1048576.0, 'f', 1) + " MB";
    return QString::number(bytes / 1073741824.0, 'f', 2) + " GB";
}

qint64 FileDownloader::getElapsedMs()
{
    static QElapsedTimer gt;
    if (!gt.isValid()) gt.start();
    return gt.elapsed();
}

} // namespace ShadowDownloader
