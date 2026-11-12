// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "account_backend.h"
#include "../secrets.h"
#include "../utils/logger.h"
#include "../utils/token_crypto.h"
#include "../utils/secure_wipe.h"
#include <cmath>
#include <vector>
#include <QCoreApplication>
#include <algorithm>
#include <cstring>

#include <QCryptographicHash>
#include <QTimer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPainter>
#include <QPointer>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <QDateTime>

#include "core/http_client.h"

namespace ShadowLauncher {

// ────────────────────────────────────────────────────────────
// Constructor
// ────────────────────────────────────────────────────────────

AccountBackend::AccountBackend(QObject *parent)
    : QObject(parent)
{
    m_dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                + QStringLiteral("/shadow");

    // Ensure skin cache directory exists
    QDir().mkpath(m_dataDir + QStringLiteral("/assets/skins"));
    qCInfo(logAccount) << QStringLiteral("账号模块已初始化");

    loadOfflineHistory();
    loadMicrosoftSession();
    loadAccounts();
    // 已登录的正版会话若不在列表里（从旧版本升级上来），补登记一次；
    // 否则左列账号列表是空的、右侧却在显示某个账号。
    if (m_loggedIn && m_isOnline && !m_username.isEmpty()) {
        bool knownAccount = false;
        for (const StoredAccount &a : m_accounts)
            if (a.mode == 0 && a.name.compare(m_username, Qt::CaseInsensitive) == 0) { knownAccount = true; break; }
        if (!knownAccount) {
            StoredAccount sa;
            sa.mode = 0;
            sa.name = m_username;
            sa.uuid = m_uuid;
            sa.refreshToken = m_msRefreshToken;
            upsertAccount(sa, true);
        }
    }

    // 启动时若恢复出了正版会话，后台会接着刷令牌、拉 MC 档案、下披风 ——
    // 这几秒里账户页同样是空白的，必须从这一刻就点亮顶部光条。
    // （之前只在 switchAccount 里置位，导致「首次进入账户页没有光条、
    //   而切号回来却有」这种不对称。）
    if (m_loggedIn && m_isOnline && !m_username.isEmpty()) {
        setIdentityLoading(true);
        // 兜底：万一令牌链 / 档案请求卡死，20s 后收掉
        QTimer::singleShot(20000, this, [this]() {
            if (m_identityLoading) {
                qCWarning(logAccount) << QStringLiteral("启动装载超时，收掉加载状态");
                setIdentityLoading(false);
            }
        });
    }

    // 头像就绪时给当前账号存一份快照（列表用；非当前账号也能显示头像）
    connect(this, &AccountBackend::skinReady, this, &AccountBackend::saveCurrentAvatarSnapshot);
    connect(this, &AccountBackend::skinReady, this, &AccountBackend::persistCurrentProfile);
    connect(this, &AccountBackend::capesReady, this, &AccountBackend::persistCurrentProfile);
    connect(this, &AccountBackend::offlineSkinReady, this, &AccountBackend::saveCurrentAvatarSnapshot);

    // Pre-render Steve and Alex offline heads (once, persistent)
    initOfflineHeads();

    // ── MicrosoftAuth ──
    m_msAuth = new MicrosoftAuth(this);
    connect(m_msAuth, &MicrosoftAuth::loginProgress, this, [this](const QString& step, const QString& detail) {
        // detail 为空时不要留一个孤零零的冒号（"Minecraft 认证: "那种）
        m_msStatus = detail.isEmpty() ? step : (step + QStringLiteral(": ") + detail);
        emit microsoftLoginProgress(step, detail);
    });
    connect(m_msAuth, &MicrosoftAuth::loginSuccess, this, [this](const QString& mcToken, const QString& username, const QString& uuid, const QString& refreshToken, int expiresIn) {
        m_msMcToken = mcToken;
        // 刷新令牌始终以非空值更新。MicrosoftAuth 现在会把刷新后的令牌透传回来
        // （旧实现用 m_refreshingToken 当闸门：该标记一旦假死，互动登录拿到的新刷新令牌
        //  会被直接丢弃 → 会话永久失去自动续期能力 → 重启后“会话无刷新令牌,已清除”）。
        if (!refreshToken.isEmpty()) {
            m_msRefreshToken = refreshToken;
        }
        m_username = username;
        m_uuid = uuid;
        m_loggedIn = true;
        m_isOnline = true;
        m_msStatus.clear();
        m_msTokenObtainedAt = QDateTime::currentSecsSinceEpoch();
        m_msTokenExpiresIn = expiresIn;  // from Mojang API response
        qCInfo(logAccount) << QStringLiteral("正版登录成功: ") << username << uuid
                           << "refreshToken:" << (refreshToken.isEmpty() ? QStringLiteral("EMPTY!") : QStringLiteral("present"));
        saveMicrosoftSession();
        {
            StoredAccount sa;
            sa.mode = 0;
            sa.name = m_username;
            sa.uuid = m_uuid;
            sa.refreshToken = m_msRefreshToken;
            // 续期刷新不应改变"当前账号"，只有真正的互动登录才置为当前
            upsertAccount(sa, !m_refreshingToken);
        }
        startBackgroundRefresh();
        if (m_refreshingToken) {
            m_refreshingToken = false;
            m_refreshStartedAtMs = 0;
            emit tokenRefreshed(true);
        } else {
            emit microsoftLoginSuccess(username, uuid);
        }
        emit accountChanged();
        // 登录成功后 busy 已变 false，但成功路径以前没有发这个信号 →
        // 顶部加载条与进度卡会一直挂着（用户实测：登录完成后加载条还在）。
        emit microsoftLoginBusyChanged();
        emit logMessage(tr("正版登录成功: %1").arg(username));
        downloadSkin(username);
    });
    connect(m_msAuth, &MicrosoftAuth::silentRefreshFailed, this, [this](const QString& error) {
        // 后台续期失败：不弹"登录失败"、不点亮加载条，只交给启动重试逻辑判断
        m_msStatus.clear();
        if (m_refreshingToken) {
            m_refreshingToken = false;
            m_refreshStartedAtMs = 0;
            emit tokenRefreshed(false);
            emit tokenRefreshFailed(false, error);
        }
        qCWarning(logAccount) << QStringLiteral("后台令牌续期失败(静默): %1").arg(error);
        emit microsoftLoginBusyChanged();
    });
    connect(m_msAuth, &MicrosoftAuth::loginFailed, this, [this](const QString& error) {
        m_msStatus.clear();
        if (m_refreshingToken) {
            m_refreshingToken = false;
            m_refreshStartedAtMs = 0;
            emit tokenRefreshed(false);
            // LaunchBackend needs tokenRefreshFailed to decide retry vs abort.
            // loginFailed from the chain (XBL/XSTS/MC/Profile) is NOT token expiry,
            // it is a transient error that should be retried, not blocked.
            emit tokenRefreshFailed(false, error);
        }
        qCWarning(logAccount) << QStringLiteral("Microsoft登录失败 错误=%1").arg(error);
        emit microsoftLoginFailed(error);
        emit microsoftLoginBusyChanged();
    });
}

// ────────────────────────────────────────────────────────────
// Offline Login
// ────────────────────────────────────────────────────────────

void AccountBackend::offlineLogin(const QString &username)
{
    QString name = username.trimmed();
    if (name.isEmpty()) {
        emit logMessage(tr("用户名不能为空"));
        return;
    }

    // Offline identity — COMPLETELY separate from premium (m_username/m_uuid untouched)
    m_offlineUsername = name;
    m_offlineUuid = generateOfflineUuid(name);
    m_isOnline = false;
    m_loggedIn = true;

    // Track offline username history (most recent first, max 20)
    m_offlineUsernames.removeAll(name);
    m_offlineUsernames.prepend(name);
    if (m_offlineUsernames.size() > 20) {
        m_offlineUsernames = m_offlineUsernames.mid(0, 20);
    }
    saveOfflineHistory();

    {
        // 先登记到多账号列表并把 current 指过来（离线账号只有名字与派生 UUID），
        // 再渲染皮肤：否则 offlineSkinReady 触发时 current 还是上一个账号，
        // 头像快照会存到上一个账号头上。
        StoredAccount sa;
        sa.mode = 1;
        sa.name = name;
        sa.uuid = m_offlineUuid;
        upsertAccount(sa, true);
    }
    emit accountChanged();
    emit offlineHistoryChanged();
    // Skin: always use offline head render (Steve/Alex by UUID hash)
    // Writes to m_offlineSkinPath (dedicated, never touches m_skinPath)
    updateOfflineSkin(name);
    qCInfo(logAccount) << QStringLiteral("离线登录: ") << name << QStringLiteral(" UUID:") << m_offlineUuid;
    emit logMessage(tr("离线登录: %1").arg(name));

    // Skin handled by updateOfflineSkin() above — no downloadSkin() call here
}

// ────────────────────────────────────────────────────────────
// Cape Selection — calls Mojang API to switch cape
// ────────────────────────────────────────────────────────────

void AccountBackend::selectCape(const QString &alias)
{
    if (m_msMcToken.isEmpty()) {
        emit capeChangeFinished(false, QStringLiteral("未登录正版账号"));
        return;
    }

    if (alias.isEmpty()) {
        // ── Disable cape ──
        qCInfo(logAccount) << QStringLiteral("卸下披风 (DELETE)");
        QNetworkRequest req(QUrl(QStringLiteral("https://api.minecraftservices.com/minecraft/profile/capes/active")));
        req.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(m_msMcToken).toUtf8());
        QNetworkReply* reply = HttpClient::instance().deleteResource(req);
        connect(reply, &QNetworkReply::finished, this, [this, reply]() {
            reply->deleteLater();
            if (reply->error() == QNetworkReply::NoError) {
                m_capePath.clear();
                m_activeCapeAlias.clear();
                for (CapeInfo& ci : m_capes) ci.active = false;
                qCInfo(logAccount) << QStringLiteral("披风已卸下");
                emit capesReady();
                emit capeReady();
                emit capeChangeFinished(true, QString());
            } else {
                QString err = reply->errorString();
                qCWarning(logAccount) << QStringLiteral("卸下披风失败 错误=%1").arg(err);
                emit capeChangeFinished(false, err);
            }
        });
    } else {
        // ── Switch to a specific cape ──
        QString capeId;
        for (const CapeInfo& ci : m_capes) {
            if (ci.alias == alias) {
                capeId = ci.capeId;
                break;
            }
        }
        if (capeId.isEmpty()) {
            qCWarning(logAccount) << QStringLiteral("披风ID未找到 alias=%1").arg(alias);
            emit capeChangeFinished(false, QStringLiteral("披风ID未找到"));
            return;
        }

        qCInfo(logAccount) << QStringLiteral("切换披风 alias=%1 capeId=%2").arg(alias, capeId);
        QNetworkRequest req(QUrl(QStringLiteral("https://api.minecraftservices.com/minecraft/profile/capes/active")));
        req.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(m_msMcToken).toUtf8());
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

        QJsonObject body;
        body[QStringLiteral("capeId")] = capeId;
        QNetworkReply* reply = HttpClient::instance().put(req, QJsonDocument(body).toJson());
        connect(reply, &QNetworkReply::finished, this, [this, reply, alias]() {
            reply->deleteLater();
            if (reply->error() == QNetworkReply::NoError) {
                m_activeCapeAlias = alias;
                m_capePath.clear();
                for (CapeInfo& ci : m_capes) {
                    ci.active = (ci.alias == alias);
                    if (ci.active) m_capePath = ci.localPath;
                }
                qCInfo(logAccount) << QStringLiteral("披风切换成功 alias=%1").arg(alias);
                emit capesReady();
                emit capeReady();
                emit capeChangeFinished(true, QString());
            } else {
                QString err = reply->errorString();
                qCWarning(logAccount) << QStringLiteral("披风切换失败 错误=%1").arg(err);
                emit capeChangeFinished(false, err);
            }
        });
    }
}

// ────────────────────────────────────────────────────────────
// Upload Skin to Mojang API
// ────────────────────────────────────────────────────────────

void AccountBackend::uploadSkin(const QString &filePath, const QString &variant)
{
    if (m_msMcToken.isEmpty()) {
        emit skinUploadFinished(false, QStringLiteral("未登录正版账号"));
        return;
    }

    QFileInfo fi(filePath);
    if (!fi.exists()) {
        emit skinUploadFinished(false, QStringLiteral("皮肤文件不存在"));
        return;
    }

    qCInfo(logAccount) << QStringLiteral("上传皮肤 variant=%1 path=%2").arg(variant, filePath);

    QHttpMultiPart* multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    // Variant field
    QHttpPart variantPart;
    variantPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                          QStringLiteral("form-data; name=\"variant\""));
    variantPart.setBody(variant.toUtf8());
    multiPart->append(variantPart);

    // File field
    QHttpPart filePart;
    filePart.setHeader(QNetworkRequest::ContentTypeHeader,
                       QStringLiteral("image/png"));
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QStringLiteral("form-data; name=\"file\"; filename=\"skin.png\""));
    QFile* file = new QFile(filePath);
    if (!file->open(QIODevice::ReadOnly)) {
        delete multiPart;
        delete file;
        emit skinUploadFinished(false, QStringLiteral("无法读取皮肤文件"));
        return;
    }
    filePart.setBodyDevice(file);
    file->setParent(multiPart);  // multiPart owns file now
    multiPart->append(filePart);

    QNetworkRequest req(QUrl(QStringLiteral("https://api.minecraftservices.com/minecraft/profile/skins")));
    req.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(m_msMcToken).toUtf8());
    QNetworkReply* reply =
        HttpClient::instance().manager() ?
            HttpClient::instance().manager()->post(req, multiPart) : nullptr;

    if (!reply) {
        delete multiPart;
        emit skinUploadFinished(false, QStringLiteral("网络请求失败"));
        return;
    }
    multiPart->setParent(reply);  // reply owns multiPart

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            qCInfo(logAccount) << QStringLiteral("皮肤上传成功");
            // 必须 forceRefresh：downloadSkin() 会走 downloadOnlineSkin(false)，
            // 命中本地缓存的旧头像后直接跳过纹理下载 —— 表现就是"上传成功但头像没变"。
            downloadOnlineSkin(true);
            emit skinUploadFinished(true, QString());
        } else {
            QString err = reply->errorString();
            qCWarning(logAccount) << QStringLiteral("皮肤上传失败 错误=%1").arg(err);
            emit skinUploadFinished(false, err);
        }
    });
}

// ────────────────────────────────────────────────────────────
// Refresh Skin (re-download/regenerate from current account)
// ────────────────────────────────────────────────────────────

void AccountBackend::refreshSkin()
{
    if (m_loggedIn && m_isOnline && !m_username.isEmpty()) {
        qCInfo(logApp) << QStringLiteral("正版皮肤刷新");
        emit logMessage(tr("正在刷新皮肤..."));
        m_refreshPending = true;
        downloadOnlineSkin(true);
    } else if (!m_offlineUsername.isEmpty()) {
        qCInfo(logApp) << QStringLiteral("离线皮肤刷新");
        emit logMessage(tr("正在刷新离线头像..."));
        updateOfflineSkin(m_offlineUsername);
        emit refreshFinished(true, QString());
    } else {
        emit logMessage(tr("未登录，无需刷新"));
        emit refreshFinished(false, tr("当前没有可刷新的账号"));
    }
}

// ────────────────────────────────────────────────────────────
// Update Offline Skin (real-time avatar preview by UUID hash)
// ────────────────────────────────────────────────────────────

void AccountBackend::updateOfflineSkin(const QString &username)
{
    QString name = username.trimmed();

    // Default to Steve model when name is empty
    QString modelName = QStringLiteral("steve");

    if (!name.isEmpty()) {
        // Generate offline UUID → hash LSB determines Steve/Alex
        QByteArray input = QStringLiteral("OfflinePlayer:").toUtf8() + name.toUtf8();
        QByteArray hash = QCryptographicHash::hash(input, QCryptographicHash::Md5);
        // Minecraft Java: UUID.hashCode() & 1 determines Alex (slim) vs Steve (wide)
        // hashCode = XOR of 4× 32-bit halves: hash[0..3]^hash[4..7]^hash[8..11]^hash[12..15]
        // Simplified to byte-level: bit0 = (hash[3]^hash[7]^hash[11]^hash[15]) & 1
        int parity = (hash[3] & 1) ^ (hash[7] & 1) ^ (hash[11] & 1) ^ (hash[15] & 1);
        modelName = parity ? QStringLiteral("alex") : QStringLiteral("steve");
        qCInfo(logAccount) << QStringLiteral("离线皮肤预览: ") << name << QStringLiteral(" -> ") << modelName
                           << "(parity=" << parity << ")";
    }

    QString headPath = m_dataDir + QStringLiteral("/assets/skins/") + modelName + QStringLiteral("_head.png");

    if (!QFileInfo::exists(headPath)) {
        initOfflineHeads();
        if (!QFileInfo::exists(headPath)) {
            qCWarning(logAccount) << QStringLiteral("离线头像仍缺失 路径=%1").arg(headPath);
            m_offlineSkinPath.clear();
            emit offlineSkinReady();
            return;
        }
    }

    // Dedicated offline path — never touches m_skinPath (premium)
    m_offlineSkinPath = toImageUrl(headPath);
    emit offlineSkinReady();
}

// ────────────────────────────────────────────────────────────
// Init Offline Heads — pre-render Steve & Alex heads once
// ────────────────────────────────────────────────────────────

void AccountBackend::initOfflineHeads()
{
    const QString skinsDir = QCoreApplication::applicationDirPath() + QStringLiteral("/skins");
    QStringList models = {QStringLiteral("steve"), QStringLiteral("alex")};

    for (const QString& model : models) {
        QString headPath = m_dataDir + QStringLiteral("/assets/skins/") + model + QStringLiteral("_head.png");
        if (QFileInfo::exists(headPath)) {
            qCInfo(logAccount) << QStringLiteral("离线头像已缓存: ") << model;
            continue;
        }

        QString skinSource = skinsDir + QStringLiteral("/") + model + QStringLiteral(".png");
        if (!QFileInfo::exists(skinSource)) {
            qCWarning(logAccount) << QStringLiteral("皮肤源文件不存在 路径=%1").arg(skinSource);
            continue;
        }

        QString rendered = renderHead3D(skinSource);
        if (rendered.isEmpty()) {
            qCWarning(logAccount) << QStringLiteral("头像渲染失败 模型=%1").arg(model);
            continue;
        }

        if (QFile::rename(rendered, headPath)) {
            qCInfo(logAccount) << QStringLiteral("离线头像已渲染: ") << headPath;
        } else {
            // fallback: copy + delete
            QFile::copy(rendered, headPath);
            QFile::remove(rendered);
            qCInfo(logAccount) << QStringLiteral("离线头像已复制: ") << headPath;
        }
    }
}

// ────────────────────────────────────────────────────────────
// Logout
// ────────────────────────────────────────────────────────────

void AccountBackend::logout()
{
    m_username.clear();
    m_uuid.clear();
    m_offlineUsername.clear();
    m_offlineUuid.clear();
    m_skinPath.clear();
    m_offlineSkinPath.clear();
    m_capePath.clear();
    m_skinVariant.clear();
    m_capes.clear();
    m_activeCapeAlias.clear();
    m_loggedIn = false;
    m_isOnline = false;

    // 复位刷新/认证状态：否则“刷新中”标记会跨登录存活，让下一次互动登录
    // 被误判成刷新流程而丢弃新的刷新令牌；未完成的认证链也要一并取消。
    m_refreshingToken = false;
    m_refreshStartedAtMs = 0;
    m_msStatus.clear();
    if (m_msAuth) m_msAuth->cancelLogin();

    // Clear MS token state and persisted session
    secureWipe(m_msRefreshToken);
    secureWipe(m_msMcToken);
    secureWipe(m_uuid);
    m_msTokenObtainedAt = 0;
    m_msTokenExpiresIn = 0;
    deleteMicrosoftSession();

    // 多账号：账号条目保留（名字/UUID 还在列表里），但凭据一律作废。
    // 不作废的话，"退出登录"后再点列表里那一行会立刻用 refreshToken 静默登录回去，
    // 等于根本没退出——这也是"退出登录"和"移除此账号"看起来一样的根源。
    if (m_currentAccount >= 0 && m_currentAccount < m_accounts.size()) {
        StoredAccount &a = m_accounts[m_currentAccount];
        secureWipe(a.refreshToken);
        a.refreshToken.clear();
        a.accessToken.clear();
        a.clientToken.clear();
    }
    // 登出后没有任何账号处于活动状态：条目全部保留，但谁都不是"当前"，
    // 否则左侧还会高亮一个其实已经退出的账号。
    m_currentAccount = -1;
    saveAccounts();
    emit accountsChanged();

    // Stop background refresh timer
    if (m_refreshTimer) {
        m_refreshTimer->stop();
        delete m_refreshTimer;
        m_refreshTimer = nullptr;
    }

    emit accountChanged();
    // 2026-11-04：skinPath / skinTexturePath 的 NOTIFY 是 skinReady，不是 accountChanged。
    // 登出清空了皮肤路径却不发 skinReady，QML 里绑定 skinPath 的头像就不会重算 ——
    // 表现为"退出登录后主页头像还在"。这里补发，让头像跟着一起回到未登录态。
    emit skinReady();
    emit offlineSkinReady();
    qCInfo(logAccount) << QStringLiteral("已登出");
    emit logMessage(tr("已登出"));
}

// ────────────────────────────────────────────────────────────
// Microsoft Login
// ────────────────────────────────────────────────────────────

void AccountBackend::setEmbeddedLoginEnabled(bool v)
{
    if (m_embeddedLoginEnabled != v) {
        m_embeddedLoginEnabled = v;
        emit embeddedLoginChanged();
        qCInfo(logAccount) << QStringLiteral("内嵌登录 %1").arg(v ? QStringLiteral("已启用") : QStringLiteral("已禁用"));
    }
}

void AccountBackend::microsoftLogin()
{
    if (!m_msAuth) return;
    if (m_msAuth->isBusy()) {
        emit logMessage(tr("Microsoft 登录已在进行中"));
        return;
    }
    // 上一次登录留下的状态文案不能带进新的登录流程
    if (!m_msStatus.isEmpty()) { m_msStatus.clear(); emit microsoftLoginProgress(QString(), QString()); }
    emit microsoftLoginBusyChanged();
    // 微软登录应用标识（Azure App ID）：真实值由 src/secrets_local.h 注入（git 忽略），
    // 仓库内为占位符（src/secrets.h）。
    const QString clientId = QStringLiteral(SHADOW_AZURE_CLIENT_ID);
    if (m_embeddedLoginEnabled) {
        qCInfo(logAccount) << QStringLiteral("使用内嵌浏览器登录");
        m_msAuth->startEmbeddedLogin(clientId);
    } else {
        qCInfo(logAccount) << QStringLiteral("使用本地回调登录");
        m_msAuth->startLogin(clientId);
    }
    // 上面那次 emit 发生在 startLogin() 之前，此时 isBusy() 还是 false，
    // QML 绑定的 microsoftLoginBusy 读到的仍是 false —— 于是"登录过程"完全不显示。
    // 真正开了流程之后再发一次。
    emit microsoftLoginBusyChanged();
}

void AccountBackend::cancelMicrosoftLogin()
{
    if (!m_msAuth) return;
    m_msAuth->cancelLogin();
    // 取消后残留的步骤文案会让"登录状态"卡片继续挂着（用户实测）
    if (!m_msStatus.isEmpty()) {
        m_msStatus.clear();
        emit microsoftLoginProgress(QString(), QString());
    }
    emit microsoftLoginBusyChanged();
}

bool AccountBackend::shouldRefresh() const
{
    if (m_msRefreshToken.isEmpty()) return false;
    if (m_msTokenExpiresIn <= 0 || m_msTokenObtainedAt <= 0) return true;
    qint64 now = QDateTime::currentSecsSinceEpoch();
    qint64 expiresAt = m_msTokenObtainedAt + m_msTokenExpiresIn;
    return (now + 3600) >= expiresAt;
}

void AccountBackend::startBackgroundRefresh()
{
    if (m_refreshTimer) return;
    m_refreshTimer = new QTimer(this);
    m_refreshTimer->setInterval(3600000);
    connect(m_refreshTimer, &QTimer::timeout, this, [this]() {
        if (shouldRefresh()) {
            qCInfo(logAccount) << QStringLiteral("后台刷新已触发");
            // 不得在此预置 m_refreshingToken：refreshMicrosoftToken() 会因该标记直接
            // return（“令牌刷新中,跳过重复请求”），标记却再无人复位 —— 此后启动刷新
            // 永远被跳过、12s×3 超时后报“网络超时，无法验证正版登录状态”。
            refreshMicrosoftToken();
        }
    });
    m_refreshTimer->start();
    qCInfo(logAccount) << QStringLiteral("后台令牌刷新已启动");
}

// ── 启动重试兜底：清除假死的“刷新中”标记 ──
void AccountBackend::resetRefreshState()
{
    if (m_refreshingToken) {
        qCWarning(logAccount) << QStringLiteral("复位令牌刷新状态（启动重试），使刷新可再次发起");
        m_refreshingToken = false;
        m_refreshStartedAtMs = 0;
        m_msStatus.clear();
    }
}

// ────────────────────────────────────────────────────────────
// Skin Cache Path
// ────────────────────────────────────────────────────────────

// ────────────────────────────────────────────────────────────
// Generate Offline UUID  (Java Edition compatible)
// ────────────────────────────────────────────────────────────

QString AccountBackend::generateOfflineUuid(const QString &username) const
{
    // Java: UUID.nameUUIDFromBytes(("OfflinePlayer:" + name).getBytes(UTF_8))
    QByteArray input = QStringLiteral("OfflinePlayer:").toUtf8()
                     + username.toUtf8();
    QByteArray hash = QCryptographicHash::hash(input, QCryptographicHash::Md5);

    // RFC 4122: set version 3 (MD5-based) and variant 10xx
    char *data = hash.data();
    data[6] = static_cast<char>((data[6] & 0x0f) | 0x30);   // version 3
    data[8] = static_cast<char>((data[8] & 0x3f) | 0x80);   // variant 10xx

    // Format as 8-4-4-4-12 hex
    QString hex = hash.toHex();
    return QStringLiteral("%1-%2-%3-%4-%5")
        .arg(QStringView(hex).mid(0, 8),
             QStringView(hex).mid(8, 4),
             QStringView(hex).mid(12, 4),
             QStringView(hex).mid(16, 4),
             QStringView(hex).mid(20, 12));
}

// ────────────────────────────────────────────────────────────
// Skin Cache Path
// ────────────────────────────────────────────────────────────

QString AccountBackend::skinCachePath(const QString &username) const
{
    QByteArray nameHash = QCryptographicHash::hash(
        username.toLower().toUtf8(), QCryptographicHash::Md5);
    QString hex = QString::fromLatin1(nameHash.toHex());
    return m_dataDir + QStringLiteral("/assets/skins/") + hex
           + QStringLiteral(".png");
}

QString AccountBackend::capeCachePath(const QString &username) const
{
    QByteArray nameHash = QCryptographicHash::hash(
        username.toLower().toUtf8(), QCryptographicHash::Md5);
    QString hex = QString::fromLatin1(nameHash.toHex());
    return m_dataDir + QStringLiteral("/assets/capes/") + hex
           + QStringLiteral(".png");
}

QVariantList AccountBackend::capes() const
{
    QVariantList list;
    for (const CapeInfo& ci : m_capes) {
        QVariantMap m;
        m[QStringLiteral("alias")] = ci.alias;
        m[QStringLiteral("capeId")] = ci.capeId;
        m[QStringLiteral("localPath")] = ci.localPath;
        m[QStringLiteral("active")] = ci.active;
        list.append(m);
    }
    return list;
}

// ────────────────────────────────────────────────────────────
// Face Cropping — extract 8×8 head from skin atlas, alpha-blend hat
// ────────────────────────────────────────────────────────────

QString AccountBackend::renderHead3D(const QString& skinPath)
{
    // Hat layer rendered larger than face layer (56 vs 48 in 64 grid)
    // Hat pixels = 7px width, Face pixels = 6px width → hat wraps around as "head套"
    QImage skin(skinPath);
    if (skin.isNull()) { qCWarning(logAccount)<<"renderHead3D: load fail"<<skinPath; return {}; }

    // ── Format detection ──
    const int skinW = skin.width();
    const int skinH = skin.height();
    const char* formatTag = "unknown";
    if (skinW == 64 && skinH == 32) formatTag = "64x32 (legacy)";
    else if (skinW == 64 && skinH == 64) formatTag = "64x64 (modern)";
    else formatTag = "custom";
    qCInfo(logAccount) << QStringLiteral("皮肤格式: ") << formatTag << skinW << "x" << skinH;

    constexpr int FACE_X=8, FACE_Y=8, FACE_W=8, FACE_H=8;
    constexpr int HAT_X=40, HAT_Y=8, HAT_W=8, HAT_H=8;
    constexpr int CANVAS = 128;
    // Ratios: face 48/64 = 3/4, hat 56/64 = 7/8
    constexpr int FACE_SZ = CANVAS * 3 / 4;   // 96
    constexpr int HAT_SZ  = CANVAS * 7 / 8;   // 112

    bool hasHat = (skinW >= 64 && skinH >= 32);
    qCInfo(logAccount) << QStringLiteral("皮肤帽子: ") << hasHat << QStringLiteral(" 格式:") << formatTag;

    // 1. Face layer: 8×8 → scaled to FACE_SZ, centered in canvas
    QImage face = skin.copy(FACE_X, FACE_Y, FACE_W, FACE_H);
    QImage faceScaled = face.scaled(FACE_SZ, FACE_SZ, Qt::IgnoreAspectRatio, Qt::FastTransformation);
    faceScaled = faceScaled.convertToFormat(QImage::Format_ARGB32_Premultiplied);

    QImage out(CANVAS, CANVAS, QImage::Format_ARGB32_Premultiplied);
    out.fill(0);
    int faceX = (CANVAS - FACE_SZ) / 2;
    int faceY = (CANVAS - FACE_SZ) / 2;
    for (int y = 0; y < FACE_SZ; ++y) {
        QRgb* dst = (QRgb*)out.scanLine(faceY + y) + faceX;
        const QRgb* src = (const QRgb*)faceScaled.constScanLine(y);
        for (int x = 0; x < FACE_SZ; ++x) dst[x] = src[x];
    }

    // 2. Hat layer: 8×8 → scaled to HAT_SZ (LARGER than face), centered on top
    if (hasHat) {
        QImage hatSrc = skin.copy(HAT_X, HAT_Y, HAT_W, HAT_H);
        QImage hat = hatSrc.scaled(HAT_SZ, HAT_SZ, Qt::IgnoreAspectRatio, Qt::FastTransformation);
        hat = hat.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        int hatX = (CANVAS - HAT_SZ) / 2;
        int hatY = (CANVAS - HAT_SZ) / 2;
        for (int y = 0; y < HAT_SZ; ++y) {
            QRgb* dst = (QRgb*)out.scanLine(hatY + y) + hatX;
            const QRgb* hatLine = (const QRgb*)hat.constScanLine(y);
            for (int x = 0; x < HAT_SZ; ++x) {
                int a = qAlpha(hatLine[x]);
                if (a >= 64) dst[x] = hatLine[x];
            }
        }
    }

    QString hp = skinPath.left(skinPath.length() - 4) + QStringLiteral("_head.png");
    if (out.save(hp, "PNG")) {
        qCInfo(logAccount) << QStringLiteral("头像: ") << hp;
        return hp;
    }
    qCWarning(logAccount) << QStringLiteral("renderHead3D 保存失败 路径=%1").arg(hp);
    return {};
}


QString AccountBackend::toImageUrl(const QString& filePath)
{
    if (filePath.isEmpty()) return {};
    if (filePath.startsWith(QStringLiteral("qrc:"))) return filePath;
    return QUrl::fromLocalFile(filePath).toString();
}

// 原始皮肤纹理（整张皮肤）：给 UI 自己裁脸用。
// 优先当前在线账号的缓存，其次上次用过的离线皮肤；都没有返回空。
QString AccountBackend::skinTexturePath() const
{
    if (!m_username.isEmpty()) {
        const QString p = skinCachePath(m_username);
        if (QFileInfo::exists(p)) return toImageUrl(p);
    }
    if (!m_offlineSkinPath.isEmpty()) {
        // 离线头图没有原始皮肤备份，只能返回空让 UI 退回头图
        return {};
    }
    return {};
}

// ────────────────────────────────────────────────────────────
// Download Skin
// ────────────────────────────────────────────────────────────

void AccountBackend::downloadSkin(const QString &username)
{
    // ── Always try Mojang API first if we have a valid mcToken ──
    if (!m_msMcToken.isEmpty()) {
        qCInfo(logAccount) << QStringLiteral("开始从Mojang获取皮肤和披风 用户=%1").arg(username);
        downloadOnlineSkin();
        return;
    }

    QString cachePath = skinCachePath(username);

    // ── Check cache first ──
    QFileInfo cacheInfo(cachePath);
    if (cacheInfo.exists() && cacheInfo.size() > 0) {
        // Check for existing face crop
        QString facePath = cachePath.left(cachePath.length() - 4) + QStringLiteral("_head.png");
        if (!QFileInfo::exists(facePath)) {
            facePath = renderHead3D(cachePath);
        }
        m_skinPath = toImageUrl(facePath.isEmpty() ? cachePath : facePath);
        qCInfo(logAccount) << QStringLiteral("皮肤缓存: ") << m_skinPath;
        emit skinReady();
        return;
    }

    // ── Offline / no token: use placeholder ──
    setFallbackSkin();
    qCInfo(logAccount) << QStringLiteral("皮肤占位: ") << username;
    emit skinReady();
}

// ────────────────────────────────────────────────────────────
// Online Skin (Mojang API)
// ────────────────────────────────────────────────────────────

void AccountBackend::downloadOnlineSkin(bool forceRefresh)
{
    // Check skin cache
    bool skinCached = false;
    QString cachePath = skinCachePath(m_username);
    QString facePath = cachePath + QStringLiteral("_head.png");
    if (QFileInfo::exists(facePath)) {
        m_skinPath = toImageUrl(facePath);
        skinCached = true;
        qCInfo(logAccount) << QStringLiteral("皮肤缓存命中(已渲染) path=%1").arg(m_skinPath);
        if (!forceRefresh)
            emit skinReady();
    } else if (QFileInfo::exists(cachePath)) {
        // Raw skin exists but no rendered face — render and use
        facePath = renderHead3D(cachePath);
        m_skinPath = toImageUrl(facePath.isEmpty() ? cachePath : facePath);
        skinCached = true;
        qCInfo(logAccount) << QStringLiteral("皮肤缓存命中(原始) path=%1").arg(m_skinPath);
        if (!forceRefresh)
            emit skinReady();
    }

    // When force-refreshing, always download skin from network (ignore cache)
    if (forceRefresh) {
        skinCached = false;
        qCInfo(logAccount) << QStringLiteral("强制刷新: 将重新下载皮肤纹理");
    }

    // Always call Mojang Profile API — even if skin is cached,
    // we need cape data which is only available from the live API.
    // In the response handler, we'll skip skin texture download if skinCached is true.

    // No cache — fetch from Mojang API
    qCInfo(logAccount) << QStringLiteral("正在调用Mojang Profile API...");
    // 从这里开始算「披风拉取中」：UI 显示加载条。记下发起者，
    // 万一中途切号，旧响应必须整条丢掉，不能写进新账号的披风列表。
    m_capesUser = m_username;
    m_capesPending = 0;
    setCapesLoading(true);
    // 兜底：网络卡死时不能让顶部光条一直转
    {
        const QString guardUser = m_username;
        QTimer::singleShot(15000, this, [this, guardUser]() {
            if (m_capesLoading && m_capesUser == guardUser) {
                qCWarning(logAccount) << QStringLiteral("披风加载超时，收掉加载状态");
                m_capesPending = 0;
                setCapesLoading(false);
                setIdentityLoading(false);
            }
        });
    }
    QNetworkRequest req(QUrl(QStringLiteral("https://api.minecraftservices.com/minecraft/profile")));
    req.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(m_msMcToken).toUtf8());

    QNetworkReply* reply = HttpClient::instance().getRaw(req);
    const QString reqUser = m_username;
    connect(reply, &QNetworkReply::finished, this, [this, reply, skinCached, reqUser]() {
        reply->deleteLater();
        // 期间切了账号：这份响应属于上一个身份，整条丢掉（加载条也一起收掉）
        if (m_username != reqUser) {
            qCInfo(logAccount) << QStringLiteral("忽略上一个账号的档案响应: ") << reqUser;
            setCapesLoading(false);
            m_capesPending = 0;
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(logAccount) << QStringLiteral("Mojang档案获取失败 错误=%1").arg(reply->errorString());
            // 令牌被 Mojang 明确拒绝（401/403）→ 本地记录的有效期不可信，主动刷新。
            // 否则会带着已死令牌启动游戏，游戏内表现就是“无效会话”。
            const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if ((httpStatus == 401 || httpStatus == 403) && !m_msRefreshToken.isEmpty()) {
                qCWarning(logAccount) << QStringLiteral("MC令牌被服务器拒绝(HTTP %1)，触发令牌刷新").arg(httpStatus);
                refreshMicrosoftToken();
            }
            m_capes.clear();
            setCapesLoading(false);
            emit capesReady();
            // 用户主动刷新失败要明确告知，不能只留一句"正在刷新"
            if (m_refreshPending) {
                m_refreshPending = false;
                emit refreshFinished(false, reply->errorString());
            }
            if (!skinCached) {
                // 无缓存 → fallback 史蒂夫
                setFallbackSkin();
            } else {
                // ⚠ 有本地缓存皮肤：保留已显示的缓存（m_skinPath 已指向本地文件），
                // 网络失败不应把正版皮肤覆盖成史蒂夫（原逻辑无条件 fallback）。
                qCInfo(logAccount) << QStringLiteral("网络失败，保留缓存皮肤: %1").arg(m_skinPath);
            }
            emit skinReady();
            return;
        }

        QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        QJsonObject profile = doc.object();

        // Update UUID and username from Mojang profile (fixes offline UUID leak)
        QString profileUuid = profile[QStringLiteral("id")].toString();
        QString profileName = profile[QStringLiteral("name")].toString();
        if (!profileUuid.isEmpty() && !profileName.isEmpty()) {
            bool changed = (m_uuid != profileUuid || m_username != profileName);
            m_uuid = profileUuid;
            m_username = profileName;
            if (changed) {
                saveMicrosoftSession();
                emit accountChanged();
                qCInfo(logAccount) << QStringLiteral("UUID已修正: ") << profileUuid;
            }
        }

        QJsonArray skins = profile[QStringLiteral("skins")].toArray();
        QJsonArray capes = profile[QStringLiteral("capes")].toArray();
        qCInfo(logAccount) << QStringLiteral("Mojang Profile API响应 皮肤数=%1 披风数=%2")
                                   .arg(skins.size()).arg(capes.size());

        QString skinUrl;
        QString skinVariant;
        for (const QJsonValue& sv : skins) {
            QJsonObject s = sv.toObject();
            if (s[QStringLiteral("state")].toString() == QStringLiteral("ACTIVE")) {
                skinUrl = s[QStringLiteral("url")].toString();
                skinVariant = s[QStringLiteral("variant")].toString();
                if (m_skinVariant != skinVariant) {
                    m_skinVariant = skinVariant;
                    emit skinVariantChanged();
                }
                qCInfo(logAccount) << QStringLiteral("从Mojang获取到皮肤 variant=%1 url=%2")
                                           .arg(skinVariant, skinUrl);
                break;
            }
        }

        // ── Cape extraction (all capes, regardless of state) ──
        m_capes.clear();
        m_activeCapeAlias.clear();
        QStringList capeUrls;
        QStringList capeAliases;
        QStringList capeIds;
        QList<bool> capeActiveFlags;
        for (const QJsonValue& cv : capes) {
            QJsonObject c = cv.toObject();
            QString alias = c[QStringLiteral("alias")].toString();
            QString state = c[QStringLiteral("state")].toString();
            QString url = c[QStringLiteral("url")].toString();
            QString id = c[QStringLiteral("id")].toString();
            bool active = (state == QStringLiteral("ACTIVE"));
            qCInfo(logAccount) << QStringLiteral("披风条目 alias=%1 state=%2 id=%3 url=%4")
                                       .arg(alias, state, id, url);
            capeUrls.append(url);
            capeAliases.append(alias);
            capeIds.append(id);
            capeActiveFlags.append(active);
            if (active) {
                m_activeCapeAlias = alias;
            }
        }

        if (capeUrls.isEmpty()) {
            qCInfo(logAccount) << QStringLiteral("Mojang档案中无披风");
            setCapesLoading(false);
            emit capesReady();
        } else {
            qCInfo(logAccount) << QStringLiteral("从Mojang获取到披风 总数=%1 ACTIVE=%2")
                                       .arg(capeUrls.size()).arg(m_activeCapeAlias);
        }

        // ── Download ALL capes ──
        if (!capeUrls.isEmpty()) {
            QDir().mkpath(m_dataDir + QStringLiteral("/assets/capes"));
            // 每张披风图一个请求：全部回来才算加载完
            m_capesPending = capeUrls.size();
            for (int i = 0; i < capeUrls.size(); ++i) {
                const QString& url = capeUrls[i];
                const QString& alias = capeAliases[i];
                const QString& id = capeIds[i];
                bool active = capeActiveFlags[i];
                QNetworkRequest capeReq(url);
                QNetworkReply* capeReply = HttpClient::instance().getRaw(capeReq);
                connect(capeReply, &QNetworkReply::finished, this, [this, capeReply, alias, id, active]() {
                    capeReply->deleteLater();
                    // 单张回来就递减；归零表示这一轮披风全部拉完
                    auto tick = [this]() {
                        if (--m_capesPending <= 0) { m_capesPending = 0; setCapesLoading(false); }
                    };
                    if (capeReply->error() == QNetworkReply::NoError) {
                        QString cachePath = capeCachePath(m_username + QStringLiteral("_") + alias);
                        QFile file(cachePath);
                        if (file.open(QIODevice::WriteOnly)) {
                            file.write(capeReply->readAll());
                            file.close();
                            QString localUrl = toImageUrl(cachePath);

                            // Add to cape list
                            CapeInfo info;
                            info.alias = alias;
                            info.capeId = id;
                            info.localPath = localUrl;
                            info.active = active;
                            m_capes.append(info);

                            // Primary (active) cape sets m_capePath for avatar
                            if (active) {
                                m_capePath = localUrl;
                            }

                            qint64 capeSize = file.size();
                            qCInfo(logAccount) << QStringLiteral("披风下载完成 alias=%1 active=%2 大小=%3字节 路径=%4")
                                                       .arg(alias).arg(active).arg(capeSize).arg(cachePath);
                            emit capesReady();
                            if (active) emit capeReady();
                        }
                        tick();
                    } else {
                        qCWarning(logAccount) << QStringLiteral("披风下载失败 alias=%1 错误=%2")
                                                      .arg(alias, capeReply->errorString());
                        // Still add to list with empty path
                        CapeInfo info;
                        info.alias = alias;
                        info.capeId = id;
                        info.localPath.clear();
                        info.active = active;
                        m_capes.append(info);
                        emit capesReady();
                        tick();
                    }
                });
            }
        }

        // 档案拉取成功即视为刷新成功（皮肤/披风的下载在各自回调里继续，
        // 那属于实现细节，不该让用户等）。
        if (m_refreshPending) {
            m_refreshPending = false;
            emit refreshFinished(true, QString());
        }

        if (!skinCached) {
            if (skinUrl.isEmpty()) {
                qCInfo(logAccount) << QStringLiteral("无Mojang皮肤,使用默认");
                setFallbackSkin();
                emit skinReady();
            } else {
                qCInfo(logAccount) << QStringLiteral("下载Mojang皮肤: ") << skinUrl;
                QNetworkRequest skinReq(skinUrl);
                QNetworkReply* skinReply = HttpClient::instance().getRaw(skinReq);
                connect(skinReply, &QNetworkReply::finished, this, [this, skinReply, skinVariant]() {
                    skinReply->deleteLater();
                    if (skinReply->error() != QNetworkReply::NoError) {
                        qCWarning(logAccount) << QStringLiteral("皮肤纹理下载失败 错误=%1").arg(skinReply->errorString());
                        setFallbackSkin();
                        emit skinReady();
                        return;
                    }
                    QString cachePath = skinCachePath(m_username);
                    QFileInfo fi(cachePath);
                    QDir().mkpath(fi.absolutePath());
                    QFile file(cachePath);
                    if (file.open(QIODevice::WriteOnly)) {
                        file.write(skinReply->readAll());
                        file.close();
                        QString facePath = renderHead3D(cachePath);
                        QString freshFace = facePath.isEmpty() ? cachePath : facePath;
                        // Append cache buster for QML Image to re-read on same path
                        m_skinPath = toImageUrl(freshFace)
                            + QStringLiteral("?t=%1").arg(QDateTime::currentMSecsSinceEpoch());
                        qint64 skinSize = file.size();
                        qCInfo(logAccount) << QStringLiteral("皮肤下载完成 variant=%1 大小=%2字节 路径=%3")
                                                   .arg(skinVariant, QString::number(skinSize), m_skinPath);
                    }
                    emit skinReady();
                });
            }
        } else {
            qCInfo(logAccount) << QStringLiteral("皮肤已缓存,跳过纹理下载");
        }
    });
}

void AccountBackend::setFallbackSkin()
{
    // Use rendered offline Steve head (always exists after initOfflineHeads)
    QString headPath = m_dataDir + QStringLiteral("/assets/skins/steve_head.png");
    if (QFileInfo::exists(headPath)) {
        m_skinPath = toImageUrl(headPath);
    } else {
        // Last resort: qrc placeholder
        m_skinPath = QStringLiteral("qrc:/ShadowLauncher/assets/steve.png");
    }
    m_capePath.clear();
}

// ────────────────────────────────────────────────────────────
// Offline History Persistence
// ────────────────────────────────────────────────────────────

void AccountBackend::loadOfflineHistory()
{
    m_offlineUsernames.clear();

    QString path = m_dataDir + QStringLiteral("/offline_history.json");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return;

    QByteArray data = file.readAll();
    file.close();

    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(data, &err);
    if (err.error != QJsonParseError::NoError || !doc.isArray())
        return;

    const QJsonArray arr = doc.array();
    m_offlineUsernames.reserve(arr.size());
    for (const QJsonValue &val : arr) {
        if (val.isString())
            m_offlineUsernames.append(val.toString());
    }
}

void AccountBackend::saveOfflineHistory()
{
    QJsonArray arr;
    for (const QString &name : m_offlineUsernames)
        arr.append(name);

    QString path = m_dataDir + QStringLiteral("/offline_history.json");
    QFileInfo fi(path);
    QDir().mkpath(fi.absolutePath());

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;

    QJsonDocument doc(arr);
    file.write(doc.toJson(QJsonDocument::Indented));
    file.close();
}

void AccountBackend::removeOfflineUsername(const QString &username)
{
    m_offlineUsernames.removeAll(username);
    saveOfflineHistory();
    emit offlineHistoryChanged();
}

// ────────────────────────────────────────────────────────────
// Microsoft Session Persistence
// ────────────────────────────────────────────────────────────

void AccountBackend::saveMicrosoftSession()
{
    QJsonObject obj;
    obj[QStringLiteral("username")] = m_username;
    obj[QStringLiteral("uuid")] = TokenCrypto::encrypt(m_uuid);
    obj[QStringLiteral("mcToken")] = TokenCrypto::encrypt(m_msMcToken);
    obj[QStringLiteral("refreshToken")] = TokenCrypto::encrypt(m_msRefreshToken);
    obj[QStringLiteral("tokenObtainedAt")] = TokenCrypto::encrypt(QString::number(m_msTokenObtainedAt));
    obj[QStringLiteral("tokenExpiresIn")] = TokenCrypto::encrypt(QString::number(m_msTokenExpiresIn));
    obj[QStringLiteral("encrypted")] = true;  // mark for migration detection

    QString path = m_dataDir + QStringLiteral("/microsoft_session.json");
    QFileInfo fi(path);
    QDir().mkpath(fi.absolutePath());

    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
        qCInfo(logAccount) << QStringLiteral("微软会话已保存: ") << path;
    }
}

void AccountBackend::deleteMicrosoftSession()
{
    QString path = m_dataDir + QStringLiteral("/microsoft_session.json");
    QFile::remove(path);
    qCInfo(logAccount) << QStringLiteral("微软会话已删除: ") << path;
}

// Helper: read a field from JSON, auto-decrypt if encrypted
static QString readSecureField(const QJsonObject &obj, const QString &key, bool isEncrypted)
{
    QString val = obj[key].toString();
    if (val.isEmpty()) return {};
    if (isEncrypted || TokenCrypto::looksEncrypted(val)) {
        QString dec = TokenCrypto::decrypt(val);
        if (!dec.isEmpty()) return dec;
        // Decrypt failed — fall through to plaintext for migration
        qCInfo(logAccount) << QStringLiteral("解密失败,尝试明文: ") << key;
    }
    return val;
}

void AccountBackend::loadMicrosoftSession()
{
    QString path = m_dataDir + QStringLiteral("/microsoft_session.json");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    QJsonObject obj = doc.object();
    bool isEncrypted = obj[QStringLiteral("encrypted")].toBool(false);

    m_username = obj[QStringLiteral("username")].toString();
    m_uuid = readSecureField(obj, QStringLiteral("uuid"), isEncrypted);
    m_msMcToken = readSecureField(obj, QStringLiteral("mcToken"), isEncrypted);
    m_msRefreshToken = readSecureField(obj, QStringLiteral("refreshToken"), isEncrypted);
    m_msTokenObtainedAt = readSecureField(obj, QStringLiteral("tokenObtainedAt"), isEncrypted).toLongLong();
    m_msTokenExpiresIn = readSecureField(obj, QStringLiteral("tokenExpiresIn"), isEncrypted).toLongLong();

    // Migration: if old plaintext file was loaded, re-save as encrypted
    if (!isEncrypted && !m_msRefreshToken.isEmpty()) {
        qCInfo(logAccount) << QStringLiteral("迁移明文会话至加密存储");
        saveMicrosoftSession();
    }

    qint64 now = QDateTime::currentSecsSinceEpoch();
    bool knownExpired = (m_msTokenExpiresIn > 0) && (m_msTokenObtainedAt > 0)
                        && (now > m_msTokenObtainedAt + m_msTokenExpiresIn);

    // Session loaded
    // Strategy: trust timestamps for display, verify on pre-launch
    if (!m_msRefreshToken.isEmpty() && !knownExpired) {
        qCInfo(logAccount) << QStringLiteral("找到微软会话: ") << m_username;
        m_loggedIn = true;
        m_isOnline = true;
        downloadSkin(m_username);
        emit accountChanged();
        // 恢复会话后同样启动后台刷新：否则长时间挂机时令牌只会在过期后才被动处理
        startBackgroundRefresh();
    } else if (m_msRefreshToken.isEmpty() && !m_msMcToken.isEmpty()) {
        // MC token without refresh token = incomplete session, can't refresh
        qCInfo(logAccount) << QStringLiteral("会话无刷新令牌,已清除");
        m_msMcToken.clear();
        m_username.clear();
        m_uuid.clear();
        // Do NOT save — don't overwrite file with empty data
    } else if (m_msRefreshToken.isEmpty() && m_msMcToken.isEmpty()) {
        // Empty session — corrupted or first run, silently skip
        qCInfo(logAccount) << QStringLiteral("会话为空,重新开始");
    } else if (knownExpired) {
        if (!m_msRefreshToken.isEmpty()) {
            // MC token expired, but we have a refresh token (valid up to 90 days)
            qCInfo(logAccount) << QStringLiteral("MC令牌过期,使用刷新令牌...");
            m_loggedIn = true;
            m_isOnline = true;
            downloadSkin(m_username);
            emit accountChanged();
            refreshMicrosoftToken();
            startBackgroundRefresh();
        } else {
            // Both tokens expired — truly need re-login
            qCInfo(logAccount) << QStringLiteral("微软会话已过期,已清除");
            m_msMcToken.clear();
            m_msRefreshToken.clear();
            m_msTokenObtainedAt = 0;
            m_msTokenExpiresIn = 0;
            m_username.clear();
            m_uuid.clear();
            m_loggedIn = false;
            m_isOnline = false;
            saveMicrosoftSession();
            emit accountChanged();
        }
    }
}

void AccountBackend::refreshMicrosoftToken()
{
    if (m_msRefreshToken.isEmpty()) {
        qCWarning(logAccount) << QStringLiteral("无刷新令牌，无法刷新微软令牌");
        return;
    }
    if (m_refreshingToken) {
        const qint64 ageMs = m_refreshStartedAtMs > 0
                                 ? (QDateTime::currentMSecsSinceEpoch() - m_refreshStartedAtMs)
                                 : -1;
        // 正常链路 ~10s 内完成；超过 60s 视为假死，允许重新发起，
        // 否则启动重试会全部变成静默 no-op，最终误报“网络超时”。
        if (ageMs >= 0 && ageMs < 60000) {
            qCInfo(logAccount) << QStringLiteral("令牌刷新中,跳过重复请求");
            return;
        }
        qCWarning(logAccount) << QStringLiteral("上一次令牌刷新已超时(%1ms)，重新发起").arg(ageMs);
        m_refreshingToken = false;
        m_refreshStartedAtMs = 0;
    }
    qCInfo(logAccount) << QStringLiteral("正在刷新微软令牌...");
    m_refreshingToken = true;
    m_refreshStartedAtMs = QDateTime::currentMSecsSinceEpoch();

    QUrlQuery postData;
    postData.addQueryItem(QStringLiteral("client_id"), QStringLiteral(SHADOW_AZURE_CLIENT_ID));
    postData.addQueryItem(QStringLiteral("refresh_token"), m_msRefreshToken);
    postData.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
    postData.addQueryItem(QStringLiteral("redirect_uri"), QStringLiteral("http://localhost"));

    QByteArray body = postData.toString(QUrl::FullyEncoded).toUtf8();

    QNetworkRequest req(QUrl(QStringLiteral("https://login.microsoftonline.com/consumers/oauth2/v2.0/token")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    req.setTransferTimeout(10000);

    QNetworkReply* rawReply = HttpClient::instance().post(req, body);
    QPointer<QNetworkReply> replyGuard(rawReply);
    connect(rawReply, &QNetworkReply::finished, this, [this, replyGuard]() {
        QNetworkReply* reply = replyGuard.data();
        if (!reply) {
            m_refreshingToken = false;
            m_refreshStartedAtMs = 0;
            qCWarning(logAccount) << QStringLiteral("Microsoft Token刷新失败 原因=reply已销毁");
            emit tokenRefreshed(false);
            emit tokenRefreshFailed(false, tr("网络请求异常"));
            return;
        }

        QByteArray raw = reply->readAll();
        QJsonObject obj = QJsonDocument::fromJson(raw).object();

        if (reply->error() != QNetworkReply::NoError || !obj[QStringLiteral("access_token")].isString()) {
            m_refreshingToken = false;
            m_refreshStartedAtMs = 0;

            // Distinguish token-expired from network/server errors
            bool tokenExpired = false;
            QString reason;

            if (!obj.isEmpty()) {
                QString err = obj[QStringLiteral("error")].toString();
                if (err == QStringLiteral("invalid_grant")) {
                    tokenExpired = true;
                    reason = tr("令牌已过期");
                }
            }

            if (!tokenExpired) {
                QNetworkReply::NetworkError netErr = reply->error();
                if (netErr == QNetworkReply::TimeoutError ||
                    netErr == QNetworkReply::ConnectionRefusedError ||
                    netErr == QNetworkReply::HostNotFoundError ||
                    netErr == QNetworkReply::TemporaryNetworkFailureError) {
                    reason = tr("网络异常，令牌刷新失败");
                } else if (netErr != QNetworkReply::NoError) {
                    int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                    if (httpStatus >= 500) {
                        reason = tr("服务器错误 (%1)，令牌刷新失败").arg(httpStatus);
                    } else {
                        reason = tr("令牌刷新失败");
                    }
                }
            }

            if (reason.isEmpty()) reason = tr("令牌刷新失败");
            // Sanitize response body: mask token/secret fields before logging
            QByteArray safeRaw = raw.left(200);
            for (const auto& field : {QByteArrayLiteral("access_token"), QByteArrayLiteral("refresh_token"),
                                      QByteArrayLiteral("token"), QByteArrayLiteral("secret")}) {
                int idx = 0;
                while ((idx = safeRaw.indexOf(field + ":\"", idx)) >= 0) {
                    int valStart = idx + field.size() + 2;
                    int valEnd = safeRaw.indexOf('"', valStart);
                    if (valEnd > valStart) {
                        safeRaw.replace(valStart, valEnd - valStart, QByteArrayLiteral("***"));
                        idx = valStart + 3;  // skip past ***
                    } else {
                        break;
                    }
                }
            }
            qCWarning(logAccount) << QStringLiteral("Microsoft Token刷新失败 原因=%1 响应=%2").arg(reason, QString::fromUtf8(safeRaw));

            emit tokenRefreshed(false);
            emit tokenRefreshFailed(tokenExpired, reason);

            if (tokenExpired) {
                // Only prompt re-login when token is genuinely expired
                emit logMessage(tr("正版登录已过期，请重新登录"));
            } else {
                emit logMessage(tr("令牌刷新暂时失败（%1），将在下次启动时重试").arg(reason));
            }

            reply->deleteLater();
            return;
        }

        m_msRefreshToken = obj[QStringLiteral("refresh_token")].toString(m_msRefreshToken);
        QString newAccessToken = obj[QStringLiteral("access_token")].toString();
        qCInfo(logAccount) << QStringLiteral("微软令牌已刷新,获取MC令牌...");

        // Continue the chain: MS access_token → XBL → XSTS → Minecraft token
        // m_refreshingToken already true from function entry
        // Don't set m_loggedIn here — wait for MC chain to complete via loginSuccess/loginFailed
        m_msAuth->refreshMcChain(newAccessToken, m_msRefreshToken);

        reply->deleteLater();
    });
}

} // namespace ShadowLauncher

namespace ShadowLauncher {

// ════════════════════════════════════════════════════════════
// 多账号列表（2026-11-04）
// 设计：只持久化"身份 + 各模式自己的凭据"，同一时刻只有一个活动账号。
//   mode 0 正版：refreshToken（加密），切回来时用它续期
//   mode 1 离线：只有名字，切回来直接离线登录
//   mode 2 外置：apiRoot + accessToken + clientToken，切回来交给 YggdrasilBackend
// 皮肤/披风不进列表：非当前账号没有真实皮肤，UI 用名字首字母占位，
// 不拿别人的头像冒充（不造假数据）。
// ════════════════════════════════════════════════════════════

QString AccountBackend::accountsFilePath() const
{
    return m_dataDir + QStringLiteral("/accounts.json");
}

static QString accountTypeText(int mode)
{
    if (mode == 0) return QStringLiteral("正版");
    if (mode == 2) return QStringLiteral("外置");
    return QStringLiteral("离线");
}

QVariantList AccountBackend::accounts() const
{
    QVariantList out;
    for (int i = 0; i < m_accounts.size(); ++i) {
        const StoredAccount &a = m_accounts.at(i);
        QVariantMap m;
        m[QStringLiteral("index")] = i;
        m[QStringLiteral("mode")] = a.mode;
        m[QStringLiteral("name")] = a.name;
        m[QStringLiteral("uuid")] = a.uuid;
        m[QStringLiteral("typeText")] = accountTypeText(a.mode);
        m[QStringLiteral("current")] = (i == m_currentAccount);
        // 凭据被登出作废后，条目还在但需要重新验证；UI 据此把点击行为改成"打开登录表单"
        const bool needsRelogin = a.needsRelogin
                               || (a.mode == 0 && a.refreshToken.isEmpty())
                               || (a.mode == 2 && a.accessToken.isEmpty());
        m[QStringLiteral("needsRelogin")] = needsRelogin;
        // 头像快照：每个账号登录/切换时各存一份，列表里不会只剩当前那个有头像
        const QString avatarPath = accountAvatarFilePath(a);
        m[QStringLiteral("avatar")] = avatarPath.isEmpty()
            ? QString() : (QStringLiteral("file:///") + avatarPath);
        out.append(m);
    }
    return out;
}

QVariantMap AccountBackend::accountAt(int index) const
{
    if (index < 0 || index >= m_accounts.size()) return {};
    const StoredAccount &a = m_accounts.at(index);
    QVariantMap m;
    m[QStringLiteral("mode")] = a.mode;
    m[QStringLiteral("name")] = a.name;
    m[QStringLiteral("uuid")] = a.uuid;
    m[QStringLiteral("apiRoot")] = a.apiRoot;
    m[QStringLiteral("accessToken")] = a.accessToken;
    m[QStringLiteral("clientToken")] = a.clientToken;
    return m;
}

QString AccountBackend::accountAvatarPath(const StoredAccount &a) const
{
    // 账号名可能带空格/中文，做一次轻量清洗，避免非法文件名
    QString safe;
    for (const QChar &ch : a.name) {
        if (ch.isLetterOrNumber() || ch == QLatin1Char('_') || ch == QLatin1Char('-'))
            safe.append(ch);
        else
            safe.append(QLatin1Char('_'));
    }
    if (safe.isEmpty()) safe = QStringLiteral("account");
    return m_dataDir + QStringLiteral("/assets/accounts/%1_%2.png").arg(a.mode).arg(safe);
}

void AccountBackend::setExternalSkinPath(const QString &url)
{
    if (url == m_externalSkinPath) return;
    m_externalSkinPath = url;
    // 落到当前外置账号的快照（切换时还会再存一次）
    if (m_currentAccount >= 0 && m_currentAccount < m_accounts.size()
        && m_accounts[m_currentAccount].mode == 2) {
        saveCurrentAvatarSnapshot();
    }
}

QString AccountBackend::accountAvatarFilePath(const StoredAccount &a) const
{
    if (!a.avatarFile.isEmpty()) {
        const QString p = m_dataDir + QStringLiteral("/assets/accounts/") + a.avatarFile;
        if (QFileInfo::exists(p)) return p;
    }
    const QString legacy = accountAvatarPath(a);
    return QFileInfo::exists(legacy) ? legacy : QString();
}

// 把当前身份的皮肤/披风写回它自己的账号条目。
// capesReady / skinReady 之后调用：下次切回这个账号可以立刻显示，
// 不必等 Mojang profile 接口回来（那一等就是 3 秒多的空状态）。
void AccountBackend::persistCurrentProfile()
{
    if (m_currentAccount < 0 || m_currentAccount >= m_accounts.size()) return;
    StoredAccount &a = m_accounts[m_currentAccount];
    bool changed = false;
    if (!m_skinPath.isEmpty() && a.skinPath != m_skinPath) { a.skinPath = m_skinPath; changed = true; }
    if (a.capePath != m_capePath) { a.capePath = m_capePath; changed = true; }
    if (a.activeCapeAlias != m_activeCapeAlias) { a.activeCapeAlias = m_activeCapeAlias; changed = true; }
    if (!m_capes.isEmpty()) {
        QJsonArray arr;
        for (const CapeInfo &ci : m_capes) {
            QJsonObject o;
            o[QStringLiteral("alias")] = ci.alias;
            o[QStringLiteral("capeId")] = ci.capeId;
            o[QStringLiteral("url")] = ci.url;
            o[QStringLiteral("localPath")] = ci.localPath;
            o[QStringLiteral("active")] = ci.active;
            arr.append(o);
        }
        const QString json = QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
        if (a.capesJson != json) { a.capesJson = json; changed = true; }
    }
    if (changed) saveAccounts();
}

void AccountBackend::setIdentityLoading(bool on)
{
    if (m_identityLoading == on) return;
    m_identityLoading = on;
    qCInfo(logAccount) << QStringLiteral("[身份] 装载状态=%1 账号=%2")
                              .arg(on ? QStringLiteral("开始") : QStringLiteral("结束"))
                              .arg(m_username);
    emit identityLoadingChanged();
}

void AccountBackend::setCapesLoading(bool on)
{
    if (m_capesLoading == on) return;
    m_capesLoading = on;
    // 披风拉完（或被放弃）= 这一轮身份装载结束
    if (!on) setIdentityLoading(false);
    qCInfo(logAccount) << QStringLiteral("[披风] 加载状态=%1 账号=%2")
                              .arg(on ? QStringLiteral("开始") : QStringLiteral("结束"))
                              .arg(m_capesUser);
    emit capesLoadingChanged();
}

void AccountBackend::saveCurrentAvatarSnapshot()
{
    if (m_currentAccount < 0 || m_currentAccount >= m_accounts.size()) return;
    const StoredAccount &a = m_accounts.at(m_currentAccount);
    // 三种账号的皮肤来源各不相同：
    //   正版 → m_skinPath；离线 → m_offlineSkinPath；外置 → YggdrasilSkinFetcher 灌进来的 m_externalSkinPath。
    // 之前外置走的是 m_offlineSkinPath（永远是空的），所以外置账号从来没有自己的头像快照，
    // 它能显示头像全靠「当前账号实时头像」兜底；一旦切走就变成字母（影报的正是这个）。
    const QString srcUrl = (a.mode == 0) ? m_skinPath
                         : (a.mode == 2) ? m_externalSkinPath
                         : m_offlineSkinPath;
    if (srcUrl.isEmpty()) return;
    const QString srcPath = QUrl(srcUrl).toLocalFile();
    if (srcPath.isEmpty() || !QFileInfo::exists(srcPath)) return;

    // 版本化文件名：内容变了文件名就变，QML 才会重新加载。
    // 以前是固定文件名 + 先删再拷：删掉那一刻 QML 正好去读，就是「字母头像」，
    // 而且拷完后同名 URL 命中缓存，不点第二下不会自己恢复（影实测）。
    const QString base = accountAvatarPath(a);
    const QFileInfo srcInfo(srcPath);
    QString stamp = QString::number(srcInfo.lastModified().toMSecsSinceEpoch());
    if (stamp.isEmpty()) stamp = QString::number(QDateTime::currentMSecsSinceEpoch());
    const QString dst = base.left(base.size() - 4) + QStringLiteral("_")

                        + stamp + QStringLiteral(".png");
    QDir().mkpath(QFileInfo(dst).absolutePath());

    // 先写临时文件再整体替换：绝不留「文件不存在/写了一半」的窗口
    const QString tmp = dst + QStringLiteral(".part");
    QFile::remove(tmp);
    if (!QFile::copy(srcPath, tmp)) return;
    const QString oldFile = accountAvatarFilePath(a);
    if (!QFileInfo::exists(dst)) {
        if (!QFile::rename(tmp, dst)) { QFile::remove(tmp); return; }
    } else {
        QFile::remove(tmp);
    }
    if (m_currentAccount >= 0 && m_currentAccount < m_accounts.size())
        m_accounts[m_currentAccount].avatarFile = QFileInfo(dst).fileName();
    // 旧快照清掉，避免目录里越积越多
    if (!oldFile.isEmpty() && oldFile != dst && QFileInfo::exists(oldFile))
        QFile::remove(oldFile);
    saveAccounts();
    qCInfo(logAccount) << QStringLiteral("账号头像快照已保存: ") << dst;
    emit accountsChanged();
}

void AccountBackend::saveAccounts()
{
    QJsonArray arr;
    for (const StoredAccount &a : m_accounts) {
        QJsonObject o;
        o[QStringLiteral("mode")] = a.mode;
        o[QStringLiteral("name")] = a.name;
        if (a.needsRelogin) o[QStringLiteral("needsRelogin")] = true;
        o[QStringLiteral("uuid")] = TokenCrypto::encrypt(a.uuid);
        if (!a.refreshToken.isEmpty())
            o[QStringLiteral("refreshToken")] = TokenCrypto::encrypt(a.refreshToken);
        if (!a.apiRoot.isEmpty())
            o[QStringLiteral("apiRoot")] = a.apiRoot;
        if (!a.accessToken.isEmpty())
            o[QStringLiteral("accessToken")] = TokenCrypto::encrypt(a.accessToken);
        if (!a.clientToken.isEmpty())
            o[QStringLiteral("clientToken")] = TokenCrypto::encrypt(a.clientToken);
        // 资料缓存（头像/皮肤/披风）：非凭据，明文存
        if (!a.avatarFile.isEmpty()) o[QStringLiteral("avatarFile")] = a.avatarFile;
        if (!a.skinPath.isEmpty()) o[QStringLiteral("skinPath")] = a.skinPath;
        if (!a.capePath.isEmpty()) o[QStringLiteral("capePath")] = a.capePath;
        if (!a.activeCapeAlias.isEmpty()) o[QStringLiteral("activeCapeAlias")] = a.activeCapeAlias;
        if (!a.capesJson.isEmpty()) o[QStringLiteral("capesJson")] = a.capesJson;
        arr.append(o);
    }
    QJsonObject root;
    root[QStringLiteral("current")] = m_currentAccount;
    root[QStringLiteral("list")] = arr;

    QDir().mkpath(m_dataDir);
    QFile f(accountsFilePath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
        f.close();
    }
}

void AccountBackend::loadAccounts()
{
    QFile f(accountsFilePath());
    if (!f.open(QIODevice::ReadOnly)) return;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    f.close();

    m_accounts.clear();
    const QJsonArray arr = root[QStringLiteral("list")].toArray();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        StoredAccount a;
        a.mode = o[QStringLiteral("mode")].toInt(1);
        a.name = o[QStringLiteral("name")].toString();
        if (a.name.isEmpty()) continue;
        a.needsRelogin = o.value(QStringLiteral("needsRelogin")).toBool(false);
        a.uuid = TokenCrypto::decrypt(o[QStringLiteral("uuid")].toString());
        a.refreshToken = TokenCrypto::decrypt(o[QStringLiteral("refreshToken")].toString());
        a.apiRoot = o[QStringLiteral("apiRoot")].toString();
        a.accessToken = TokenCrypto::decrypt(o[QStringLiteral("accessToken")].toString());
        a.clientToken = TokenCrypto::decrypt(o[QStringLiteral("clientToken")].toString());
        a.avatarFile = o[QStringLiteral("avatarFile")].toString();
        a.skinPath = o[QStringLiteral("skinPath")].toString();
        a.capePath = o[QStringLiteral("capePath")].toString();
        a.activeCapeAlias = o[QStringLiteral("activeCapeAlias")].toString();
        a.capesJson = o[QStringLiteral("capesJson")].toString();
        m_accounts.append(a);
    }
    m_currentAccount = root[QStringLiteral("current")].toInt(-1);
    if (m_currentAccount >= m_accounts.size()) m_currentAccount = -1;
    qCInfo(logAccount) << QStringLiteral("账号列表已加载: ") << m_accounts.size()
                       << QStringLiteral(" 当前=") << m_currentAccount;
}

void AccountBackend::markNeedsRelogin(const QString &name, int mode)
{
    if (name.isEmpty()) return;
    bool changed = false;
    for (StoredAccount &a : m_accounts) {
        if (a.mode == mode && a.name.compare(name, Qt::CaseInsensitive) == 0) {
            if (!a.needsRelogin) { a.needsRelogin = true; changed = true; }
        }
    }
    if (changed) {
        saveAccounts();
        emit accountsChanged();
        qCInfo(logAccount) << QStringLiteral("账号已标记为需重新登录:") << name << "mode=" << mode;
    }
}

void AccountBackend::upsertAccount(const StoredAccount &a, bool makeCurrent)
{
    if (a.name.isEmpty()) return;
    int found = -1;
    for (int i = 0; i < m_accounts.size(); ++i) {
        if (m_accounts.at(i).mode == a.mode && m_accounts.at(i).name.compare(a.name, Qt::CaseInsensitive) == 0) {
            found = i;
            break;
        }
    }
    if (found >= 0) {
        StoredAccount &dst = m_accounts[found];
        // 这次是带着新令牌来的 → 之前"需重新登录"的标记作废
        dst.needsRelogin = false;
        if (!a.uuid.isEmpty()) dst.uuid = a.uuid;
        if (!a.refreshToken.isEmpty()) dst.refreshToken = a.refreshToken;
        if (!a.apiRoot.isEmpty()) dst.apiRoot = a.apiRoot;
        if (!a.accessToken.isEmpty()) dst.accessToken = a.accessToken;
        if (!a.clientToken.isEmpty()) dst.clientToken = a.clientToken;
    } else {
        m_accounts.append(a);
        found = m_accounts.size() - 1;
    }
    if (makeCurrent) m_currentAccount = found;
    saveAccounts();
    emit accountsChanged();
}

void AccountBackend::upsertExternalAccount(const QString &name, const QString &uuid,
                                           const QString &apiRoot, const QString &accessToken,
                                           const QString &clientToken)
{
    StoredAccount a;
    a.mode = 2;
    a.name = name;
    a.uuid = uuid;
    a.apiRoot = apiRoot;
    a.accessToken = accessToken;
    a.clientToken = clientToken;
    {
        const QByteArray h = QCryptographicHash::hash(accessToken.toUtf8(),
                                                      QCryptographicHash::Sha1).toHex();
        qCInfo(logAccount) << QStringLiteral("[账号列表] 写入外置令牌 %1/len%2 uuid=%3")
                                  .arg(QString::fromLatin1(h.left(8)))
                                  .arg(accessToken.size())
                                  .arg(uuid.left(8));
    }
    upsertAccount(a, true);
}

void AccountBackend::clearActiveIdentity()
{
    m_username.clear();
    m_uuid.clear();
    m_offlineUsername.clear();
    m_offlineUuid.clear();
    m_skinPath.clear();
    m_offlineSkinPath.clear();
    m_capePath.clear();
    m_activeCapeAlias.clear();
    m_capes.clear();
    m_msMcToken.clear();
    secureWipe(m_msRefreshToken);
    m_msTokenObtainedAt = 0;
    m_msTokenExpiresIn = 0;
    m_loggedIn = false;
    m_isOnline = false;
    // 切号时把加载状态一起收掉：披风加载条绝不能挂到下一个账号身上
    m_capesPending = 0;
    m_capesUser.clear();
    setCapesLoading(false);
    setIdentityLoading(false);
    if (m_refreshTimer) m_refreshTimer->stop();
    emit accountChanged();
    emit skinReady();
    emit offlineSkinReady();
}

void AccountBackend::switchAccount(int index)
{
    if (index < 0 || index >= m_accounts.size()) return;
    if (index == m_currentAccount) return;
    const StoredAccount a = m_accounts.at(index);

    // 切走之前先把当前账号的头像存下来，否则旧账号会丢头像
    saveCurrentAvatarSnapshot();
    clearActiveIdentity();
    m_currentAccount = index;

    if (a.mode == 1) {
        // 离线：直接重新登录，会写 offlineUsername/offlineUuid
        offlineLogin(a.name);
    } else if (a.mode == 0) {
        // 正版：先装载身份并用 refreshToken 续期（失败会走 microsoftLoginFailed，
        // UI 提示"已过期，请重新登录"，但账号仍留在列表里）
        m_username = a.name;
        m_uuid = a.uuid;
        m_msRefreshToken = a.refreshToken;
        m_loggedIn = true;
        m_isOnline = true;
        // 从切换这一刻点亮顶部加载条：后面还有令牌链 + 档案 + 披风下载，
        // 全都跑完（或超时）才熄灭。
        setIdentityLoading(true);
        // 先把它上次的资料摆上去：否则要等令牌刷新 + MC 档案 + Mojang profile
        // 一连串接口回来（实测 3.5 秒），期间列表是字母头像、详情写「没有可用披风」。
        if (!a.skinPath.isEmpty()) m_skinPath = a.skinPath;
        if (!a.capePath.isEmpty()) m_capePath = a.capePath;
        m_activeCapeAlias = a.activeCapeAlias;
        if (!a.capesJson.isEmpty()) {
            m_capes.clear();
            const QJsonArray arr = QJsonDocument::fromJson(a.capesJson.toUtf8()).array();
            for (const QJsonValue &v : arr) {
                const QJsonObject o = v.toObject();
                CapeInfo ci;
                ci.alias = o[QStringLiteral("alias")].toString();
                ci.capeId = o[QStringLiteral("capeId")].toString();
                ci.url = o[QStringLiteral("url")].toString();
                ci.localPath = o[QStringLiteral("localPath")].toString();
                ci.active = o.value(QStringLiteral("active")).toBool(false);
                m_capes.append(ci);
            }
            emit capesReady();
        }
        saveMicrosoftSession();
        emit accountChanged();
        emit skinReady();
        startBackgroundRefresh();
        downloadSkin(a.name);
        if (!m_msRefreshToken.isEmpty()) refreshMicrosoftToken();
        else emit microsoftLoginFailed(tr("这个正版账号没有可用的登录凭据，请重新登录"));
    } else {
        // 外置：本地身份已清空，真正的会话由 ShadowBackend 调 YggdrasilBackend 恢复
        emit accountChanged();
    }

    saveAccounts();
    emit accountsChanged();
    qCInfo(logAccount) << QStringLiteral("已切换账号: ") << a.name << QStringLiteral(" mode=") << a.mode;
    emit logMessage(tr("已切换到 %1").arg(a.name));
}

bool AccountBackend::removeAccount(int index)
{
    if (index < 0 || index >= m_accounts.size()) return false;
    const StoredAccount gone = m_accounts.takeAt(index);
    QFile::remove(accountAvatarPath(gone));

    // 删的是「当前正在用的微软身份」时，必须连持久化会话一起删掉。
    // 否则下次启动 loadMicrosoftSession() 会读到它，构造函数里那段
    // 「已登录但不在列表 → 补登记」又会把账号原样写回来 —— 表现就是
    // 移除账号、重启后它自己又出现了（影实测）。
    const bool wasMsIdentity = (gone.mode == 0)
        && gone.name.compare(m_username, Qt::CaseInsensitive) == 0;
    // 必须在下面的分支之前清：分支里有 `return true`，放在后面会被跳过。
    if (wasMsIdentity) {
        deleteMicrosoftSession();
        secureWipe(m_msRefreshToken);
        m_msMcToken.clear();
        m_msTokenObtainedAt = 0;
        m_msTokenExpiresIn = 0;
        m_loggedIn = false;
        m_isOnline = false;
        m_username.clear();
        m_uuid.clear();
    }

    if (index == m_currentAccount) {
        clearActiveIdentity();
        m_currentAccount = -1;
        if (!m_accounts.isEmpty()) {
            // 还有别的账号：切到第一个
            const int next = 0;
            saveAccounts();
            emit accountsChanged();
            switchAccount(next);
            return true;
        }
        deleteMicrosoftSession();
    } else if (index < m_currentAccount) {
        --m_currentAccount;
    }
    saveAccounts();
    emit accountsChanged();
    emit logMessage(tr("已移除账号 %1").arg(gone.name));
    return true;
}
} // namespace ShadowLauncher
