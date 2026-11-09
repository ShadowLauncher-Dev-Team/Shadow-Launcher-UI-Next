// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置（全屏页）—— 顶栏 + 左栏九项 + 内容区
//
// 承载：StageShell 的全屏页宿主（与版本页/账户页同一套：侧栏收起、页面右滑入、返回回版本列表）
// 动效：左栏选中条用 Theme.durFast；页面切换由壳负责，这里不做淡化
import QtQuick
import ShadowLauncher.Next

Item {
    id: page
    property string versionId: ""
    property var toast: null
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
        return placeholderComp
    }
    function paneTitle(k) {
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].t === "i" && rows[i].k === k) return rows[i].label
        return ""
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
            anchors.fill: parent
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            clip: true
            contentHeight: navCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: navCol
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
                color: "#3f4753"
                font.family: Theme.fontFamily
                font.pixelSize: 10
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

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: 22
                radius: 2
                color: Theme.accent
                opacity: itemRoot.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
            }

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                radius: 6
                color: "#0f131a"
                opacity: (hover.hovered || itemRoot.active) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
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
            anchors.fill: parent
            sourceComponent: page.paneFor(page.currentKey)

            NumberAnimation on opacity {
                // 分区切换只做极轻的淡入，避免和壳的整页动效打架
                from: 0; to: 1; duration: Theme.durFast
                running: false
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
        id: placeholderComp
        VsPlaceholderPane {
            versionId: page.versionId
            title: page.paneTitle(page.currentKey)
        }
    }
}
