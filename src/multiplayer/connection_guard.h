// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
// Connection Guard — rate limiting, brute-force protection
#pragma once
#include <QObject>
#include <QHash>
#include <QList>
#include <QString>
#include <QTimer>
#include <qmath.h>

namespace ShadowLauncher {

class ConnectionGuard : public QObject {
    Q_OBJECT
public:
    explicit ConnectionGuard(QObject* parent = nullptr);

    // Returns true if connection is allowed
    bool allowConnect(const QString& ip);
    bool allowPacket(const QString& peerId);

    // 入房尝试的判定结果：不只回答「放不放行」，还回答「为什么」和「还要等几秒」。
    // 旧接口只返回 bool，导致「房码本身无效」和「被频率限制」在调用方无法区分（D6）。
    struct JoinGate {
        bool allowed = false;    // 本次尝试放行
        bool throttled = false;  // 命中连续失败冷却（kJoinCooldown 次）
        int  retryAfterSec = 0;  // 被限流时：剩余秒数（>=1）；放行时为 0
    };
    JoinGate tryJoinRoom(const QString& ip);

    // 冷却策略本身（公开给调用方拼文案用：说「连续 N 次失败」不能在前端写死数字）
    static constexpr int kJoinCooldown = 3;         // Failures before cooldown
    static constexpr int kJoinCooldownSec = 60;     // Cooldown duration

    void cleanupExpired();

signals:
    void blocked(const QString& ip, const QString& reason);

private:
    struct RateEntry { QList<qint64> times; };
    QHash<QString, RateEntry> m_connectLog;   // IP → timestamps
    QHash<QString, RateEntry> m_joinLog;      // IP → timestamps
    QHash<QString, RateEntry> m_packetLog;    // peerId → timestamps

    // Limits
    static constexpr int kMaxConnPerMinute = 20;     // TCP accept rate
    static constexpr int kMaxJoinPerMinute = 6;      // Room code attempts
    static constexpr int kMaxPacketsPerSec = 100;    // Per-client packet rate

    QTimer* m_cleanupTimer;
    bool checkAndAdd(const QString& key, QHash<QString, RateEntry>& log,
                     int maxCount, qint64 windowMs, bool& hitCooldown,
                     int cooldownThreshold = -1, int* retryAfterSec = nullptr);
};

} // namespace
