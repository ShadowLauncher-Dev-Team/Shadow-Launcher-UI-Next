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

// ── 请求类别 → 取源方式（统一决策点）──
// 结论（2026-11-05 核实）：元数据与大文件的最优策略不同，这不算混乱；
// 混乱的是"每个调用点自己决定"（3 处 setPreferOfficial(false) 硬编码）。
//   Metadata：几 KB 的 JSON/HTML，两个源都可能快 → 竞速，先成功者赢（延迟最优）
//   Artifact：单个 10–20MB 安装器/大文件 → 优先源先发，另一个兜底（吞吐最优，且只需一次失败转移）
enum class RequestClass {
    Metadata,        // version_manifest / 版本 JSON / 资源索引 / 加载器 meta 列表（小、快、谁快用谁）
    McFile,          // MC jar / libraries / assets（大文件，跟随「文件下载源」）
    LoaderArtifact   // Forge/NeoForge 安装器与 Maven 依赖（大文件，但官方 Maven 在国内长期偏慢）
};

struct SourceRoute {
    bool race;              // true = 双源同时发；false = 优先源先发、失败换源
    bool preferOfficial;    // race=false 时的优先源
};

inline SourceRoute routeFor(RequestClass cls, DownloadSourcePolicy fileSource,
                            DownloadSourcePolicy listSource)
{
    switch (cls) {
    case RequestClass::Metadata:
        return SourceRoute{ true, preferOfficial(listSource) };
    case RequestClass::LoaderArtifact:
        // 镜像优先 + 官方兜底：这不是拍脑袋，而是因为 files.minecraftforge.net /
        // maven.neoforged.net 在国内长期偏慢且会断，BMCLAPI 的 Maven 缓存是快路径。
        // 与「文件下载源」分开是刻意的：MC 文件与加载器 Maven 是两个不同的宿主集合。
        Q_UNUSED(fileSource);
        return SourceRoute{ false, false };
    case RequestClass::McFile:
    default:
        return SourceRoute{ false, preferOfficial(fileSource) };
    }
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
