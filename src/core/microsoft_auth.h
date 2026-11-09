// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

// ── Microsoft OAuth2 Authorization Code Flow for Minecraft ──
// Uses Microsoft Identity Platform v2 endpoint (consumers tenant)
//
// Mode A: localhost callback — system browser → localhost → code extraction
// Mode B: embedded login — standalone wv2login.exe (Edge WebView2 in a
//         separate process; never runs WebView2 inside this process, so
//         closing the login window can never crash the launcher)

#include <QObject>
#include <QString>
#include <QPointer>

class QTcpServer;
class QProcess;

namespace ShadowLauncher {

class MicrosoftAuth : public QObject {
    Q_OBJECT
public:
    explicit MicrosoftAuth(QObject* parent = nullptr);
    ~MicrosoftAuth();

    Q_INVOKABLE void startLogin(const QString& clientId);
    Q_INVOKABLE void startEmbeddedLogin(const QString& clientId);
    Q_INVOKABLE void cancelLogin();
    /// msRefreshToken：刷新流程新得到的刷新令牌（可选）。透传后 loginSuccess 始终携带
    /// 最新刷新令牌，避免 AccountBackend 因无法区分“互动登录 / 后台刷新”而丢弃它。
    /// silent=true 为"后台静默续期"：不发进度、不算用户登录（顶部加载条不亮）。
    Q_INVOKABLE void refreshMcChain(const QString& msAccessToken,
                                    const QString& msRefreshToken = QString(),
                                    bool silent = true);
    bool isBusy() const { return m_busy; }
    /// 用户主动登录（需要显示进度 / 加载条）是否在进行
    bool isUserBusy() const { return m_busy && !m_silent; }
    bool isSilent() const { return m_silent; }

signals:
    void loginProgress(const QString& step, const QString& detail);
    /// 后台静默续期失败：只用于内部重试判断，UI 不弹"登录失败"
    void silentRefreshFailed(const QString& error);
    void loginSuccess(const QString& minecraftToken, const QString& username,
                      const QString& uuid, const QString& refreshToken, int expiresIn = 86400);
    void loginFailed(const QString& error);

    // Internal — progress step signals (used with QueuedConnection)
    void _internalCodeReady(const QString& code, const QString& redirectUri);
    void _internalTokenReady(const QString& accessToken);

private:
    // 统一的忙碌/失败收尾：先复位再发信号。
    // 以前失败分支写成"emit loginFailed(...) 然后 m_busy=false"，
    // UI 收到信号时读到的 isBusy() 仍是 true，之后再没有通知 → 顶部加载条永久卡住。
    void beginBusy(bool silent);
    void finishBusy();
    void fail(const QString& error);
    void emitProgress(const QString& step, const QString& detail = QString());

    bool m_busy = false;
    bool m_silent = false;
    QTimer* m_watchdog = nullptr;
    QString m_clientId;
    QString m_localRedirectUri;
    QString m_msAccessToken;
    QString m_msRefreshToken;
    QString m_msMcToken;
    int m_msTokenExpiresIn = 86400;
    QTcpServer* m_localServer = nullptr;
    QTcpServer* m_localServer6 = nullptr;   // IPv6/::1 监听（浏览器可能先连 ::1）
    QProcess* m_wv2Process = nullptr;
    bool m_embeddedMode = false;
    bool m_codeCaptured = false;

    void startWv2LoginProcess(const QString& clientId);
    Q_INVOKABLE void exchangeCode(const QString& code, const QString& redirectUri);
    void authenticateXbl(const QString& accessToken);
    void authenticateXsts(const QString& xblToken);
    void authenticateMc(const QString& xstsToken, const QString& uhs);
    void fetchMcProfile(const QString& mcAccessToken);
};

} // namespace ShadowLauncher
