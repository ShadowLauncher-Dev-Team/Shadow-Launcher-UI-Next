// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root
    property Window hostWindow: null

    RowLayout {
        anchors.fill: parent
        spacing: 0

        SideBar {
            Layout.preferredWidth: root.width < 900 ? Theme.sideWNarrow : Theme.sideW
            Layout.fillHeight: true
            narrow: root.width < 900
            hostWindow: root.hostWindow
        }

        StagePage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            hostWindow: root.hostWindow
        }
    }
}