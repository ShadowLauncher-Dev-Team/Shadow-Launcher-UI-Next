// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置（全屏页）—— 顶栏 + 左栏九项 + 内容区
//
// 承载：StageShell 的全屏页宿主（与版本页/账户页同一套：侧栏收起、页面右滑入、返回回版本列表）
// 动效：左栏选中胶囊继承主菜单 SideBar（单个 Item 的 y 用 durSlow+easeEnter 滑到新位置）；
//       内容区分区切换用 durBase 淡入+上移 6px，与壳的整页切换（durPage）分层，不互相干扰
import QtQuick
import ShadowLauncher.Next

Item {
    id: page
    property string versionId: ""
    property var toast: null
    // 分区页在扫盘/批量改名时把顶部光条点亮（StageShell 读这个）
    property bool busy: false
    signal close()

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property string currentKey: "quick"

    // 左栏行：t = "g" 分组小字 / "i" 分区项
    readonly property var rows: [
        { t: "i", k: "quick",    label: "快捷入口",   icon: "zap" },
        { t: "i", k: "overview", label: "概览",       icon: "info" },
        { t: "g", label: "启动" },
        { t: "i", k: "launch",   label: "启动配置",   icon: "sliders-horizontal" },
        { t: "i", k: "memory",   label: "内存设置",   icon: "cpu" },
        { t: "g", label: "内容" },
        { t: "i", k: "mods",     label: "Mod 管理",   icon: "puzzle" },
        { t: "i", k: "packs",    label: "资源包",     icon: "package" },
        { t: "i", k: "saves",    label: "存档",       icon: "box" },
        { t: "g", label: "维护" },
        { t: "i", k: "tools",    label: "工具与维护", icon: "wrench" },
        { t: "i", k: "export",   label: "导出整合包", icon: "package-plus" }
    ]

    function paneFor(k) {
        if (k === "quick") return quickComp
        if (k === "overview") return overviewComp
        if (k === "launch") return launchComp
        if (k === "memory") return memoryComp
        if (k === "tools") return toolsComp
        if (k === "mods") return modsComp
        if (k === "packs") return packsComp
        if (k === "saves") return savesComp
        if (k === "export") return exportComp
        return placeholderComp
    }
    function paneTitle(k) {
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].t === "i" && rows[i].k === k) return rows[i].label
        return ""
    }

    // 左栏选中胶囊的目标位置：分组 34 / 分区项 40，位置纯计算（不用 mapToItem，避免 Loader 未完成时算错）
    readonly property int navGroupH: 34
    readonly property int navItemH: 40
    function navY(k) {
        var y = 0
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].t === "i" && rows[i].k === k) return y
            y += (rows[i].t === "g" ? navGroupH : navItemH)
        }
        return -1
    }

    // --ui-pane <key> 直接落在某个分区（截图/验收用）
    Component.onCompleted: {
        var args = Qt.application.arguments
        var i = args.indexOf("--ui-pane")
        if (i >= 0 && i + 1 < args.length && args[i + 1].indexOf("--") !== 0)
            page.currentKey = args[i + 1]
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---------- 顶栏 ----------
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 56

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }

        SButton {
            id: backBtn
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: "返回"
            onClicked: page.close()
        }

        Row {
            anchors.left: backBtn.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                text: "版本设置"
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.versionId
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }

    // ---------- 左栏 ----------
    Rectangle {
        id: nav
        anchors.left: parent.left
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        width: Theme.sideW
        color: Theme.sidebar

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.line
        }

        Flickable {
            id: navFlick
            anchors.fill: parent
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            clip: true
            contentHeight: navHost.height
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: navHost
                width: navFlick.width
                height: navCol.implicitHeight

                // 选中胶囊：继承主菜单 SideBar 的做法 —— 一整块从旧位置滑到新位置，
                // 而不是"旧的竖条缩回去、新的竖条长出来"两段互不相关的动作。
                Item {
                    id: selPill
                    z: 0
                    x: 10
                    width: Math.max(0, navHost.width - 20)
                    visible: page.navY(page.currentKey) >= 0
                    y: Math.max(0, page.navY(page.currentKey)) + 2
                    height: page.navItemH - 4

                    Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: "#151a23"
                    }
                    // 左侧强调条跟着胶囊一起走
                    Rectangle {
                        width: 2
                        radius: 1
                        anchors.left: parent.left
                        anchors.leftMargin: -8
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height * 0.55
                        color: Theme.accent
                    }
                }

                Column {
                    id: navCol
                    z: 1
                    width: parent.width

                    Repeater {
                        model: page.rows
                        delegate: Loader {
                            width: navCol.width
                            sourceComponent: modelData.t === "g" ? groupComp : itemComp
                            property var rowData: modelData
                        }
                    }
                }
            }
        }
    }

    Component {
        id: groupComp
        Item {
            width: navCol.width
            height: 34
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                text: rowData.label
                color: "#6b7686"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1.1
            }
        }
    }

    Component {
        id: itemComp
        Item {
            id: itemRoot
            width: navCol.width
            height: 40
            readonly property bool active: page.currentKey === rowData.k

            // 选中高亮由外层 selPill 承担（滑动的那一块）。这里只做 hover，
            // 否则会出现"胶囊在滑、行背景自己也在亮灭"的两套高亮打架。
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                radius: Theme.rSm
                color: "#0f131a"
                opacity: (hover.hovered && !itemRoot.active) ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                SIcon {
                    name: rowData.icon
                    size: 15
                    color: itemRoot.active ? "#7fa9f5" : "#4d5666"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowData.label
                    color: itemRoot.active ? "#ffffff" : Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                    }
                }
            }

            HoverHandler { id: hover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: page.currentKey = rowData.k
            }
        }
    }

    // ---------- 内容区 ----------
    Item {
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom

        Loader {
            id: paneLoader
            anchors.fill: parent
            sourceComponent: page.paneFor(page.currentKey)
            // 分区页自报 busy（扫盘/批量改名），转给壳的顶部光条
            onLoaded: {
                var it = paneLoader.item
                if (it && it.busyChanged !== undefined) {
                    it.busyChanged.connect(function(b) { page.busy = b })
                    page.busy = (it.loading === true)
                } else {
                    page.busy = false
                }
            }
            onSourceComponentChanged: {
                page.busy = false
                if (paneIn) paneIn.restart()
            }

            // 分区切换：新页淡入 + 上移 6px。
            // 只做入场不做交叉淡出——旧页在同一帧被替换掉，底色一致不会闪；
            // 壳的整页切换用 durPage(320)，这里 durBase(180)，两级动效层次分明不抢戏。
            transform: Translate { id: paneSlide; y: 0 }

            ParallelAnimation {
                id: paneIn
                NumberAnimation {
                    target: paneLoader; property: "opacity"
                    from: 0; to: 1
                    duration: Theme.durBase
                    easing.type: Theme.easeEnter
                }
                NumberAnimation {
                    target: paneSlide; property: "y"
                    from: 6; to: 0
                    duration: Theme.durBase
                    easing.type: Theme.easeEnter
                }
            }
        }
    }

    Component {
        id: quickComp
        VsQuickPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: overviewComp
        VsOverviewPane {
            versionId: page.versionId
            toast: page.toast
            onRequestPane: (k) => page.currentKey = k
        }
    }
    Component {
        id: launchComp
        VsLaunchPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: memoryComp
        VsMemoryPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: toolsComp
        VsToolsPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: modsComp
        VsModsPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: packsComp
        VsPacksPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: savesComp
        VsSavesPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: exportComp
        VsExportPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: placeholderComp
        VsPlaceholderPane {
            versionId: page.versionId
            title: page.paneTitle(page.currentKey)
        }
    }
}
