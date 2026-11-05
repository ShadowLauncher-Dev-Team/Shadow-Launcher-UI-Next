// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 资源库网格卡片（A 方案「货架式」）：竖向，40 图标 + 中英名 + 两行简介 + 下载量/日期/来源
Rectangle {
    id: tile

    property string title: ""
    property string zh: ""
    property string description: ""
    property string iconUrl: ""
    property string slug: ""
    property int downloads: 0
    property string source: "Modrinth"
    property string dateModified: ""
    signal clicked()

    property bool hovered: false
    implicitHeight: 150
    radius: Theme.rMd
    color: hovered ? "#0f141b" : "#0b0e13"
    border.width: 1
    border.color: hovered ? "#2b3644" : Theme.line
    Behavior on color { ColorAnimation { duration: Theme.durFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tile.hovered = true
        onExited: tile.hovered = false
        onClicked: tile.clicked()
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Row {
            width: parent.width
            spacing: 10
            Rectangle {
                width: 40; height: 40
                radius: Theme.rSm
                color: "#12161c"
                clip: true
                Image {
                    anchors.fill: parent
                    source: tile.iconUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: tile.iconUrl.length > 0
                }
            }
            Column {
                width: parent.width - 50
                spacing: 2
                Text {
                    width: parent.width
                    text: tile.zh.length > 0 ? tile.zh : tile.title
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: tile.zh.length > 0 ? tile.title : ""
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            width: parent.width
            height: 30
            text: tile.description
            color: Theme.fg2
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            spacing: 8
            Text {
                text: tile.downloads >= 100000000 ? (tile.downloads / 100000000).toFixed(1) + "亿"
                    : tile.downloads >= 10000 ? (tile.downloads / 10000).toFixed(0) + "万" : tile.downloads.toString()
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                text: tile.dateModified.length >= 10 ? tile.dateModified.substring(0, 10) : ""
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Item { width: parent.width - 150; height: 1 }
            Text {
                text: tile.source === "CurseForge" ? "CF" : "MR"
                color: tile.source === "CurseForge" ? Theme.warn : Theme.ok
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }
}
