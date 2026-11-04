// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 外壳：侧栏 + 内容区 + 启动浮层 + 版本页 + 账户页 + 全局窗口按钮
// 版本/账户都是"隶属启动页的全屏页"：打开时侧栏整体收起、页面 anchors.fill 全窗。
//
// 动效（2026-11-04）：
//   · 全屏页进出 = 侧栏宽度收到 0（durPage）+ 页面淡入并从右侧 24px 滑入；返回反向
//   · 位移放在容器的 transform 上，不动页面自身的 anchors，避免和组件内部布局打架
//   · 关闭时 visible 要等透明度真正降下去才置 false，否则会硬切
Item {
    id: root
    property Window hostWindow: null
    readonly property bool narrow: width < 900
    readonly property int sideW: (narrow ? Theme.sideWNarrow : Theme.sideW)
    property bool versionsOpen: false
    property bool accountOpen: false
    readonly property bool fullOpen: versionsOpen || accountOpen

    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--ui-versions") >= 0) root.versionsOpen = true
        if (Qt.application.arguments.indexOf("--ui-account") >= 0) root.accountOpen = true
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    // 侧栏：宽度动画收放，内容裁掉不溢出
    SideBar {
        id: sideBar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.fullOpen ? 0 : root.sideW
        narrow: root.narrow
        hostWindow: root.hostWindow
        // 快起：前 40% 时间就收掉大部分宽度，与页面淡入同帧开始，视觉上是一次动作
        Behavior on width {
            NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter }
        }
    }

    // 启动页：始终在原地（被全屏页盖住），只关掉交互
    StagePage {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        enabled: !root.fullOpen
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

    // 版本管理（全窗覆盖）
    Item {
        id: versionsHost
        anchors.fill: parent
        visible: root.versionsOpen || opacity > 0.01
        opacity: root.versionsOpen ? 1 : 0
        // 透明度比位移先完成：用户先"看到内容"，再感受滑动，
        // 避免出现"侧栏收走了、页面还是空的"这种先后感
        Behavior on opacity {
            NumberAnimation { duration: Theme.durBase; easing.type: root.versionsOpen ? Theme.easeEnter : Theme.easeExit }
        }
        transform: Translate {
            x: root.versionsOpen ? 0 : 16
            Behavior on x {
                NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter }
            }
        }
        VersionPage {
            anchors.fill: parent
            onClose: root.versionsOpen = false
        }
    }

    // 账户（全窗覆盖）
    Item {
        id: accountHost
        anchors.fill: parent
        visible: root.accountOpen || opacity > 0.01
        opacity: root.accountOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durBase; easing.type: root.accountOpen ? Theme.easeEnter : Theme.easeExit }
        }
        // 账户页从下方浮起（与版本页的横移区分开，减少"每次都一样"的疲劳）
        transform: Translate {
            y: root.accountOpen ? 0 : 20
            Behavior on y {
                NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter }
            }
        }
        AccountPage {
            anchors.fill: parent
            onClose: root.accountOpen = false
        }
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
