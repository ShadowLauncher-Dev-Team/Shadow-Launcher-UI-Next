// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── 源策略 → 具体 URL（唯一来源）──
// 契约：DOWNLOAD_CONTRACT.md「源策略的三个域」。
// 「版本列表源」(listSource) 只作用于 MC 版本清单域：版本清单、版本 JSON、资源索引。
// 模组/光影平台（Modrinth/CF ↔ MCIM）是另一个域，不走这里。

#include <QString>
#include "../utils/types.h"

namespace ShadowLauncher {
namespace SourcePolicy {

/// AutoSwitch 与 PreferOfficial 同义：官方优先、失败自动切镜像
inline bool preferOfficial(DownloadSourcePolicy p) {
    return p == DownloadSourcePolicy::PreferOfficial || p == DownloadSourcePolicy::AutoSwitch;
}

inline QString mcManifestMirror() {
    return QStringLiteral("https://bmclapi2.bangbang93.com/mc/game/version_manifest.json");
}
inline QString mcManifestOfficial() {
    return QStringLiteral("https://launchermeta.mojang.com/mc/game/version_manifest.json");
}

/// 版本清单主源（MC 版本列表）
inline QString mcManifestPrimary(DownloadSourcePolicy p) {
    return preferOfficial(p) ? mcManifestOfficial() : mcManifestMirror();
}
/// 版本清单兜底源
inline QString mcManifestFallback(DownloadSourcePolicy p) {
    return preferOfficial(p) ? mcManifestMirror() : mcManifestOfficial();
}

} // namespace SourcePolicy
} // namespace ShadowLauncher
