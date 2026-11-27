// SPDX-License-Identifier: AGPL-3.0-or-later
#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace ShadowLauncher {

// 外观控制器单例（QML 名：Appearance）。
//
// 职责边界（2026-11-27 D10 收敛）：
//   • 调色板不由这里提供。QML 侧唯一的颜色真源是 ui/Theme.qml —— 实测 ui/ 目录下
//     'Appearance.' 的引用数为 0（唯一命中 Appearance 的是 SettingsPage.qml:338 的
//     组件 id appearanceComp，指 SetAppearancePane，不是本单例）。
//   • colorTokens() 里那套十六进制值与 Theme.qml 并存就是「双调色板」（改色两边会打架）。
//     本类不再以它为真源，QSettings 也从不写颜色（savePreferences 只写 mode/density/reducedMotion）。
//     它保留的原因只有一个：tests/test_appearance_controller.cpp:49-52 断言了 dark/light
//     的 color.background 与 color.primary；测试文件不在本次改动边界内，删表会让该测试
//     变红。新增或修改颜色一律改 ui/Theme.qml，不要往这里加。
//   • 仍在用的功能（不要一起删）：mode(system/light/dark) / density / reducedMotion，
//     以及 control/motion/radius/space/type/z 六组非颜色令牌，由 main_release 的
//     --ui-next-mode、--ui-next-density 与 QSettings 的 appearance/* 驱动。
//   • 壁纸不在这里：壁纸真源是 Theme.bgUrl() + ShadowBackend.customBgUrl。
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
