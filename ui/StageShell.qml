// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property Window hostWindow: null
    readonly property bool narrow: width < 900
    readonly property int sideW: narrow ? Theme.sideWNarrow : Theme.sideW

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    SideBar {
        id: sideBar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.sideW
        narrow: root.narrow
        hostWindow: root.hostWindow
    }

    StagePage {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        hostWindow: root.hostWindow
        narrow: root.narrow
    }

    // 启动浮层（页面内，不新开窗口）
    LaunchOverlay {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}