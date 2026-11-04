// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QtGlobal>

namespace ShadowDownloader {

/// ── 兜底重试的"这包数据能不能收"判定（纯函数，自检可覆盖）──
/// 背景：最终兜底重试以前要求必须有 SHA1（expectedSha1 非空），于是 CurseForge
/// 这类"没有 sha1"的文件一旦前几轮失败就永远不会被兜底救回来。
/// 判定顺序：
///   1) 有 SHA1 且实算匹配 → 收；
///   2) 期望大小已知且实收 >= 期望 → 收（服务器忽略 Range 返回全量时会更大）；
///   3) 无 SHA1、大小未知、收到非空 → 收（没有更强的校验手段，与主路径同语义）；
///   4) 其余 → 拒（数据不完整，继续换源/重试）。
inline bool acceptFallbackPayload(bool hasSha1, bool sha1Match,
                                  qint64 expectedSize, qint64 dataSize,
                                  bool isUnknownSize)
{
    if (hasSha1 && sha1Match) return true;
    if (expectedSize > 0 && dataSize >= expectedSize) return true;
    if (!hasSha1 && isUnknownSize && dataSize > 0) return true;
    return false;
}

} // namespace ShadowDownloader
