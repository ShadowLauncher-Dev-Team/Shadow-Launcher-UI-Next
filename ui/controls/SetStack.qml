// SPDX-License-Identifier: AGPL-3.0-or-later
// 设置行（纵向）：标题 + 说明在上一行，控件占满下方整行宽度。
// 多行输入框、预览图这类「横向放不下 / 需要宽度」的内容用这个。
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string label: ""
    property string desc: ""
    property bool divider: true
    // bare=true：不画标题/说明（外观页「只剩预览」模式用），只保留控件本身
    property bool bare: false
    default property alias content: slot.data

    // 没有控件时不能再加 10 的间距和 28 的上下留白，否则只有标题+说明的行
    // 会在下方空出一大块（影报的「每个框下方都存在较多空白」）。
    readonly property bool _hasSlot: slot.children.length > 0
    readonly property real _labH: root.bare ? 0 : labBox.implicitHeight
    implicitHeight: _labH + (_hasSlot ? (root.bare ? 0 : 10) + slot.implicitHeight : 0) + (root.bare ? 16 : 28)

    Column {
        id: labBox
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.top: parent.top
        anchors.topMargin: 14
        spacing: 3
        visible: !root.bare

        Text {
            width: parent.width
            text: root.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 14
        }
        Text {
            width: parent.width
            visible: root.desc.length > 0
            text: root.desc
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 12
            lineHeightMode: Text.FixedHeight
            lineHeight: 17
            wrapMode: Text.WordWrap
        }
    }

    Column {
        id: slot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.top: labBox.bottom
        anchors.topMargin: 10
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
