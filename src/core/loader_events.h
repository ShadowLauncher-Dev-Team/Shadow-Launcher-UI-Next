// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── 安装器事件 → 步骤 key 的映射（单一来源）──
// 目标：把"安装器进度语义"与"步骤推进"解耦。安装器只报语义（主文件/校验/依赖库/安装），
// 由这张表决定落到哪个 key；换安装器实现时不用改步骤推进。
// 注意：OptiFine 没有"校验"步骤（jarKey 之后直接 installKey），Fabric 的"主文件"是配置。

#include <QString>
#include "step_keys.h"

namespace ShadowLauncher {
namespace LoaderEvents {

struct Map {
    QString artifactKey;   // 主文件 / 配置（安装器 jar、Fabric profile、OptiFine jar）
    QString verifyKey;     // 校验步骤（可能为空：OptiFine 无）
    QString libsKey;       // 安装器依赖库（可能为空：OptiFine 无）
    QString installKey;    // 安装步骤
    QString loaderLabel;   // Forge / NeoForge / Fabric / OptiFine
};

inline Map forLoader(const QString& loaderType)
{
    if (loaderType == QStringLiteral("fabric"))
        return Map{ StepKeys::fabricConfig(), QString(), StepKeys::fabricLibs(),
                    StepKeys::fabricInstall(), QStringLiteral("Fabric") };
    if (loaderType == QStringLiteral("optifine"))
        return Map{ StepKeys::optifineJar(), QString(), QString(),
                    StepKeys::optifineInstall(), QStringLiteral("OptiFine") };
    if (loaderType == QStringLiteral("neoforge"))
        return Map{ StepKeys::loaderInstaller(), StepKeys::loaderVerify(), StepKeys::loaderLibs(),
                    StepKeys::loaderInstall(), QStringLiteral("NeoForge") };
    // forge 及默认
    return Map{ StepKeys::loaderInstaller(), StepKeys::loaderVerify(), StepKeys::loaderLibs(),
                StepKeys::loaderInstall(), QStringLiteral("Forge") };
}

} // namespace LoaderEvents
} // namespace ShadowLauncher
