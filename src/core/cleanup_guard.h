// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── 清理/守卫的纯逻辑（可自检）──
// 抽出来的目的：这两段逻辑后果分别是"误删整版"和"磁盘残留"，不该只靠真机时序验证。

#include <QString>
#include <QStringList>
#include <QDir>
#include <QFileInfo>

namespace ShadowLauncher {
namespace CleanupGuard {

/// 版本目录里是否存在用户存档。三种布局都要认：
///   versions/<id>/saves            （标准）
///   versions/<id>/game/saves       （版本隔离）
///   <gameDir>/saves                （共享根）
/// 命中任一即视为"玩过"，取消清理必须跳过删除。
inline bool dirHasUserSaves(const QString& versionDir, const QString& gameDir)
{
    const QStringList candidates = {
        versionDir + QStringLiteral("/saves"),
        versionDir + QStringLiteral("/game/saves"),
        gameDir + QStringLiteral("/saves"),
    };
    for (const QString& p : candidates) {
        if (!p.isEmpty() && QDir(p).exists()) return true;
    }
    return false;
}

/// 删除资源索引输家留下的 <fileName>.part.* 分片（镜像先赢时官方分片永远不会被回调清理）。
/// 返回删除的文件数。
inline int removeStaleIndexParts(const QString& dir, const QString& fileName)
{
    if (dir.isEmpty() || fileName.isEmpty()) return 0;
    QDir d(dir);
    if (!d.exists()) return 0;
    const QStringList stale = d.entryList({ fileName + QStringLiteral(".part.*") }, QDir::Files);
    int removed = 0;
    for (const QString& f : stale) {
        if (QFile::remove(d.absoluteFilePath(f))) ++removed;
    }
    return removed;
}

} // namespace CleanupGuard
} // namespace ShadowLauncher
