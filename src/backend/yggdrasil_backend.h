// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QJsonObject>
#include <QNetworkAccessManager>

#include "core/yggdrasil_auth.h"
#include "yggdrasil_skin_fetcher.h"

namespace ShadowLauncher {

/// Yggdrasil 外置登录后端 — 给 QML 消费的 QObject 封装
class YggdrasilBackend : public QObject {
    Q_OBJECT

    // ══ QML 可读属性 ══
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY stateChanged)
    Q_PROPERTY(QString apiRoot READ apiRoot NOTIFY stateChanged)
    Q_PROPERTY(QString email READ email NOTIFY stateChanged)
    Q_PROPERTY(QString username READ username NOTIFY stateChanged)
    Q_PROPERTY(QString uuid READ uuid NOTIFY stateChanged)
    Q_PROPERTY(QString accessToken READ accessToken NOTIFY stateChanged)
    Q_PROPERTY(QString clientToken READ clientToken NOTIFY stateChanged)
    Q_PROPERTY(QString metaServerName READ metaServerName NOTIFY metaReady)
    Q_PROPERTY(QString registerUrl READ registerUrl NOTIFY metaReady)
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(int profileIndex READ profileIndex NOTIFY profilesChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(bool hadSavedSession READ hadSavedSession CONSTANT)
    Q_PROPERTY(QString serverAddress READ serverAddress WRITE setServerAddress NOTIFY serverAddressChanged)
    Q_PROPERTY(bool serverAddressValid READ serverAddressValid NOTIFY serverAddressChanged)
    Q_PROPERTY(QString serverName READ serverName WRITE setServerName NOTIFY serverNameChanged)
    Q_PROPERTY(bool autoJoinServer READ autoJoinServer WRITE setAutoJoinServer NOTIFY autoJoinServerChanged)
    Q_PROPERTY(QObject* skinFetcher READ skinFetcherObj CONSTANT)

    // 多角色选择弹窗用：获取每行缓存的头像 URL
    Q_PROPERTY(QStringList profileHeadUrls READ profileHeadUrls NOTIFY profileHeadsChanged)
    QStringList profileHeadUrls() const;

    /// 预加载全部角色的头像缓存
    Q_INVOKABLE void preloadProfileSkins();

public:
    explicit YggdrasilBackend(QObject *parent = nullptr);

    // ── Getters ──
    bool loggedIn() const { return m_session.isValid(); }
    QString apiRoot() const { return m_session.apiRoot; }
    QString email() const { return m_session.email; }
    QString username() const { return m_session.username; }
    QString uuid() const { return m_session.uuid; }
    QString accessToken() const { return m_session.accessToken; }
    QString clientToken() const { return m_session.clientToken; }
    QString metaServerName() const { return m_meta.serverName; }
    QString registerUrl() const { return m_meta.registerUrl; }
    QVariantList profiles() const;
    int profileIndex() const { return m_session.selectedProfileIndex; }
    QString statusMessage() const { return m_statusMessage; }

    /// ALI（API 地址指示）解析 —— authlib-injector 规范：
    ///   用户输入可以是简写（如 littleskin.cn），客户端先规范化成 https://littleskin.cn，
    ///   再 GET 该地址；若响应头带 X-Authlib-Injector-API-Location，
    ///   则真实 API 根 = 该头（相对路径按当前 URL 解析）；否则输入本身即 API 根。
    /// 这样「点一下填 littleskin.cn」就能自动变成 https://littleskin.cn/api/yggdrasil，
    /// 而且对任何启用了 ALI 的皮肤站都通用，不需要为每家写死地址。
    Q_INVOKABLE void resolveApiRoot(const QString &input);
    /// 纯函数版（不联网）：只做规范化，输入本身已像 API 根时直接用
    static QString normalizeApiRoot(const QString &input);

    /// 拖入识别：从一个本地文件里找 API 地址。
    /// 支持：
    ///   · 文本类（.txt/.json/.yml/.properties/.url/.ini/.cfg/.conf）—— 搜第一个像 Yggdrasil 的 URL
    ///   · .jar —— authlib-injector 本体。它内部不含站点 API 地址，
    ///     但如果是某个皮肤站打包的 jar，常量池里通常留着站点域名，能搜到就顺带用上；
    ///     搜不到也不是错误，UI 会提示「已识别 authlib-injector，请填站点地址」。
    /// outKind 返回识别结果类型：api / authlib / unknown
    Q_INVOKABLE bool resolveApiFromFile(const QString &filePath, QString *outKind = nullptr);

    Q_INVOKABLE void fetchMeta(const QString &apiRoot);
    Q_INVOKABLE void login(const QString &apiRoot, const QString &email, const QString &password);
    Q_INVOKABLE void refreshToken();
    /// 主动校验本地会话是否仍然有效：调用 authserver/validate（非轮换），
    /// 令牌已失效则清除会话/落盘。启动恢复会话后、用户切换回外置登录时都应调用
    /// （旧实现从不校验 → 令牌早已失效仍显示“已登录”，头像无限转圈）。
    Q_INVOKABLE void validateSession();
    // 只清本地会话，不吊销服务端令牌。
    // 多账号切换时用这个：账号列表存的凭据就是这个 accessToken，
    // Yggdrasil 没有 refresh token，吊销了等于把该账号的长期凭据烧掉
    // （实测：切到正版账号 → logout 吊销 → 切回外置 403 → 被判需重新登录）。
    Q_INVOKABLE void logout();
    // 真正注销：吊销服务端令牌。只允许在「账号已被移除」时调用。
    void logoutRevoking();
private:
    void doLogout(bool invalidateRemote);
public:
    Q_INVOKABLE void selectProfile(int index);
    /// 取消登录流程（用户关闭多角色弹窗时调用）
    Q_INVOKABLE void cancelLogin();
    Q_INVOKABLE void fetchSkin();

    /// 从多账号列表恢复一个已存凭据的外置账号（不重新登录，只装回会话 + 校验）
    Q_INVOKABLE void restoreSession(const QString &apiRoot, const QString &accessToken,
                                    const QString &clientToken, const QString &username,
                                    const QString &uuid);

    // 持久化 session
    Q_INVOKABLE void saveSession();
    Q_INVOKABLE void loadSession();
    Q_INVOKABLE void deleteSavedSession();
    bool hadSavedSession() const { return m_hadSavedSession; }
    QString sessionFilePath() const;
    QObject* skinFetcherObj() const { return m_skinFetcher; }

    // ── 服务器设置 ──
    static bool isValidServerAddress(const QString &addr);
    QString serverAddress() const;
    void setServerAddress(const QString &addr);
    bool serverAddressValid() const { return isValidServerAddress(serverAddress()); }
    QString serverName() const;
    void setServerName(const QString &name);
    bool autoJoinServer() const;
    void setAutoJoinServer(bool enabled);

signals:
    /// ALI 解析成功：resolved 是可直接用于登录的 API 根
    void apiRootResolved(const QString &resolved);
    /// ALI 解析失败（网络不通 / 地址无效）
    void apiRootResolveFailed(const QString &error);
    void metaReady();
    void metaFailed(const QString &error);
    void loginSuccess();
    /// refresh 成功会轮换 accessToken/clientToken。
    /// 外层必须把这个新值写回多账号列表，否则 accounts.json 里留的是旧令牌，
    /// 下次“从多账号列表恢复”就会拿旧令牌去校验 → 403 → 被判过期。
    void tokensRotated();
    void loginFailed(const QString &error);
    /// 服务端判定令牌已失效、本地会话被清掉。
    /// username 是被清掉的那个账号，外层据此把账号列表里对应条目标记为"需重新登录"，
    /// 否则下次点它还会拿死令牌去恢复，形成"一点就过期"的循环。
    void externalSessionExpired(const QString &username);
    /// 登录成功后需要选择角色时触发（让 QML 弹出多角色选择弹窗）
    void showProfileSelection();
    void stateChanged();
    void profilesChanged();
    void statusMessageChanged();
    void serverAddressChanged();
    void serverNameChanged();
    void autoJoinServerChanged();
    void profileHeadsChanged();

private slots:
    void onAliResolveReply();
    void onMetaReply();
    void onAuthenticateReply();
    void onRefreshReply();
    void onBindReply();
    void onValidateReply();
    void onLogoutReply();
    void onSkinPreloaded();

private:
    void preloadNextSkin();
    void setStatus(const QString &msg);
    void doRefresh(bool isValidation);
    /// 用 selectedProfile 刷新一次，换取“已绑定角色”的令牌
    void bindProfile();
    void doValidate();
    /// 令牌被服务端判定失效：清除本地会话并通知 UI 重新登录
    void clearSessionAfterExpiry();
    bool m_bindingProfile = false;
    // ALI 解析：记录规范化后的输入，供回包时判断"用户原样输入的地址"与"头指示的地址"
    QString m_aliInput;
    QString m_aliFetchedUrl;
    // 登录成功信号要等 bindProfile 完成后再发：
    // authenticate 返回的令牌没绑定角色，此刻若先 emit loginSuccess，
    // 多账号列表就会把「未绑定令牌」存进 accounts.json，
    // 而 bindProfile 随后会轮换令牌、让旧的那个立刻作废 ——
    // 于是从列表恢复时必然 403，表现为「刚登录就需重新登录」。
    bool m_deferLoginSuccess = false;
    // 发起 refresh/validate 时用的令牌快照。
    // 绑定角色会轮换令牌，迟到的旧请求若被 403 判死，会把刚换好的新令牌连坐清掉
    // （实测：登录成功后 0.3s 内 validate 用未绑定角色的令牌 403 → refresh 403 → 会话被清）。
    QString m_tokenUsedForRefresh;

    QNetworkAccessManager *m_nam = nullptr;
    YggdrasilAuth m_auth;
    YggdrasilSession m_session;
    YggdrasilMeta m_meta;
    QString m_statusMessage;
    QString m_pendingApiRoot;   // 登录过程中记录的 API Root
    QString m_pendingEmail;     // 登录过程中记录邮箱
    bool m_loggingOut = false;
    bool m_pendingProfile = false;   // 登录成功等待选角色
    bool m_refreshing = false;          // 刷新/校验进行中（防重复请求）
    qint64 m_lastValidateMs = 0;        // 上次校验时间（节流，避免反复切换 tab 打接口）
    int m_preloadIdx = -1;
    int m_headSeq = 0;           // 头像预加载索引
    bool m_hadSavedSession = false;  // session.json 是否存在过
    YggdrasilSkinFetcher *m_skinFetcher = nullptr;
};

} // namespace ShadowLauncher
