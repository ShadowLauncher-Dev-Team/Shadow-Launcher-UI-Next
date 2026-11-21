// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── 区域判定 ──
// 用途：下载设置一次性迁移（settings_backend 的 regionPolicyV1）时标注国内/其他，
// 供日志与人工排障；它不再决定源策略——下载源「自动」已改为官方优先、与区域
// 无关（见 source_policy.h 的 preferOfficial）。单发首字节会误判：官方 CDN 首字节
// 虽慢，并发吞吐却远高于 302 到第三方节点池的 BMCLAPI。
//
// 判定顺序：系统时区 → 系统区域代码。两者任一命中「中国」即认为在国内。
// 不联网、不引入第三方库，纯本地判断。

#include <QDateTime>
#include <QLocale>
#include <QString>
#include <QTimeZone>

namespace ShadowLauncher {
namespace RegionUtils {

inline bool isChinaTimeZone()
{
    const QString id = QTimeZone::systemTimeZoneId().toLower();
    if (id.isEmpty())
        return false;
    return id == QStringLiteral("asia/shanghai")
        || id == QStringLiteral("asia/chongqing")
        || id == QStringLiteral("asia/harbin")
        || id == QStringLiteral("asia/urumqi")
        || id == QStringLiteral("prc")
        || id == QStringLiteral("asia/hong_kong")
        || id == QStringLiteral("asia/macau")
        || id == QStringLiteral("asia/taipei");
}

inline bool isChinaLocale()
{
    const QLocale::Country c = QLocale::system().country();
    return c == QLocale::China || c == QLocale::HongKong || c == QLocale::Macau
        || c == QLocale::Taiwan;
}

/// 是否位于中国（含港澳台）。缓存一次：时区/区域在进程生命周期内不会变。
inline bool isChinaRegion()
{
    static const bool v = isChinaTimeZone() || isChinaLocale();
    return v;
}

} // namespace RegionUtils
} // namespace ShadowLauncher
