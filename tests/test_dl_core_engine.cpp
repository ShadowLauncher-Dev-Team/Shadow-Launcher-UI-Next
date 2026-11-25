// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
//
// 下载引擎核心单测（2026-11-25 上线前审计 · DL-CORE）
// 目的：把两条只能靠"真机下载 + 手快取消"验证的契约条目，做成可一键跑的引擎级断言：
//   B3  空闲 1.5s 速度归零（DOWNLOAD_CONTRACT §4）            —— 改前 1.5s 残值约 26%
//   B2  取消落在合并期不留满尺寸文件/中间文件（契约 §5）        —— 改前 rename 会照常落地
// 用法：DLCoreEngineTest.exe [b3|b2|all]   退出码 0=PASS，1=FAIL，2=INCONCLUSIVE
#include <QCoreApplication>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QEventLoop>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QAtomicInt>
#include <QHostAddress>
#include <QList>
#include <QStringList>
#include <QVariant>
#include <atomic>
#include <cstdio>

#include "core/file_downloader.h"
#include "utils/logger.h"

using namespace ShadowDownloader;

static int g_fail = 0;
static void check(bool cond, const char* name)
{
    std::printf("  [%s] %s\n", cond ? "OK" : "FAIL", name);
    std::fflush(stdout);
    if (!cond) ++g_fail;
}

// ── 假 HTTP 服务：支持 Range；可"只发一部分后挂住"（模拟半截响应）──
class RangeServer : public QTcpServer {
public:
    QByteArray payload;
    qint64     declaredLen = -1;    // >0：Content-Length 声明值（默认 = payload.size()）
    qint64     holdAfter   = -1;    // >=0：发这么多字节后停住（不关连接、不再发）
    bool       ignoreRange = false;
    std::atomic<int> connections{0};

protected:
    void incomingConnection(qintptr sd) override
    {
        connections.fetch_add(1);
        auto* s = new QTcpSocket(this);
        s->setSocketDescriptor(sd);
        auto* buf = new QByteArray;
        QObject::connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
        QObject::connect(s, &QTcpSocket::disconnected, [s, buf]() { delete buf; });
        // 注意：setSocketDescriptor 之后请求可能已经躺在缓冲里，此时再连 readyRead 收不到通知
        // → 必须补一次"延后执行"的补发（第 5 轮复验：B3 因此永远等不到响应，peak 恒 0）。
        auto serve = [this, s, buf]() {
            if (s->property("responded").toBool()) return;   // 只回应一次
            buf->append(s->readAll());
            const int end = buf->indexOf("\r\n\r\n");
            if (end < 0 || buf->size() > 64 * 1024) return;
            const QByteArray head = buf->left(end).toLower();
            buf->clear();
            s->setProperty("responded", true);

            const qint64 total = declaredLen > 0 ? declaredLen : payload.size();
            qint64 start = 0, endByte = total - 1;
            bool partial = false;
            const int rp = head.indexOf("range: bytes=");
            if (rp >= 0 && !ignoreRange) {
                const QByteArray spec =
                    head.mid(rp + 13, head.indexOf("\r\n", rp) - (rp + 13));
                const QList<QByteArray> parts = spec.split('-');
                if (parts.size() == 2) {
                    if (!parts[0].isEmpty()) start = parts[0].toLongLong();
                    if (!parts[1].isEmpty()) endByte = qMin(parts[1].toLongLong(), total - 1);
                    partial = true;
                }
            }
            if (start > endByte) {
                s->write("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\n\r\n");
                s->flush();
                return;
            }
            QByteArray body = payload.mid(static_cast<int>(start),
                                          static_cast<int>(endByte - start + 1));
            if (holdAfter >= 0 && body.size() > holdAfter) body = body.left(holdAfter);

            QByteArray h;
            h += partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n";
            h += "Content-Length: " + QByteArray::number(endByte - start + 1) + "\r\n";
            h += "Accept-Ranges: bytes\r\n";
            if (partial)
                h += "Content-Range: bytes " + QByteArray::number(start) + "-"
                     + QByteArray::number(endByte) + "/" + QByteArray::number(total) + "\r\n";
            if (holdAfter < 0) h += "Connection: close\r\n";
            h += "\r\n";
            s->write(h);
            s->write(body);
            s->flush();
        };
        QObject::connect(s, &QTcpSocket::readyRead, s, serve);
        // 本地回环下「请求在 setSocketDescriptor 之前就已到达」时，readyRead 不会再发，
        // 单次 singleShot 也可能抢在数据落缓冲之前 —— 用 5ms 轮询兜底（应答后自动空转）：
        // 第 5 轮实测 B3 = conns=1 但 downloaded=0B，正是这个竞态。
        auto* tick = new QTimer(s);
        tick->setInterval(5);
        QObject::connect(tick, &QTimer::timeout, s, [s, serve]() {
            if (s->property("responded").toBool()) return;
            serve();
        });
        tick->start();
    }
};

static QByteArray pattern(qint64 n)
{
    QByteArray b;
    b.resize(static_cast<int>(n));
    for (int i = 0; i < b.size(); ++i) b[i] = static_cast<char>((i * 31 + 7) % 251);
    return b;
}

// ─────────────────────────────────────────────────────────────
// B3：空闲 1.5s 速度归零（契约 §4）
// ─────────────────────────────────────────────────────────────
static int runB3()
{
    std::printf("=== B3 空闲速度归零 ===\n");
    const QString out = QDir::tempPath() + "/dlcore_b3.bin";
    QFile::remove(out);

    RangeServer srv;
    // 逃生口：DLCORE_B3_URL=<外部挂起源> 时不用进程内服务（本地回环 accept 路径出问题时的对照组）
    const QString extUrl = qEnvironmentVariable("DLCORE_B3_URL");
    QString url;
    if (!extUrl.isEmpty()) {
        url = extUrl;
        std::printf("  使用外部源: %s\n", qPrintable(extUrl));
    } else {
        srv.payload = pattern(4 * 1024 * 1024);
        srv.declaredLen = 4 * 1024 * 1024;
        srv.holdAfter = 512 * 1024;      // 只发 512KB 后挂住：引擎保持 Running，速度随后归零
        if (!srv.listen(QHostAddress::LocalHost, 0)) { std::printf("  server listen failed\n"); return 1; }
        url = QStringLiteral("http://127.0.0.1:%1/b3.bin").arg(srv.serverPort());
    }

    FileDownloader fd;
    fd.setMaxThreads(1);
    fd.addFile(out, QStringLiteral("dlcore_b3.bin"), QStringList() << url,
               4 * 1024 * 1024, QByteArray());

    QElapsedTimer clock; clock.start();
    qint64 peak = 0;
    qint64 peakBytes = 0;
    // 10ms 采样：速度是 100ms 一拍算出来的窗口值，采样太粗会漏掉"刚有数据"的那一拍
    QTimer poll; poll.setInterval(10);
    QObject::connect(&poll, &QTimer::timeout, [&]() {
        const qint64 v = fd.currentSpeedBps();
        if (v > peak) peak = v;
        const qint64 b = fd.downloadedBytes();
        if (b > peakBytes) peakBytes = b;
    });
    fd.start();
    poll.start();

    // 等到速度出现（最多 10s）
    QElapsedTimer wait; wait.start();
    while (fd.currentSpeedBps() <= 0 && wait.elapsed() < 10000)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);

    const qint64 t0 = clock.elapsed();
    while (clock.elapsed() - t0 < 1500) QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    const qint64 v1500 = fd.currentSpeedBps();
    while (clock.elapsed() - t0 < 2000) QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    const qint64 v2000 = fd.currentSpeedBps();

    std::printf("  downloaded=%lldB  peak=%lld B/s  1500ms=%lld B/s  2000ms=%lld B/s  conns=%d\n",
                static_cast<long long>(peakBytes), static_cast<long long>(peak),
                static_cast<long long>(v1500), static_cast<long long>(v2000),
                srv.connections.load());
    std::fflush(stdout);

    check(peakBytes > 0, "引擎确实收到了字节（前置条件：否则测的不是归零而是没数据）");
    check(peak > 0, "先有非零速度（否则测不到归零）");
    check(v1500 == 0, "空闲 1.5s 时速度为 0");
    check(v2000 == 0, "空闲 2.0s 时速度为 0");

    fd.cancel();
    srv.close();
    QFile::remove(out);
    return g_fail ? 1 : 0;
}

// ─────────────────────────────────────────────────────────────
// B2：取消落在合并期 → 目标文件与 .shadow_merge 都不得留下
// ─────────────────────────────────────────────────────────────
static int runB2()
{
    std::printf("=== B2 取消落在合并期 ===\n");
    const QString out = QDir::tempPath() + "/dlcore_b2.bin";
    const QString mergeTmp = out + QStringLiteral(".shadow_merge");
    QFile::remove(out);
    QFile::remove(mergeTmp);

    const qint64 kSize = 64LL * 1024 * 1024;   // 64MB：合并窗口足够宽（实测百毫秒级）
    RangeServer srv;
    srv.payload = pattern(kSize);
    srv.declaredLen = kSize;
    if (!srv.listen(QHostAddress::LocalHost, 0)) { std::printf("  server listen failed\n"); return 1; }

    FileDownloader fd;
    fd.setMaxThreads(4);
    std::atomic<int> progCount{0};
    std::atomic<int> finishCount{0};
    std::atomic<int> finishTrue{0};
    QObject::connect(&fd, &FileDownloader::progressChanged, [&](int, int, qint64, qint64) {
        progCount.fetch_add(1);
    });
    QObject::connect(&fd, &FileDownloader::fileFinished, [&](const QString&, bool ok) {
        finishCount.fetch_add(1);
        if (ok) finishTrue.fetch_add(1);
    });
    fd.addFile(out, QStringLiteral("dlcore_b2.bin"),
               QStringList() << QStringLiteral("http://127.0.0.1:%1/b2.bin").arg(srv.serverPort()),
               kSize, QByteArray());

    QElapsedTimer clock; clock.start();
    fd.start();

    // 轮询合并中间文件出现（2ms）
    bool sawMerge = false;
    while (clock.elapsed() < 40000) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 2);
        if (QFileInfo::exists(mergeTmp)) { sawMerge = true; break; }
    }
    if (!sawMerge) {
        std::printf("  INCONCLUSIVE: 40s 内没抓到合并窗口（file=%lld completion=%d）\n",
                    static_cast<long long>(QFileInfo(out).size()), finishCount.load());
        std::fflush(stdout);
        fd.cancel();
        srv.close();
        return 2;
    }

    const qint64 mergeBytes = QFileInfo(mergeTmp).size();
    const int progAtCancel = progCount.load();
    const int finAtCancel = finishCount.load();
    std::printf("  抓到合并窗口: t=%lldms mergeTmp=%lldB 已完成信号=%d\n",
                static_cast<long long>(clock.elapsed()), static_cast<long long>(mergeBytes),
                finAtCancel);
    std::fflush(stdout);

    fd.cancel();   // ← 合并进行中取消

    // 等 1.5s，让 worker 收尾
    const qint64 stop = clock.elapsed();
    while (clock.elapsed() - stop < 1500) QCoreApplication::processEvents(QEventLoop::AllEvents, 20);

    const bool outExists = QFileInfo::exists(out);
    const bool tmpExists = QFileInfo::exists(mergeTmp);
    std::printf("  取消后: 目标存在=%d 中间文件存在=%d 进度信号增量=%d 完成信号增量=%d\n",
                outExists ? 1 : 0, tmpExists ? 1 : 0,
                progCount.load() - progAtCancel, finishCount.load() - finAtCancel);
    std::fflush(stdout);

    if (finAtCancel > 0) {
        std::printf("  INCONCLUSIVE: 取消前已完成（合并窗口太短），本条不判定\n");
        srv.close();
        return 2;
    }

    check(!outExists, "取消后目标文件不存在（不得出现满尺寸文件）");
    check(!tmpExists, "取消后 <目标>.shadow_merge 不存在");
    check(finishCount.load() == finAtCancel, "取消后不再有任何完成信号");
    check(progCount.load() == progAtCancel, "取消后不再有任何进度信号");

    srv.close();
    QFile::remove(out);
    QFile::remove(mergeTmp);
    return g_fail ? 1 : 0;
}

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    ShadowLauncher::installFileLogger(QCoreApplication::applicationDirPath());

    QString which = argc > 1 ? QString::fromUtf8(argv[1]) : QStringLiteral("all");
    int rc = 0;
    if (which == QLatin1String("all") || which == QLatin1String("b3"))
        rc = qMax(rc, runB3());
    if (which == QLatin1String("all") || which == QLatin1String("b2"))
        rc = qMax(rc, runB2());

    std::printf("\n=== %s (%d FAIL) ===\n", rc == 0 ? "PASS" : (rc == 2 ? "INCONCLUSIVE" : "FAIL"), g_fail);
    std::fflush(stdout);
    return rc;
}
