// SPDX-License-Identifier: AGPL-3.0-or-later
// 启动页 —— 首屏只回答：玩哪个 / 要不要启动
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: page
    property Window hostWindow: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property bool narrow: width < 900
    readonly property string ver: (b && b.selectedVersion) ? b.selectedVersion : ""
    readonly property string userName: b ? (b.isOnline ? (b.username || "") : (b.offlineUsername || "")) : ""
    readonly property bool launching: b ? b.launching : false
    readonly property bool running: b ? b.isRunning : false
    readonly property string statusText: b ? (b.launchStatus || "") : ""

    // "1.20.1-Fabric_0.16.9" → 主 [1.20.1] / 副 [Fabric 0.16.9]
    readonly property var verParts: {
        if (ver.length === 0) return ["", ""]
        var i = ver.indexOf("-")
        if (i < 0) i = ver.indexOf("_")
        if (i <= 0) return [ver, ""]
        return [ver.substring(0, i), ver.substring(i + 1).split("_").join(" ")]
    }

    // ---------- 背景 + 遮罩 ----------
    Image {
        id: bgImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: (page.b && page.b.customBgPath && page.b.customBgPath.length > 0)
                ? ("file:///" + page.b.customBgPath)
                : "qrc:/ui/assets/stage-aurora.jpg"
        // 小窗上移，保住画面主体
        height: parent.height * (page.narrow ? 1.12 : 1.0)
        y: page.narrow ? -parent.height * 0.06 : 0
    }

    Rectangle {   // 底部
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: parent.height * 0.70
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#0005080e" }
            GradientStop { position: 0.30; color: "#2805080e" }
            GradientStop { position: 0.62; color: "#8c05080e" }
            GradientStop { position: 1.00; color: "#f005080e" }
        }
    }
    Rectangle {   // 左侧
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
        width: parent.width * (page.narrow ? 0.72 : 0.62)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.00; color: "#b805080e" }
            GradientStop { position: 0.46; color: "#2e05080e" }
            GradientStop { position: 1.00; color: "#0005080e" }
        }
    }
    Rectangle {   // 顶部
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: parent.height * 0.40
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#a005080e" }
            GradientStop { position: 0.34; color: "#1a05080e" }
            GradientStop { position: 0.80; color: "#0005080e" }
        }
    }

    // ---------- 拖拽（最底层，交互控件在其上） ----------
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        property point pressPos
        onPressed: (m) => { pressPos = Qt.point(m.x, m.y) }
        onPositionChanged: (m) => {
            if (!pressed || !page.hostWindow) return
            page.hostWindow.x += m.x - pressPos.x
            page.hostWindow.y += m.y - pressPos.y
        }
    }

    // ---------- 顶栏 ----------
    Item {
        id: topRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: page.narrow ? 46 : Theme.topH

        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: page.narrow ? 96 : Theme.padR
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            SAcctChip {
                backend: page.b
                name: page.userName
                online: page.b ? page.b.isOnline : false
                onClicked: console.info("[ui] account chip clicked")
            }
        }
    }

    // ---------- 窗口按钮（关闭 hover 变红） ----------
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        spacing: 4
        SWindowButton {
            iconName: "minus"
            onClicked: if (page.hostWindow) page.hostWindow.showMinimized()
        }
        SWindowButton {
            iconName: "x"
            danger: true
            onClicked: if (page.hostWindow) page.hostWindow.close()
        }
    }

    // ---------- 左下：状态 / 标题 / 操作 ----------
    Column {
        id: bodyCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: page.narrow ? 28 : Theme.padL
        anchors.rightMargin: page.narrow ? 24 : 64
        anchors.bottomMargin: page.narrow ? 34 : Theme.padB
        spacing: 0

        Row {
            id: kicker
            spacing: 9
            visible: page.launching || page.running || page.statusText.length > 0
            Rectangle {
                width: 22; height: 1
                color: page.launching ? Theme.accent : Theme.ok
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: page.launching ? (page.statusText.length > 0 ? page.statusText : "正在准备启动")
                      : (page.running ? "游戏运行中" : page.statusText)
                color: Theme.fg2
                font.family: Theme.fontFamily
                font.pixelSize: 11.5
                font.letterSpacing: 1.0
            }
        }

        Item { width: 1; height: kicker.visible ? 15 : 0 }

        Row {
            spacing: page.narrow ? 8 : 14
            Text {
                text: page.verParts[0].length > 0 ? page.verParts[0] : "未选择版本"
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: page.narrow ? 34 : 58
                font.weight: Font.Bold
                font.letterSpacing: page.narrow ? -0.6 : -1.2
            }
            Text {
                visible: page.verParts[1].length > 0
                text: page.verParts[1]
                color: "#9fb4cf"
                font.family: Theme.fontFamily
                font.pixelSize: page.narrow ? 34 : 58
                font.weight: Font.DemiBold
                font.letterSpacing: page.narrow ? -0.6 : -1.2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: page.narrow ? 4 : 8
            }
        }

        Item { width: 1; height: page.narrow ? 20 : 34 }

        Row {
            spacing: 10
            SButton {
                kind: 0
                busy: page.launching
                dimmed: page.running || page.ver.length === 0
                text: page.launching ? "取消启动" : (page.running ? "游戏中" : "启动游戏")
                iconName: page.launching ? "x" : "play"
                onClicked: {
                    if (!page.b) return
                    if (page.launching) { page.b.cancelLaunch(); return }
                    if (page.running) return
                    if (page.ver.length === 0) return
                    page.b.launch(page.ver, page.b.isOnline)
                }
            }
            SButton {
                kind: 1
                text: "版本"
                iconName: "list"
                onClicked: console.info("[ui] version list")
            }
            SButton {
                kind: 1
                text: "设置"
                iconName: "settings"
                onClicked: console.info("[ui] settings")
            }
        }
    }
}