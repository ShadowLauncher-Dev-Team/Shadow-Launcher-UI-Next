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
    // 圆角可覆盖：启动浮层面板是 radius 2 的直角语言，内部禁止嵌套大圆角
    property int radius: kind === 0 ? Theme.rMd : Theme.rSm
    // ghost 的危险变体（描边红/文字红）：只给"重试/结束进程"这类真实危险动作用
    property bool danger: false
    // 灰态但**仍可点**：用于"未登录，点了去登录"这类引导（dimmed 是不可点，别混用）
    property bool muted: false
    signal clicked()

    implicitHeight: kind === 0 ? 48 : 34
    implicitWidth: inner.implicitWidth + (kind === 0 ? 68 : 28)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: {
            if (root.kind === 0) {
                if (root.busy) return Theme.danger
                if (root.dimmed || root.muted) return "#1b2129"
                return Theme.accentBot
            }
            return "transparent"
        }
        border.width: (root.kind === 0 && root.muted) ? 1 : (root.kind === 0 ? 0 : 1)
        border.color: root.kind === 0 ? "#222b36" : (root.danger ? "#6d2a2a" : Theme.line2)
        antialiasing: true

        // 主按钮渐亮（覆盖在纯色之上）
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.kind === 0 && !root.busy && !root.dimmed && !root.muted
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.accentTop }
                GradientStop { position: 1.0; color: Theme.accentBot }
            }
        }

        scale: press.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }

    RowLayout {
        id: inner
        anchors.centerIn: parent
        spacing: 9
        SIcon {
            visible: root.iconName !== ""
            name: root.iconName
            size: root.kind === 0 ? 18 : 14
            color: root.kind === 0
                   ? (root.muted ? "#8d96a4" : "#ffffff")
                   : (root.danger ? "#ff9a94" : Theme.fg2)
        }
        Text {
            text: root.text
            color: root.kind === 0
                   ? (root.muted ? "#8d96a4" : "#ffffff")
                   : (root.danger ? "#ff9a94" : Theme.fg)
            font.family: Theme.fontFamily
            font.pixelSize: root.kind === 0 ? 15 : 13
            font.weight: root.kind === 0 ? Font.DemiBold : Font.Normal
            font.letterSpacing: root.kind === 0 ? 0.4 : 0
        }
    }

    // ghost 悬停底色：用透明度过渡，不再硬切（独立于 MouseArea，避免 z 序问题）
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.kind === 1 && !root.dimmed
        opacity: root.hovered ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
        }
        color: root.danger ? "#1aef4444" : "#16ffffff"
        border.width: 1
        border.color: root.danger ? "#8a3333" : "#333a47"
    }

    // 主按钮 hover 提亮（4% 白覆盖）：只解释"鼠标在这里"，不改变主色
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.kind === 0 && !root.busy && !root.dimmed && !root.muted
        color: "#0dffffff"
        opacity: root.hovered ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
        }
    }

    MouseArea {
        id: press
        anchors.fill: parent
        // 必须同时看 root.enabled：以前只判断 dimmed，
        // 调用方写 enabled: false 时按钮看着灰、实际照样能点（点了触发空操作，用户以为坏了）。
        enabled: root.enabled && !root.dimmed
        cursorShape: (root.enabled && !root.dimmed) ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: true
        onContainsMouseChanged: root.hovered = containsMouse
        onClicked: root.clicked()
    }
}