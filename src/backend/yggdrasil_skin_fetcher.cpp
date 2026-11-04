// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "yggdrasil_skin_fetcher.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QUrl>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QLoggingCategory>
#include <QImage>
#include <QDateTime>
#include <QCoreApplication>
#include "core/render_head_util.h"

Q_LOGGING_CATEGORY(logYggSkin, "shadow.yggdrasil.skin")

namespace ShadowLauncher {

// ── 辅助：文件路径转 QML 可用的 URL ──
static QString toImageUrl(const QString& filePath)
{
    if (filePath.isEmpty()) return {};
    return QUrl::fromLocalFile(filePath).toString();
}

// ── 头部渲染：复用了正版登录的 renderHead3D 逻辑 ──
// 移植到 render_head_util.h，两边共用
static QString renderHead(const QString &fullSkinPath)
{
    return renderHeadFromSkin(fullSkinPath);
}

// ── 兜底头像：账号后端渲染好的 steve_head.png → 现场渲染随附 steve.png ──
static QString fallbackHeadFile()
{
    const QString accountHead =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        + QStringLiteral("/shadow/assets/skins/steve_head.png");
    if (QFile::exists(accountHead)) return accountHead;

    const QString source = QCoreApplication::applicationDirPath() + QStringLiteral("/skins/steve.png");
    if (!QFile::exists(source)) return {};

    const QString out = YggdrasilSkinFetcher::cacheDir() + QStringLiteral("/_fallback_head.png");
    if (QFile::exists(out)) return out;

    const QString staged = YggdrasilSkinFetcher::cacheDir() + QStringLiteral("/_fallback.png");
    if (!QFile::exists(staged)) QFile::copy(source, staged);
    const QString rendered = renderHead(staged);
    return rendered.isEmpty() ? staged : rendered;
}

// ── 缓存目录 ──

QString YggdrasilSkinFetcher::cacheDir()
{
    QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                   + QStringLiteral("/yggdrasil/skins");
    QDir().mkpath(path);
    return path;
}

// ── 构造 ──

YggdrasilSkinFetcher::YggdrasilSkinFetcher(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
{
}

// ── PCL 方案: McSkinGetAddress + McSkinDownload ──

void YggdrasilSkinFetcher::fetchSkin(const QString &apiRoot, const QString &uuid)
{
    if (apiRoot.isEmpty() || uuid.isEmpty()) {
        m_skinPath.clear();
        m_skinVariant = 0;
        emit skinChanged();
        emit skinFailed(QStringLiteral("无法获取皮肤：参数不完整"));
        return;
    }

    // PCL McSkinGetAddress: GET {apiRoot}/sessionserver/session/minecraft/profile/{uuid}
    // (variant 信息在 profile 返回中，所以先不查缓存，等 onProfileReply 里再查): GET {apiRoot}/sessionserver/session/minecraft/profile/{uuid}
    m_pendingUuid = uuid;
    m_pendingVariant = 0;

    // ── 缓存/兜底优先：先给 UI 一个可用头像。这样即使服务器不可达、令牌已失效，
    //    也不会让 MinecraftHead2D 因 skinPath 为空而无限转圈（旧实现只有网络成功才有头像）。
    const QString preCache = cacheDir() + QStringLiteral("/") + uuid + QStringLiteral(".png");
    if (QFile::exists(preCache)) {
        QString preHead = preCache.left(preCache.length() - 4) + QStringLiteral("_head.png");
        if (!QFile::exists(preHead)) preHead = renderHead(preCache);
        setSkinFromFile(preHead.isEmpty() ? preCache : preHead, m_skinVariant);
        qCDebug(logYggSkin) << "Cache hit (pre-request):" << preCache;
    } else if (m_skinPath.isEmpty()) {
        applyFallbackSkin();
    }

    QString urlStr = apiRoot;
    if (!urlStr.endsWith(QLatin1Char('/')))
        urlStr.append(QLatin1Char('/'));
    urlStr += QStringLiteral("sessionserver/session/minecraft/profile/");
    urlStr += uuid;
    urlStr += QStringLiteral("?unsigned=true");

    QNetworkRequest req{QUrl(urlStr)};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ShadowLauncher/1.0"));
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, &YggdrasilSkinFetcher::onProfileReply);

    qCDebug(logYggSkin) << "Fetching skin profile:" << urlStr;
}

void YggdrasilSkinFetcher::onProfileReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        if (m_skinPath.isEmpty()) applyFallbackSkin();
        emit skinFailed(QStringLiteral("获取皮肤信息失败: ") + reply->errorString());
        return;
    }

    QByteArray data = reply->readAll();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    QJsonObject root = doc.object();
    QJsonArray props = root.value(QStringLiteral("properties")).toArray();

    // PCL: 找 name == "textures" → value (base64)
    QString texturesBase64;
    for (const QJsonValue &v : props) {
        QJsonObject prop = v.toObject();
        if (prop.value(QStringLiteral("name")).toString() == QStringLiteral("textures")) {
            texturesBase64 = prop.value(QStringLiteral("value")).toString();
            break;
        }
    }

    if (texturesBase64.isEmpty()) {
        if (m_skinPath.isEmpty()) applyFallbackSkin();
        emit skinFailed(QStringLiteral("皮肤数据为空"));
        return;
    }

    // PCL: Base64 解码 → JSON
    QByteArray decoded = QByteArray::fromBase64(texturesBase64.toUtf8());
    QJsonObject texturesObj = QJsonDocument::fromJson(decoded).object();
    QJsonObject textures = texturesObj.value(QStringLiteral("textures")).toObject();

    // 提取 SKIN.url + metadata.model
    QString skinUrl;
    int variant = 0;
    QJsonObject skin = textures.value(QStringLiteral("SKIN")).toObject();
    if (!skin.isEmpty()) {
        skinUrl = skin.value(QStringLiteral("url")).toString();
        QJsonObject meta = skin.value(QStringLiteral("metadata")).toObject();
        if (meta.value(QStringLiteral("model")).toString() == QStringLiteral("slim"))
            variant = 1;
    }

    if (skinUrl.isEmpty()) {
        if (m_skinPath.isEmpty()) applyFallbackSkin();
        emit skinFailed(QStringLiteral("用户未设置自定义皮肤"));
        return;
    }

    // 再查一次缓存（第一次查时 variant 还未解析）
    QString cachedPath = cacheDir() + QStringLiteral("/") + m_pendingUuid + QStringLiteral(".png");
    if (QFile::exists(cachedPath)) {
        QString headPath = cachedPath.left(cachedPath.length() - 4) + QStringLiteral("_head.png");
        if (!QFile::exists(headPath))
            headPath = renderHead(cachedPath);
        if (headPath.isEmpty())
            headPath = cachedPath;  // fallback: 用完整皮肤
        setSkinFromFile(headPath, variant);
        qCDebug(logYggSkin) << "Cache hit (post-parse):" << cachedPath;
        return;
    }

    // PCL McSkinDownload: 下载皮肤 PNG
    m_pendingVariant = variant;
    QNetworkRequest skinReq{QUrl(skinUrl)};
    skinReq.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ShadowLauncher/1.0"));
    QNetworkReply *dlReply = m_nam->get(skinReq);
    connect(dlReply, &QNetworkReply::finished, this, &YggdrasilSkinFetcher::onDownloadReply);
}

void YggdrasilSkinFetcher::onDownloadReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        if (m_skinPath.isEmpty()) applyFallbackSkin();
        emit skinFailed(QStringLiteral("下载皮肤失败: ") + reply->errorString());
        return;
    }

    QByteArray pngData = reply->readAll();

    // PCL: 下载到 .downloading → 重命名（防写一半进程崩）
    QString cachedPath = cacheDir() + QStringLiteral("/") + m_pendingUuid + QStringLiteral(".png");
    QString tmpPath = cachedPath + QStringLiteral(".downloading");

    QFile file(tmpPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(pngData);
        file.close();
        QFile::remove(cachedPath);
        QFile::rename(tmpPath, cachedPath);
        // 生成头部裁剪
        QString headPath = renderHead(cachedPath);
        if (headPath.isEmpty()) headPath = cachedPath;  // fallback: 用完整皮肤
        setSkinFromFile(headPath, m_pendingVariant);
        qCDebug(logYggSkin) << "Skin cached:" << cachedPath;
        return;
    }

    emit skinFailed(QStringLiteral("保存皮肤缓存失败"));
    if (m_skinPath.isEmpty()) applyFallbackSkin();
}

// ── 设置皮肤路径（带 cache-buster，保证 QML 端重新读取）──
void YggdrasilSkinFetcher::setSkinFromFile(const QString &filePath, int variant)
{
    if (filePath.isEmpty()) return;
    m_skinPath = toImageUrl(filePath)
                 + QStringLiteral("?t=%1").arg(QDateTime::currentMSecsSinceEpoch());
    m_skinVariant = variant;
    emit skinChanged();
    emit skinReady();
}

// ── 网络失败/无缓存时的兜底头像 ──
void YggdrasilSkinFetcher::applyFallbackSkin()
{
    const QString fb = fallbackHeadFile();
    if (fb.isEmpty()) {
        qCWarning(logYggSkin) << "No fallback head available";
        return;
    }
    setSkinFromFile(fb, 0);
    qCDebug(logYggSkin) << "Using fallback head:" << fb;
}

} // namespace ShadowLauncher
