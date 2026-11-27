// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "connection_guard.h"
#include <QDateTime>
#include <QDebug>
#include "../utils/logger.h"

namespace ShadowLauncher {

ConnectionGuard::ConnectionGuard(QObject* parent)
    : QObject(parent)
    , m_cleanupTimer(new QTimer(this))
{
    m_cleanupTimer->setInterval(60000); // cleanup every 60s
    connect(m_cleanupTimer, &QTimer::timeout, this, &ConnectionGuard::cleanupExpired);
    m_cleanupTimer->start();
}

bool ConnectionGuard::allowConnect(const QString& ip)
{
    bool c;
    if (!checkAndAdd(ip, m_connectLog, kMaxConnPerMinute, 60000, c)) {
        emit blocked(ip, QStringLiteral("连接过于频繁，已被暂时限制"));
        return false;
    }
    return true;
}

// 入房尝试：不再在这里 emit blocked()（那条信号会把中文文案直接推给 UI，
// 调用方无法区分「房码无效」与「被限流」，也无法带上剩余秒数）。
// 判定结果交给 MultiplayerManager::joinRoom 决定文案与错误码。
ConnectionGuard::JoinGate ConnectionGuard::tryJoinRoom(const QString& ip)
{
    JoinGate gate;
    int retryAfterSec = 0;
    gate.allowed = checkAndAdd(ip, m_joinLog, kMaxJoinPerMinute, 60000,
                               gate.throttled, kJoinCooldown, &retryAfterSec);
    gate.retryAfterSec = gate.allowed ? 0 : qMax(1, retryAfterSec);
    return gate;
}

bool ConnectionGuard::allowPacket(const QString& peerId)
{
    bool c;
    if (!checkAndAdd(peerId, m_packetLog, kMaxPacketsPerSec, 1000, c)) {
        // Don't spam toast for packet drops — just silently drop
        return false;
    }
    return true;
}

bool ConnectionGuard::checkAndAdd(const QString& key,
                                   QHash<QString, RateEntry>& log,
                                   int maxCount, qint64 windowMs,
                                   bool& hitCooldown,
                                   int cooldownThreshold,
                                   int* retryAfterSec)
{
    hitCooldown = false;
    if (retryAfterSec) *retryAfterSec = 0;
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    auto& entry = log[key];
    qint64 cutoff = now - windowMs;

    // Remove expired entries
    while (!entry.times.isEmpty() && entry.times.first() < cutoff)
        entry.times.removeFirst();

    // Cooldown check: if we've had N+ failures, enforce cooldown
    if (cooldownThreshold > 0 && entry.times.size() >= cooldownThreshold) {
        qint64 lastAttempt = entry.times.last();
        qint64 cooldownUntil = lastAttempt + kJoinCooldownSec * 1000;
        if (now < cooldownUntil) {
            hitCooldown = true;
            // 剩余秒数向上取整：还剩 0.2s 也要说「请 1 秒后再试」，不能说「请 0 秒」
            if (retryAfterSec)
                *retryAfterSec = static_cast<int>((cooldownUntil - now + 999) / 1000);
            return false;
        }
        // Cooldown expired, clear and retry
        entry.times.clear();
    }

    if (entry.times.size() >= maxCount) {
        // 滑动窗口打满（窗口比冷却短时才会走到）：等最早一次记录滑出窗口
        if (retryAfterSec && !entry.times.isEmpty())
            *retryAfterSec = static_cast<int>((entry.times.first() + windowMs - now + 999) / 1000);
        return false;
    }

    entry.times.append(now);
    return true;
}

void ConnectionGuard::cleanupExpired()
{
    qint64 now = QDateTime::currentMSecsSinceEpoch();

    auto cleanup = [&](QHash<QString, RateEntry>& log) {
        QStringList expired;
        for (auto it = log.begin(); it != log.end(); ++it) {
            while (!it->times.isEmpty() && it->times.first() < now - 120000)
                it->times.removeFirst();
            if (it->times.isEmpty())
                expired.append(it.key());
        }
        for (const auto& k : expired)
            log.remove(k);
    };

    cleanup(m_connectLog);
    cleanup(m_joinLog);
    cleanup(m_packetLog);
}

} // namespace
