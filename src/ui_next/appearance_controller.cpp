// SPDX-License-Identifier: AGPL-3.0-or-later
#include "appearance_controller.h"

#include <QEasingCurve>
#include <QGuiApplication>
#include <QSettings>
#include <QStyleHints>

namespace ShadowLauncher {

AppearanceController::AppearanceController(QObject* parent)
    : QObject(parent)
{
    loadPreferences();
    updateEffectiveMode();
    connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged,
            this, [this](Qt::ColorScheme) { updateEffectiveMode(); });
}

QVariantList AppearanceController::availableThemes() const
{
    return { QVariantMap {
        { QStringLiteral("id"), QStringLiteral("midnight-blue") },
        { QStringLiteral("displayName"), QStringLiteral("黑蓝回响") },
        { QStringLiteral("modes"), QStringList { QStringLiteral("dark"), QStringLiteral("light") } }
    } };
}

void AppearanceController::setThemeId(const QString& themeId)
{
    if (themeId != QStringLiteral("midnight-blue") || m_themeId == themeId)
        return;
    m_themeId = themeId;
    savePreferences();
    rebuildTokens();
    emit themeIdChanged();
}

void AppearanceController::setMode(const QString& mode)
{
    if (mode != QStringLiteral("system") && mode != QStringLiteral("light") && mode != QStringLiteral("dark"))
        return;
    if (m_mode == mode)
        return;
    m_mode = mode;
    savePreferences();
    updateEffectiveMode();
    emit modeChanged();
}

void AppearanceController::setDensity(const QString& density)
{
    if (density != QStringLiteral("compact") && density != QStringLiteral("comfortable")
        && density != QStringLiteral("spacious"))
        return;
    if (m_density == density)
        return;
    m_density = density;
    savePreferences();
    rebuildTokens();
    emit densityChanged();
}

void AppearanceController::setReducedMotion(bool reducedMotion)
{
    if (m_reducedMotion == reducedMotion)
        return;
    m_reducedMotion = reducedMotion;
    savePreferences();
    rebuildTokens();
    emit reducedMotionChanged();
}

void AppearanceController::loadPreferences()
{
    QSettings settings;
    const QString mode = settings.value(QStringLiteral("appearance/mode"), QStringLiteral("system")).toString();
    const QString density = settings.value(QStringLiteral("appearance/density"), QStringLiteral("comfortable")).toString();
    // themeId 是常量：调色板真源在 ui/Theme.qml，本类不再恢复任何主题标识。
    m_themeId = QStringLiteral("midnight-blue");
    m_mode = (mode == QStringLiteral("light") || mode == QStringLiteral("dark")) ? mode : QStringLiteral("system");
    m_density = (density == QStringLiteral("compact") || density == QStringLiteral("spacious"))
        ? density : QStringLiteral("comfortable");
    m_reducedMotion = settings.value(QStringLiteral("appearance/reducedMotion"), false).toBool();
}

void AppearanceController::savePreferences() const
{
    if (!m_persistenceEnabled)
        return;
    QSettings settings;
    // 不再写 appearance/themeId：loadPreferences() 无条件把它设回常量 "midnight-blue"，
    // 这个键写了也永远不会被读回，只会在注册表里留垃圾。颜色本身从不持久化。
    settings.setValue(QStringLiteral("appearance/mode"), m_mode);
    settings.setValue(QStringLiteral("appearance/density"), m_density);
    settings.setValue(QStringLiteral("appearance/reducedMotion"), m_reducedMotion);
}

void AppearanceController::updateEffectiveMode()
{
    const bool systemLight = QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Light;
    const QString next = m_mode == QStringLiteral("system")
        ? (systemLight ? QStringLiteral("light") : QStringLiteral("dark")) : m_mode;
    if (m_effectiveMode == next && !m_tokens.isEmpty())
        return;
    m_effectiveMode = next;
    rebuildTokens();
    emit effectiveModeChanged();
}

// 非调色板真源。QML 唯一引用的颜色来源是 ui/Theme.qml（ui/ 下 'Appearance.' 引用数 0）。
// 此表不持久化（savePreferences 不写 color 组），保留原因仅为本类 tokens() 的既有契约被
// tests/test_appearance_controller.cpp:49-52 断言。改颜色请改 ui/Theme.qml。
QVariantMap AppearanceController::colorTokens() const
{
    if (m_effectiveMode == QStringLiteral("light")) {
        return {
            { QStringLiteral("background"), QStringLiteral("#F8FAFC") },
            { QStringLiteral("foreground"), QStringLiteral("#0F172A") },
            { QStringLiteral("card"), QStringLiteral("#FFFFFF") },
            { QStringLiteral("cardForeground"), QStringLiteral("#0F172A") },
            { QStringLiteral("popover"), QStringLiteral("#FFFFFF") },
            { QStringLiteral("popoverForeground"), QStringLiteral("#0F172A") },
            { QStringLiteral("primary"), QStringLiteral("#2563EB") },
            { QStringLiteral("primaryForeground"), QStringLiteral("#FFFFFF") },
            { QStringLiteral("secondary"), QStringLiteral("#EFF6FF") },
            { QStringLiteral("secondaryForeground"), QStringLiteral("#1E3A8A") },
            { QStringLiteral("muted"), QStringLiteral("#F1F5F9") },
            { QStringLiteral("mutedForeground"), QStringLiteral("#64748B") },
            { QStringLiteral("accent"), QStringLiteral("#E2E8F0") },
            { QStringLiteral("accentForeground"), QStringLiteral("#0F172A") },
            { QStringLiteral("destructive"), QStringLiteral("#DC2626") },
            { QStringLiteral("destructiveForeground"), QStringLiteral("#FFFFFF") },
            { QStringLiteral("border"), QStringLiteral("#E2E8F0") },
            { QStringLiteral("input"), QStringLiteral("#E2E8F0") },
            { QStringLiteral("ring"), QStringLiteral("#2563EB") },
            { QStringLiteral("sidebar"), QStringLiteral("#F1F5F9") },
            { QStringLiteral("sidebarForeground"), QStringLiteral("#334155") },
            { QStringLiteral("sidebarAccent"), QStringLiteral("#E2E8F0") },
            { QStringLiteral("sidebarBorder"), QStringLiteral("#E2E8F0") },
            { QStringLiteral("success"), QStringLiteral("#15803D") },
            { QStringLiteral("warning"), QStringLiteral("#B45309") },
            { QStringLiteral("info"), QStringLiteral("#2563EB") },
            { QStringLiteral("scrim"), QStringLiteral("#800F172A") }
        };
    }
    return {
        { QStringLiteral("background"), QStringLiteral("#0C0F16") },
        { QStringLiteral("foreground"), QStringLiteral("#E8ECF8") },
        { QStringLiteral("card"), QStringLiteral("#11141C") },
        { QStringLiteral("cardForeground"), QStringLiteral("#E8ECF8") },
        { QStringLiteral("popover"), QStringLiteral("#151A24") },
        { QStringLiteral("popoverForeground"), QStringLiteral("#E8ECF8") },
        { QStringLiteral("primary"), QStringLiteral("#3B82F6") },
        { QStringLiteral("primaryForeground"), QStringLiteral("#FFFFFF") },
        { QStringLiteral("secondary"), QStringLiteral("#1A1F2E") },
        { QStringLiteral("secondaryForeground"), QStringLiteral("#E8ECF8") },
        { QStringLiteral("muted"), QStringLiteral("#171C27") },
        { QStringLiteral("mutedForeground"), QStringLiteral("#8B95A9") },
        { QStringLiteral("accent"), QStringLiteral("#1C2638") },
        { QStringLiteral("accentForeground"), QStringLiteral("#E8ECF8") },
        { QStringLiteral("destructive"), QStringLiteral("#EF4444") },
        { QStringLiteral("destructiveForeground"), QStringLiteral("#FFFFFF") },
        { QStringLiteral("border"), QStringLiteral("#232A39") },
        { QStringLiteral("input"), QStringLiteral("#232A39") },
        { QStringLiteral("ring"), QStringLiteral("#60A5FA") },
        { QStringLiteral("sidebar"), QStringLiteral("#10141D") },
        { QStringLiteral("sidebarForeground"), QStringLiteral("#B8C2D8") },
        { QStringLiteral("sidebarAccent"), QStringLiteral("#1A2130") },
        { QStringLiteral("sidebarBorder"), QStringLiteral("#232A39") },
        { QStringLiteral("success"), QStringLiteral("#4ADE80") },
        { QStringLiteral("warning"), QStringLiteral("#FBBF24") },
        { QStringLiteral("info"), QStringLiteral("#60A5FA") },
        { QStringLiteral("scrim"), QStringLiteral("#99000000") }
    };
}

QVariantMap AppearanceController::controlTokens() const
{
    if (m_density == QStringLiteral("compact")) {
        return {
            { QStringLiteral("height"), 32 }, { QStringLiteral("listItem"), 36 },
            { QStringLiteral("cardPadding"), 12 }, { QStringLiteral("pagePadding"), 16 },
            { QStringLiteral("gap"), 12 }, { QStringLiteral("sidebarWidth"), 168 }
        };
    }
    if (m_density == QStringLiteral("spacious")) {
        return {
            { QStringLiteral("height"), 48 }, { QStringLiteral("listItem"), 52 },
            { QStringLiteral("cardPadding"), 24 }, { QStringLiteral("pagePadding"), 32 },
            { QStringLiteral("gap"), 28 }, { QStringLiteral("sidebarWidth"), 200 }
        };
    }
    return {
        { QStringLiteral("height"), 40 }, { QStringLiteral("listItem"), 44 },
        { QStringLiteral("cardPadding"), 20 }, { QStringLiteral("pagePadding"), 24 },
        { QStringLiteral("gap"), 20 }, { QStringLiteral("sidebarWidth"), 184 }
    };
}

QVariantMap AppearanceController::motionTokens() const
{
    const int scale = m_reducedMotion ? 0 : 1;
    const QVariantList standardCurve { 0.2, 0.0, 0.0, 1.0, 1.0, 1.0 };
    const QVariantList emphasizedCurve { 0.05, 0.7, 0.1, 1.0, 1.0, 1.0 };
    const QVariantList expressiveCurve { 0.34, 1.2, 0.64, 1.0, 1.0, 1.0 };
    const QVariantList exitCurve { 0.3, 0.0, 0.8, 0.15, 1.0, 1.0 };
    return {
        { QStringLiteral("instant"), 0 },
        { QStringLiteral("quick"), 120 * scale },
        { QStringLiteral("state"), 160 * scale },
        { QStringLiteral("exit"), 140 * scale },
        { QStringLiteral("enter"), 200 * scale },
        { QStringLiteral("overlay"), 240 * scale },
        { QStringLiteral("page"), 280 * scale },
        { QStringLiteral("signature"), 600 * scale },
        { QStringLiteral("ritual"), 900 * scale },
        { QStringLiteral("toastHold"), 3000 },
        { QStringLiteral("easeStandard"), static_cast<int>(QEasingCurve::OutCubic) },
        { QStringLiteral("easeExit"), static_cast<int>(QEasingCurve::InCubic) },
        { QStringLiteral("bezier"), QVariantMap {
            { QStringLiteral("standard"), standardCurve },
            { QStringLiteral("emphasized"), emphasizedCurve },
            { QStringLiteral("expressive"), expressiveCurve },
            { QStringLiteral("exit"), exitCurve }
        } },
        { QStringLiteral("stagger"), QVariantMap {
            { QStringLiteral("micro"), 28 * scale },
            { QStringLiteral("item"), 55 * scale },
            { QStringLiteral("section"), 120 * scale }
        } },
        { QStringLiteral("distance"), QVariantMap {
            { QStringLiteral("micro"), 4 * scale },
            { QStringLiteral("state"), 10 * scale },
            { QStringLiteral("enter"), 24 * scale },
            { QStringLiteral("overlay"), 32 * scale },
            { QStringLiteral("page"), 60 * scale }
        } },
        { QStringLiteral("scale"), QVariantMap {
            { QStringLiteral("press"), 1.0 - 0.04 * scale },
            { QStringLiteral("hover"), 1.0 + 0.035 * scale },
            { QStringLiteral("enter"), 1.0 - 0.055 * scale },
            { QStringLiteral("overlay"), 1.0 - 0.08 * scale },
            { QStringLiteral("signature"), 1.0 + 0.06 * scale }
        } },
        { QStringLiteral("spring"), QVariantMap {
            { QStringLiteral("control"), QVariantMap { { QStringLiteral("damping"), 22 }, { QStringLiteral("stiffness"), 260 }, { QStringLiteral("mass"), 1 } } },
            { QStringLiteral("celebration"), QVariantMap { { QStringLiteral("damping"), 9 }, { QStringLiteral("stiffness"), 180 }, { QStringLiteral("mass"), 1.1 } } }
        } },
        { QStringLiteral("profiles"), QVariantMap {
            { QStringLiteral("pageEnter"), QVariantMap { { QStringLiteral("duration"), 420 * scale }, { QStringLiteral("distance"), 48 * scale }, { QStringLiteral("scale"), 1.0 - 0.035 * scale } } },
            { QStringLiteral("overlayOpen"), QVariantMap { { QStringLiteral("duration"), 360 * scale }, { QStringLiteral("distance"), 24 * scale }, { QStringLiteral("scale"), 1.0 - 0.1 * scale } } },
            { QStringLiteral("launchRitual"), QVariantMap { { QStringLiteral("duration"), 900 * scale }, { QStringLiteral("distance"), 36 * scale }, { QStringLiteral("scale"), 1.0 + 0.08 * scale } } },
            { QStringLiteral("ambient"), QVariantMap { { QStringLiteral("duration"), m_reducedMotion ? 0 : 18000 }, { QStringLiteral("enabled"), !m_reducedMotion } } }
        } }
    };
}

void AppearanceController::rebuildTokens()
{
    QVariantMap next;
    next.insert(QStringLiteral("color"), colorTokens());
    next.insert(QStringLiteral("control"), controlTokens());
    next.insert(QStringLiteral("motion"), motionTokens());
    next.insert(QStringLiteral("radius"), QVariantMap {
        { QStringLiteral("xs"), 4 }, { QStringLiteral("sm"), 6 }, { QStringLiteral("md"), 10 },
        { QStringLiteral("lg"), 14 }, { QStringLiteral("window"), 18 }, { QStringLiteral("full"), 9999 }
    });
    next.insert(QStringLiteral("space"), QVariantMap {
        { QStringLiteral("xs"), 4 }, { QStringLiteral("sm"), 8 }, { QStringLiteral("md"), 12 },
        { QStringLiteral("lg"), 16 }, { QStringLiteral("xl"), 24 }, { QStringLiteral("xxl"), 32 }
    });
    next.insert(QStringLiteral("type"), QVariantMap {
        { QStringLiteral("family"), QStringLiteral("Segoe UI Variable, Microsoft YaHei UI, Noto Sans SC, sans-serif") },
        { QStringLiteral("monoFamily"), QStringLiteral("JetBrains Mono, Cascadia Mono, Consolas, monospace") },
        { QStringLiteral("brand"), 8 }, { QStringLiteral("caption"), 12 },
        { QStringLiteral("secondary"), 13 }, { QStringLiteral("body"), 14 },
        { QStringLiteral("title"), 16 }, { QStringLiteral("section"), 20 },
        { QStringLiteral("display"), 28 }
    });
    next.insert(QStringLiteral("z"), QVariantMap {
        { QStringLiteral("background"), 0 }, { QStringLiteral("page"), 10 },
        { QStringLiteral("navigation"), 20 }, { QStringLiteral("overlay"), 100 },
        { QStringLiteral("toast"), 110 }, { QStringLiteral("debug"), 120 }
    });
    m_tokens = next;
    ++m_revision;
    emit tokensChanged();
    emit revisionChanged();
}

} // namespace ShadowLauncher
