// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "microsoft_auth.h"
#include "http_client.h"
#include "../utils/logger.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QTcpServer>
#include <QUrl>
#include <QUrlQuery>
#include <QTimer>
#include <QWindow>
#include <QWidget>
#include <QDebug>

namespace ShadowLauncher {

using namespace Qt::StringLiterals;

// ── Constants ──

static const char* kAuthUrl = "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize";
static const char* kTokenUrl = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token";
static const char* kNativeRedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient";

static const QString kClientId = u"YOUR_CLIENT_ID_HERE"_s;

static QString createState() {
    QByteArray bytes;
    bytes.resize(32);
    for (int i = 0; i < 32; ++i) bytes[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
    return QString::fromLatin1(bytes.toHex());
}

// ── Constructor / Destructor ──

MicrosoftAuth::MicrosoftAuth(QObject* parent) : QObject(parent) {
    qCInfo(logAccount) << QStringLiteral("MSA认证模块初始化");
}
MicrosoftAuth::~MicrosoftAuth() { cancelLogin(); }

// ── cancelLogin ──

// ── 忙碌状态收尾 ────────────────────────────────────────────
// 认证链有 6~7 个异步步骤，任何一个失败都必须"先复位 busy 再通知"，
// 否则 UI 读到的是旧值，加载条会永久挂着。
void MicrosoftAuth::beginBusy(bool silent) {
    m_busy = true;
    m_silent = silent;
    if (!m_watchdog) {
        m_watchdog = new QTimer(this);
        m_watchdog->setSingleShot(true);
        connect(m_watchdog, &QTimer::timeout, this, [this]() {
            if (!m_busy) return;
            qCWarning(logAccount) << QStringLiteral("认证链 90s 未完成，强制收尾");
            fail(tr("认证超时，请重试"));
        });
    }
    // 兜底看门狗：网络请求挂死也不会让"登录中"永远为真
    m_watchdog->start(90 * 1000);
}

void MicrosoftAuth::finishBusy() {
    m_busy = false;
    m_silent = false;
    if (m_watchdog && m_watchdog->isActive()) m_watchdog->stop();
}

void MicrosoftAuth::fail(const QString& error) {
    const bool wasSilent = m_silent;
    finishBusy();
    if (wasSilent) {
        // 后台续期失败不该弹"登录失败"，只交给内部重试逻辑
        emit silentRefreshFailed(error);
    } else {
        emit loginFailed(error);
    }
}

void MicrosoftAuth::emitProgress(const QString& step, const QString& detail) {
    if (m_silent) return;   // 静默续期不冒充"正在登录"
    emit loginProgress(step, detail);
}

void MicrosoftAuth::cancelLogin() {
    qCInfo(logAccount) << QStringLiteral("取消登录");
    if (m_localServer) { m_localServer->close(); m_localServer->deleteLater(); m_localServer = nullptr; }
    if (m_wv2Process) {
        m_wv2Process->kill();
        m_wv2Process->deleteLater();
        m_wv2Process = nullptr;
    }
    m_embeddedMode = false;
    finishBusy();
    m_codeCaptured = false;
}

// ═══════════════════════════════════════════════════
// Localhost callback login (Mode A — default)
// ═══════════════════════════════════════════════════

void MicrosoftAuth::startLogin(const QString& clientId) {
    if (m_busy) return;
    beginBusy(false);
    m_embeddedMode = false;
    m_clientId = clientId.isEmpty() ? kClientId : clientId;
    qCInfo(logAccount) << QStringLiteral("开始本地回调登录 clientId=%1").arg(m_clientId);

    // Create local HTTP server
    m_localServer = new QTcpServer(this);
    int port = 0;
    for (int p : {49152, 49153, 49154, 49155, 49156}) {
        if (m_localServer->listen(QHostAddress::LocalHost, p)) { port = p; break; }
    }
    if (port == 0) {
        qCWarning(logAccount) << QStringLiteral("本地回调端口全部占用");
        fail(tr("无法启动本地回调服务器"));
        return;
    }
    m_localRedirectUri = QStringLiteral("http://localhost:%1").arg(port);

    auto onLocalConnection = [this]() {
        // 浏览器可能连 IPv6 ::1 或 IPv4 127.0.0.1，两个 server 共用这一段
        auto* srv = qobject_cast<QTcpServer*>(sender());
        auto* socket = srv ? srv->nextPendingConnection() : nullptr;
        if (!socket) return;
        socket->waitForReadyRead(1000);
        const QByteArray data = socket->readAll();
        const QString request = QString::fromUtf8(data);
        const QString firstLine = request.section(QStringLiteral("\r\n"), 0, 0);
        qCInfo(logAccount) << QStringLiteral("[MSA] 回调请求: ") << firstLine.left(240);

        // 从请求行里取 path?query，用 QUrl 正规解析（以前是字符串 indexOf("code=") 硬切）
        const int sp1 = firstLine.indexOf(QLatin1Char(' '));
        const int sp2 = firstLine.indexOf(QLatin1Char(' '), sp1 + 1);
        const QString target = (sp1 > 0 && sp2 > sp1)
                ? firstLine.mid(sp1 + 1, sp2 - sp1 - 1) : QString();
        const QUrl callbackUrl(QStringLiteral("http://localhost") + target);
        const QUrlQuery cbQuery(callbackUrl);

        // 非回调请求（favicon、探测请求等）：回个 204 但**保持监听**，
        // 不能像以前那样把第一条连接当回调、发现没有 code 就直接判失败。
        if (!target.startsWith(QLatin1Char('/')) || target.startsWith(QStringLiteral("/favicon"))) {
            socket->write("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n");
            socket->close();
            socket->deleteLater();
            return;
        }

        auto respondAndStop = [this, socket](const char* body) {
            QByteArray html = "<html><body><h2>" + QByteArray(body)
                    + "</h2><p>请返回启动器</p></body></html>";
            socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                          "Connection: close\r\n\r\n" + html);
            socket->close();
            socket->deleteLater();
            if (m_localServer) { m_localServer->close(); m_localServer->deleteLater(); m_localServer = nullptr; }
            if (m_localServer6) { m_localServer6->close(); m_localServer6->deleteLater(); m_localServer6 = nullptr; }
        };

        // 微软把错误也重定向回来（AADSTSxxxx / access_denied 等）：把真实原因显示出来，
        // 否则只会看到"未找到验证码"，完全不知道该改什么。
        if (cbQuery.hasQueryItem(QStringLiteral("error"))) {
            const QString err = cbQuery.queryItemValue(QStringLiteral("error"));
            QString desc = cbQuery.queryItemValue(QStringLiteral("error_description"), QUrl::FullyDecoded);
            if (desc.isEmpty()) desc = err;
            const QString shortDesc = desc.left(180);
            qCWarning(logAccount) << QStringLiteral("[MSA] 回调报错: ") << err << shortDesc;
            respondAndStop("登录失败，请在启动器内查看原因");
            fail(tr("微软回调报错：%1（%2）").arg(err, shortDesc));
            return;
        }

        const QString code = QUrlQuery(callbackUrl).queryItemValue(QStringLiteral("code"), QUrl::FullyDecoded);
        if (code.isEmpty()) {
            respondAndStop("登录失败：回调里没有授权码");
            fail(tr("浏览器回调里没有授权码，请重试"));
            return;
        }
        respondAndStop("登录成功");
        emitProgress(tr("获取授权码"), code.left(15) + u"..."_s);
        exchangeCode(code, m_localRedirectUri);
    };
    connect(m_localServer, &QTcpServer::newConnection, this, onLocalConnection);
    // Windows 上 localhost 可能先解析到 ::1；只监听 127.0.0.1 时浏览器会报 ERR_CONNECTION_REFUSED
    m_localServer6 = new QTcpServer(this);
    if (m_localServer6->listen(QHostAddress::LocalHostIPv6, port)) {
        connect(m_localServer6, &QTcpServer::newConnection, this, onLocalConnection);
    } else {
        m_localServer6->deleteLater();
        m_localServer6 = nullptr;
    }

    QString state = createState();
    QUrl url(kAuthUrl);
    QUrlQuery q;
    q.addQueryItem("client_id", m_clientId);
    q.addQueryItem("response_type", "code");
    q.addQueryItem("redirect_uri", m_localRedirectUri);
    q.addQueryItem("scope", "XboxLive.signin offline_access");
    q.addQueryItem("prompt", "select_account");
    q.addQueryItem("state", state);
    url.setQuery(q);

    emitProgress(tr("打开浏览器"), url.toString().left(80));
    QDesktopServices::openUrl(url);

    // 5 分钟没拿到回调就主动失败，避免 UI 永远停在"打开浏览器"
    QTimer::singleShot(5 * 60 * 1000, this, [this]() {
        if (!m_busy || m_embeddedMode) return;
        if (m_localServer) { m_localServer->close(); m_localServer->deleteLater(); m_localServer = nullptr; }
        fail(tr("登录超时（5 分钟未完成浏览器登录），请重试"));
    });
}

// ═══════════════════════════════════════════════════
// Embedded login (wv2login.exe — Edge WebView2, separate process)
// The WebView2 browser never runs inside this process, so closing the
// login window can never crash the launcher. The helper writes the OAuth
// code to a result file we delete right after reading.
// ═══════════════════════════════════════════════════

void MicrosoftAuth::startEmbeddedLogin(const QString& clientId) {
    startWv2LoginProcess(clientId);
}

// ═══════════════════════════════════════════════════
// Embedded login (Mode C — standalone wv2login.exe)
// The WebView2 browser runs in a separate process; the launcher only
// reads the result file, so closing the login window can never crash us.
// ═══════════════════════════════════════════════════

void MicrosoftAuth::startWv2LoginProcess(const QString& clientId) {
    m_clientId = clientId.isEmpty() ? kClientId : clientId;
    const QString redirect = u"https://login.microsoftonline.com/common/oauth2/nativeclient"_s;

    // 先判断助手在不在，再决定要不要开始流程：
    // startLogin() 开头有 if (m_busy) return;，若先 beginBusy 再降级会静默什么都不做。
    const QString exePath = QCoreApplication::applicationDirPath() + QStringLiteral("/wv2login.exe");
    if (!QFileInfo::exists(exePath)) {
        // 内嵌登录依赖独立的 WebView2 助手程序，它不在本仓库内、也不随构建产出。
        // 缺它就死在这里等于「正版登录完全不可用」，所以降级到本地回调 + 系统浏览器：
        // 流程同样是标准 OAuth 授权码，只是窗口在浏览器里而不是内嵌。
        qCWarning(logApp) << QStringLiteral("[wv2login] 未找到 %1，降级为浏览器登录").arg(exePath);
        m_embeddedMode = false;
        startLogin(m_clientId);
        return;
    }

    beginBusy(false);
    m_embeddedMode = true;
    qCInfo(logApp) << QStringLiteral("[wv2login] 启动独立登录进程 clientId=%1").arg(m_clientId);

    // Result file + WebView2 profile live in the launcher's private data
    // directory (NOT C:\Users\Public — that is world-readable and would leak
    // the authorization code / login cookies). The code file is deleted right
    // after reading; the profile holds login cookies and stays private.
    const QString dataDir =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    const QString outFile = dataDir + QStringLiteral("/wv2login_result_%1.txt")
                                        .arg(QCoreApplication::applicationPid());
    const QString profileDir = dataDir + QStringLiteral("/wv2login-profile");
    QDir().mkpath(profileDir);
    QFile::remove(outFile);

    // Kill any stale helper from a previous run before starting a new one.
    if (m_wv2Process) {
        m_wv2Process->kill();
        m_wv2Process->deleteLater();
    }
    m_wv2Process = new QProcess(this);
    connect(m_wv2Process, &QProcess::finished, this,
            [this, outFile, redirect](int exitCode, QProcess::ExitStatus) {
        qCInfo(logApp) << QStringLiteral("[wv2login] 进程退出 exitCode=%1").arg(exitCode);
        // Read the result file the helper wrote (UTF-8: "code=..." or "cancel").
        QString content;
        {
            QFile f(outFile);
            if (f.open(QIODevice::ReadOnly)) {
                content = QString::fromUtf8(f.readAll());
            }
        }
        QFile::remove(outFile);

        m_embeddedMode = false;
        finishBusy();
        if (content.startsWith(u"code="_s) && content.size() > 5) {
            const QString code = content.mid(5);
            qCInfo(logApp) << QStringLiteral("[wv2login] 已获取授权码 code=%1...").arg(code.left(15));
            emitProgress(tr("获取授权码"), code.left(15) + u"..."_s);
            exchangeCode(code, redirect);
        } else {
            qCInfo(logApp) << QStringLiteral("[wv2login] 未完成登录（窗口关闭/失败），按取消处理");
            emit loginFailed(tr("登录被用户手动取消"));
        }
    });
    connect(m_wv2Process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError err) {
        qCWarning(logApp) << QStringLiteral("[wv2login] 启动失败 error=%1").arg(static_cast<int>(err));
    });

    emitProgress(tr("正在加载登录页面"), QString());
    m_wv2Process->start(exePath, {
        QStringLiteral("--client-id=") + m_clientId,
        QStringLiteral("--output-file=") + outFile,
        QStringLiteral("--user-data-folder=") + profileDir,
    });
}

// ═══════════════════════════════════════════════════
// Token exchange + MC auth (shared between both modes)
// ═══════════════════════════════════════════════════

void MicrosoftAuth::exchangeCode(const QString& code, const QString& redirectUri) {
    qCInfo(logAccount) << QStringLiteral("换取Token 授权码=%1...").arg(code.left(15));
    emitProgress(tr("换取访问令牌"), QString());

    QUrlQuery params;
    params.addQueryItem("client_id", m_clientId);
    params.addQueryItem("code", code);
    params.addQueryItem("redirect_uri", redirectUri);
    params.addQueryItem("grant_type", "authorization_code");

    QNetworkRequest req(QUrl(QString::fromLatin1(kTokenUrl)));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    auto* reply = HttpClient::instance().post(req, params.toString(QUrl::FullyEncoded).toUtf8());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QByteArray data = reply->readAll();
        if (status != 200) {
            qCWarning(logAccount) << QStringLiteral("Token换取失败 HTTP=%1").arg(status);
            fail(QStringLiteral("Token exchange failed: %1").arg(status));
            return;
        }
        QJsonObject resp = QJsonDocument::fromJson(data).object();
        if (resp.contains("error")) {
            fail(resp["error_description"].toString());
            return;
        }
        m_msAccessToken = resp["access_token"].toString();
        m_msRefreshToken = resp["refresh_token"].toString();
        qCInfo(logAccount) << QStringLiteral("Token换取成功 类型=%1 过期=%2s").arg(resp["token_type"].toString(), QString::number(resp["expires_in"].toInt()));
        authenticateXbl(m_msAccessToken);
    });
}

void MicrosoftAuth::authenticateXbl(const QString& accessToken) {
    qCInfo(logAccount) << QStringLiteral("XBL认证");
    emitProgress(tr("Xbox Live 认证"), QString());
    QJsonObject body;
    QJsonObject props;
    props["AuthMethod"] = "RPS";
    props["SiteName"] = "user.auth.xboxlive.com";
    props["RpsTicket"] = QStringLiteral("d=%1").arg(accessToken);
    body["Properties"] = props;
    body["RelyingParty"] = "http://auth.xboxlive.com";
    body["TokenType"] = "JWT";

    QNetworkRequest req(QUrl(QString::fromLatin1("https://user.auth.xboxlive.com/user/authenticate")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    auto* reply = HttpClient::instance().post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        QJsonObject resp = QJsonDocument::fromJson(reply->readAll()).object();
        QString token = resp["Token"].toString();
        if (token.isEmpty()) { qCWarning(logAccount) << QStringLiteral("XBL认证失败 错误=%1").arg(QStringLiteral("Token为空")); fail(tr("XBL 令牌为空")); return; }
        qCInfo(logAccount) << QStringLiteral("XBL认证成功");
        authenticateXsts(token);
    });
}

void MicrosoftAuth::authenticateXsts(const QString& xblToken) {
    qCInfo(logAccount) << QStringLiteral("XSTS认证");
    emitProgress(tr("XSTS 认证"), QString());
    QJsonObject body;
    QJsonObject props;
    props["SandboxId"] = "RETAIL";
    props["UserTokens"] = QJsonArray{xblToken};
    body["Properties"] = props;
    body["RelyingParty"] = "rp://api.minecraftservices.com/";
    body["TokenType"] = "JWT";

    QNetworkRequest req(QUrl(QString::fromLatin1("https://xsts.auth.xboxlive.com/xsts/authorize")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    auto* reply = HttpClient::instance().post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        QJsonObject resp = QJsonDocument::fromJson(reply->readAll()).object();
        if (resp.contains("XErr")) {
            qCWarning(logAccount) << QStringLiteral("XSTS认证失败 XErr=%1").arg(resp["XErr"].toInt());
            fail(tr("XSTS 错误: %1").arg(resp["XErr"].toInt()));
            return;
        }
        QString token = resp["Token"].toString();
        QString uhs = resp["DisplayClaims"].toObject()["xui"].toArray()[0].toObject()["uhs"].toString();
        if (token.isEmpty() || uhs.isEmpty()) { fail(tr("XSTS 响应无效")); return; }
        authenticateMc(token, uhs);
    });
}

void MicrosoftAuth::authenticateMc(const QString& xstsToken, const QString& uhs) {
    qCInfo(logAccount) << QStringLiteral("Minecraft认证");
    emitProgress(tr("Minecraft 认证"), QString());
    QJsonObject body;
    body["identityToken"] = QStringLiteral("XBL3.0 x=%1;%2").arg(uhs, xstsToken);

    QNetworkRequest req(QUrl(QString::fromLatin1("https://api.minecraftservices.com/authentication/login_with_xbox")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    auto* reply = HttpClient::instance().post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        QJsonObject resp = QJsonDocument::fromJson(reply->readAll()).object();
        m_msMcToken = resp["access_token"].toString();
        if (m_msMcToken.isEmpty()) { fail(tr("MC 令牌为空")); return; }
        m_msTokenExpiresIn = resp["expires_in"].toInt(86400);
        qCInfo(logAccount) << QStringLiteral("MC认证成功 expiresIn=%1s").arg(m_msTokenExpiresIn);
        fetchMcProfile(m_msMcToken);
    });
}

void MicrosoftAuth::fetchMcProfile(const QString& mcAccessToken) {
    qCInfo(logAccount) << QStringLiteral("获取MC档案");
    emitProgress(tr("获权个人信息"), QString());

    QNetworkRequest req(QUrl(QString::fromLatin1("https://api.minecraftservices.com/minecraft/profile")));
    req.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(mcAccessToken).toUtf8());

    auto* reply = HttpClient::instance().getRaw(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        finishBusy();
        QJsonObject resp = QJsonDocument::fromJson(reply->readAll()).object();
        QString name = resp["name"].toString();
        QString uuid = resp["id"].toString();
        if (name.isEmpty() || uuid.isEmpty()) { fail(tr("未找到 Minecraft 档案")); return; }
        qCInfo(logAccount) << QStringLiteral("MC档案获取成功 玩家=%1 UUID=%2").arg(name, uuid);
        emit loginSuccess(m_msMcToken, name, uuid, m_msRefreshToken, m_msTokenExpiresIn);
    });
}

void MicrosoftAuth::refreshMcChain(const QString& msAccessToken, const QString& msRefreshToken,
                                 bool silent) {
    qCInfo(logAccount) << QStringLiteral("刷新MC令牌链");
    // 记录刷新得到的新令牌，供 loginSuccess 透传（旧实现不设置 → 信号里 refreshToken 为空）
    if (!msRefreshToken.isEmpty()) m_msRefreshToken = msRefreshToken;
    if (m_busy) {
        // Don't silently skip — the caller (LaunchBackend step 0) is waiting for
        // a signal and will hang if we return without emitting anything.
        // Emit loginFailed so AccountBackend can relay tokenRefreshFailed.
        // m_busy is cleared in fetchMcProfile on success, or in each chain
        // step's error handler.
        qCWarning(logApp) << QStringLiteral("[MSA] refreshMcChain 阻塞 已有认证流程在进行,发射失败信号");
        // fail() 会先复位再发信号；这里被顶掉的多半是后台续期，按静默失败上报
        fail(tr("认证流程冲突，请稍后重试"));
        return;
    }
    // 后台续期默认静默：不发进度、不点亮顶部加载条（用户不应看到"自动登录"）
    beginBusy(silent);
    authenticateXbl(msAccessToken);
}

} // namespace ShadowLauncher
