// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── 区域判定（2026-11-18）──
// 用途：下载源「自动」策略要按区域择优。国内的实际情况是 Mojang 官方 CDN
// （resources.download.minecraft.net / libraries.minecraft.net）单次请求首字节
// 280–800ms，而 BMCLAPI 只要 50–70ms —— 同一个文件差 4–10 倍。
// 这部分与 HMCL 做法一致（HMCLDownloadProvider：RegionUtils.MACHINE_REGION == "CN"
// 时 DEFAULT 策略 mirrorFirst = true）。
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
