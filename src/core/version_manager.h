// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QObject>
#include <QVector>
#include <QString>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <future>

#include "../utils/types.h"

namespace ShadowLauncher {

class VersionManager : public QObject {
    Q_OBJECT

public:
    explicit VersionManager(QObject* parent = nullptr);
    ~VersionManager() override;

    // ── 配置 ──
    void setDataDir(const QString& path) { m_dataDir = path; }
    /// 下载源策略：true=官方清单优先（BMCLAPI 兜底）；false=BMCLAPI 优先（默认）
    void setPreferOfficial(bool v) { m_preferOfficial = v; }
    QString dataDir() const { return m_dataDir; }

    void setGameDir(const QString& path) { m_gameDir = path; }
    QString gameDir() const { return m_gameDir; }

    // ── 版本获取 ──
    /// 触发异步获取版本列表：有缓存立即发一次 versionsReady（界面秒开），
    /// 随后**总是**后台回源校验；内容有变化再发一次 versionsReady 并覆盖缓存。
    /// 每次调用都会回源，所以"刷新版本列表"能真正拿到新版本。
    void fetchVersions();

    /// 返回已加载的版本列表（不触发网络请求）
    QVector<McVersion> cachedVersions() const { return m_versions; }
    bool hasVersions() const { return !m_versions.isEmpty(); }

    // ── 安装状态 ──
    /// 检查版本是否已安装（{gameDir}/versions/{versionId}/{versionId}.json 存在）
    bool isInstalled(const QString& versionId) const;

    /// 获取版本安装路径
    QString getVersionPath(const QString& versionId) const;

    // ── 缓存 ──
    /// 从缓存文件加载（成功返回 true）
    bool loadFromCache();

    /// 保存当前版本列表到缓存文件
    void saveToCache() const;

    /// 缓存文件路径
    QString cacheFilePath() const;

    /// 网络获取（无缓存时，内部使用）
    void doNetworkFetch();

signals:
    /// 版本列表就绪（数量可能为 0，表示没有可用版本）
    void versionsReady(const QVector<McVersion>& versions);

    /// 网络请求出错
    void fetchError(const QString& error);

private:
    /// 应用一份新清单：内容变化才发 versionsReady，并覆盖缓存
    void applyManifest(const QVector<McVersion>& parsed, const QString& from);

    /// 解析 Mojang version_manifest.json
    QVector<McVersion> parseManifest(const QByteArray& rawJson) const;

    // ── 成员 ──
    QNetworkAccessManager* m_nam = nullptr;
    QVector<McVersion> m_versions;
    QString m_dataDir;
    QString m_gameDir;
    bool m_preferOfficial = false;   // 版本清单源策略（官方优先 / 镜像优先）
    bool m_fetching = false;         // 回源请求在途（防重复点击/重复 fetch 打出多份请求）
    bool m_servedFromCache = false;  // 本轮已用缓存兜底过（决定失败时是否发 fetchError）
    std::future<void> m_cacheLoadFuture;
};

} // namespace ShadowLauncher
