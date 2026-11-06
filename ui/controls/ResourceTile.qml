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
    // 页面统一推进的高光相位（用于 hover 时扫一道光）
    property real shimmerPhase: 0
    property bool pressed: false
    implicitHeight: 150
    radius: Theme.rMd
    color: hovered ? "#0f141b" : "#0b0e13"
    border.width: 1
    border.color: hovered ? "#33465e" : Theme.line
    clip: true
    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

    // ── 悬停 / 按压 ──
    // 悬停：整卡上浮 2px + 边框提亮（不是只变色），视线先感到"这张卡是活的"
    // 按压：缩到 0.975 再弹回（easePop 过冲），松手的回弹比按下更明显
    transform: Translate {
        y: tile.hovered ? -2 : 0
        Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
    }
    scale: tile.pressed ? 0.975 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easePop } }

    // hover 时一道柔光从左扫到右（复用页面相位，卡片自己不持有动画）
    SShimmer {
        anchors.fill: parent
        phase: tile.shimmerPhase
        active: tile.hovered
        bandWidth: 90
        strength: 0.07
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tile.hovered = true
        onExited: tile.hovered = false
        onPressed: tile.pressed = true
        onReleased: tile.pressed = false
        onCanceled: tile.pressed = false
        onClicked: {
            tile.pressed = false
            ripple.burst(hit.mouseX, hit.mouseY)
            tile.clicked()
        }
    }

    // 点击涟漪：扩散后再离开（过渡到详情页的"起手式"）
    SRipple {
        id: ripple
        anchors.fill: parent
        color: "#8fb6f8"
        maxRadius: 260
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
                color: tile.hovered ? "#161c25" : "#12161c"
                clip: true
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                Image {
                    anchors.fill: parent
                    source: tile.iconUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: tile.iconUrl.length > 0
                    // hover 时图标轻微推近（1.08），卡片"凑过来"的感觉
                    scale: tile.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
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
                    x: tile.hovered ? 2 : 0
                    Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
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
