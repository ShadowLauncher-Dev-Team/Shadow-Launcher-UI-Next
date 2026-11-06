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
    // 下载页与版本页/账户页同一套：侧栏宽度收到 0，页面淡入 + 右移 24
    property bool downloadOpen: false
    // 下载进度：独立页面（不再借用 DownloadPage 的 mode=2 视图）
    property bool progressOpen: false
    // 资源详情页（从资源库卡片打开）
    property bool resDetailOpen: false
    // 资源详情也按"全屏独立页"处理：打开时侧栏收起、页面铺满整窗（与版本页/账户页同一套）
    readonly property bool fullOpen: versionsOpen || accountOpen || resDetailOpen
    readonly property var b: (typeof backend !== "undefined") ? backend : null
    // 顶部加载条：登录这类"不知道还要多久"的等待（后续可接更多长任务）
    // 登录这类不确定等待 + 资源库在途请求，统一走顶部 SLoadingBar
    readonly property bool loading: (b ? b.microsoftLoginBusy : false)
        || (downloadPage ? downloadPage.resourceBusy : false)
        || (resDetail ? resDetail.loadingVersions : false)

    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--ui-versions") >= 0) root.versionsOpen = true
        if (Qt.application.arguments.indexOf("--ui-account") >= 0) root.accountOpen = true
        if (Qt.application.arguments.indexOf("--ui-download") >= 0) {
            root.downloadOpen = true
            root.progressOpen = false
            sideBar.currentLabel = "下载"
        }
        if (Qt.application.arguments.indexOf("--ui-progress") >= 0) {
            root.progressOpen = true
            root.downloadOpen = false
            sideBar.currentLabel = "下载进度"
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    // 顶部加载条（Material / Google 线性风格）：压在窗口最上沿
    SLoadingBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        z: 1000
        running: root.loading
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
        // 点击侧栏"下载"进下载页；点其它主项离开（侧栏常驻，页面内不需要返回键）
        onNavActivated: (label) => {
            if (label === "下载") {
                // 侧栏「下载」= 下载列表页：从配置态或独立进度页回来都先回到列表
                downloadPage.resetToList()
                root.downloadOpen = true
                root.progressOpen = false
            } else if (label === "下载进度") {
                // 侧栏「下载进度」：独立页面，与「下载」互不捆绑
                root.progressOpen = true
                root.downloadOpen = false
                sideBar.currentLabel = "下载进度"
            } else if (label === "启动" || label === "联机" || label === "统计" || label === "设置") {
                root.downloadOpen = false
                root.progressOpen = false
            }
            // 其余子项（帮助文档 / 实用网站）暂未实现：保持当前页面不动
        }
        // 快起：前 40% 时间就收掉大部分宽度，与页面淡入同帧开始，视觉上是一次动作。
        // 复原（关闭全屏页）时 duration 归 0：那一刻全屏页还完全不透明，宽度跳变看不见；
        // 若也给 320ms，下面的列表要在整段动画里连续重排，最后半段露出来时就是一顿。
        Behavior on width {
            NumberAnimation {
                duration: root.fullOpen ? Theme.durPage : 0
                easing.type: Theme.easeEnter
            }
        }
    }

    // 拖动带（2026-11-05）：只有窗口上部一条可以拖。
    // 放在 SideBar 之后、页面之前：页面里的按钮/输入框都在这层之上，
    // 点到它们不会误触拖动；顶部空白处才拖动窗口。
    // 放在外壳层而不是启动页，是为了让版本页/账户页这些全屏页也能拖。
    MouseArea {
        id: dragBand
        anchors.left: sideBar.right
        anchors.right: parent.right
        anchors.top: parent.top
        height: Theme.topH
        acceptedButtons: Qt.LeftButton
        property point pressPos
        onPressed: (m) => { pressPos = Qt.point(m.x, m.y) }
        onPositionChanged: (m) => {
            if (!pressed || !root.hostWindow) return
            root.hostWindow.x += m.x - pressPos.x
            root.hostWindow.y += m.y - pressPos.y
        }
    }

    // 启动页：始终在原地（被全屏页盖住），只关掉交互
    StagePage {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        enabled: !root.fullOpen && !root.downloadOpen && !root.progressOpen
        hostWindow: root.hostWindow
        narrow: root.narrow
        toast: toastHost
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
            toast: toastHost
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
        // 账户页从下方浮起（与版本页的横移区分开）。
        // 20px 在 320ms 里几乎看不出方向，实测被当成"没生效"，所以给到 48px。
        transform: Translate {
            y: root.accountOpen ? 0 : 48
            Behavior on y {
                NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter }
            }
        }
        AccountPage {
            anchors.fill: parent
            toast: toastHost
            onClose: root.accountOpen = false
        }
    }

    // 下载页（全窗，与版本页同构：淡入 + 右移 24px）
    Item {
        id: downloadHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.downloadOpen || opacity > 0.01
        opacity: root.downloadOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durBase; easing.type: root.downloadOpen ? Theme.easeEnter : Theme.easeExit }
        }
        transform: Translate {
            y: root.downloadOpen ? 0 : 8
            Behavior on y {
                NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter }
            }
        }
        DownloadPage {
            id: downloadPage
            anchors.fill: parent
            toast: toastHost
            onClose: root.downloadOpen = false
            // 配置页点了「开始安装」：切到独立进度页，侧栏高亮跟随
            onOpenProgress: {
                root.progressOpen = true
                root.downloadOpen = false
                sideBar.currentLabel = "下载进度"
            }
            onOpenResourceDetail: (kind, item) => {
                resDetail.kind = kind
                resDetail.item = item
                root.resDetailOpen = true
            }
        }
    }

    // 资源详情（全屏独立页：铺满整窗、不透明、拦截穿透；与版本页同构淡入）
    Item {
        id: resDetailHost
        anchors.fill: parent
        visible: root.resDetailOpen || opacity > 0.01
        opacity: root.resDetailOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durBase; easing.type: root.resDetailOpen ? Theme.easeEnter : Theme.easeExit }
        }
        transform: Translate {
            y: root.resDetailOpen ? 0 : 8
            Behavior on y {
                NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter }
            }
        }
        // 不透明底：全屏页下面就是资源库列表，不铺底会叠字
        Rectangle {
            anchors.fill: parent
            color: Theme.bg
        }
        ResourceDetailPage {
            id: resDetail
            anchors.fill: parent
            toast: toastHost
            onBack: root.resDetailOpen = false
        }
    }

    // 下载进度（独立页，与下载页同构：淡入 + 轻微上移）
    Item {
        id: progressHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.progressOpen || opacity > 0.01
        opacity: root.progressOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durBase; easing.type: root.progressOpen ? Theme.easeEnter : Theme.easeExit }
        }
        transform: Translate {
            y: root.progressOpen ? 0 : 8
            Behavior on y {
                NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter }
            }
        }
        ProgressPage {
            id: progressPage
            anchors.fill: parent
            toast: toastHost
        }
    }

    // Toast：右下角通知栈。全窗挂一份，页面通过 toast 属性调用；
    // 不再往顶栏塞一行绿色文字（会挤动右侧按钮，且离开该页就看不到）。
    ToastHost {
        id: toastHost
        anchors.fill: parent
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
