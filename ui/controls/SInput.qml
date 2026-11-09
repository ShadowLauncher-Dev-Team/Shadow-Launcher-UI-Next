// SPDX-License-Identifier: AGPL-3.0-or-later
// 普通单行输入：34 高、底 #0d1016、聚焦蓝边。不是搜索框（搜索用 SField）
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string text: ""
    property string placeholder: ""
    property alias input: edit
    signal edited(string value)

    implicitHeight: 34
    implicitWidth: 220

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: "#0d1016"
        border.width: 1
        border.color: edit.activeFocus ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        text: root.placeholder
        visible: edit.text.length === 0
        color: "#3f4753"
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
    TextInput {
        id: edit
        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: "#cfd6e1"
        selectionColor: Theme.accent
        selectedTextColor: "#ffffff"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        clip: true
        selectByMouse: true
        onTextChanged: if (root.text !== text) { root.text = text; root.edited(text) }
    }
}
