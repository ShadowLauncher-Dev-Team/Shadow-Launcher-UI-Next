// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── 下载步骤词表（唯一来源）──
// 契约：DOWNLOAD_CONTRACT.md 第 1 节。
// 三条安装路径（原版 / 加载器 / 整合包）共用同一套 key；显示名只由 UI 决定，
// 后端业务逻辑一律按 key 找步骤，**不再按中文名子串匹配**。
//
// 迁移期：旧代码还在按中文名找步骤，keyForLegacyName() 提供"旧名 → key"的桥，
// 等所有调用点改成 stepIndexByKey 之后即可删除。

#include <QString>
#include <QHash>

namespace ShadowLauncher {
namespace StepKeys {

// ── key 常量（不要手写字符串，用这里的函数）──
inline QString baseJson()       { return QStringLiteral("base.json"); }
inline QString baseLibraries()  { return QStringLiteral("base.libraries"); }
inline QString baseAssets()     { return QStringLiteral("base.assets"); }
inline QString baseVerify()     { return QStringLiteral("base.verify"); }
inline QString baseJar()        { return QStringLiteral("base.jar"); }

inline QString loaderInstaller(){ return QStringLiteral("loader.installer"); }
inline QString loaderVerify()   { return QStringLiteral("loader.verify"); }
inline QString loaderLibs()     { return QStringLiteral("loader.libs"); }
inline QString loaderInstall()  { return QStringLiteral("loader.install"); }

inline QString fabricConfig()   { return QStringLiteral("fabric.config"); }
inline QString fabricLibs()     { return QStringLiteral("fabric.libs"); }
inline QString fabricInstall()  { return QStringLiteral("fabric.install"); }
inline QString fabricApi()      { return QStringLiteral("fabric.api"); }

inline QString optifineJar()    { return QStringLiteral("optifine.jar"); }
inline QString optifineInstall(){ return QStringLiteral("optifine.install"); }

inline QString metaResolve()    { return QStringLiteral("meta.resolve"); }
inline QString metaOverrides()  { return QStringLiteral("meta.overrides"); }
inline QString modsDownload()   { return QStringLiteral("mods.download"); }
inline QString modsVerify()     { return QStringLiteral("mods.verify"); }
inline QString javaCheck()      { return QStringLiteral("java.check"); }
inline QString javaInstall()    { return QStringLiteral("java.install"); }
inline QString userdataImport() { return QStringLiteral("userdata.import"); }

/// 旧中文步骤名 → key（迁移期桥接；新代码不要用）
inline QString keyForLegacyName(const QString& name)
{
    if (name.isEmpty()) return QString();
    // 原版路径
    if (name.contains(QStringLiteral("下载版本JSON")))      return baseJson();
    if (name.contains(QStringLiteral("下载支持库")))         return baseLibraries();
    if (name.contains(QStringLiteral("下载资源文件")))       return baseAssets();
    if (name.contains(QStringLiteral("校验游戏资源完整性"))) return baseVerify();
    // 合并路径（原版部分）
    if (name.contains(QStringLiteral("下载原版 JSON")))     return baseJson();
    if (name.contains(QStringLiteral("下载原版支持库")))     return baseLibraries();
    if (name.contains(QStringLiteral("下载原版资源")))       return baseAssets();
    // 加载器
    if (name.contains(QStringLiteral("下载 Fabric 配置")))   return fabricConfig();
    if (name.contains(QStringLiteral("下载 Fabric 依赖库"))) return fabricLibs();
    if (name.contains(QStringLiteral("安装 Fabric")))        return fabricInstall();
    if (name.contains(QStringLiteral("下载 Fabric API")))    return fabricApi();
    if (name.contains(QStringLiteral("安装器库")))           return loaderLibs();
    if (name.contains(QStringLiteral("主文件")))             return loaderInstaller();
    if (name.contains(QStringLiteral("校验")) && name.contains(QStringLiteral("完整性")))
        return loaderVerify();
    if (name.startsWith(QStringLiteral("安装 ")))            return loaderInstall();
    return QString();
}

} // namespace StepKeys
} // namespace ShadowLauncher
