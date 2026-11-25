// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "yggdrasil_skin_fetcher.h"
#include "core/yggdrasil_auth.h"   // YggdrasilMeta::skinHostAllowedFor（皮肤域名白名单）
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
#include <QCryptographicHash>
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

// ── 缓存文件名：uuid 来自服务器响应，绝不能直接拼进路径 ──
// 实测（2026-11-25 审计）：authlib 服务器把 selectedProfile.id 回成
// "../../../../PWNED_TRAVERSAL" 时，缓存被写到 %APPDATA%\PWNED_TRAVERSAL.png，
// 即"远端可写任意路径的 .png"。这里只保留安全字符，异常值退化为哈希。
static QString safeCacheStem(const QString &uuid)
{
    QString stem;
    stem.reserve(qMin(uuid.size(), 64));
    for (const QChar &ch : uuid) {
        const ushort u = ch.unicode();
        if ((u >= '0' && u <= '9') || (u >= 'a' && u <= 'z')
            || (u >= 'A' && u <= 'Z') || u == QLatin1Char('-'))
            stem.append(ch);
    }
    if (stem.isEmpty() || stem.size() > 64)
        return QString::fromLatin1(QCryptographicHash::hash(uuid.toUtf8(), QCryptographicHash::Sha1)
                                       .toHex().left(32));
    return stem;
}

// ── 下载结果校验：不是 PNG / 太大 / 尺寸离谱一律不落盘 ──
// 实测（同日审计）：站点对 /skin.png 回 200 + "<html>..." 时，这段 HTML 被写进
// skins/<uuid>.png 并当成头像发布给 QML（头像永远的坏图，且下次命中缓存不再重下）。
static bool isUsableSkinPng(const QByteArray &data)
{
    constexpr int kMaxSkinBytes = 4 * 1024 * 1024;
    if (data.size() < 64 || data.size() > kMaxSkinBytes) return false;
    if (!data.startsWith("\x89PNG\r\n\x1a\n")) return false;
    QImage probe;
    if (!probe.loadFromData(data, "PNG")) return false;
    // 允许高清皮肤（128/256/512），只挡掉明显不是皮肤的尺寸
    return probe.width() >= 32 && probe.height() >= 32
        && probe.width() <= 1024 && probe.height() <= 1024;
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

void YggdrasilSkinFetcher::fetchSkin(const QString &apiRoot, const QString &uuid,
                                      const QStringList &allowedSkinDomains)
{
    if (apiRoot.isEmpty() || uuid.isEmpty()) {
        m_skinPath.clear();
        m_skinVariant = 0;
        emit skinChanged();
        emit skinFailed(QStringLiteral("无法获取皮肤：参数不完整"));
        return;
    }

    // PCL McSkinGetAddress: GET {apiRoot}/sessionserver/session/minecraft/profile/{uuid}
    // 缓存命中时先按上一轮的 variant 出图，等 profile 返回后再用其中的 model 校正
    // 换账号：上一个账号的头像立刻作废。留着它只会让"新账号拉取失败"看起来
    // 像"新账号就是这个脸"（也更不该在失败时回落到别人的皮肤）。
    if (m_skinOwnerUuid != uuid) {
        m_skinPath.clear();
        m_skinVariant = 0;
        m_skinOwnerUuid.clear();
    }
    m_pendingUuid = uuid;
    m_pendingVariant = 0;
    m_pendingSkinDomains = allowedSkinDomains;

    // ── 缓存/兜底优先：先给 UI 一个可用头像。这样即使服务器不可达、令牌已失效，
    //    也不会让 MinecraftHead2D 因 skinPath 为空而无限转圈（旧实现只有网络成功才有头像）。
    const QString preCache = cacheDir() + QStringLiteral("/") + safeCacheStem(uuid) + QStringLiteral(".png");
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
    QString cachedPath = cacheDir() + QStringLiteral("/") + safeCacheStem(m_pendingUuid) + QStringLiteral(".png");
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

    // 下载前先校验主机是否在站点声明的 skinDomains 内。
    // 站点没声明时 YggdrasilMeta::skinHostAllowedFor 直接放行（保持旧行为），
    // 只有"声明了白名单却指向别处"才拦 —— 那种情况基本就是 profile 被篡改。
    if (!YggdrasilMeta::skinHostAllowedFor(m_pendingSkinDomains, skinUrl)) {
        qCWarning(logYggSkin) << "Skin URL host not in skinDomains, refusing to download:"
                              << skinUrl << "domains=" << m_pendingSkinDomains;
        if (m_skinPath.isEmpty()) applyFallbackSkin();
        emit skinFailed(QStringLiteral("皮肤地址不在该站点声明的域名内，已跳过下载"));
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

    if (!isUsableSkinPng(pngData)) {
        qCWarning(logYggSkin) << "Downloaded skin is not a usable PNG, discarding: bytes="
                              << pngData.size();
        // 坏图绝不留进缓存：留下就等于把"坏头像"固化成该账号的皮肤
        if (m_skinPath.isEmpty()) applyFallbackSkin();
        emit skinFailed(QStringLiteral("皮肤文件无效（不是有效的 PNG），已使用默认头像"));
        return;
    }

    // PCL: 下载到 .downloading → 重命名（防写一半进程崩）
    QString cachedPath = cacheDir() + QStringLiteral("/") + safeCacheStem(m_pendingUuid) + QStringLiteral(".png");
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
    m_skinOwnerUuid = m_pendingUuid;   // 这张图属于哪个账号：换账号时据此作废
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
