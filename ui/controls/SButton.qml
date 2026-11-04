// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root

    // kind: 0 = primary(实心) 1 = ghost(描边)
    property int kind: 0
    property string text: ""
    property string iconName: ""
    property bool busy: false
    property bool dimmed: false
    property bool hovered: false
    signal clicked()

    implicitHeight: kind === 0 ? 48 : 34
    implicitWidth: inner.implicitWidth + (kind === 0 ? 68 : 28)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.kind === 0 ? Theme.rMd : Theme.rSm
        color: {
            if (root.kind === 0) {
                if (root.busy) return Theme.danger
                if (root.dimmed) return "#1b2129"
                return Theme.accentBot
            }
            return "transparent"
        }
        border.width: root.kind === 0 ? 0 : 1
        border.color: Theme.line2
        antialiasing: true

        // 主按钮渐亮（覆盖在纯色之上）
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.kind === 0 && !root.busy && !root.dimmed
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.accentTop }
                GradientStop { position: 1.0; color: Theme.accentBot }
            }
        }

        // 毛边高光
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            radius: parent.radius
            visible: root.kind === 0 && !root.busy && !root.dimmed
            color: "#33ffffff"
        }

        // 启动中的进度线（不确定进度 → 流动片段，不假装百分比）
        Rectangle {
            id: prog
            visible: root.busy
            height: 2
            width: parent.width * 0.28
            y: parent.height - 2
            color: "#ffffff"
            opacity: 0.85
            NumberAnimation on x {
                running: root.busy
                from: -prog.width
                to: bg.width
                duration: 1150
                loops: Animation.Infinite
            }
        }

        scale: press.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    RowLayout {
        id: inner
        anchors.centerIn: parent
        spacing: 9
        SIcon {
            visible: root.iconName !== ""
            name: root.iconName
            size: root.kind === 0 ? 18 : 14
            color: root.kind === 0 ? "#ffffff" : Theme.fg2
        }
        Text {
            text: root.text
            color: root.kind === 0 ? "#ffffff" : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: root.kind === 0 ? 15 : 13
            font.weight: root.kind === 0 ? Font.DemiBold : Font.Normal
            font.letterSpacing: root.kind === 0 ? 0.4 : 0
        }
    }

    // ghost 悬停底色（独立于 MouseArea，避免 z 序问题）
    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        visible: root.kind === 1 && root.hovered && !root.dimmed
        color: "#16ffffff"
        border.width: 1
        border.color: "#333a47"
    }

    MouseArea {
        id: press
        anchors.fill: parent
        enabled: !root.dimmed
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onContainsMouseChanged: root.hovered = containsMouse
        onClicked: root.clicked()
    }
}