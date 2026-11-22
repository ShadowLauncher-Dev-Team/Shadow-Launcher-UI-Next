// SPDX-License-Identifier: AGPL-3.0-or-later
// 普通单行输入：34 高、底 bgCard2、聚焦蓝边。不是搜索框（搜索用 SField）
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
        color: Theme.bgCard2
        border.width: 1
        border.color: edit.activeFocus ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }
    SPlaceholder {
        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        target: edit
        label: root.placeholder
        color: Theme.line3
        font.pixelSize: 12
    }
    TextInput {
        id: edit
        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.right: parent.right
        anchors.rightMargin: 10
        // 撑满整个框高（不能只 verticalCenter）：否则 TextInput 只有文字那一行的高度，
        // 鼠标停在框的上下留白处时根本不在文本区上 —— 光标不变 I 形、点击也点不中。
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        text: root.text
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentFg
        font.family: Theme.fontFamily
        font.pixelSize: 12
        clip: true
        selectByMouse: true
        onTextChanged: if (root.text !== text) { root.text = text; root.edited(text) }
    }
}