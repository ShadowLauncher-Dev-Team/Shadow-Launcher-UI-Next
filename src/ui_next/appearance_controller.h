// SPDX-License-Identifier: AGPL-3.0-or-later
#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace ShadowLauncher {

class AppearanceController : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Appearance)
    QML_SINGLETON
    Q_PROPERTY(QString themeId READ themeId WRITE setThemeId NOTIFY themeIdChanged)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(QString effectiveMode READ effectiveMode NOTIFY effectiveModeChanged)
    Q_PROPERTY(QString density READ density WRITE setDensity NOTIFY densityChanged)
    Q_PROPERTY(bool reducedMotion READ reducedMotion WRITE setReducedMotion NOTIFY reducedMotionChanged)
    Q_PROPERTY(QVariantMap tokens READ tokens NOTIFY tokensChanged)
    Q_PROPERTY(QVariantList availableThemes READ availableThemes CONSTANT)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    explicit AppearanceController(QObject* parent = nullptr);

    QString themeId() const { return m_themeId; }
    QString mode() const { return m_mode; }
    QString effectiveMode() const { return m_effectiveMode; }
    QString density() const { return m_density; }
    bool reducedMotion() const { return m_reducedMotion; }
    QVariantMap tokens() const { return m_tokens; }
    QVariantList availableThemes() const;
    int revision() const { return m_revision; }

    Q_INVOKABLE void setThemeId(const QString& themeId);
    Q_INVOKABLE void setMode(const QString& mode);
    Q_INVOKABLE void setDensity(const QString& density);
    Q_INVOKABLE void setReducedMotion(bool reducedMotion);
    void setPersistenceEnabled(bool enabled) { m_persistenceEnabled = enabled; }

signals:
    void themeIdChanged();
    void modeChanged();
    void effectiveModeChanged();
    void densityChanged();
    void reducedMotionChanged();
    void tokensChanged();
    void revisionChanged();

private:
    void loadPreferences();
    void savePreferences() const;
    void updateEffectiveMode();
    void rebuildTokens();
    QVariantMap colorTokens() const;
    QVariantMap controlTokens() const;
    QVariantMap motionTokens() const;

    QString m_themeId = QStringLiteral("midnight-blue");
    QString m_mode = QStringLiteral("system");
    QString m_effectiveMode = QStringLiteral("dark");
    QString m_density = QStringLiteral("comfortable");
    bool m_reducedMotion = false;
    QVariantMap m_tokens;
    int m_revision = 0;
    bool m_persistenceEnabled = true;
};

} // namespace ShadowLauncher
