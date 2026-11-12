// SPDX-License-Identifier: AGPL-3.0-or-later
// 设置分组：小标题 + 卡片容器（行之间由 SetRow 自带分隔线，卡片圆角靠 clip 收干净）
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string title: ""
    property bool danger: false
    default property alias content: body.data

    implicitHeight: head.height + card.height

    Item {
        id: head
        width: parent.width
        // 空标题时不留空隙，否则每个分组顶部都会多出 20 多像素的空白
        height: root.title.length > 0 ? titleText.implicitHeight + 10 : 0

        Text {
            id: titleText
            x: 2
            width: parent.width - 4
            text: root.title
            visible: root.title.length > 0
            color: root.danger ? Theme.dangerText : Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1.1
        }
    }

    Rectangle {
        id: card
        anchors.top: head.bottom
        width: parent.width
        height: body.implicitHeight
        radius: Theme.rMd
        color: Theme.bgCard2
        border.width: 1
        border.color: root.danger ? Theme.bgHover : Theme.line
        clip: true

        Column {
            id: body
            width: parent.width
        }
    }
}
