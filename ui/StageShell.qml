// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 外壳：侧栏 + 内容区 + 启动浮层 + 版本页 + 账户页 + 全局窗口按钮
// 版本/账户都是"隶属启动页的全屏页"：打开时侧栏整体收起、页面 anchors.fill 全窗，
// 顶部各自带返回。--ui-versions / --ui-account 供截图与调试直接进入。
Item {
    id: root
    property Window hostWindow: null
    readonly property bool narrow: width < 900
    readonly property int sideW: (narrow ? Theme.sideWNarrow : Theme.sideW)
    property bool versionsOpen: false
    property bool accountOpen: false

    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--ui-versions") >= 0) root.versionsOpen = true
        if (Qt.application.arguments.indexOf("--ui-account") >= 0) root.accountOpen = true
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    SideBar {
        id: sideBar
        visible: !root.versionsOpen && !root.accountOpen
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: (root.versionsOpen || root.accountOpen) ? 0 : root.sideW
        narrow: root.narrow
        hostWindow: root.hostWindow
    }

    StagePage {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.versionsOpen && !root.accountOpen
        hostWindow: root.hostWindow
        narrow: root.narrow
        onOpenVersions: root.versionsOpen = true
        onOpenAccount: root.accountOpen = true
    }

    // 启动浮层（页面内，不新开窗口）；启动中压住一切
    LaunchOverlay {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    // 版本管理（全窗覆盖，侧栏已收起）
    VersionPage {
        anchors.fill: parent
        visible: root.versionsOpen
        onClose: root.versionsOpen = false
    }

    // 账户（全窗覆盖，侧栏已收起）
    AccountPage {
        anchors.fill: parent
        visible: root.accountOpen
        onClose: root.accountOpen = false
    }

    // 窗口按钮：所有页面共用（否则进全屏页就丢最小化/关闭）
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        spacing: 4
        z: 900
        SWindowButton {
            iconName: "minus"
            onClicked: if (root.hostWindow) root.hostWindow.showMinimized()
        }
        SWindowButton {
            iconName: "x"
            danger: true
            onClicked: if (root.hostWindow) root.hostWindow.close()
        }
    }
}
