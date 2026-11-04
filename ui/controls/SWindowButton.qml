// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string iconName: "x"
    property bool danger: false          // 关闭按钮：hover 变红
    property Window hostWindow: null
    signal clicked()

    width: 32
    height: 32

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: {
            if (!root.danger) return hover.containsMouse ? "#1affffff" : "transparent"
            return hover.containsMouse ? Theme.danger : "transparent"
        }
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }

    SIcon {
        anchors.centerIn: parent
        name: root.iconName
        size: 15
        color: root.danger && hover.containsMouse ? "#ffffff" : Theme.fg2
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}