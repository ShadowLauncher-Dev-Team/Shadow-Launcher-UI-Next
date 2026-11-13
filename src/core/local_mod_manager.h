// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVariantList>
#include <QVector>
#include <QSet>

namespace ShadowLauncher {

struct LocalModEntry {
    QString fileName;      // e.g. "sodium-fabric-0.6.10.jar" (disabled: "sodium-fabric-0.6.10.jar.disabled")
    QString modName;       // e.g. "Sodium"
    QString modId;         // e.g. "sodium"
    QString version;       // e.g. "0.6.10"
    QString description;
    QString iconPath;      // cache file path (empty if no icon)
    QStringList authors;
    QString loader;        // "fabric", "forge", "neoforge", "unknown"
    qint64 fileSize = 0;
    QString fileSizeText;  // e.g. "892 KB"
    bool valid = false;    // JAR parse succeeded
    bool enabled = true;   // false = file renamed to *.jar.disabled (2026-08-07)
};

struct LocalResourcePackEntry {
    QString fileName;      // e.g. "Faithful.zip"
    QString displayName;   // From pack.mcmeta description or baseName (color codes stripped)
    int packFormat = 0;    // pack_format from pack.mcmeta
    QString versionLabel;  // Human-readable: "格式 34 · 1.20.5+"
    QString description;   // From pack.mcmeta description
    QString iconPath;      // Cached pack.png path (empty if no icon)
    qint64 fileSize = 0;
    QString fileSizeText;  // e.g. "2.2 MB"
    bool valid = false;    // ZIP parse succeeded
};

// 光影包（shaderpacks/，2026-11-13）
// 和资源包的区别：没有 pack.mcmeta 可读，也没有游戏内开关；
// 启/禁用靠文件名后缀（.zip ↔ .zip.disabled，与 Mod 的 jar ↔ jar.disabled 同一套约定）。
struct LocalShaderPackEntry {
    QString fileName;      // e.g. "BSL_v8.2.zip" / "BSL_v8.2.zip.disabled" / 解包文件夹名
    QString displayName;   // 去掉 .disabled 后缀与扩展名的显示名
    QString description;   // 光影包没有统一的元数据格式，目前留空
    QString iconPath;      // 光影包没有图标规范（Iris / OptiFine 都不提供），目前为空
    qint64 fileSize = 0;
    QString fileSizeText;  // e.g. "4.1 MB"
    bool valid = false;
    bool enabled = true;   // false = 文件名以 .disabled 结尾
    bool isFolder = false; // true = shaderpacks/<文件夹>/shaders 的解包态（只列出，不提供启/禁用）
};

class LocalModManager : public QObject {
    Q_OBJECT
public:
    explicit LocalModManager(QObject* parent = nullptr);

    // Set the game directory base (e.g. ".minecraft")
    void setGameDir(const QString& dir);
    QString gameDir() const;

    // Scan mods folder for a given version, return parsed entries
    QVariantList scanMods(const QString& versionId);

    // Import a JAR file to the mods folder (copy), trigger scan
    bool importMod(const QString& filePath, const QString& versionId);

    // Delete a mod by filename
    bool deleteMod(const QString& fileName, const QString& versionId);

    // Enable/disable a mod (rename *.jar ↔ *.jar.disabled, aligned with 主流启动器/主流启动器)
    bool setModEnabled(const QString& fileName, const QString& versionId, bool enabled);
    /// 批量全部启用/禁用（2026-08-11）：遍历 mods 目录 jar ↔ jar.disabled，返回实际改动数
    int setAllModsEnabled(const QString& versionId, bool enabled);

    // Open the mods folder in explorer
    bool openModsFolder(const QString& versionId);

    // Get mods folder path for a version
    QString modsDir(const QString& versionId) const;

    // ── Resource Pack operations ──
    // Scan resourcepacks folder for a given version, return parsed entries
    QVariantList scanResourcePacks(const QString& versionId);

    // Import a ZIP resource pack to the resourcepacks folder (copy), trigger scan
    bool importResourcePack(const QString& filePath, const QString& versionId);

    // Delete a resource pack by filename
    bool deleteResourcePack(const QString& fileName, const QString& versionId);

    // Get resourcepacks folder path for a version
    QString resourcePacksDir(const QString& versionId) const;

    // ── Shader Pack operations（光影包，2026-11-13）──
    // 扫描 shaderpacks 目录：*.zip（启用）/ *.zip.disabled（禁用），
    // 外加含 shaders/ 子目录的解包态光影（只列出）。
    // 光影包没有标准的元数据/图标文件，所以只给名字、大小、启用态，不解压 zip（几十 MB 的包解一次不值）。
    QVariantList scanShaderPacks(const QString& versionId);

    // 导入 zip 光影包（复制进 shaderpacks/，重名自动加序号）
    bool importShaderPack(const QString& filePath, const QString& versionId);

    // 删除光影包（zip 删文件，解包态删整个文件夹）
    bool deleteShaderPack(const QString& fileName, const QString& versionId);

    // 启/禁用：x.zip ↔ x.zip.disabled（游戏只扫 *.zip，改名即等于从光影列表里消失）
    bool setShaderPackEnabled(const QString& fileName, const QString& versionId, bool enabled);

    // Get shaderpacks folder path for a version（与 resourcePacksDir 同一套隔离判定）
    QString shaderPacksDir(const QString& versionId) const;

    // Cache directory for extracted icons

signals:
    void modsChanged(const QString& versionId);
    void importFinished(const QString& fileName, bool success, const QString& error);

private:
    LocalModEntry parseJar(const QString& jarPath);
    LocalModEntry parseFabricJson(const QByteArray& data, const QString& jarPath, const QString& fileName, qint64 fileSize);
    LocalModEntry parseNeoForgeToml(const QByteArray& data, const QString& jarPath, const QString& fileName, qint64 fileSize);
    LocalModEntry parseForgeMcmodInfo(const QByteArray& data, const QString& jarPath, const QString& fileName, qint64 fileSize);
    QString extractJarIcon(const QByteArray& jarData, const QString& iconInternalPath, const QString& modId);

    // Resource pack helpers
    LocalResourcePackEntry parseResourcePackZip(const QString& zipPath);
    QString extractPackPng(const QByteArray& zipData, const QString& packName);
    static QString packFormatToVersionLabel(int packFormat);
    static QString stripColorCodes(const QString& text);

    // Shader pack helpers
    static QVariantMap spEntryToMap(const LocalShaderPackEntry& e);

    QString formatFileSize(qint64 bytes) const;
    QVariantMap entryToMap(const LocalModEntry& e) const;
    static QVariantMap rpEntryToMap(const LocalResourcePackEntry& e);

    QString m_gameDir;
    QString m_iconCacheDir;
};

} // namespace ShadowLauncher
