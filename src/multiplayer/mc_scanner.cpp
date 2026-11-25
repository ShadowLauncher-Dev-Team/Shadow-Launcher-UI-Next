// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "mc_scanner.h"
#include "../utils/logger.h"
#include <QNetworkInterface>
#include <QRegularExpression>
#include <QDateTime>
#include <QHostAddress>

namespace ShadowLauncher {

const QString McScanner::kMcMulticastAddrV4 = QStringLiteral("224.0.2.60");

McScanner::McScanner(QObject* parent)
    : QObject(parent)
{
}

McScanner::~McScanner()
{
    stop();
}

void McScanner::start(std::function<bool(const QString&)> motdFilter)
{
    stop();  // restart if already running
    m_motdFilter = std::move(motdFilter);
    m_rxPackets = 0;
    m_startedAtMs = QDateTime::currentMSecsSinceEpoch();
    m_lastStateLogMs = m_startedAtMs;
    m_lastPacketMs = 0;

    // ── 单个通配 socket + 逐网卡加组 ──
    // 不用「每块网卡 bind 一个 socket」：绑到具体地址后，MC 从别的网卡发的包
    // （系统多播路由可能选到已断开的网卡）就永远收不到，实测 2 分钟 0 包。
    auto* sock = new QUdpSocket(this);
    if (!sock->bind(QHostAddress::AnyIPv4, kMulticastPort,
                    QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        qCWarning(logNet) << QStringLiteral("[MCScanner] 绑定 0.0.0.0:%1 失败 err=%2")
            .arg(kMulticastPort).arg(sock->errorString());
        sock->deleteLater();
        return;
    }
    sock->setSocketOption(QAbstractSocket::MulticastTtlOption, 4);
    sock->setSocketOption(QAbstractSocket::MulticastLoopbackOption, 1);
    m_socket = sock;
    connect(sock, &QUdpSocket::readyRead, this, &McScanner::onDatagramReady);

    refreshInterfaces();   // 先按当前网卡加组

    // 网卡会变（EasyTier TUN 开房后才出现、WLAN 掉线重连）：每 3s 补齐一次
    m_refreshTimer = new QTimer(this);
    m_refreshTimer->setInterval(3000);
    connect(m_refreshTimer, &QTimer::timeout, this, &McScanner::refreshInterfaces);
    m_refreshTimer->start();

    // Cleanup timer: 每 1s 清一次过期条目（Terracotta 自己的循环是 500ms，不必对齐）
    m_cleanupTimer = new QTimer(this);
    m_cleanupTimer->setInterval(1000);
    connect(m_cleanupTimer, &QTimer::timeout, this, &McScanner::onCleanupTick);
    m_cleanupTimer->start();

    qCInfo(logNet) << QStringLiteral("[MCScanner] 开始监听 0.0.0.0:%1（多播组 %2）")
        .arg(kMulticastPort).arg(kMcMulticastAddrV4);
}

void McScanner::stop()
{
    if (m_refreshTimer) {
        m_refreshTimer->stop();
        m_refreshTimer->deleteLater();
        m_refreshTimer = nullptr;
    }
    if (m_cleanupTimer) {
        m_cleanupTimer->stop();
        m_cleanupTimer->deleteLater();
        m_cleanupTimer = nullptr;
    }
    if (m_socket) {
        const QHostAddress group(kMcMulticastAddrV4);
        if (!m_joinedIfaces.isEmpty()) {
            for (const QNetworkInterface& iface : QNetworkInterface::allInterfaces()) {
                if (m_joinedIfaces.contains(iface.humanReadableName()))
                    m_socket->leaveMulticastGroup(group, iface);
            }
        }
        if (m_joinedDefault)
            m_socket->leaveMulticastGroup(group);
        m_socket->disconnect(this);
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    m_joinedIfaces.clear();
    m_joinedDefault = false;
    m_servers.clear();
}

void McScanner::refreshInterfaces()
{
    if (!m_socket)
        return;

    const QHostAddress group(kMcMulticastAddrV4);

    // 1) 永远保住一份「默认接口」成员关系。
    //    MC 发包走哪块网卡，由系统多播路由决定；用 INADDR_ANY 加组时系统也按同一条
    //    路由选网卡 —— 这条成员关系正好落在 MC 的发包网卡上（实测本机广播从一块
    //    「已断开但仍留着 DHCP 地址」的有线网卡出去，只有 ANY 成员关系收得到）。
    //    路由变了（EasyTier TUN 开房后才出现、WLAN 重连）时重新 join 会加到新网卡；
    //    已存在的成员关系会返回失败，属于正常情况，静默忽略。
    // 只在「还没成功过」或「已经 10 秒没收到任何包」时补，避免每 3s 反复加组
    // （Windows 上重复的 IP_ADD_MEMBERSHIP 会累积成员关系，20 个就上限了）。
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const bool silent = (nowMs - m_lastPacketMs) > 10000;
    if (!m_joinedDefault || silent) {
        if (m_socket->joinMulticastGroup(group)) {
            m_joinedDefault = true;
            qCInfo(logNet) << QStringLiteral("[MCScanner] 已加入多播组（默认接口）");
        }
    }

    // 2) 再对每块可用网卡显式加组：覆盖「MC 监听侧加组落在了别的网卡」的情况。
    QStringList present;
    QList<QNetworkInterface> toJoin;

    for (const QNetworkInterface& iface : QNetworkInterface::allInterfaces()) {
        const auto flags = iface.flags();
        if (!(flags & QNetworkInterface::IsUp) || !(flags & QNetworkInterface::IsRunning))
            continue;
        if (flags & QNetworkInterface::IsLoopBack)
            continue;
        // 有 IPv4 地址才算（169.254.* 也算：MC 可能从它发，加组失败会自动跳过）
        bool hasV4 = false;
        for (const QNetworkAddressEntry& entry : iface.addressEntries()) {
            if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol && !entry.ip().isLoopback()) {
                hasV4 = true;
                break;
            }
        }
        if (!hasV4)
            continue;

        const QString name = iface.humanReadableName();
        present << name;
        if (!m_joinedIfaces.contains(name))
            toJoin.append(iface);
    }

    // 新增的网卡加组（同一个组、同一个 socket，多网卡 membership 是允许的）
    for (const QNetworkInterface& iface : toJoin) {
        if (m_socket->joinMulticastGroup(group, iface)) {
            m_joinedIfaces << iface.humanReadableName();
            qCInfo(logNet) << QStringLiteral("[MCScanner] 已加入多播组 网卡=%1")
                .arg(iface.humanReadableName());
        } else {
            // 常见原因：该网卡已被上面的「默认接口」成员关系覆盖（WSAEADDRINUSE），
            // 或者 169.254 虚拟网卡 / 正在切换的 TUN —— 都不致命，下轮还会再试。
            qCDebug(logNet) << QStringLiteral("[MCScanner] 显式加组跳过 网卡=%1 err=%2")
                .arg(iface.humanReadableName(), m_socket->errorString());
        }
    }

    // 已经消失的网卡退组
    for (int i = m_joinedIfaces.size() - 1; i >= 0; --i) {
        if (present.contains(m_joinedIfaces.at(i)))
            continue;
        const QString gone = m_joinedIfaces.takeAt(i);
        qCInfo(logNet) << QStringLiteral("[MCScanner] 网卡已消失，退出多播组 网卡=%1").arg(gone);
    }

    // 诊断用：真正生效的成员关系 = 默认接口 + 显式网卡
    if (m_joinedIfaces.isEmpty() && !m_joinedDefault) {
        qCDebug(logNet) << QStringLiteral("[MCScanner] 当前没有任何多播成员关系");
    }
}

void McScanner::onDatagramReady()
{
    drainSocket();
}

void McScanner::drainSocket()
{
    if (!m_socket)
        return;
    while (m_socket->hasPendingDatagrams()) {
        QByteArray buf;
        buf.resize(static_cast<int>(m_socket->pendingDatagramSize()));
        QHostAddress sender;
        quint16 senderPort = 0;
        m_socket->readDatagram(buf.data(), buf.size(), &sender, &senderPort);
        if (buf.isEmpty())
            continue;
        ++m_rxPackets;
        m_lastPacketMs = QDateTime::currentMSecsSinceEpoch();
        processDatagram(buf, sender.toString());
    }
}

void McScanner::processDatagram(const QByteArray& data, const QString& sourceIp)
{
    // Aligns with Terracotta scanning.rs: parse [MOTD]...[/MOTD][AD]...[/AD]
    QString text = QString::fromUtf8(data);

    // Extract MOTD
    static QRegularExpression motdRx(QStringLiteral(R"(\[MOTD\](.*?)\[/MOTD\])"));
    auto motdMatch = motdRx.match(text);
    if (!motdMatch.hasMatch()) return;

    QString motd = motdMatch.captured(1);

    // Apply filter (typically: exclude self's MOTD)
    if (m_motdFilter && !m_motdFilter(motd)) return;

    // Extract port
    static QRegularExpression adRx(QStringLiteral(R"(\[AD\](\d+)\[/AD\])"));
    auto adMatch = adRx.match(text);
    if (!adMatch.hasMatch()) return;

    bool ok = false;
    quint16 port = static_cast<quint16>(adMatch.captured(1).toUShort(&ok));
    if (!ok || port == 0) return;

    // Update or add entry
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    bool isNew = !m_servers.contains(port);

    McScanResult& entry = m_servers[port];
    entry.port = port;
    entry.motd = motd;
    entry.hostAddress = sourceIp;
    entry.lastSeenMs = now;

    if (isNew) {
        qCInfo(logNet) << QStringLiteral("[MCScanner] 发现服务器 port=%1 motd=\"%2\" ip=%3")
            .arg(port).arg(motd).arg(sourceIp);
        emit serversChanged();
    }
}

void McScanner::onCleanupTick()
{
    cleanupExpired();
    logListenState(false);
}

// 诊断：每 15s 记一次监听状态。0 包时给 warn，方便一眼区分
// 「接收链路坏」（有网卡但 0 包）与「游戏根本没广播」（历史上整合包会这样）。
void McScanner::logListenState(bool force)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!force && now - m_lastStateLogMs < 15000)
        return;
    m_lastStateLogMs = now;
    // 实际生效的成员关系 = 显式网卡 + 「默认接口」兜底，这里要一起显示，
    // 否则日志会写成「加组网卡:（空）」，下次排查又看不出到底加在哪。
    QStringList active = m_joinedIfaces;
    if (m_joinedDefault)
        active << QStringLiteral("默认接口");
    const QString ifaces = active.isEmpty() ? QStringLiteral("无") : active.join(QStringLiteral(", "));

    const qint64 secs = (now - m_startedAtMs) / 1000;
    if (m_rxPackets == 0 && secs >= 10) {
        qCWarning(logNet) << QStringLiteral("[MCScanner] 已监听 %1 秒，收到 0 个组播包（加组: %2）")
            .arg(secs).arg(ifaces);
    } else {
        qCInfo(logNet) << QStringLiteral("[MCScanner] 已监听 %1 秒，组播包=%2，在线服务=%3（加组: %4）")
            .arg(secs).arg(m_rxPackets).arg(m_servers.size()).arg(ifaces);
    }
}

void McScanner::cleanupExpired()
{
    // Remove servers with no beacon for 5s (aligns with Terracotta)
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    bool changed = false;

    QList<quint16> expired;
    for (auto it = m_servers.constBegin(); it != m_servers.constEnd(); ++it) {
        if ((now - it->lastSeenMs) >= kExpiryMs) {
            expired.append(it.key());
        }
    }

    for (quint16 port : expired) {
        qCInfo(logNet) << QStringLiteral("[MCScanner] 服务器超时移除 port=%1").arg(port);
        m_servers.remove(port);
        changed = true;
    }

    if (changed)
        emit serversChanged();
}

QList<quint16> McScanner::ports() const
{
    QList<quint16> result;
    for (auto it = m_servers.constBegin(); it != m_servers.constEnd(); ++it) {
        result.append(it.key());
    }
    return result;
}

QList<McScanResult> McScanner::results() const
{
    return m_servers.values();
}

} // namespace ShadowLauncher
