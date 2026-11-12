// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "yggdrasil_backend.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QEventLoop>
#include <QLoggingCategory>
#include <QSettings>
#include <QRegularExpression>
#include <QTimer>
#include <QDateTime>
#include <QNetworkRequest>
#include "yggdrasil_skin_fetcher.h"

Q_LOGGING_CATEGORY(logYggBackend, "shadow.yggdrasil.backend")

namespace ShadowLauncher {

static QString yggdrasilDataDir()
{
    QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                   + QStringLiteral("/yggdrasil");
    QDir().mkpath(path);
    return path;
}

YggdrasilBackend::YggdrasilBackend(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_auth(m_nam)
    , m_skinFetcher(new YggdrasilSkinFetcher(this))
{
    loadSession();

    connect(m_skinFetcher, &YggdrasilSkinFetcher::skinReady,
            this, &YggdrasilBackend::onSkinPreloaded);
    connect(m_skinFetcher, &YggdrasilSkinFetcher::skinFailed,
            this, &YggdrasilBackend::onSkinPreloaded);
}

QVariantList YggdrasilBackend::profiles() const
{
    QVariantList list;
    for (const auto &p : m_session.profiles) {
        QVariantMap m;
        m[QStringLiteral("id")] = p.id;
        m[QStringLiteral("name")] = p.name;
        list.append(m);
    }
    return list;
}

void YggdrasilBackend::setStatus(const QString &msg)
{
    if (m_statusMessage != msg) {
        m_statusMessage = msg;
        emit statusMessageChanged();
    }
}

void YggdrasilBackend::fetchMeta(const QString &apiRoot)
{
    if (apiRoot.trimmed().isEmpty()) {
        emit metaFailed(QStringLiteral("认证服务器地址不能为空"));
        return;
    }

    setStatus(QStringLiteral("正在获取服务器信息..."));
    QNetworkReply *reply = m_auth.fetchMeta(apiRoot.trimmed());
    connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onMetaReply);
}

void YggdrasilBackend::login(const QString &apiRoot, const QString &email, const QString &password)
{
    if (apiRoot.trimmed().isEmpty() || email.trimmed().isEmpty() || password.isEmpty()) {
        emit loginFailed(QStringLiteral("请填写完整的登录信息"));
        return;
    }

    m_pendingApiRoot = apiRoot.trimmed();
    m_pendingEmail = email.trimmed();

    setStatus(QStringLiteral("正在登录..."));
    qCInfo(logYggBackend) << QStringLiteral("[外置登录] 发起认证 apiRoot=%1 user=%2 pwdLen=%3")
                                 .arg(apiRoot.trimmed(), m_pendingEmail)
                                 .arg(password.length());

    QNetworkReply *reply = m_auth.authenticate(
        apiRoot.trimmed(), email.trimmed(), password,
        YggdrasilAuth::generateClientToken());

    connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onAuthenticateReply);
}

void YggdrasilBackend::refreshToken()
{
    doRefresh(false);
}

// ── 主动校验会话（启动恢复 / 切回外置登录时调用）──
// 外置登录令牌可能在别处登录、服务端失效等原因提前作废，而本地 session.json
// 结构上依然“有效”。不主动校验就会一直显示已登录（假状态），头像/启动随之失败。
void YggdrasilBackend::validateSession()
{
    if (!m_session.isValid() || m_session.accessToken.isEmpty()) return;
    if (m_refreshing) return;
    if (m_bindingProfile) return;   // 同 doValidate：绑定中校验必然 403

    // 节流：60s 内已校验过就不再打接口（反复切换 tab 不会反复请求）
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (m_lastValidateMs > 0 && (now - m_lastValidateMs) < 60000) return;
    m_lastValidateMs = now;

    qCDebug(logYggBackend) << "Validating saved yggdrasil session for" << m_session.username;
    doValidate();
}

void YggdrasilBackend::doRefresh(bool isValidation)
{
    if (!m_session.isValid() || m_session.accessToken.isEmpty()) return;
    if (m_refreshing) return;

    m_refreshing = true;
    m_tokenUsedForRefresh = m_session.accessToken;
    setStatus(isValidation ? QStringLiteral("正在验证外置登录状态...")
                           : QStringLiteral("正在刷新令牌..."));

    // 带上 selectedProfile：多角色账号的令牌必须绑定角色，否则 refresh 会被拒
    QNetworkReply *reply = m_auth.refresh(
        m_session.apiRoot, m_session.accessToken, m_session.clientToken,
        m_session.uuid, m_session.username);
    connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onRefreshReply);
}

// 非轮换校验：authserver/validate（204=有效 / 403=失效），不会把本地令牌换掉，
// 因此切换 tab / 启动恢复时可以放心调用。
void YggdrasilBackend::doValidate()
{
    if (!m_session.isValid() || m_session.accessToken.isEmpty()) return;
    if (m_refreshing) return;
    // 正在绑定角色：此刻手上的令牌还没绑定 profile，validate 必然 403，
    // 那条 403 会顺着 refresh 复核把刚登录好的会话判死。等绑定完再说。
    if (m_bindingProfile) return;

    m_refreshing = true;
    setStatus(QStringLiteral("正在验证外置登录状态..."));

    QNetworkReply *reply = m_auth.validate(
        m_session.apiRoot, m_session.accessToken, m_session.clientToken);
    connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onValidateReply);
}

void YggdrasilBackend::onValidateReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    m_refreshing = false;

    if (reply->error() == QNetworkReply::OperationCanceledError) return;
    if (m_session.accessToken.isEmpty()) return;   // 期间已登出

    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    reply->readAll();

    if (reply->error() == QNetworkReply::NoError) {
        // 成功通常为 204 No Content
        setStatus(QString());
        qCDebug(logYggBackend) << "Yggdrasil session is valid";
        return;
    }

    if (httpStatus == 401 || httpStatus == 403) {
        // 不能凭 validate 的 403 就直接判"令牌失效"：
        // 部分皮肤站（如 LittleSkin）的 authserver/validate 对所有请求都返回 403，
        // 用它下结论会把刚登录成功的用户"一瞬间"踢成过期。
        // 改用 refresh 复核：令牌有效时 refresh 会成功并顺带续期；
        // refresh 也被服务端拒绝，才真正清会话。
        qCWarning(logYggBackend) << "validate rejected http=" << httpStatus
                                 << ", 交给 refresh 复核";
        doRefresh(true);
        return;
    }

    if (httpStatus == 404 || httpStatus == 405 || httpStatus == 501) {
        // 服务端未实现 validate 端点 → 退回 refresh 校验（会轮换并落盘新令牌）
        qCDebug(logYggBackend) << "validate endpoint unsupported, falling back to refresh";
        doRefresh(true);
        return;
    }

    // 网络类错误：保留会话，待下次校验（不误判为过期）
    qCWarning(logYggBackend) << "Yggdrasil validate failed (network):" << reply->errorString();
    setStatus(QString());
}

// 令牌失效：清会话 + 落盘删除 + 通知 UI（脱离假登录态）
void YggdrasilBackend::clearSessionAfterExpiry()
{
    qCWarning(logYggBackend) << "Yggdrasil session expired/invalid, clearing local session";
    const QString expiredUser = m_session.username;
    m_session.clear();
    m_meta = YggdrasilMeta();
    m_pendingEmail.clear();
    m_refreshing = false;
    m_tokenUsedForRefresh.clear();
    deleteSavedSession();
    setStatus(QString());
    emit stateChanged();
    emit profilesChanged();
    if (!expiredUser.isEmpty())
        emit externalSessionExpired(expiredUser);
    emit loginFailed(QStringLiteral("外置登录会话已过期，请重新登录"));
}

void YggdrasilBackend::logout()
{
    if (!m_session.isValid()) return;

    m_loggingOut = true;
    setStatus(QStringLiteral("正在登出..."));

    // 尝试 invalidate 服务端令牌（不需要等结果，本地直接清）
    if (!m_session.accessToken.isEmpty()) {
        QNetworkReply *reply = m_auth.invalidate(
            m_session.apiRoot, m_session.accessToken, m_session.clientToken);
        connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onLogoutReply);
    }

    // 不管 invalidate 是否成功，本地先清理
    m_session.clear();
    m_meta = YggdrasilMeta();
    m_pendingEmail.clear();
    m_loggingOut = false;
    m_refreshing = false;
    m_lastValidateMs = 0;
    setStatus(QString());
    deleteSavedSession();
    emit stateChanged();
    emit profilesChanged();
}

void YggdrasilBackend::selectProfile(int index)
{
    if (index < 0 || index >= m_session.profiles.size()) return;
    m_session.selectedProfileIndex = index;
    m_session.username = m_session.profiles[index].name;
    m_session.uuid = m_session.profiles[index].id;
    emit profilesChanged();
    emit stateChanged();
    saveSession();
    if (m_pendingProfile) {
        m_pendingProfile = false;
        m_lastValidateMs = QDateTime::currentMSecsSinceEpoch();
        emit loginSuccess();
    }
    // 选好角色后把令牌绑定上去（多角色账号必须这一步，否则令牌未绑定角色）
    bindProfile();
    fetchSkin();
}

void YggdrasilBackend::cancelLogin()
{
    if (!m_pendingProfile) return;
    m_pendingProfile = false;
    m_session.clear();
    emit stateChanged();
}

void YggdrasilBackend::fetchSkin()
{
    if (!m_session.isValid() || m_session.apiRoot.isEmpty() || m_session.uuid.isEmpty())
        return;
    m_skinFetcher->fetchSkin(m_session.apiRoot, m_session.uuid);
}

void YggdrasilBackend::preloadProfileSkins()
{
    if (m_session.profiles.isEmpty() || m_session.apiRoot.isEmpty()) return;
    m_preloadIdx = 0;
    preloadNextSkin();
}

void YggdrasilBackend::onSkinPreloaded()
{
    m_headSeq++;
    emit profileHeadsChanged();
    preloadNextSkin();
}

void YggdrasilBackend::preloadNextSkin()
{
    if (m_preloadIdx < 0 || m_preloadIdx >= m_session.profiles.size()) {
        m_preloadIdx = -1;
        return;
    }
    const auto &p = m_session.profiles[m_preloadIdx];
    m_preloadIdx++;

    QString headPath = YggdrasilSkinFetcher::cacheDir()
                       + QStringLiteral("/") + p.id + QStringLiteral("_head.png");
    if (QFile::exists(headPath)) {
        m_headSeq++;
        emit profileHeadsChanged();
        QTimer::singleShot(0, this, &YggdrasilBackend::preloadNextSkin);
        return;
    }
    m_skinFetcher->fetchSkin(m_session.apiRoot, p.id);
}

QStringList YggdrasilBackend::profileHeadUrls() const
{
    QStringList urls;
    for (const auto &p : m_session.profiles) {
        QString headPath = YggdrasilSkinFetcher::cacheDir()
                           + QStringLiteral("/") + p.id + QStringLiteral("_head.png");
        if (QFile::exists(headPath)) {
            QString url = QUrl::fromLocalFile(headPath).toString();
            urls.append(url + QStringLiteral("?seq=%1").arg(m_headSeq));
        } else {
            urls.append(QString());
        }
    }
    return urls;
}

QString YggdrasilBackend::sessionFilePath() const
{
    return yggdrasilDataDir() + QStringLiteral("/session.json");
}

void YggdrasilBackend::restoreSession(const QString &apiRoot, const QString &accessToken,
                                     const QString &clientToken, const QString &username,
                                     const QString &uuid)
{
    m_session.apiRoot = apiRoot;
    m_session.accessToken = accessToken;
    m_session.clientToken = clientToken;
    m_session.username = username;
    m_session.uuid = uuid;
    m_session.email.clear();
    m_session.profiles.clear();
    m_session.selectedProfileIndex = 0;
    saveSession();
    m_statusMessage.clear();
    emit stateChanged();
    emit statusMessageChanged();
    qCInfo(logYggBackend) << QStringLiteral("外置账号已从多账号列表恢复: ") << apiRoot << username;
    // 令牌可能早已过期：恢复后立刻校验（validateSession 内部对不支持的服端回落 refresh）
    validateSession();
    fetchSkin();
}

void YggdrasilBackend::saveSession()
{
    QJsonObject obj;
    obj[QStringLiteral("apiRoot")]         = m_session.apiRoot;
    obj[QStringLiteral("email")]           = m_session.email;
    obj[QStringLiteral("accessToken")]     = m_session.accessToken;
    obj[QStringLiteral("clientToken")]     = m_session.clientToken;
    obj[QStringLiteral("username")]        = m_session.username;
    obj[QStringLiteral("uuid")]            = m_session.uuid;
    obj[QStringLiteral("profileIndex")]    = m_session.selectedProfileIndex;

    QJsonArray profiles;
    for (const auto &p : m_session.profiles) {
        profiles.append(p.toJson());
    }
    obj[QStringLiteral("profiles")] = profiles;

    // 也存 meta 信息
    QJsonObject metaObj;
    metaObj[QStringLiteral("serverName")] = m_meta.serverName;
    metaObj[QStringLiteral("registerUrl")] = m_meta.registerUrl;
    obj[QStringLiteral("meta")] = metaObj;

    QJsonDocument doc(obj);
    QFile file(sessionFilePath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(doc.toJson(QJsonDocument::Indented));
        file.close();
        qCDebug(logYggBackend) << "Saved yggdrasil session";
    }
}

void YggdrasilBackend::loadSession()
{
    QFile file(sessionFilePath());
    m_hadSavedSession = file.exists();
    if (!file.open(QIODevice::ReadOnly)) return;

    QByteArray data = file.readAll();
    file.close();

    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(data, &err);
    if (err.error != QJsonParseError::NoError) return;

    QJsonObject root = doc.object();
    m_session.apiRoot          = root.value(QStringLiteral("apiRoot")).toString();
    m_session.email            = root.value(QStringLiteral("email")).toString();
    m_session.accessToken      = root.value(QStringLiteral("accessToken")).toString();
    m_session.clientToken      = root.value(QStringLiteral("clientToken")).toString();
    m_session.username         = root.value(QStringLiteral("username")).toString();
    m_session.uuid             = root.value(QStringLiteral("uuid")).toString();
    m_session.selectedProfileIndex = root.value(QStringLiteral("profileIndex")).toInt();

    QJsonArray profilesArr = root.value(QStringLiteral("profiles")).toArray();
    m_session.profiles.clear();
    for (const QJsonValue &v : profilesArr) {
        m_session.profiles.append(YggdrasilProfile::fromJson(v.toObject()));
    }

    QJsonObject metaObj = root.value(QStringLiteral("meta")).toObject();
    m_meta.serverName = metaObj.value(QStringLiteral("serverName")).toString();
    m_meta.registerUrl = metaObj.value(QStringLiteral("registerUrl")).toString();

    // 校验 session 合法性：apiRoot 必须看起来像 URL
    if (m_session.isValid() && !m_session.apiRoot.startsWith(QStringLiteral("http://"))
            && !m_session.apiRoot.startsWith(QStringLiteral("https://"))) {
        qCWarning(logYggBackend) << "Corrupted session: apiRoot is not a URL, discarding";
        m_session.clear();
        deleteSavedSession();
        emit stateChanged();
        return;
    }

    if (m_session.isValid()) {
        qCDebug(logYggBackend) << "Loaded yggdrasil session for" << m_session.username;
        emit stateChanged();
        if (!m_session.profiles.isEmpty())
            emit profilesChanged();

        // 先加载缓存皮肤，让 UI 立即显示
        fetchSkin();

        // 主动校验恢复出来的会话：令牌可能早已失效，不校验就是“假登录态”
        m_lastValidateMs = 0;
        validateSession();
    }
}

void YggdrasilBackend::deleteSavedSession()
{
    QFile::remove(sessionFilePath());
}

// ── 服务器地址格式验证 ──
// 合法格式: host 或 host:port
// host: 字母/数字/连字符/点，不能以连字符开头/结尾
// port: 可选，1-65535
bool YggdrasilBackend::isValidServerAddress(const QString &addr)
{
    if (addr.isEmpty()) return true;  // 空地址 = 未设置，视为合法

    // 禁止空格和控制字符
    for (const QChar &c : addr) {
        if (c.isSpace() || (c.unicode() < 0x20 && c.unicode() != 0)) return false;
    }

    // 分离 host 和 port
    QStringList parts = addr.split(QLatin1Char(':'));
    if (parts.size() > 2) return false;  // 多个冒号

    // 验证 host
    const QString &host = parts[0];
    if (host.isEmpty()) return false;

    // host 长度限制（DNS 标签）
    if (host.size() > 253) return false;

    // host 不能以 . - 开头/结尾
    if (host.startsWith(QLatin1Char('.')) || host.startsWith(QLatin1Char('-'))
        || host.endsWith(QLatin1Char('.')) || host.endsWith(QLatin1Char('-'))) {
        return false;
    }

    // host 逐字符检查：只允许字母、数字、点、连字符
    for (const QChar &c : host) {
        ushort u = c.unicode();
        bool ok = (u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z')
                  || (u >= '0' && u <= '9') || u == '.' || u == '-';
        if (!ok) return false;
    }

    // 验证 port（如果有）
    if (parts.size() == 2) {
        bool ok = false;
        int port = parts[1].toInt(&ok);
        if (!ok || port < 1 || port > 65535) return false;
    }

    return true;
}

// ── 服务器设置（QSettings 持久化）──

QString YggdrasilBackend::serverAddress() const
{
    QSettings settings;
    return settings.value(QStringLiteral("yggdrasil/serverAddress"), QString()).toString();
}

void YggdrasilBackend::setServerAddress(const QString &addr)
{
    QSettings settings;
    QString trimmed = addr.trimmed();
    QString old = settings.value(QStringLiteral("yggdrasil/serverAddress"), QString()).toString();
    if (old == trimmed) return;
    if (!isValidServerAddress(trimmed)) {
        qCWarning(logYggBackend) << "server address rejected (invalid):" << trimmed;
        return;  // 不保存非法地址
    }
    settings.setValue(QStringLiteral("yggdrasil/serverAddress"), trimmed);
    emit serverAddressChanged();
}

QString YggdrasilBackend::serverName() const
{
    QSettings settings;
    return settings.value(QStringLiteral("yggdrasil/serverName"), QString()).toString();
}

void YggdrasilBackend::setServerName(const QString &name)
{
    QSettings settings;
    QString trimmed = name.trimmed();
    QString old = settings.value(QStringLiteral("yggdrasil/serverName"), QString()).toString();
    if (old == trimmed) return;
    settings.setValue(QStringLiteral("yggdrasil/serverName"), trimmed);
    emit serverNameChanged();
}

bool YggdrasilBackend::autoJoinServer() const
{
    QSettings settings;
    return settings.value(QStringLiteral("yggdrasil/autoJoinServer"), false).toBool();
}

void YggdrasilBackend::setAutoJoinServer(bool enabled)
{
    QSettings settings;
    bool old = settings.value(QStringLiteral("yggdrasil/autoJoinServer"), false).toBool();
    if (old == enabled) return;
    settings.setValue(QStringLiteral("yggdrasil/autoJoinServer"), enabled);
    emit autoJoinServerChanged();
}

// ── Slots (网络回复处理) ──

void YggdrasilBackend::onMetaReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    if (reply->error() == QNetworkReply::OperationCanceledError) return;

    if (reply->error() != QNetworkReply::NoError) {
        QString err = reply->errorString();
        setStatus(QString());
        emit metaFailed(QStringLiteral("获取服务器信息失败: ") + err);
        return;
    }

    QByteArray data = reply->readAll();
    QString errorOut;
    YggdrasilMeta meta = YggdrasilAuth::parseMeta(data, errorOut);

    if (!errorOut.isEmpty()) {
        setStatus(QString());
        emit metaFailed(errorOut);
        return;
    }

    m_meta = meta;
    setStatus(QStringLiteral("已连接: ") + meta.serverName);
    emit metaReady();
}

void YggdrasilBackend::onAuthenticateReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    if (reply->error() == QNetworkReply::OperationCanceledError) {
        setStatus(QString());
        emit loginFailed(QStringLiteral("登录已取消"));
        return;
    }

    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (reply->error() != QNetworkReply::NoError) {
        // 尝试从响应体解析结构化错误信息
        QByteArray body = reply->readAll();
        qCWarning(logYggBackend) << QStringLiteral("[外置登录] 认证失败 http=%1 body=%2")
                                        .arg(httpStatus).arg(QString::fromUtf8(body.left(300)));
        QString errorOut;
        YggdrasilSession tmp = YggdrasilAuth::parseAuthenticate(body, m_pendingApiRoot, m_pendingEmail, errorOut);
        setStatus(QString());
        if (!errorOut.isEmpty())
            emit loginFailed(errorOut);
        else
            emit loginFailed(QStringLiteral("网络错误: ") + reply->errorString());
        return;
    }

    QByteArray data = reply->readAll();
    QString errorOut;
    YggdrasilSession session = YggdrasilAuth::parseAuthenticate(
        data, m_pendingApiRoot, m_pendingEmail, errorOut);

    if (!errorOut.isEmpty()) {
        setStatus(QString());
        emit loginFailed(errorOut);
        return;
    }

    // 登录成功 — 待选择角色（多角色）或直接完成（单角色）
    m_session = session;
    setStatus(QString());
    // 暂不保存 session、不发射 loginSuccess、不获取皮肤

    qCInfo(logYggBackend) << QStringLiteral("[外置登录] 认证成功 http=%1 profiles=%2 tokenLen=%3 clientTokenLen=%4")
                                 .arg(httpStatus)
                                 .arg(m_session.profiles.size())
                                 .arg(m_session.accessToken.length())
                                 .arg(m_session.clientToken.length());

    if (m_session.profiles.isEmpty()) {
        emit loginFailed(QStringLiteral("该账号下没有可用角色"));
        return;
    }

    if (m_session.profiles.size() == 1) {
        // 单一角色直接完成
        m_session.selectedProfileIndex = 0;
        m_session.username = m_session.profiles[0].name;
        m_session.uuid = m_session.profiles[0].id;
        saveSession();
        // 刚认证成功：60s 内不必再 validate，否则会在 bindProfile 之前用未绑定令牌打接口
        m_lastValidateMs = QDateTime::currentMSecsSinceEpoch();
        emit loginSuccess();
        emit stateChanged();
        emit profilesChanged();
        // authenticate 拿到的令牌没有绑定角色，必须再刷一次才会被服务端认可，
        // 否则重启后 validate/refresh 一律 403（表现为“重启一次就过期”）。
        bindProfile();
        fetchSkin();
    } else {
        // 多角色：等待用户选择
        m_pendingProfile = true;
        m_session.selectedProfileIndex = -1;  // 未选择
        m_session.username.clear();
        m_session.uuid.clear();
        emit stateChanged();
        emit profilesChanged();
        emit showProfileSelection();
    }
}

void YggdrasilBackend::onRefreshReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    m_refreshing = false;

    if (reply->error() == QNetworkReply::OperationCanceledError) return;

    // 登出后到达的迟到响应：不得据此复活会话
    if (m_session.accessToken.isEmpty()) return;

    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QByteArray data = reply->readAll();

    if (reply->error() != QNetworkReply::NoError) {
        QString errOut;
        YggdrasilAuth::parseRefresh(data, m_session.apiRoot, m_session.email, errOut);
        // 区分“令牌被判定失效”与“纯网络异常”：前者必须清会话，后者保留待下次重试
        const bool tokenRejected =
            httpStatus == 401 || httpStatus == 403
            || reply->error() == QNetworkReply::AuthenticationRequiredError
            || data.contains("\"error\"");
        if (tokenRejected) {
            // 迟到的 403：本次请求用的令牌已经被换掉了（bindProfile/refresh 轮换），
            // 这条失败说的是旧令牌，不能拿来判死当前会话。
            if (!m_tokenUsedForRefresh.isEmpty()
                && m_tokenUsedForRefresh != m_session.accessToken) {
                qCDebug(logYggBackend) << "忽略过期令牌的迟到失败响应 http=" << httpStatus;
                return;
            }
            qCWarning(logYggBackend) << "Yggdrasil token rejected http=" << httpStatus
                                     << "detail=" << errOut;
            clearSessionAfterExpiry();
        } else {
            qCWarning(logYggBackend) << "Yggdrasil token refresh failed (network):" << reply->errorString();
            setStatus(QString());
        }
        return;
    }

    QString errorOut;
    YggdrasilSession session = YggdrasilAuth::parseRefresh(
        data, m_session.apiRoot, m_session.email, errorOut);

    if (!errorOut.isEmpty()) {
        // HTTP 200 但响应体是 error → 令牌同样已失效（同样要挡迟到响应）
        if (!m_tokenUsedForRefresh.isEmpty()
            && m_tokenUsedForRefresh != m_session.accessToken) {
            qCDebug(logYggBackend) << "忽略过期令牌的迟到拒绝响应:" << errorOut;
            return;
        }
        qCWarning(logYggBackend) << "Yggdrasil token refresh rejected:" << errorOut;
        clearSessionAfterExpiry();
        return;
    }

    // 保留角色列表/索引；刷新响应缺 selectedProfile 时沿用旧用户名与 UUID
    session.profiles = m_session.profiles;
    session.selectedProfileIndex = m_session.selectedProfileIndex;
    if (session.username.isEmpty()) session.username = m_session.username;
    if (session.uuid.isEmpty()) session.uuid = m_session.uuid;
    m_session = session;
    saveSession();
    emit tokensRotated();
    emit stateChanged();
    setStatus(QString());
    qCDebug(logYggBackend) << "Yggdrasil token refreshed/validated";
}

// 用 selectedProfile 刷新一次，换回“已绑定角色”的令牌。
// 账号下有多个角色时，authenticate 直接返回的令牌是不绑定角色的，
// 这种令牌在 validate/refresh 会被服务端拒绝，等于登录只在本次运行有效。
void YggdrasilBackend::bindProfile()
{
    if (m_session.accessToken.isEmpty() || m_session.uuid.isEmpty()) return;
    if (m_bindingProfile) return;
    m_bindingProfile = true;

    QNetworkReply *reply = m_auth.refresh(
        m_session.apiRoot, m_session.accessToken, m_session.clientToken,
        m_session.uuid, m_session.username);
    connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onBindReply);
}

void YggdrasilBackend::onBindReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();
    m_bindingProfile = false;

    if (reply->error() == QNetworkReply::OperationCanceledError) return;
    if (m_session.accessToken.isEmpty()) return;   // 期间已登出

    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QByteArray data = reply->readAll();

    if (reply->error() != QNetworkReply::NoError) {
        QString errOut;
        YggdrasilAuth::parseRefresh(data, m_session.apiRoot, m_session.email, errOut);
        qCWarning(logYggBackend) << "Yggdrasil bind-profile failed http=" << httpStatus
                                 << "detail=" << errOut;
        const bool authError = httpStatus == 401 || httpStatus == 403
                               || data.contains("\"error\"");
        if (authError) clearSessionAfterExpiry();
        return;
    }

    QString errorOut;
    YggdrasilSession session = YggdrasilAuth::parseRefresh(
        data, m_session.apiRoot, m_session.email, errorOut);
    if (!errorOut.isEmpty()) {
        qCWarning(logYggBackend) << "Yggdrasil bind-profile rejected:" << errorOut;
        clearSessionAfterExpiry();
        return;
    }

    session.profiles = m_session.profiles;
    session.selectedProfileIndex = m_session.selectedProfileIndex;
    if (session.username.isEmpty()) session.username = m_session.username;
    if (session.uuid.isEmpty()) session.uuid = m_session.uuid;
    m_session = session;
    saveSession();
    m_lastValidateMs = QDateTime::currentMSecsSinceEpoch();
    qCInfo(logYggBackend) << QStringLiteral("[外置登录] 令牌已绑定角色 uuid=%1 tokenLen=%2")
                                 .arg(m_session.uuid).arg(m_session.accessToken.length());
    emit tokensRotated();
    emit stateChanged();
}

void YggdrasilBackend::onLogoutReply()
{
    auto *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();
    // 登出不需要额外处理，已经在 logout() 中清理了
}

} // namespace ShadowLauncher
