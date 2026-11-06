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
    // 资源详情按"全屏独立页"处理：打开时侧栏收起、页面铺满整窗（与版本页/账户页同一套）
    //
    // 但侧栏收起会改变下面列表页的宽度 → 列数 3↔4、卡片尺寸全部重排。
    // 如果收起的同一帧就开始，用户会在详情页还半透明时看到身后整片卡片"跳一下"。
    // 所以详情页的收起延后到页面已经完全不透明之后再执行（那一刻重排在纯不透明页后面，看不见）。
    property bool sideNarrowed: false          // 侧栏是否已真正收起（与页面可见性解耦）
    // fullOpen：页面是否处于"全屏页"状态（拦住底下页面的交互）
    readonly property bool fullOpen: versionsOpen || accountOpen || resDetailOpen
    // sideCollapsed：侧栏是否应该收起。版本页/账户页立刻收；资源详情延后收（见 onResDetailOpenChanged）
    readonly property bool sideCollapsed: versionsOpen || accountOpen || sideNarrowed
    onResDetailOpenChanged: {
        if (resDetailOpen) {
            narrowDelay.restart()
        } else {
            narrowDelay.stop()
            sideNarrowed = false               // 复原立刻执行：此刻详情页仍不透明
        }
    }
    Timer {
        id: narrowDelay
        interval: Theme.durSlow
        onTriggered: root.sideNarrowed = root.resDetailOpen
    }
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
        width: root.sideCollapsed ? 0 : root.sideW
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
                // 版本页/账户页照旧给动画；资源详情只在"延后收起"那一刻给动画（页面已不透明）；还原一律立刻
                duration: (root.sideNarrowed || root.versionsOpen || root.accountOpen) ? Theme.durPage : 0
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

    // ══ 全屏页宿主 ══
    // 菜单级切页一律「硬切」：不做 opacity 淡入淡出，也不做位移。
    // 原因（实测）：只要过渡里有一帧半透明，下层一直亮着的启动页就会透出来，
    // 观感就是"先淡出看到启动页，再淡入目标页"。硬切时新旧页在同一个事件循环里切换，
    // 渲染只输出一帧结果，中间态根本不存在。
    // 每个宿主自带不透明实底，保证任何时刻都不叠字。

    // 版本管理（全窗覆盖）
    Item {
        id: versionsHost
        anchors.fill: parent
        visible: root.versionsOpen
        Rectangle { anchors.fill: parent; color: Theme.bg }
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
        visible: root.accountOpen
        Rectangle { anchors.fill: parent; color: Theme.bg }
        AccountPage {
            anchors.fill: parent
            toast: toastHost
            onClose: root.accountOpen = false
        }
    }

    // 下载页
    Item {
        id: downloadHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.downloadOpen
        Rectangle { anchors.fill: parent; color: Theme.bg }
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

    // 资源详情（全屏独立页，自带实底，拦截穿透）
    Item {
        id: resDetailHost
        anchors.fill: parent
        visible: root.resDetailOpen
        Rectangle { anchors.fill: parent; color: Theme.bg }
        ResourceDetailPage {
            id: resDetail
            anchors.fill: parent
            toast: toastHost
            onBack: root.resDetailOpen = false
        }
    }

    // 下载进度
    Item {
        id: progressHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.progressOpen
        Rectangle { anchors.fill: parent; color: Theme.bg }
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
