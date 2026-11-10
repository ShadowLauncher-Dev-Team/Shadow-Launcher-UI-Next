// SPDX-License-Identifier: AGPL-3.0-or-later
#include "ui_next_presenter.h"

#include <QMetaObject>

#include "backend/shadow_backend.h"
#include "backend/account_backend.h"
#include "backend/yggdrasil_backend.h"

namespace ShadowLauncher {

UiNextPresenter::UiNextPresenter(QObject* parent)
    : QObject(parent)
{
}

void UiNextPresenter::initialize(ShadowBackend* backend)
{
    if (m_backend)
        disconnect(m_backend, nullptr, this, nullptr);
    m_backend = backend;
    connect(m_backend, &ShadowBackend::accountChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::selectedVersionChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::versionListReady, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::installedVersionsChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::loginModeChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::runningCountChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::launchStateChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::launchProgressChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::installStateChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::installPhaseChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::microsoftLoginProgress, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::javaPathChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::memorySettingsChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::gameDirChanged, this, [this] { bumpRevision(); });
    connect(m_backend, &ShadowBackend::microsoftLoginSuccess, this, [this] { emit loginSucceeded(); });
    connect(m_backend, &ShadowBackend::microsoftLoginFailed, this, [this](const QString& error) { emit loginFailed(error); });

    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    if (ygg) {
        connect(ygg, &YggdrasilBackend::stateChanged, this, [this] { bumpRevision(); });
        connect(ygg, &YggdrasilBackend::profilesChanged, this, [this] { bumpRevision(); });
        connect(ygg, &YggdrasilBackend::statusMessageChanged, this, [this] { bumpRevision(); });
        connect(ygg, &YggdrasilBackend::showProfileSelection, this, [this] { bumpRevision(); });
        connect(ygg, &YggdrasilBackend::loginSuccess, this, [this] {
            m_externalLoginBusy = false;
            bumpRevision();
            emit loginSucceeded();
        });
        connect(ygg, &YggdrasilBackend::loginFailed, this, [this](const QString& error) {
            m_externalLoginBusy = false;
            bumpRevision();
            emit loginFailed(error);
        });
    }
}

QString UiNextPresenter::appVersion() const
{
    return m_backend ? m_backend->appVersion() : QString();
}

QString UiNextPresenter::displayUsername() const
{
    if (!m_backend)
        return QStringLiteral("未登录");
    QString name;
    if (loginMode() == 1) {
        name = m_backend->offlineUsername().trimmed();
    } else if (loginMode() == 2) {
        auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
        name = ygg ? ygg->property("username").toString().trimmed() : QString();
    } else {
        name = m_backend->username().trimmed();
    }
    return name.isEmpty() ? QStringLiteral("未登录") : name;
}

bool UiNextPresenter::hasAccount() const
{
    if (!m_backend)
        return false;
    if (loginMode() == 1)
        return !m_backend->offlineUsername().trimmed().isEmpty();
    if (loginMode() == 2) {
        auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
        return ygg && ygg->property("loggedIn").toBool();
    }
    return m_backend->isOnline();
}

bool UiNextPresenter::isOnline() const
{
    return m_backend && m_backend->isOnline();
}

QString UiNextPresenter::selectedVersion() const
{
    const QString version = m_backend ? m_backend->selectedVersion().trimmed() : QString();
    return version.isEmpty() ? QStringLiteral("尚未选择版本") : version;
}

QStringList UiNextPresenter::installedVersions() const
{
    return m_backend ? m_backend->installedVersions() : QStringList();
}

int UiNextPresenter::availableVersionCount() const
{
    return m_backend ? m_backend->versionIds().size() : 0;
}

int UiNextPresenter::runningCount() const
{
    return m_backend ? m_backend->runningCount() : 0;
}

bool UiNextPresenter::launching() const
{
    return m_backend && m_backend->isLaunching();
}

bool UiNextPresenter::running() const
{
    return m_backend && m_backend->isRunning();
}

int UiNextPresenter::launchProgress() const
{
    return m_backend ? m_backend->launchProgress() : 0;
}

bool UiNextPresenter::installing() const
{
    return m_backend && m_backend->isInstalling();
}

QString UiNextPresenter::installPhase() const
{
    return m_backend ? m_backend->installPhase() : QString();
}

QString UiNextPresenter::launchVersion() const
{
    return m_backend ? m_backend->launchVersion() : QString();
}

QString UiNextPresenter::launchUsername() const
{
    return m_backend ? m_backend->launchUsername() : QString();
}

int UiNextPresenter::loginMode() const
{
    return m_backend ? m_backend->lastLoginMode() : 1;
}

QString UiNextPresenter::accountType() const
{
    if (!m_backend)
        return QStringLiteral("未登录");
    if (loginMode() == 1)
        return m_backend->offlineUsername().trimmed().isEmpty() ? QStringLiteral("未登录") : QStringLiteral("离线账户");
    if (loginMode() == 2) {
        auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
        const bool loggedIn = ygg && ygg->property("loggedIn").toBool();
        return loggedIn ? QStringLiteral("外置账户") : QStringLiteral("未登录");
    }
    return m_backend->username().trimmed().isEmpty() ? QStringLiteral("未登录") : QStringLiteral("正版账户");
}

bool UiNextPresenter::canLaunch() const
{
    if (!m_backend || m_backend->selectedVersion().trimmed().isEmpty() || m_backend->isLaunching())
        return false;
    if (loginMode() == 1)
        return !m_backend->offlineUsername().trimmed().isEmpty();
    if (loginMode() == 2) {
        auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
        return ygg && ygg->property("loggedIn").toBool();
    }
    return m_backend->isOnline();
}

bool UiNextPresenter::loginBusy() const
{
    if (!m_backend)
        return false;
    if (loginMode() == 2)
        return m_externalLoginBusy;
    if (loginMode() == 0) {
        AccountBackend* account = m_backend->account();
        return account && account->property("microsoftLoginBusy").toBool();
    }
    return false;
}

QString UiNextPresenter::loginStatus() const
{
    if (!m_backend)
        return QString();
    if (loginMode() == 2) {
        auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
        return ygg ? ygg->property("statusMessage").toString() : QString();
    }
    if (loginMode() == 0) {
        AccountBackend* account = m_backend->account();
        return account ? account->property("msStatus").toString() : QString();
    }
    return QString();
}

QString UiNextPresenter::externalApiRoot() const
{
    if (!m_backend)
        return QString();
    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    return ygg ? ygg->property("apiRoot").toString() : QString();
}

QVariantList UiNextPresenter::externalProfiles() const
{
    if (!m_backend)
        return {};
    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    return ygg ? ygg->property("profiles").toList() : QVariantList();
}

int UiNextPresenter::externalProfileIndex() const
{
    if (!m_backend)
        return -1;
    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    return ygg ? ygg->property("profileIndex").toInt() : -1;
}

QString UiNextPresenter::gameDir() const
{
    return m_backend ? m_backend->gameDir() : QString();
}

QString UiNextPresenter::javaLabel() const
{
    if (!m_backend)
        return QStringLiteral("未检测到 Java");
    const int major = m_backend->javaMajor();
    if (major > 0)
        return QStringLiteral("Java %1").arg(major);
    const QString version = m_backend->javaVersion().trimmed();
    return version.isEmpty() ? QStringLiteral("未检测到 Java") : version;
}

int UiNextPresenter::maxMemoryMb() const
{
    return m_backend ? m_backend->maxMemoryMb() : 0;
}

bool UiNextPresenter::autoMemory() const
{
    return m_backend && m_backend->autoMemoryEnabled();
}

int UiNextPresenter::systemMemoryTotalMb() const
{
    if (!m_backend)
        return 0;
    return m_backend->systemMemoryInfo().value(QStringLiteral("total")).toInt();
}

int UiNextPresenter::systemMemoryPercent() const
{
    if (!m_backend)
        return 0;
    return m_backend->systemMemoryInfo().value(QStringLiteral("percent")).toInt();
}

QString UiNextPresenter::launchStatus() const
{
    const QString status = m_backend ? m_backend->launchStatus().trimmed() : QString();
    return status.isEmpty() ? QStringLiteral("当前没有启动任务") : status;
}

void UiNextPresenter::refreshVersions()
{
    if (m_backend)
        m_backend->refreshVersionList();
}

void UiNextPresenter::refreshInstalled()
{
    if (m_backend)
        m_backend->refreshInstalledList();
}

void UiNextPresenter::selectVersion(const QString& versionId)
{
    if (m_backend && !versionId.trimmed().isEmpty())
        m_backend->setSelectedVersion(versionId);
}

void UiNextPresenter::launchSelected()
{
    if (canLaunch())
        m_backend->launch(m_backend->selectedVersion(), loginMode() != 1);
}

void UiNextPresenter::cancelLaunch()
{
    if (m_backend)
        m_backend->cancelLaunch();
}

void UiNextPresenter::setLoginMode(int mode)
{
    if (m_backend && mode >= 0 && mode <= 2)
        m_backend->setLastLoginMode(mode);
}

void UiNextPresenter::microsoftLogin()
{
    if (m_backend) {
        setLoginMode(0);
        m_backend->microsoftLogin();
    }
}

void UiNextPresenter::cancelMicrosoftLogin()
{
    if (m_backend)
        m_backend->cancelMicrosoftLogin();
}

void UiNextPresenter::offlineLogin(const QString& username)
{
    if (m_backend && !username.trimmed().isEmpty()) {
        setLoginMode(1);
        m_backend->offlineLogin(username.trimmed());
    }
}

void UiNextPresenter::externalLogin(const QString& apiRoot, const QString& email, const QString& password)
{
    if (!m_backend)
        return;
    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    if (!ygg)
        return;
    setLoginMode(2);
    m_externalLoginBusy = true;
    bumpRevision();
    QMetaObject::invokeMethod(ygg, "login", Q_ARG(QString, apiRoot), Q_ARG(QString, email), Q_ARG(QString, password));
}

void UiNextPresenter::selectExternalProfile(int index)
{
    if (!m_backend)
        return;
    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    if (ygg)
        QMetaObject::invokeMethod(ygg, "selectProfile", Q_ARG(int, index));
}

void UiNextPresenter::cancelExternalLogin()
{
    if (!m_backend)
        return;
    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    if (ygg)
        QMetaObject::invokeMethod(ygg, "cancelLogin");
    m_externalLoginBusy = false;
    bumpRevision();
}

void UiNextPresenter::externalLogout()
{
    if (!m_backend)
        return;
    auto* ygg = static_cast<YggdrasilBackend*>(m_backend->yggdrasil());
    if (ygg)
        QMetaObject::invokeMethod(ygg, "logout");
}

void UiNextPresenter::logout()
{
    if (m_backend)
        m_backend->logout();
}

bool UiNextPresenter::openLauncherLogs()
{
    return m_backend && m_backend->openLauncherLogsFolder();
}

bool UiNextPresenter::openGameFolder()
{
    return m_backend && m_backend->openGameDir(m_backend->selectedVersion());
}

bool UiNextPresenter::openLogsFolder()
{
    return m_backend && m_backend->openLogsFolder(m_backend->selectedVersion());
}

bool UiNextPresenter::openVersionsFolder()
{
    if (!m_backend)
        return false;
    const QString version = m_backend->selectedVersion();
    return version.isEmpty() ? m_backend->openGameDir({}) : m_backend->openVersionDir(version);
}

void UiNextPresenter::bumpRevision()
{
    ++m_revision;
    emit stateChanged();
}

} // namespace ShadowLauncher
