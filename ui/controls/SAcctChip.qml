// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root
    property var backend: null
    property string name: ""
    property bool online: false
    signal clicked()

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 24

    Rectangle {
        anchors.fill: parent
        radius: 99
        color: hover.containsMouse ? "#1dffffff" : "#0effffff"
        border.width: 1
        border.color: "#12ffffff"
        Behavior on color { ColorAnimation { duration: 110 } }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Rectangle {
            width: 22; height: 22; radius: 99
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2b3444" }
                GradientStop { position: 1.0; color: "#1a212c" }
            }
            Text {
                anchors.centerIn: parent
                text: root.name.length > 0 ? root.name.substring(0, 1).toUpperCase() : "?"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }
        }
        Text {
            text: root.name.length > 0 ? root.name : "未登录"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 12.5
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}