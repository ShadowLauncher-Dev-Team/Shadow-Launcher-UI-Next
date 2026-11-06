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

        // 底部三列：左=下载量，中=更新日期，右=来源（全称，不再缩写）。
        // 用锚点而不是 Row + 硬编码宽度：之前 Item{width: parent.width-150} 让三列各自偏移，
        // 卡片宽度一变就错位。
        Item {
            width: parent.width
            height: 13

            Text {
                id: dlText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: tile.downloads >= 100000000 ? (tile.downloads / 100000000).toFixed(1) + "亿"
                    : tile.downloads >= 10000 ? (tile.downloads / 10000).toFixed(0) + "万" : tile.downloads.toString()
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: tile.dateModified.length >= 10 ? tile.dateModified.substring(0, 10) : ""
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: tile.source === "CurseForge" ? "CurseForge" : "Modrinth"
                color: tile.source === "CurseForge" ? Theme.warn : Theme.ok
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
    }
}
