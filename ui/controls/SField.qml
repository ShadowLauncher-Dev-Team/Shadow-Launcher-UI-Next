// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 搜索框（浮动标签）：空态标签落在框内当占位，聚焦或有内容时缩小上浮、压住边框。
// 全站搜索统一用它，避免每个页面各写一套 TextInput + 叠一层 placeholder Text。
Item {
    id: root

    property string label: "搜索"
    property alias text: input.text
    property alias input: input
    property bool busy: false
    signal edited(string value)
    signal accepted()

    implicitHeight: 36
    implicitWidth: 240

    readonly property bool active: input.activeFocus || input.text.length > 0

    // 外部点击（页面空白、切 tab、点卡片）时主动收起焦点：
    // 否则输入框会一直保持"聚焦态"，蓝边和聚焦下划线永远不消失（用户报的"一直显蓝"）。
    function blur() { input.focus = false }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.rSm
        color: "#0d1016"
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

    }

    SIcon {
        id: icon
        x: 11
        anchors.verticalCenter: parent.verticalCenter
        name: "search"; size: 13; color: input.activeFocus ? Theme.fg2 : Theme.fg3
    }

    TextInput {
        id: input
        anchors.left: icon.right; anchors.leftMargin: 9
        anchors.right: parent.right; anchors.rightMargin: 10
        // 同 SInput：撑满框高，否则只有文字那一行算文本区（光标不变 I 形、边缘点不中）
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: "#ffffff"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        clip: true
        selectByMouse: true
        onTextChanged: root.edited(text)
        Keys.onReturnPressed: root.accepted()
        Keys.onEscapePressed: { text = ""; root.edited("") }
    }

    // 浮动标签：空态在框内，激活后上浮到边框上
    Item {
        id: labelBox
        x: root.active ? 26 : icon.x + icon.width + 9
        y: root.active ? -7 : (parent.height - labelText.height) / 2
        width: labelText.implicitWidth + 8
        height: labelText.height
        Behavior on y { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
        Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

        Rectangle {
            anchors.fill: parent
            visible: root.active
            color: Theme.bg
        }
        Text {
            id: labelText
            anchors.centerIn: parent
            text: root.label
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: root.active ? 10 : 12
        }
    }

    // 清空：有内容且不是 busy 时出现
    Item {
        id: clearBtn
        width: 16; height: 16
        anchors.right: parent.right; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: opacity > 0.01
        opacity: input.text.length > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
        scale: input.text.length > 0 ? 1.0 : 0.8
        Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easePop } }
        SIcon { anchors.centerIn: parent; name: "x"; size: 11; color: clearHover.containsMouse ? Theme.fg2 : Theme.fg3 }
        MouseArea {
            id: clearHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { input.text = ""; root.edited("") }
        }
    }
}
