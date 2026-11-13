// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkReply>

namespace ShadowLauncher {

/// Yggdrasil 认证协议中一个角色
struct YggdrasilProfile {
    QString id;   // UUID with dashes
    QString name; // Player name

    [[nodiscard]] QJsonObject toJson() const;
    static YggdrasilProfile fromJson(const QJsonObject &obj);
};

/// 认证服务器元数据
struct YggdrasilMeta {
    QString serverName;
    QString registerUrl;
    /// 允许承载皮肤纹理的域名白名单（meta.skinDomains）。
    /// 用于校验 profile 里给出的皮肤 URL 是否来自站点自己信任的域名 ——
    /// 不校验的话，一个被篡改的 profile 可以让启动器去拉任意域名上的图。
    QStringList skinDomains;
    /// 站点是否提供签名公钥（signaturePublickey）。
    /// 目前只记录不校验（校验需要验签 profile，后续再做）；但"有没有"本身
    /// 对一个站点是否规范是有用的信号。
    bool hasSignatureKey = false;

    [[nodiscard]] bool isValid() const { return !serverName.isEmpty(); }
    /// 皮肤 URL 是否在被信任的域名下；没声明 skinDomains 时一律放行（保持旧行为）
    [[nodiscard]] bool skinHostAllowed(const QString &url) const {
        return skinHostAllowedFor(skinDomains, url);
    }
    /// 静态版：域名白名单判断（domains 为空 -> 放行）
    static bool skinHostAllowedFor(const QStringList &domains, const QString &url);
};

/// 完整认证 session
struct YggdrasilSession {
    QString apiRoot;
    QString email;
    QString accessToken;
    QString clientToken;
    QList<YggdrasilProfile> profiles;
    int selectedProfileIndex = 0;
    QString username;  // selectedProfile.name
    QString uuid;      // selectedProfile.id

    [[nodiscard]] bool isValid() const {
        return !apiRoot.isEmpty() && !accessToken.isEmpty() && !username.isEmpty();
    }
    void clear();
};

/// Yggdrasil 认证协议（纯网络逻辑，非 QObject）
class YggdrasilAuth {
public:
    explicit YggdrasilAuth(QNetworkAccessManager *nam);

    // ── 请求 ──
    QNetworkReply* fetchMeta(const QString &apiRoot);
    QNetworkReply* authenticate(const QString &apiRoot,
                                const QString &username,
                                const QString &password,
                                const QString &clientToken);
    QNetworkReply* refresh(const QString &apiRoot,
                           const QString &accessToken,
                           const QString &clientToken,
                           const QString &selectedProfile = QString(),
                           const QString &selectedProfileName = QString());
    /// 校验令牌是否仍然有效（authserver/validate，不轮换令牌）
    /// 204 = 有效；403 = 已失效；404/405 = 服务端未实现该端点
    QNetworkReply* validate(const QString &apiRoot,
                            const QString &accessToken,
                            const QString &clientToken);
    QNetworkReply* invalidate(const QString &apiRoot,
                              const QString &accessToken,
                              const QString &clientToken);

    // ── 响应解析 ──
    static YggdrasilMeta parseMeta(const QByteArray &data, QString &errorOut);
    static YggdrasilSession parseAuthenticate(const QByteArray &data,
                                               const QString &apiRoot,
                                               const QString &emailInput,
                                               QString &errorOut);
    static YggdrasilSession parseRefresh(const QByteArray &data,
                                          const QString &apiRoot,
                                          const QString &email,
                                          QString &errorOut);

    // ── 工具 ──
    static QString generateClientToken();

private:
    QNetworkAccessManager *m_nam;

    QNetworkReply* doPost(const QString &url, const QJsonObject &body);
    QNetworkReply* doGet(const QString &url);
};

} // namespace ShadowLauncher
