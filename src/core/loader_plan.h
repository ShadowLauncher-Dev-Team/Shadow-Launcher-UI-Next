// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── 加载器安装"计划"（LoaderPlan）──
// 目标：四条安装路径的步骤清单/权重/显隐只在这里定义一次。
// 编排层只管"按 plan 建步骤、跑安装器、收尾"，不再各自拼数组。
// 安装器内部算法（Forge installer/loader libs 解析等）不在本文件范围内。

#include <QString>
#include <QStringList>
#include <QVector>
#include "step_keys.h"

namespace ShadowLauncher {
namespace LoaderPlan {

struct Plan {
    QString loaderLabel;        // "Forge" / "NeoForge" / "Fabric" / "OptiFine" / 空
    QStringList keys;
    QVector<qreal> weights;
    QVector<bool> shows;
};

/// loaderType: "vanilla"(或空) / "fabric" / "forge" / "neoforge" / "optifine"
/// hasFabricApi: Fabric 路径是否追加 Fabric API 步骤
inline Plan make(const QString& loaderType, bool hasFabricApi = false)
{
    Plan p;
    if (loaderType == QStringLiteral("fabric")) {
        p.loaderLabel = QStringLiteral("Fabric");
        p.keys = {StepKeys::baseJson(), StepKeys::baseLibraries(), StepKeys::baseAssets(),
                  StepKeys::baseVerify(), StepKeys::fabricConfig(), StepKeys::fabricLibs(),
                  StepKeys::fabricInstall()};
        p.weights = {3.0, 8.0, 5.0, 0.5, 0.1, 2.0, 0.5};
        p.shows = {true, true, true, true, true, true, true};
        if (hasFabricApi) {
            p.keys.append(StepKeys::fabricApi());
            p.weights.append(0.05);
            p.shows.append(true);
        }
        return p;
    }
    if (loaderType == QStringLiteral("optifine")) {
        p.loaderLabel = QStringLiteral("OptiFine");
        p.keys = {StepKeys::baseJson(), StepKeys::baseLibraries(), StepKeys::baseAssets(),
                  StepKeys::optifineJar(), StepKeys::optifineInstall()};
        p.weights = {1.0, 8.0, 5.0, 3.0, 1.0};
        p.shows = {true, true, true, true, true};
        return p;
    }
    if (loaderType == QStringLiteral("forge") || loaderType == QStringLiteral("neoforge")) {
        p.loaderLabel = (loaderType == QStringLiteral("neoforge"))
                            ? QStringLiteral("NeoForge") : QStringLiteral("Forge");
        p.keys = {StepKeys::baseJson(), StepKeys::baseLibraries(), StepKeys::baseAssets(),
                  StepKeys::baseVerify(), StepKeys::loaderInstaller(), StepKeys::loaderVerify(),
                  StepKeys::loaderLibs(), StepKeys::loaderInstall()};
        p.weights = {3.0, 8.0, 5.0, 0.5, 6.0, 0.5, 4.0, 6.0};
        p.shows = {true, true, true, true, true, true, true, true};
        return p;
    }
    // vanilla
    p.keys = {StepKeys::baseJson(), StepKeys::baseLibraries(), StepKeys::baseAssets(),
              StepKeys::baseVerify()};
    p.weights = {1.0, 3.0, 5.0, 1.0};
    p.shows = {false, true, true, true};   // JSON 步下载前隐藏
    return p;
}

} // namespace LoaderPlan
} // namespace ShadowLauncher
