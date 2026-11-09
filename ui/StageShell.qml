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
    // 版本设置（从版本页的版本卡片进入；叠在版本页之上，返回时回到版本页）
    property bool settingsOpen: false
    property string settingsVersionId: ""
    property bool accountOpen: false
    // 下载页与版本页/账户页同一套：侧栏宽度收到 0，页面淡入 + 右移 24
    property bool downloadOpen: false
    // 下载进度：独立页面（不再借用 DownloadPage 的 mode=2 视图）
    property bool progressOpen: false
    // 联机：与下载页同一套宿主（侧栏常驻、页面自绘标题），不是全屏页
    property bool multiplayerOpen: false
    // 资源详情页（从资源库卡片打开）
    property bool resDetailOpen: false
    // 资源详情按"全屏独立页"处理：打开时侧栏收起、页面铺满整窗（与版本页/账户页同一套）
    //
    // 但侧栏收起会改变下面列表页的宽度 → 列数 3↔4、卡片尺寸全部重排。
    // 如果收起的同一帧就开始，用户会在详情页还半透明时看到身后整片卡片"跳一下"。
    // 所以详情页的收起延后到页面已经完全不透明之后再执行（那一刻重排在纯不透明页后面，看不见）。
    property bool sideNarrowed: false          // 侧栏是否已真正收起（与页面可见性解耦）
    // fullOpen：页面是否处于"全屏页"状态（拦住底下页面的交互）
    readonly property bool fullOpen: versionsOpen || accountOpen || resDetailOpen || settingsOpen
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

    // ── 模组/资源「文件下载」追踪 ──
    // 后端对 downloadModFile 只发信号（started/progress/finished/failed/cancelled），没有 model；
    // 详情页要就地显示进度、下载进度页也要能看到，所以统一在壳里收成一份表。
    property var fileDl: []
    // 已提示过的下载 id（后端 finished/failed 可能都发，避免重复 toast）
    property var _toasted: ({})
    function _dlIdx(id) {
        for (var i = 0; i < root.fileDl.length; ++i)
            if (root.fileDl[i].id === id) return i
        return -1
    }
    function _dlPatch(id, patch) {
        var arr = root.fileDl.slice()
        var i = root._dlIdx(id)
        var o = i >= 0 ? arr[i]
                       : ({ id: id, name: "", received: 0, total: 0, speed: 0, state: "run", path: "", error: "" })
        for (var k in patch) o[k] = patch[k]
        if (i >= 0) arr[i] = o; else arr.push(o)
        root.fileDl = arr
    }
    // 已结束的下载条目 4s 后从列表里移除：卡片消失，进度页不再挂一条"已完成"
    Timer {
        interval: 500
        repeat: true
        running: root.fileDl.length > 0
        onTriggered: {
            var now = Date.now(), keep = [], changed = false
            for (var i = 0; i < root.fileDl.length; ++i) {
                var d = root.fileDl[i]
                if (d.state !== "run" && d.hideAt > 0 && d.hideAt <= now) { changed = true; continue }
                keep.push(d)
            }
            if (changed) root.fileDl = keep
        }
    }
    Connections {
        target: root.b
        ignoreUnknownSignals: true
        function onModFileDownloadStarted(downloadId, fileName, fileSize, displayName) {
            root._dlPatch(downloadId, { name: displayName || fileName, total: fileSize, state: "run" })
        }
        function onModFileDownloadProgress(downloadId, received, total, speed) {
            root._dlPatch(downloadId, { received: received, total: total, speed: speed })
        }
        function onModFileDownloadFinished(downloadId, success, filePath, displayName) {
            root._dlPatch(downloadId, {
                name: displayName || "", state: success ? "done" : "fail", path: filePath || "",
                speed: 0, received: -1, hideAt: Date.now() + 4000
            })
            // 同一个下载 id 只提示一次：后端在失败路径上会先发 finished(false) 再发 failed，
            // 不去重就会出现两条"下载失败/完成"（用户报的重复弹窗）
            if (root._toasted[downloadId]) return
            var m2 = {}
            for (var k in root._toasted) m2[k] = root._toasted[k]
            m2[downloadId] = true
            root._toasted = m2
            if (success) toastHost.show((displayName || "文件") + " 下载完成", 2600, "success")
            else toastHost.show((displayName || "文件") + " 下载失败", 3200, "error")
        }
        function onModFileDownloadFailed(downloadId, errorDetail, displayName) {
            root._dlPatch(downloadId, { state: "fail", error: errorDetail || "", speed: 0, hideAt: Date.now() + 6000 })
            if (root._toasted[downloadId]) return
            var m3 = {}
            for (var k in root._toasted) m3[k] = root._toasted[k]
            m3[downloadId] = true
            root._toasted = m3
            toastHost.show((displayName || "文件") + " 下载失败：" + (errorDetail || "未知错误"), 3600, "error")
        }
        function onModFileDownloadCancelled(downloadId, displayName) {
            root._dlPatch(downloadId, { state: "fail", error: "已取消", speed: 0, hideAt: Date.now() + 3000 })
        }
    }
    // 顶部加载条：登录这类"不知道还要多久"的等待（后续可接更多长任务）
    // 登录这类不确定等待 + 资源库在途请求，统一走顶部 SLoadingBar
    readonly property bool loading: (b ? b.microsoftLoginBusy : false)
        || (downloadPage ? downloadPage.resourceBusy : false)
        // 只在详情页还开着的时候算它：关掉后残留的请求不该让顶部继续转
        || (root.resDetailOpen && resDetail ? resDetail.loadingVersions : false)
        // 版本设置里的扫盘 / 批量改名也点亮光条（几百个 jar 几秒没反馈会以为死了）
        || (root.settingsOpen && settingsPage.busy)

    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--ui-versions") >= 0) root.versionsOpen = true
        // 版本设置预览：--ui-settings [versionId]（截图/验收用；不给 id 就用当前选中版本）
        var si = Qt.application.arguments.indexOf("--ui-settings")
        if (si >= 0) {
            root.settingsVersionId = (si + 1 < Qt.application.arguments.length
                                      && Qt.application.arguments[si + 1].indexOf("--") !== 0)
                                     ? Qt.application.arguments[si + 1]
                                     : (b ? b.selectedVersion : "")
            root.settingsOpen = true
        }
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
                root.multiplayerOpen = false
            } else if (label === "下载进度") {
                // 侧栏「下载进度」：独立页面，与「下载」互不捆绑
                root.progressOpen = true
                root.downloadOpen = false
                root.multiplayerOpen = false
                sideBar.currentLabel = "下载进度"
            } else if (label === "联机") {
                // 联机页：与下载页同级，侧栏常驻
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = true
            } else if (label === "启动" || label === "统计" || label === "设置") {
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = false
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
    // 启动页宿主：clip + 实底包一层。
    // 之前直接给 StagePage 加 translate：位移不改变 anchors，页面左移后**压到了侧栏右缘上面**
    // （侧栏先声明、启动页后声明 → 启动页在上），于是侧栏右边露出一条极光色的缝。
    // 现在位移只作用在宿主内部，宿主 clip 住，越界部分画不出去。
    Item {
        id: stageHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        Item {
            anchors.fill: parent
            transform: Translate {
                x: (root.downloadOpen || root.progressOpen || root.fullOpen || root.multiplayerOpen) ? -22 : 0
                Behavior on x { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
            }
            // 回主页时也带一点"顶回来"的缩放，和全屏页入场保持同一套语言
            scale: (root.downloadOpen || root.progressOpen || root.fullOpen) ? 0.99 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
            StagePage {
                anchors.fill: parent
                enabled: !root.fullOpen && !root.downloadOpen && !root.progressOpen && !root.multiplayerOpen
                hostWindow: root.hostWindow
                narrow: root.narrow
                toast: toastHost
                onOpenVersions: root.versionsOpen = true
                onOpenAccount: root.accountOpen = true
                // 启动页「设置」= 当前选中版本的版本设置；没选版本就先去选
                onOpenSettings: (vid) => {
                    if (vid && vid.length > 0) {
                        root.settingsVersionId = vid
                        root.settingsOpen = true
                    } else {
                        root.versionsOpen = true
                    }
                }
            }
        }
    }

    // 启动浮层（页面内，不新开窗口）；启动中压住一切
    LaunchOverlay {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    // ══ 全屏页宿主 ══
    // 过渡的做法（两次翻车后的定论）：
    //   · 宿主自身**从不做 opacity 动画**，一出现就是不透明实底 —— 半透明帧是"透出启动页"的唯一根因；
    //   · 动效只做在宿主内部的位移上（内容从右/下方 12~40px 归位），且宿主 clip 住，
    //     位移留下的缝露出的是宿主自己的底色，不是下层页面；
    //   · 关闭方向是硬切（目标页本来就是下层），进入方向才有过渡。

    // 版本管理（全窗覆盖）
    Item {
        id: versionsHost
        anchors.fill: parent
        visible: root.versionsOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 右侧 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            anchors.fill: parent
            x: root.versionsOpen ? 0 : 24
            Behavior on x { NumberAnimation { duration: root.versionsOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            scale: root.versionsOpen ? 1 : 0.988
            Behavior on scale { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
        VersionPage {
            anchors.fill: parent
            toast: toastHost
            onClose: root.versionsOpen = false
            onOpenSettings: (vid) => {
                root.settingsVersionId = vid
                root.settingsOpen = true
            }
        }
        }
    }

    // 版本设置（全窗覆盖；叠在版本页之上，返回回到版本页）
    Item {
        id: settingsHost
        anchors.fill: parent
        visible: root.settingsOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        Item {
            anchors.fill: parent
            x: root.settingsOpen ? 0 : 24
            Behavior on x { NumberAnimation { duration: root.settingsOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            scale: root.settingsOpen ? 1 : 0.988
            Behavior on scale { NumberAnimation { duration: root.settingsOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            VersionSettingsPage {
                id: settingsPage
                anchors.fill: parent
                versionId: root.settingsVersionId
                toast: toastHost
                onClose: root.settingsOpen = false
            }
        }
    }

    // 账户（全窗覆盖）
    Item {
        id: accountHost
        anchors.fill: parent
        visible: root.accountOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 下方 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            anchors.fill: parent
            y: root.accountOpen ? 0 : 40
            Behavior on y { NumberAnimation { duration: root.accountOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            scale: root.accountOpen ? 1 : 0.988
            Behavior on scale { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
        AccountPage {
            anchors.fill: parent
            toast: toastHost
            onClose: root.accountOpen = false
        }
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
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 右侧 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            anchors.fill: parent
            x: root.downloadOpen ? 0 : 24
            Behavior on x { NumberAnimation { duration: root.downloadOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            scale: root.downloadOpen ? 1 : 0.988
            Behavior on scale { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
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
    }

    // 联机页（与下载页同一套：侧栏常驻，页面自绘标题与内容）
    Item {
        id: multiplayerHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.multiplayerOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场只做位移 + 轻微缩放，宿主不透明且 clip 住 —— 不会透出下层启动页
        Item {
            anchors.fill: parent
            x: root.multiplayerOpen ? 0 : 24
            Behavior on x { NumberAnimation { duration: root.multiplayerOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            scale: root.multiplayerOpen ? 1 : 0.988
            Behavior on scale { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
        MultiplayerPage {
            anchors.fill: parent
            toast: toastHost
        }
        }
    }

    // 资源详情（全屏独立页，自带实底，拦截穿透）
    Item {
        id: resDetailHost
        anchors.fill: parent
        visible: root.resDetailOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 下方 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            anchors.fill: parent
            y: root.resDetailOpen ? 0 : 12
            Behavior on y { NumberAnimation { duration: root.resDetailOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            scale: root.resDetailOpen ? 1 : 0.988
            Behavior on scale { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
        ResourceDetailPage {
            id: resDetail
            anchors.fill: parent
            toast: toastHost
            fileDl: root.fileDl
            onDownloadsStarted: {
                // 下载已经在跑，直接把用户送到能看到它的地方
                root.resDetailOpen = false
                root.progressOpen = true
                sideBar.currentLabel = "下载进度"
            }
            onBack: root.resDetailOpen = false
        }
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
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 下方 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            anchors.fill: parent
            y: root.progressOpen ? 0 : 12
            Behavior on y { NumberAnimation { duration: root.progressOpen ? Theme.durPage : 0; easing.type: Theme.easeEnter } }
            scale: root.progressOpen ? 1 : 0.988
            Behavior on scale { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
        ProgressPage {
            id: progressPage
            anchors.fill: parent
            toast: toastHost
            fileDl: root.fileDl
        }
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
