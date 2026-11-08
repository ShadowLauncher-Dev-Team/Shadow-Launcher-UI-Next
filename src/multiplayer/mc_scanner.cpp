// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "mc_scanner.h"
#include "../utils/logger.h"
#include <QNetworkInterface>
#include <QRegularExpression>
#include <QDateTime>

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

    // ── IPv4 multicast: bind to each local address ──
    // Aligns with Terracotta scanning.rs: bind to each local IP, join 224.0.2.60
    const QList<QHostAddress> localAddresses = QNetworkInterface::allAddresses();
    const QHostAddress kSubnetCheck(QStringLiteral("10.144.144.0"));  // Terracotta EasyTier subnet
    quint32 subnetCheckNBO = kSubnetCheck.toIPv4Address();  // already in network byte order

    for (const QHostAddress& addr : localAddresses) {
        if (addr.protocol() != QAbstractSocket::IPv4Protocol)
            continue;
        if (addr == QHostAddress::LocalHost || addr == QHostAddress::LocalHostIPv6)
            continue;
        // 2026-11-08：不再跳过 EasyTier 子网（10.144.144.0/24）。
        // 跳过是为了避免扫到自家 scaffold 广播，但代价是：EasyTier 网卡若被系统选为
        // 组播出口，MC 的 LAN 广播就彻底收不到（实测踩到）。自身/陶瓦 MOTD 已由
        // motdFilter 过滤，因此保留该接口更安全。
        Q_UNUSED(subnetCheckNBO);

        auto* sock = new QUdpSocket(this);
        if (!sock->bind(addr, kMulticastPort, QUdpSocket::ShareAddress)) {
            qCWarning(logNet) << QStringLiteral("[MCScanner] 绑定失败 addr=%1 端口=%2 err=%3")
                .arg(addr.toString()).arg(kMulticastPort).arg(sock->errorString());
            sock->deleteLater();
            continue;
        }
        // Qt 6 joinMulticastGroup with default interface; binding to specific addr already pins the interface
        if (!sock->joinMulticastGroup(QHostAddress(kMcMulticastAddrV4))) {
            qCWarning(logNet) << QStringLiteral("[MCScanner] 加入多播组失败 addr=%1 group=%2 err=%3")
                .arg(addr.toString()).arg(kMcMulticastAddrV4).arg(sock->errorString());
            sock->deleteLater();
            continue;
        }

        // 2026-11-08 修复：原来只保留第一个成功的 socket，其余既没 connect 也没释放，
        // 等于只在一个接口上监听。多网卡机器（WLAN + 169.254 虚拟网卡 + EasyTier）
        // 上 MC 广播如果从别的接口出去就永远收不到 → 联机页一直“等待中”。
        // 现改为：每个接口各留一个 socket，全部 connect。
        m_sockets.append(sock);
        connect(sock, &QUdpSocket::readyRead, this, [this, sock]() { drainSocket(sock); });
        if (!m_socketV4) {
            m_socketV4 = sock;
            qCInfo(logNet) << QStringLiteral("[MCScanner] 多播监听已启动 addr=%1").arg(addr.toString());
        } else {
            qCInfo(logNet) << QStringLiteral("[MCScanner] 追加多播监听 addr=%1").arg(addr.toString());
        }
    }

    // If no per-interface socket worked, try Any as fallback
    if (!m_socketV4) {
        m_socketV4 = new QUdpSocket(this);
        if (!m_socketV4->bind(QHostAddress::AnyIPv4, kMulticastPort, QUdpSocket::ShareAddress)) {
            qCWarning(logNet) << QStringLiteral("[MCScanner] 绑定 Any 失败 err=%1").arg(m_socketV4->errorString());
            m_socketV4->deleteLater();
            m_socketV4 = nullptr;
        } else {
            m_socketV4->joinMulticastGroup(QHostAddress(kMcMulticastAddrV4));
            m_sockets.append(m_socketV4);
            connect(m_socketV4, &QUdpSocket::readyRead, this, [this]() { drainSocket(m_socketV4); });
            qCInfo(logNet) << QStringLiteral("[MCScanner] 多播监听已启动(Any)");
        }
    }

    if (m_socketV4) {
        m_socketV4->setSocketOption(QAbstractSocket::MulticastTtlOption, 4);
    }

    // Cleanup timer: every 1s, remove expired entries (aligns with Terracotta's 500ms loop)
    m_cleanupTimer = new QTimer(this);
    m_cleanupTimer->setInterval(1000);
    connect(m_cleanupTimer, &QTimer::timeout, this, &McScanner::onCleanupTick);
    m_cleanupTimer->start();
}

void McScanner::stop()
{
    if (m_cleanupTimer) {
        m_cleanupTimer->stop();
        m_cleanupTimer->deleteLater();
        m_cleanupTimer = nullptr;
    }
    for (QUdpSocket* sock : m_sockets) {
        if (!sock) continue;
        sock->leaveMulticastGroup(QHostAddress(kMcMulticastAddrV4));
        sock->disconnect(this);
        sock->deleteLater();
    }
    m_sockets.clear();
    m_socketV4 = nullptr;
    m_servers.clear();
}

void McScanner::onDatagramReceived()
{
    drainSocket(m_socketV4);
}

void McScanner::drainSocket(QUdpSocket* sock)
{
    if (!sock) return;

    while (sock->hasPendingDatagrams()) {
        QByteArray buf;
        buf.resize(static_cast<int>(sock->pendingDatagramSize()));
        QHostAddress sender;
        quint16 senderPort = 0;
        sock->readDatagram(buf.data(), buf.size(), &sender, &senderPort);

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
