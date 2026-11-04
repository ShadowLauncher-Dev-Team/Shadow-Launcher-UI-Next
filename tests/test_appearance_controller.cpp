// SPDX-License-Identifier: AGPL-3.0-or-later
#include "ui_next/appearance_controller.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QSettings>
#include <QVariantMap>

using ShadowLauncher::AppearanceController;

namespace {

int failures = 0;

void check(bool condition, const char* message)
{
    if (!condition) {
        qCritical("FAIL: %s", message);
        ++failures;
    }
}

QString token(const AppearanceController& controller, const char* group, const char* key)
{
    return controller.tokens().value(QString::fromLatin1(group)).toMap()
        .value(QString::fromLatin1(key)).toString();
}

} // namespace

int main(int argc, char** argv)
{
    qInfo("test: start");
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("ShadowTeamTests"));
    QCoreApplication::setApplicationName(QStringLiteral("AppearanceControllerTests"));
    qInfo("test: application ready");
    QSettings().clear();

    {
        qInfo("test: constructing controller");
        AppearanceController controller;
        qInfo("test: controller ready");
        check(controller.themeId() == QStringLiteral("midnight-blue"), "default theme is midnight-blue");
        check(controller.availableThemes().size() == 1, "one built-in theme is available");
        check(controller.revision() == 1, "initial token snapshot is published once");

        controller.setMode(QStringLiteral("dark"));
        check(token(controller, "color", "background") == QStringLiteral("#0C0F16"), "dark background token");
        controller.setMode(QStringLiteral("light"));
        check(token(controller, "color", "background") == QStringLiteral("#F8FAFC"), "light background token");
        check(token(controller, "color", "primary") == QStringLiteral("#2563EB"), "light primary token");

        controller.setDensity(QStringLiteral("compact"));
        check(token(controller, "control", "height") == QStringLiteral("32"), "compact control height");
        const QVariantMap profiles = controller.tokens().value(QStringLiteral("motion")).toMap()
            .value(QStringLiteral("profiles")).toMap();
        check(profiles.value(QStringLiteral("pageEnter")).toMap().value(QStringLiteral("duration")).toInt() == 420,
              "complex page choreography is available");
        controller.setReducedMotion(true);
        check(token(controller, "motion", "page") == QStringLiteral("0"), "reduced motion removes page duration");
        const QVariantMap reducedProfiles = controller.tokens().value(QStringLiteral("motion")).toMap()
            .value(QStringLiteral("profiles")).toMap();
        check(reducedProfiles.value(QStringLiteral("pageEnter")).toMap().value(QStringLiteral("duration")).toInt() == 0,
              "reduced motion disables choreography duration");

        const int revision = controller.revision();
        controller.setMode(QStringLiteral("sepia"));
        controller.setDensity(QStringLiteral("tiny"));
        check(controller.revision() == revision, "invalid preferences are ignored without a new snapshot");
    }

    qInfo("test: persistence scope");
    {
        AppearanceController restored;
        check(restored.mode() == QStringLiteral("light"), "mode persists across controller instances");
        check(restored.density() == QStringLiteral("compact"), "density persists across controller instances");
        check(restored.reducedMotion(), "reduced motion persists across controller instances");
        restored.setMode(QStringLiteral("system"));
        check(restored.effectiveMode() == QStringLiteral("light")
                || restored.effectiveMode() == QStringLiteral("dark"),
              "system mode resolves to a concrete mode");
    }

    QSettings().clear();
    if (failures == 0)
        qInfo("AppearanceController tests passed");
    return failures == 0 ? 0 : 1;
}
