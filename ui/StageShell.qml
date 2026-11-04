// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 外壳：侧栏 + 内容区 + 启动浮层 + 版本管理页
// 版本管理隶属启动页（不是侧栏一级导航）：打开时侧栏整体收起、版本页占满整窗，
// 顶部自带返回。--ui-versions 供截图/调试直接进入该页。
Item {
    id: root
    property Window hostWindow: null
    readonly property bool narrow: width < 900
    readonly property int sideW: (narrow ? Theme.sideWNarrow : Theme.sideW)
    property bool versionsOpen: false

    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--ui-versions") >= 0)
            root.versionsOpen = true
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    SideBar {
        id: sideBar
        visible: !root.versionsOpen
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.versionsOpen ? 0 : root.sideW
        narrow: root.narrow
        hostWindow: root.hostWindow
    }

    StagePage {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.versionsOpen
        hostWindow: root.hostWindow
        narrow: root.narrow
        onOpenVersions: root.versionsOpen = true
    }

    // 启动浮层（页面内，不新开窗口）；启动中压住一切，包括版本页
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
}
