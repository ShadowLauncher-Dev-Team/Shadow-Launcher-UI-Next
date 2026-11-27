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
#include <QCryptographicHash>
#include <QNetworkRequest>
#include "yggdrasil_skin_fetcher.h"
#include "../utils/token_crypto.h"

Q_LOGGING_CATEGORY(logYggBackend, "shadow.yggdrasil.backend")

namespace ShadowLauncher {

static QString yggdrasilDataDir()
{
    QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                   + QStringLiteral("/yggdrasil");
    QDir().mkpath(path);
    return path;
}

// 令牌指纹：只打前 8 位 SHA1，既能区分是哪一版令牌，又不会把凭据写进日志。
// 排查「登录后立刻被判过期」时，全靠它对齐 authenticate / bind / 落盘 / 恢复 四处用的是不是同一个令牌。
static QString tokenFp(const QString &token)
{
    if (token.isEmpty()) return QStringLiteral("<empty>");
    const QByteArray h = QCryptographicHash::hash(token.toUtf8(), QCryptographicHash::Sha1).toHex();
    return QString::fromLatin1(h.left(8)) + QStringLiteral("/len") + QString::number(token.size());
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

// ══ ALI（API 地址指示）══════════════════════════════════════════
// authlib-injector 规定的服务发现方式，LittleSkin 等皮肤站全站启用：
//   输入 littleskin.cn -----> GET https://littleskin.cn
//                     <----- X-Authlib-Injector-API-Location: /api/yggdrasil
//   => 真实 API 根 https://littleskin.cn/api/yggdrasil
// 没有这个头的站点，输入本身就被当作 API 根（旧行为不变）。
QString YggdrasilBackend::normalizeApiRoot(const QString &input)
{
    QString s = input.trimmed();
    if (s.isEmpty()) return QString();
    // 用户可能粘贴了带 scheme 的完整地址，也可能只输入域名
    if (!s.contains(QStringLiteral("://")))
        s.prepend(QStringLiteral("https://"));
    // 去掉末尾多余的斜杠（ALI 头是相对路径时靠 resolved() 拼接，留着也无害，
    // 但存进 session.json / 拼 /authserver 时多一个斜杠会变成双斜杠）
    while (s.endsWith(QLatin1Char('/'))) s.chop(1);
    return s;
}

// 拖入识别：本函数只在本地读文件、找候选地址（不联网），
// 找到后交给 resolveApiRoot 做 ALI 解析（联网那一步在那边），两者职责分开、失败原因清楚。
QString YggdrasilBackend::resolveApiFromFile(const QString &filePath)
{
    // QML 的 DropArea 给的是 file:// URL（含百分号编码，中文路径必须解开）
    QString path = filePath;
    if (path.startsWith(QStringLiteral("file:"), Qt::CaseInsensitive))
        path = QUrl(path).toLocalFile();
    if (path.isEmpty()) return QString();

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        qCWarning(logYggBackend) << "[drop] 打不开文件:" << path;
        return QString();
    }

    const QString suffix = QFileInfo(path).suffix().toLower();
    const bool isJar = (suffix == QStringLiteral("jar") || suffix == QStringLiteral("zip"));
    // jar 里翻常量池；上限 8MB 足够覆盖 authlib-injector（约 1MB）
    const qint64 cap = isJar ? 8LL * 1024 * 1024 : 256LL * 1024;
    QByteArray raw = f.read(cap);
    f.close();

    // jar 是二进制，但 URL 是纯 ASCII，直接按 Latin-1 粗扫不会因为编码失败漏掉
    const QString text = QString::fromLatin1(raw);

    const bool isAuthlibJar = isJar && (text.contains(QStringLiteral("authlib-injector"), Qt::CaseInsensitive)
                                        || text.contains(QStringLiteral("yushijinhun"), Qt::CaseInsensitive));
    if (isJar && !isAuthlibJar) return QString();

    // 找第一个「像 Yggdrasil API 根」的地址。
    // 两种情况都要认：
    //   ① 完整 URL —— https://littleskin.cn/api/yggdrasil
    //   ② **裸域名** —— 用户从网页上复制下来的多半就是 littleskin.cn 这种，
    //      没有 scheme。不认它的话，拖入最常见的输入反而无效。
    static const QRegularExpression urlRe(
        QStringLiteral(R"(https?://[A-Za-z0-9.\-]+(?::\d+)?(?:/[A-Za-z0-9._~%!$&'()*+,;=:@/\-]*)?)"));
    static const QRegularExpression bareApiRe(
        QStringLiteral(R"(([A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,})/api/yggdrasil\b)"));
    static const QRegularExpression bareHostRe(
        QStringLiteral(R"(\b([A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.(?:cn|com|net|org|cc|io|me|top|xyz|dev|in|hk|tw))\b)"));

    QString best;
    auto it = urlRe.globalMatch(text);
    while (it.hasNext()) {
        const QString u = it.next().captured(0);
        if (u.contains(QStringLiteral("yggdrasil"), Qt::CaseInsensitive)) { best = u; break; }
        if (best.isEmpty() && !u.contains(QStringLiteral(".json"))
            && !u.contains(QStringLiteral(".png")) && !u.contains(QStringLiteral(".jar")))
            best = u;
    }

    // 没有完整 URL 时，退一步找裸域名
    if (best.isEmpty()) {
        auto m = bareApiRe.match(text);
        if (m.hasMatch()) best = m.captured(1);
    }
    if (best.isEmpty()) {
        auto m = bareHostRe.match(text);
        if (m.hasMatch()) best = m.captured(1);
    }

    if (best.isEmpty()) {
        // jar 认得出来但没有地址：算"识别成功但没有可用地址"，由 UI 提示用户补填
        qCInfo(logYggBackend) << "[drop] 认出 authlib-injector 但文件里没有站点地址:" << path;
        return isAuthlibJar ? QStringLiteral("authlib") : QString();
    }

    qCInfo(logYggBackend) << "[drop] 从文件识别出地址:" << best << "来处:" << path;
    resolveApiRoot(best);
    return QStringLiteral("api");
}

void YggdrasilBackend::resolveApiRoot(const QString &input)
{
    const QString base = normalizeApiRoot(input);
    if (base.isEmpty()) {
        emit apiRootResolveFailed(QStringLiteral("地址不能为空"));
        return;
    }

    m_aliInput = base;
    m_aliFetchedUrl = base;

    // 已经是明显的 API 根（路径里带 yggdrasil / authserver / api 段）就不用再探一次，
    // 直接当结果——离线站点、内网地址也可以少一次无效请求。
    const QUrl u(base);
    const QString path = u.path().toLower();
    if (path.contains(QStringLiteral("yggdrasil"))
        || path.contains(QStringLiteral("authserver"))
        || path.endsWith(QStringLiteral("/api"))) {
        emit apiRootResolved(base);
        return;
    }

    setStatus(QStringLiteral("正在解析认证服务器地址..."));

    QNetworkRequest req{QUrl(base)};
    // 只要头，不要正文；部分站点会返回整页 HTML，浪费带宽
    req.setRawHeader("Accept", "application/json");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setTransferTimeout(8000);

    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onAliResolveReply);
}

void YggdrasilBackend::onAliResolveReply()
{
    auto *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply) return;
    reply->deleteLater();

    const QByteArray loc = reply->rawHeader("X-Authlib-Injector-API-Location");
    const auto err = reply->error();

    if (!loc.isEmpty()) {
        // 头里可能是相对路径（LittleSkin 就是 "/api/yggdrasil"），按请求 URL 解析
        QUrl resolved = QUrl(m_aliFetchedUrl).resolved(QUrl(QString::fromUtf8(loc).trimmed()));
        QString out = resolved.toString();
        while (out.endsWith(QLatin1Char('/'))) out.chop(1);
        qCInfo(logYggBackend) << QStringLiteral("[ALI] %1 -> %2").arg(m_aliFetchedUrl, out);
        setStatus(QString());
        emit apiRootResolved(out);
        return;
    }

    // 没有 ALI 头：只要请求本身成功（或重定向成功），就把输入当作 API 根。
    // 注意 4xx 也可能是"API 根没有根路径资源"，所以这里不看状态码，只看网络层是否通。
    if (err == QNetworkReply::NoError
        || err == QNetworkReply::ContentNotFoundError
        || err == QNetworkReply::ProtocolInvalidOperationError) {
        qCInfo(logYggBackend) << QStringLiteral("[ALI] %1 无 ALI 头，按原地址使用").arg(m_aliFetchedUrl);
        setStatus(QString());
        emit apiRootResolved(m_aliInput);
        return;
    }

    setStatus(QString());
    emit apiRootResolveFailed(QStringLiteral("无法连接到 %1：%2")
                                  .arg(m_aliFetchedUrl, reply->errorString()));
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

// 登录流程唯一收尾口。三处出口都必须经过它，pending 才不可能漏复位：
//   ① onAuthenticateReply() —— 覆盖「应答成功」与「应答失败（含解析失败/取消）」两支；
//   ② onLoginTimeout()     —— 覆盖「根本没有应答」；
//   ③ doLogout()           —— 覆盖「登录途中被切号/登出」。
// 反面教材：2026-11 那次「永远 busy」就是标记只在成功分支复位，失败与无应答两条路把它焊死。
void YggdrasilBackend::finishLogin()
{
    if (m_loginTimer && m_loginTimer->isActive()) m_loginTimer->stop();
    if (!m_loginPending) return;
    m_loginPending = false;
    emit loginPendingChanged();
}

void YggdrasilBackend::dropLoginReply()
{
    if (!m_loginReply) return;
    QNetworkReply *r = m_loginReply.data();
    m_loginReply = nullptr;
    disconnect(r, nullptr, this, nullptr);
    r->abort();
    r->deleteLater();
}

void YggdrasilBackend::login(const QString &apiRoot, const QString &email, const QString &password)
{
    // 重入保护：连点 / 回车重发 / 脚本复用入口都挡在这里，服务端只会看到一条 authenticate。
    // QML 侧按钮同时也被 loginPending 禁用（那道只是可视化的那半，不能当唯一防线）。
    if (m_loginPending) {
        qCInfo(logYggBackend) << QStringLiteral("[外置登录] 上一次认证还没结束，忽略重复请求");
        emit loginFailed(QStringLiteral("正在登录中，请稍候"));
        return;
    }

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

    m_loginPending = true;
    emit loginPendingChanged();

    // 超时兜底：QNetworkReply 没有设 transferTimeout（core/yggdrasil_auth.cpp 不设），
    // 一个卡死的连接可以挂上几分钟。20s 到点强制收尾，宁可让用户重试，也不能永远 busy。
    if (!m_loginTimer) {
        m_loginTimer = new QTimer(this);   // 父对象 this：随 backend 一起销毁，不会有悬垂定时器
        m_loginTimer->setSingleShot(true);
        m_loginTimer->setInterval(20000);
        connect(m_loginTimer, &QTimer::timeout, this, &YggdrasilBackend::onLoginTimeout);
    }
    m_loginTimer->start();

    QNetworkReply *reply = m_auth.authenticate(
        apiRoot.trimmed(), email.trimmed(), password,
        YggdrasilAuth::generateClientToken());

    m_loginReply = reply;
    connect(reply, &QNetworkReply::finished, this, &YggdrasilBackend::onAuthenticateReply);
}

void YggdrasilBackend::onLoginTimeout()
{
    if (!m_loginPending) return;
    qCWarning(logYggBackend) << QStringLiteral("[外置登录] 认证 20 秒无应答，强制收尾");
    // 把在途请求摘掉，否则迟到的成功响应会在已经提示「超时」之后又把会话装上（半登录态）
    dropLoginReply();
    finishLogin();
    setStatus(QString());
    emit loginFailed(QStringLiteral("登录超时：20 秒内没有收到认证服务器响应，请检查地址与网络后重试"));
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
    qCInfo(logYggBackend) << QStringLiteral("[refresh] 使用令牌 %1 uuid=%2")
                                 .arg(tokenFp(m_session.accessToken), m_session.uuid.left(8));
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
    m_deferLoginSuccess = false;
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
    doLogout(false);
}

void YggdrasilBackend::logoutRevoking()
{
    doLogout(true);
}

// invalidateRemote=false：只清本地，保留服务端令牌 —— 切号时必须这样，
// 否则 accounts.json 里存的那个 accessToken 会被吊销，下次恢复必然 403。
void YggdrasilBackend::doLogout(bool invalidateRemote)
{
    // 登录途中被切号 / 登出：先把 pending 收掉。放在早退分支之前，
    // 因为「登录还没完成」时 m_session 往往正是 invalid（早退会跳过下面的清理）。
    finishLogin();
    dropLoginReply();

    if (!m_session.isValid()) return;

    qCInfo(logYggBackend) << QStringLiteral("[登出] %1 令牌=%2")
                                 .arg(invalidateRemote ? QStringLiteral("吊销服务端令牌")
                                                       : QStringLiteral("仅清本地，保留令牌供账号列表使用"),
                                      tokenFp(m_session.accessToken));

    m_loggingOut = true;
    setStatus(QStringLiteral("正在登出..."));

    if (invalidateRemote && !m_session.accessToken.isEmpty()) {
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
        m_deferLoginSuccess = true;   // 同样等绑定完成再发
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
    m_skinFetcher->fetchSkin(m_session.apiRoot, m_session.uuid, m_meta.skinDomains);
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
    m_skinFetcher->fetchSkin(m_session.apiRoot, p.id, m_meta.skinDomains);
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
    qCInfo(logYggBackend) << QStringLiteral("[恢复] 传入令牌 %1 uuid=%2 当前会话令牌 %3")
                                 .arg(tokenFp(accessToken), uuid.left(8), tokenFp(m_session.accessToken));
    // 已经是同一个会话（令牌、服务器、角色都一致）：这次「恢复」纯属重复劳动。
    // 更糟的是它会再触发一次 validate/refresh —— 刚登录完立刻打这两个接口，
    // 只会把刚拿到的令牌白白消耗一次，甚至被服务端轮换判死。直接当空操作。
    if (m_session.isValid() && accessToken == m_session.accessToken
        && apiRoot == m_session.apiRoot) {
        qCInfo(logYggBackend) << QStringLiteral("[恢复] 与本会话完全一致，跳过校验");
        emit stateChanged();
        return;
    }
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

// ── 落盘凭据的读写：一律走 TokenCrypto（AES-256-GCM + DPAPI 保护的密钥）──
// 2026-11-25 审计实测：session.json 里 accessToken / clientToken 原来是**明文**，
// 用一份假 authlib 服务器登录后文件里直接就是 '"accessToken": "AUDITFAKE-..."'。
// 同目录的 accounts.json 早就加密了，只有这份 session 漏了。
static QString encryptForDisk(const QString &plain, const char *what)
{
    if (plain.isEmpty()) return {};
    const QString enc = TokenCrypto::encrypt(plain);
    if (enc.isEmpty()) {
        qCWarning(logYggBackend) << QStringLiteral("令牌加密失败，本次不落盘（避免明文写盘）: ") << what;
        return {};
    }
    return enc;
}

static QString readSecretFromDisk(const QJsonObject &root, const QString &key, bool &needMigrate)
{
    const QString raw = root.value(key).toString();
    if (raw.isEmpty()) return {};
    const QString dec = TokenCrypto::decrypt(raw);
    if (!dec.isEmpty()) return dec;
    if (!TokenCrypto::looksEncrypted(raw)) {
        // 旧版本明文落盘：先读进来，loadSession 末尾会以加密形式重写
        needMigrate = true;
        return raw;
    }
    qCWarning(logYggBackend) << QStringLiteral("会话令牌解密失败，按空处理: ") << key;
    return {};
}

void YggdrasilBackend::saveSession()
{
    QJsonObject obj;
    obj[QStringLiteral("apiRoot")]         = m_session.apiRoot;
    obj[QStringLiteral("email")]           = m_session.email;
    obj[QStringLiteral("accessToken")]     = encryptForDisk(m_session.accessToken, "accessToken");
    obj[QStringLiteral("clientToken")]     = encryptForDisk(m_session.clientToken, "clientToken");
    obj[QStringLiteral("encrypted")]       = true;
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
    bool needMigrate = false;
    m_session.apiRoot          = root.value(QStringLiteral("apiRoot")).toString();
    m_session.email            = root.value(QStringLiteral("email")).toString();
    m_session.accessToken      = readSecretFromDisk(root, QStringLiteral("accessToken"), needMigrate);
    m_session.clientToken      = readSecretFromDisk(root, QStringLiteral("clientToken"), needMigrate);
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

    // 明文旧文件：立刻以加密形式重写，别让明文多留一秒钟
    if (needMigrate && m_session.isValid()) {
        qCInfo(logYggBackend) << QStringLiteral("迁移明文会话至加密存储: ") << sessionFilePath();
        saveSession();
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
    // 解析成功不写常驻提示。站点名已经由 metaServerName 暴露给 UI，
    // 而 statusMessage 这一行只该交代"正在做什么"或"哪里失败了"。
    // 之前这里写死「已连接: xxx」且之后从不清理，看起来像登录已经完成，
    // 其实只是读到了 meta —— 用户点一下就会莫名其妙多出一句"已连接"。
    setStatus(QString());
    emit metaReady();
}

void YggdrasilBackend::onAuthenticateReply()
{
    // 应答到了：先复位 pending（成功 / 失败 / 取消 / 解析失败全走这条），
    // 同时把 20s 兜底定时器停掉（finishLogin 内部会 stop）。
    m_loginReply = nullptr;
    finishLogin();

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
        // 登录成功延后到绑定完成（见 onBindReply）
        m_deferLoginSuccess = true;
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
        if (authError) {
            clearSessionAfterExpiry();
        } else if (m_deferLoginSuccess) {
            // 绑角色失败但认证成功（网络原因）：会话仍可用，照常通知 UI 登录成功，别把用户卡在登录页
            m_deferLoginSuccess = false;
            emit loginSuccess();
        }
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
    qCInfo(logYggBackend) << QStringLiteral("[外置登录] 令牌已绑定角色 uuid=%1 令牌=%2")
                                 .arg(m_session.uuid.left(8), tokenFp(m_session.accessToken));
    emit tokensRotated();
    // 先把绑定后的令牌交给多账号列表，再宣布登录成功
    if (m_deferLoginSuccess) {
        m_deferLoginSuccess = false;
        emit loginSuccess();
    }
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
