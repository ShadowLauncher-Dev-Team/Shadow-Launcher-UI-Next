// SPDX-License-Identifier: AGPL-3.0-or-later
// 设置行（横向）：左标题 + 说明，右侧控件。控件塞进默认 content（一个右对齐的 Row）。
//
// 高度取「标签块」与「控件」两者较高者 + 上下留白，所以放 34 高的输入框和
// 放 40 高的滑块都能自适应，不用逐行写死。
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string label: ""
    property string desc: ""
    property bool divider: true
    property int minHeight: 56
    default property alias content: slot.data

    implicitHeight: Math.max(root.minHeight,
                             Math.max(labBox.implicitHeight, slot.implicitHeight) + 26)

    Column {
        id: labBox
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.right: slot.left
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            width: parent.width
            text: root.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 14
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.desc.length > 0
            text: root.desc
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 12
            // 同 SetNote：比例行高会把余量堆在文字下方导致偏上，用固定行高让字在行内居中
            lineHeightMode: Text.FixedHeight
            lineHeight: 17
            wrapMode: Text.WordWrap
        }
    }

    Row {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.line
        visible: root.divider
    }
}
