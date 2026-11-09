// SPDX-License-Identifier: AGPL-3.0-or-later
// 设置行：左标签 96 + 内容区（子元素按顺序塞进来）
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string label: ""
    property string hint: ""
    property int labelWidth: 96
    property bool divider: true
    property bool compact: false
    // 内容比一行高时（多行输入框）用 rowHeight 撑开，否则输入框会溢出到下一行
    property int rowHeight: 0
    default property alias content: slot.data

    implicitHeight: rowHeight > 0 ? rowHeight : (compact ? 44 : 52)

    Text {
        id: lab
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.labelWidth
        text: root.label
        color: "#7b8494"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    Item {
        id: slot
        anchors.left: lab.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
    }

    Text {
        anchors.left: slot.left
        anchors.leftMargin: 2
        anchors.top: slot.top
        anchors.topMargin: 4
        text: root.hint
        visible: root.hint.length > 0
        color: "#3f4753"
        font.family: Theme.fontFamily
        font.pixelSize: 10
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: "#11141d"
        visible: root.divider
    }
}
