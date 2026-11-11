// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QDateTime>

#include "utils/types.h"
#include "../core/microsoft_auth.h"

namespace ShadowLauncher {

struct CapeInfo {
    Q_GADGET
    Q_PROPERTY(QString alias MEMBER alias CONSTANT)
    Q_PROPERTY(QString capeId MEMBER capeId CONSTANT)
    Q_PROPERTY(QString localPath MEMBER localPath CONSTANT)
    Q_PROPERTY(bool active MEMBER active CONSTANT)
public:
    QString alias;
    QString capeId;    // Mojang cape UUID for API switching
    QString url;
    QString localPath;
    bool active = false;
};

class AccountBackend : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString username READ username NOTIFY accountChanged)
    Q_PROPERTY(QString offlineUsername READ offlineUsername NOTIFY accountChanged)
    Q_PROPERTY(bool isLoggedIn READ isLoggedIn NOTIFY accountChanged)
    Q_PROPERTY(bool isOnline READ isOnline NOTIFY accountChanged)
    Q_PROPERTY(QString accountUuid READ accountUuid NOTIFY accountChanged)
    Q_PROPERTY(QString offlineUuid READ offlineUuid NOTIFY accountChanged)
    Q_PROPERTY(QString skinPath READ skinPath NOTIFY skinReady)
    // 原始皮肤纹理（整张 64/128）。UI 自己裁脸用：renderHead3D 对部分皮肤会渲染出
    // 错误的头部图（2026-11-04 实测某皮肤渲染成紫色竖条），所以不能只依赖 skinPath。
    Q_PROPERTY(QString skinTexturePath READ skinTexturePath NOTIFY skinReady)
    Q_PROPERTY(QString offlineSkinPath READ offlineSkinPath NOTIFY offlineSkinReady)
    Q_PROPERTY(QString capePath READ capePath NOTIFY capeReady)
    Q_PROPERTY(QVariantList capes READ capes NOTIFY capesReady)
    Q_PROPERTY(QString skinVariant READ skinVariant NOTIFY skinVariantChanged)
    Q_PROPERTY(QStringList offlineUsernames READ offlineUsernames NOTIFY offlineHistoryChanged)
    // ── 多账号列表（2026-11-04）──
    // 结构：[{mode:0/1/2, name, uuid, current:bool, typeText}]
    // 只有当前账号有真实皮肤/令牌，其余条目只存"身份"，切换时才装载。
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)
    Q_PROPERTY(int currentAccount READ currentAccount NOTIFY accountsChanged)
    Q_PROPERTY(bool microsoftLoginBusy READ isMicrosoftLoginBusy NOTIFY microsoftLoginBusyChanged)
    Q_PROPERTY(bool embeddedLoginEnabled READ embeddedLoginEnabled WRITE setEmbeddedLoginEnabled NOTIFY embeddedLoginChanged)

public:
    explicit AccountBackend(QObject *parent = nullptr);

    // ── Property getters ──
    QString username() const { return m_username; }
    QString offlineUsername() const { return m_offlineUsername; }
    bool isLoggedIn() const { return m_loggedIn; }
    bool isOnline() const { return m_isOnline; }
    QString accountUuid() const { return m_uuid; }
    QString offlineUuid() const { return m_offlineUuid; }
    QString mcToken() const { return m_msMcToken; }
    QString skinPath() const { return m_skinPath; }
    QString skinTexturePath() const;
    QString offlineSkinPath() const { return m_offlineSkinPath; }
    QVariantList capes() const;
    QString capePath() const { return m_capePath; }
    QString skinVariant() const { return m_skinVariant; }
    QStringList offlineUsernames() const { return m_offlineUsernames; }

    // ── Slots ──
    Q_INVOKABLE void offlineLogin(const QString &username);
    Q_INVOKABLE void microsoftLogin();
    Q_INVOKABLE void cancelMicrosoftLogin();
    Q_INVOKABLE void selectCape(const QString &alias);
    Q_INVOKABLE void uploadSkin(const QString &filePath, const QString &variant);
    Q_INVOKABLE void refreshSkin();
    Q_INVOKABLE void updateOfflineSkin(const QString &username);
    Q_INVOKABLE void removeOfflineUsername(const QString &username);
    void logout();

    // ── 多账号 ──
    QVariantList accounts() const;
    int currentAccount() const { return m_currentAccount; }
    /// 切到列表第 index 个账号（会清理当前身份再装载；外置模式只清本地态，
    /// 真正的外置会话由 ShadowBackend 交给 YggdrasilBackend 恢复）
    Q_INVOKABLE void switchAccount(int index);
    /// 从列表移除第 index 个账号；移除的是当前账号则切到剩下的第一个（没有就清空登录态）
    Q_INVOKABLE bool removeAccount(int index);
    /// 外置登录成功后由 ShadowBackend 写入列表
    Q_INVOKABLE void upsertExternalAccount(const QString &name, const QString &uuid,
                                           const QString &apiRoot, const QString &accessToken,
                                           const QString &clientToken);
    /// 外置账号切换用：取某条目的字段（找不到返回空 map）
    Q_INVOKABLE QVariantMap accountAt(int index) const;
    // 只把"用户主动登录"算作忙碌：后台静默续期不点亮顶部加载条
    Q_INVOKABLE bool isMicrosoftLoginBusy() const { return m_msAuth && m_msAuth->isUserBusy(); }
    bool embeddedLoginEnabled() const { return m_embeddedLoginEnabled; }
    void setEmbeddedLoginEnabled(bool v);
    QString msRefreshToken() const { return m_msRefreshToken; }
    /// MC AccessToken 本身是否仍在有效期内（不要求存在刷新令牌）。
    /// 启动前的硬校验用它：过期就绝不放行（否则游戏内会出现“无效会话”）。
    bool msMcTokenValid() const { return !m_msMcToken.isEmpty()
                                       && m_msTokenExpiresIn > 0 && m_msTokenObtainedAt > 0
                                       && (m_msTokenObtainedAt + m_msTokenExpiresIn) > QDateTime::currentSecsSinceEpoch(); }
    /// 完整可用判断：MC token 未过期且存在刷新令牌（可自动续期）
    bool msTokenValid() const { return msMcTokenValid() && !m_msRefreshToken.isEmpty(); }
    void refreshMicrosoftToken();
    bool shouldRefresh() const;
    void startBackgroundRefresh();
    /// 启动重试兜底：清除“刷新中”标记，允许重新发起刷新。
    /// 原实现里后台定时器会把该标记置位后又被自身提前 return，导致此后所有刷新被静默跳过。
    void resetRefreshState();

    // Microsoft login state
    Q_PROPERTY(QString msStatus READ msStatus NOTIFY microsoftLoginProgress)
    QString msStatus() const { return m_msStatus; }

signals:
    void embeddedLoginChanged();
    void accountChanged();
    void accountsChanged();   // 多账号列表变化
    void skinReady();
    void offlineSkinReady();
    void capeReady();
    void capesReady();
    void skinVariantChanged();
    void capeChangeFinished(bool success, const QString &errorMsg);
    void skinUploadFinished(bool success, const QString &errorMsg);
    // 「刷新状态」的结果。skinReady/capesReady 不带成败，UI 无法判断该提示成功还是失败，
    // 所以单独给一条带结果的信号（只在用户主动刷新时发，启动流程不发）。
    void refreshFinished(bool success, const QString &errorMsg);
    void offlineHistoryChanged();
    void logMessage(const QString &msg);

    // Microsoft login signals
    void microsoftLoginProgress(const QString& step, const QString& detail);
    void microsoftLoginSuccess(const QString& username, const QString& uuid);
    void microsoftLoginFailed(const QString& error);
    void microsoftLoginBusyChanged();
    void tokenRefreshed(bool ok);
    void tokenRefreshFailed(bool tokenExpired, const QString& reason);

private:
    void downloadSkin(const QString &username);
    void downloadOnlineSkin(bool forceRefresh = false);
    void setFallbackSkin();
    QString renderHead3D(const QString& skinPath);
    static QString toImageUrl(const QString& filePath);
    void loadOfflineHistory();
    void saveOfflineHistory();
    void saveMicrosoftSession();
    void loadMicrosoftSession();
    void deleteMicrosoftSession();

    // ── 多账号持久化 ──
    struct StoredAccount {
        int mode = 0;          // 0 正版 / 1 离线 / 2 外置
        QString name;
        QString uuid;
        QString refreshToken;  // mode 0
        QString apiRoot;       // mode 2
        QString accessToken;   // mode 2
        QString clientToken;   // mode 2
    };
    QString accountsFilePath() const;
    /// 每个账号的头像快照路径（切换/登录后把当前头像存一份，列表里每个账号都能显示）
    QString accountAvatarPath(const StoredAccount &a) const;
    void saveCurrentAvatarSnapshot();
    void loadAccounts();
    void saveAccounts();
    void upsertAccount(const StoredAccount &a, bool makeCurrent = true);
    void clearActiveIdentity();
    QList<StoredAccount> m_accounts;
    int m_currentAccount = -1;
    QString generateOfflineUuid(const QString &username) const;
    QString skinCachePath(const QString &username) const;
    QString capeCachePath(const QString &username) const;
    void initOfflineHeads();

    // Microsoft login state
    MicrosoftAuth* m_msAuth = nullptr;
    bool m_refreshingToken = false;
    qint64 m_refreshStartedAtMs = 0;  // 刷新链路起点（防“刷新中”标记假死）
    QString m_msStatus;
    QString m_msRefreshToken;
    QString m_msMcToken;
    qint64 m_msTokenObtainedAt = 0;   // QDateTime::currentSecsSinceEpoch() when MC token was obtained
    qint64 m_msTokenExpiresIn = 0;    // seconds until expiry (from Mojang response)
    QTimer* m_refreshTimer = nullptr; // periodic background token refresh

    QString m_username;
    QString m_uuid;
    QString m_offlineUsername;
    QString m_offlineUuid;
    QString m_skinPath;
    QString m_offlineSkinPath;
    QString m_capePath;  // active cape path (for avatar)
    QString m_activeCapeAlias;
    QString m_skinVariant;
    QList<CapeInfo> m_capes;
    // 用户主动刷新中：用于把 downloadOnlineSkin 的响应转成 refreshFinished
    bool m_refreshPending = false;
    bool m_loggedIn = false;
    bool m_isOnline = false;
    QStringList m_offlineUsernames;
    bool m_embeddedLoginEnabled = false;
    QString m_dataDir;
};

} // namespace ShadowLauncher
