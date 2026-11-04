// SPDX-License-Identifier: AGPL-3.0-or-later
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace ShadowLauncher {

class ShadowBackend;

class UiNextPresenter : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(UiNext)
    QML_SINGLETON
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(QString displayUsername READ displayUsername NOTIFY stateChanged)
    Q_PROPERTY(bool hasAccount READ hasAccount NOTIFY stateChanged)
    Q_PROPERTY(bool isOnline READ isOnline NOTIFY stateChanged)
    Q_PROPERTY(QString selectedVersion READ selectedVersion NOTIFY stateChanged)
    Q_PROPERTY(QStringList installedVersions READ installedVersions NOTIFY stateChanged)
    Q_PROPERTY(int availableVersionCount READ availableVersionCount NOTIFY stateChanged)
    Q_PROPERTY(int runningCount READ runningCount NOTIFY stateChanged)
    Q_PROPERTY(bool launching READ launching NOTIFY stateChanged)
    Q_PROPERTY(bool running READ running NOTIFY stateChanged)
    Q_PROPERTY(int launchProgress READ launchProgress NOTIFY stateChanged)
    Q_PROPERTY(bool installing READ installing NOTIFY stateChanged)
    Q_PROPERTY(QString installPhase READ installPhase NOTIFY stateChanged)
    Q_PROPERTY(QString launchVersion READ launchVersion NOTIFY stateChanged)
    Q_PROPERTY(QString launchUsername READ launchUsername NOTIFY stateChanged)
    Q_PROPERTY(QString launchStatus READ launchStatus NOTIFY stateChanged)
    Q_PROPERTY(int loginMode READ loginMode NOTIFY stateChanged)
    Q_PROPERTY(QString accountType READ accountType NOTIFY stateChanged)
    Q_PROPERTY(bool canLaunch READ canLaunch NOTIFY stateChanged)
    Q_PROPERTY(bool loginBusy READ loginBusy NOTIFY stateChanged)
    Q_PROPERTY(QString loginStatus READ loginStatus NOTIFY stateChanged)
    Q_PROPERTY(QString externalApiRoot READ externalApiRoot NOTIFY stateChanged)
    Q_PROPERTY(QVariantList externalProfiles READ externalProfiles NOTIFY stateChanged)
    Q_PROPERTY(int externalProfileIndex READ externalProfileIndex NOTIFY stateChanged)
    Q_PROPERTY(QString gameDir READ gameDir NOTIFY stateChanged)
    Q_PROPERTY(QString javaLabel READ javaLabel NOTIFY stateChanged)
    Q_PROPERTY(int maxMemoryMb READ maxMemoryMb NOTIFY stateChanged)
    Q_PROPERTY(bool autoMemory READ autoMemory NOTIFY stateChanged)
    Q_PROPERTY(int systemMemoryTotalMb READ systemMemoryTotalMb NOTIFY stateChanged)
    Q_PROPERTY(int systemMemoryPercent READ systemMemoryPercent NOTIFY stateChanged)
    Q_PROPERTY(double totalHours READ totalHours NOTIFY stateChanged)
    Q_PROPERTY(int revision READ revision NOTIFY stateChanged)

public:
    explicit UiNextPresenter(QObject* parent = nullptr);
    void initialize(ShadowBackend* backend);

    QString appVersion() const;
    QString displayUsername() const;
    bool hasAccount() const;
    bool isOnline() const;
    QString selectedVersion() const;
    QStringList installedVersions() const;
    int availableVersionCount() const;
    int runningCount() const;
    bool launching() const;
    bool running() const;
    int launchProgress() const;
    bool installing() const;
    QString installPhase() const;
    QString launchVersion() const;
    QString launchUsername() const;
    QString launchStatus() const;
    int loginMode() const;
    QString accountType() const;
    bool canLaunch() const;
    bool loginBusy() const;
    QString loginStatus() const;
    QString externalApiRoot() const;
    QVariantList externalProfiles() const;
    int externalProfileIndex() const;
    QString gameDir() const;
    QString javaLabel() const;
    int maxMemoryMb() const;
    bool autoMemory() const;
    int systemMemoryTotalMb() const;
    int systemMemoryPercent() const;
    double totalHours() const;
    int revision() const { return m_revision; }

    Q_INVOKABLE void refreshVersions();
    Q_INVOKABLE void refreshInstalled();
    Q_INVOKABLE void selectVersion(const QString& versionId);
    Q_INVOKABLE void launchSelected();
    Q_INVOKABLE void cancelLaunch();
    Q_INVOKABLE void setLoginMode(int mode);
    Q_INVOKABLE void microsoftLogin();
    Q_INVOKABLE void cancelMicrosoftLogin();
    Q_INVOKABLE void offlineLogin(const QString& username);
    Q_INVOKABLE void externalLogin(const QString& apiRoot, const QString& email, const QString& password);
    Q_INVOKABLE void selectExternalProfile(int index);
    Q_INVOKABLE void cancelExternalLogin();
    Q_INVOKABLE void externalLogout();
    Q_INVOKABLE void logout();
    Q_INVOKABLE bool openLauncherLogs();
    Q_INVOKABLE bool openGameFolder();
    Q_INVOKABLE bool openLogsFolder();
    Q_INVOKABLE bool openVersionsFolder();

signals:
    void stateChanged();
    void loginSucceeded();
    void loginFailed(const QString& error);

private:
    void bumpRevision();

    ShadowBackend* m_backend = nullptr;
    int m_revision = 0;
    bool m_externalLoginBusy = false;
};

} // namespace ShadowLauncher
