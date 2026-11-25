// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
// Minecraft LAN Scanner — listens on 224.0.2.60:4445 for [MOTD]...[/MOTD][AD]port[/AD]
// Aligns with Terracotta scanning.rs: multicast discovery with MOTD filter + 5s expiry
//
// 2026-11-25 重写接收端（原实现逐网卡 bind 具体地址，实测会「绑上了但 0 包」）：
//   - 唯一 socket 绑 0.0.0.0:4445（ShareAddress），再对每块可用网卡显式加组；
//   - 每 3s 重新枚举网卡：EasyTier 的 TUN 是开房之后才出现的，启动时加不到组；
//   - 为什么必须通配绑定：MC 的广播走哪块网卡由系统多播路由决定，实测它会从
//     「已断开但仍留着 DHCP 地址」的有线网卡发出，此时绑在
//     WLAN 地址上的 socket 一个包都收不到；通配绑定 + 逐网卡加组才能都收到。
#pragma once
#include <QObject>
#include <QList>
#include <QUdpSocket>
#include <QTimer>
#include <QHash>
#include <QNetworkInterface>
#include <functional>

namespace ShadowLauncher {

// Scan result: a LAN-discovered Minecraft server
struct McScanResult {
    quint16 port = 0;
    QString motd;
    QString hostAddress;  // source IP of the broadcast
    qint64 lastSeenMs = 0;  // timestamp of last received beacon
};

class McScanner : public QObject {
    Q_OBJECT
public:
    explicit McScanner(QObject* parent = nullptr);
    ~McScanner() override;

    // Start scanning. motdFilter returns true if we should include a server with this MOTD.
    // Typically: [](const QString& m) { return m != MOTD; } to exclude self.
    void start(std::function<bool(const QString&)> motdFilter);
    void stop();

    // Get current list of discovered ports (non-expired, within 5s window)
    QList<quint16> ports() const;

    // Get full scan results (port + motd + host)
    QList<McScanResult> results() const;

signals:
    // Emitted when the discovered server list changes (port added or expired)
    void serversChanged();

private slots:
    void onDatagramReady();
    /// 排空 socket 的待读报文
    void drainSocket();
    void onCleanupTick();
    /// 重新枚举网卡并补齐/清理多播组（TUN 网卡会在扫描中途出现）
    void refreshInterfaces();

private:
    void processDatagram(const QByteArray& data, const QString& sourceIp);
    void cleanupExpired();
    void logListenState(bool force);

    QUdpSocket* m_socket = nullptr;   // 唯一接收 socket：AnyIPv4:4445
    // 已加组的网卡（按接口名去重；Qt 的 leave 也要同一个 QNetworkInterface）
    QStringList m_joinedIfaces;
    bool m_joinedDefault = false;   // 一块网卡都没加成功时退回的「默认接口」成员关系
    std::function<bool(const QString&)> m_motdFilter;

    // Discovered servers keyed by port
    QHash<quint16, McScanResult> m_servers;
    QTimer* m_cleanupTimer = nullptr;
    QTimer* m_refreshTimer = nullptr;   // 3s 枚举网卡

    // 诊断计数：收到多少组播包（含被 MOTD 过滤掉的），用来区分
    // 「接收链路坏」与「游戏根本没在广播」
    quint64 m_rxPackets = 0;
    qint64 m_startedAtMs = 0;
    qint64 m_lastStateLogMs = 0;
    qint64 m_lastPacketMs = 0;   // 最后一次收到组播包的时间（用于判断要不要重加组）

    static constexpr qint64 kExpiryMs = 5000;  // 5s expiry (aligns with Terracotta)
    static constexpr quint16 kMulticastPort = 4445;
    static const QString kMcMulticastAddrV4;
};

} // namespace ShadowLauncher
