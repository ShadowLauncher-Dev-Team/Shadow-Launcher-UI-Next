// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts

// ResourceTile — 货架式（A 方案）网格卡片
// 与 DownloadCard（横向列表行）并存：网格里用 Tile，窄列表里用 Card。
// 数据字段与后端池子一致：title/zh/desc/downloads/source/versions/loadersList/dateModified
Rectangle {
    id: tile

    property string title: ""
    property string zh: ""
    property string description: ""
    property string iconUrl: ""
    property string slug: ""
    property int downloads: 0
    property string source: "Modrinth"
    property string gameVersions: ""
    property string loaders: ""
    property string dateModified: ""

    signal clicked()

    property bool hovered: false

    implicitHeight: content.implicitHeight + 24
    radius: StyleTokens.radiusLg
    color: hovered ? StyleTokens.accentSubtle : StyleTokens.bgPrimary
    border.width: 1
    border.color: hovered ? StyleTokens.accentHover : StyleTokens.bgInput
    scale: hovered ? 1.008 : 1.0
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tile.hovered = true
        onExited: tile.hovered = false
        onClicked: tile.clicked()
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 8

        // 图标 + 名称
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                radius: StyleTokens.radiusMd
                color: StyleTokens.bgInput
                clip: true
                Image {
                    anchors.fill: parent
                    source: tile.iconUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: tile.iconUrl.length > 0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: tile.zh.length > 0 ? tile.zh : tile.title
                    color: StyleTokens.textPrimary
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: tile.zh.length > 0 ? tile.title : ""
                    visible: text.length > 0
                    color: StyleTokens.textMuted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        // 简介（固定两行高度，网格对齐）
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            text: tile.description
            color: StyleTokens.textSecondary
            font.pixelSize: 11
            lineHeight: 1.35
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
        }

        // 底部元信息
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: tile.downloads >= 100000000 ? (tile.downloads / 100000000).toFixed(1) + "亿"
                     : tile.downloads >= 10000 ? (tile.downloads / 10000).toFixed(0) + "万"
                     : tile.downloads.toString()
                color: StyleTokens.textMuted
                font.pixelSize: 11
            }
            Text {
                text: tile.dateModified.length > 0 ? tile.dateModified.substring(0, 10) : ""
                color: StyleTokens.textMuted
                font.pixelSize: 11
                visible: text.length > 0
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: srcLabel.implicitWidth + 12
                implicitHeight: 18
                radius: 9
                color: tile.source === "CurseForge" ? "#2a2013" : "#12241c"
                Text {
                    id: srcLabel
                    anchors.centerIn: parent
                    text: tile.source === "CurseForge" ? "CurseForge" : "Modrinth"
                    color: tile.source === "CurseForge" ? "#e0a458" : "#5ec98a"
                    font.pixelSize: 10
                }
            }
        }
    }
}
