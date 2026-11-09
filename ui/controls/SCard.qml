// SPDX-License-Identifier: AGPL-3.0-or-later
// 设置块卡片：一张卡 = 一个功能域。标题 13/600，内容由调用方塞
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string title: ""
    property int cardPaddingBottom: 10
    default property alias content: body.data

    implicitHeight: body.implicitHeight + header.height + cardPaddingBottom

    Rectangle {
        anchors.fill: parent
        radius: Theme.rWin
        color: "#0b0d12"
        border.width: 1
        border.color: Theme.line2
    }

    Text {
        id: header
        x: 20
        topPadding: 15
        bottomPadding: 4
        width: parent.width - 40
        text: root.title
        visible: root.title.length > 0
        color: "#eef2f8"
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Column {
        id: body
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
    }
}
