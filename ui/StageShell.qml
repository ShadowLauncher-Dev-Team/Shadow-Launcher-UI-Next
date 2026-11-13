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

    // ── 配色方案：后端是唯一真源，Theme.scheme 只是它的镜像 ──
    // 外观页写 b.colorScheme → 这里同步 Theme.scheme → 全局颜色 binding 立即重算。
    readonly property string colorScheme: (root.b && root.b.colorScheme) ? root.b.colorScheme : "dark"
    onColorSchemeChanged: Theme.scheme = root.colorScheme
    readonly property bool narrow: width < 900
    readonly property int sideW: (narrow ? Theme.sideWNarrow : Theme.sideW)
    property bool versionsOpen: false
    // 版本设置（从版本页的版本卡片进入；叠在版本页之上，返回时回到版本页）
    property bool settingsOpen: false
    // 全局设置（与「版本设置」是两件事：那个按版本，这个改全局默认值）
    property bool prefsOpen: false
    // 进设置前侧栏选中的是哪一项：退出时要还原回去，
    // 否则侧栏一直停在高亮的「设置」上（影报：从设置页出来，左侧仍显示设置页）。
    property string prefsPrevLabel: "启动"
    property string settingsVersionId: ""
    property bool accountOpen: false
    // 下载页与版本页/账户页同一套：侧栏宽度收到 0，页面淡入 + 右移 24
    property bool downloadOpen: false
    // 下载进度：独立页面（不再借用 DownloadPage 的 mode=2 视图）
    property bool progressOpen: false
    // 联机：与下载页同一套宿主（侧栏常驻、页面自绘标题），不是全屏页
    property bool multiplayerOpen: false
    // 帮助文档：官网的 VitePress 站点。启动器不内嵌，直接开系统浏览器 ——
    // 文档、截图、更新节奏跟官网是同一份，也省得打包体积翻倍。
    readonly property string helpDocsUrl: "https://shadowlauncher.cn/docs/"
    // 资源详情页（从资源库卡片打开）
    property bool resDetailOpen: false
    // 资源详情按"全屏独立页"处理：打开时侧栏收起、页面铺满整窗（与版本页/账户页同一套）
    //
    // 但侧栏收起会改变下面列表页的宽度 → 列数 3↔4、卡片尺寸全部重排。
    // 如果收起的同一帧就开始，用户会在详情页还半透明时看到身后整片卡片"跳一下"。
    // 所以详情页的收起延后到页面已经完全不透明之后再执行（那一刻重排在纯不透明页后面，看不见）。
    property bool sideNarrowed: false          // 侧栏是否已真正收起（与页面可见性解耦）
    // fullOpen：页面是否处于"全屏页"状态（拦住底下页面的交互）
    readonly property bool fullOpen: versionsOpen || accountOpen || resDetailOpen || settingsOpen || prefsOpen
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

        // ── 后端统一反馈通道（2026-11-13 补接线）─────────────────
        // ShadowBackend::toastMessage 原来没有任何 QML 监听：更新模块的 16 条提示
        // （已是最新版本 / 检查更新失败 / 发现新版本正在后台下载 / 下载失败…）
        // 以及模组安装、版本后端的提示全部石沉大海 —— 用户点「检查更新」只看到
        // 按钮闪一下「检查中」，看不出结果。这里统一接到 ToastHost。
        function onColorSchemeChanged() { Theme.scheme = (root.b && root.b.colorScheme) ? root.b.colorScheme : "dark" }

        function onToastMessage(message) {
            if (!message || message.length === 0) return
            toastHost.show(message, 3000)
        }

        // 更新下载完成：常驻可点，点了重启并由 SLUpdater 安装
        function onUpdateReadyForRestart(version) {
            var v = (version && version.length > 0) ? version : "新版本"
            toastHost.showAction("更新已就绪：" + v + "，点击立即重启安装", function() {
                if (root.b) root.b.quitForUpdate()
            }, "success")
        }

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
    // 验收钩子：--update-check 延迟一点再点「检查更新」，等界面挂好、ToastHost 就绪
    Timer {
        id: schemeFlipTimer
        interval: 1500
        onTriggered: {
            if (!root.b) return
            var next = (root.b.colorScheme === "light") ? "dark" : "light"
            console.info("[ui] --scheme-flip ->", next)
            root.b.setColorScheme(next)
        }
    }

    Timer {
        id: updateCheckTimer
        interval: 1500
        onTriggered: {
            console.info("[ui] --update-check: 触发检查更新")
            if (root.b) root.b.checkForUpdate()
        }
    }

    // 顶部加载条：登录这类"不知道还要多久"的等待（后续可接更多长任务）
    // 登录这类不确定等待 + 资源库在途请求，统一走顶部 SLoadingBar
    readonly property bool loading: (b ? b.microsoftLoginBusy : false)
        // 同下面两条：只在下载页还开着的时候算它。
        // downloadPage 是常驻对象（不是按需卸载），里面的资源视图扫描不会因为退出而立刻结束，
        // 少了这个条件就会出现「进 Mod 页又马上退出，顶部光条还在一直转」。
        || (root.downloadOpen && downloadPage ? downloadPage.resourceBusy : false)
        // 只在详情页还开着的时候算它：关掉后残留的请求不该让顶部继续转
        || (root.resDetailOpen && resDetail ? resDetail.loadingVersions : false)
        // 版本设置里的扫盘 / 批量改名也点亮光条（几百个 jar 几秒没反馈会以为死了）
        || (root.settingsOpen && settingsPage.busy)
        || (root.prefsOpen && prefsPage.busy)
        // 皮肤上传 / 披风切换都要等服务器，1~3 秒没反馈会以为没点上
        || (root.accountOpen && accountPage ? accountPage.wardrobeBusy : false)

    // --ui-reenter 的驱动：进/退 每 1.2s 交替一次，用于连拍验证"第二次及以后进入是否还有过渡"。
    // 第一次 open 是初始状态（不播 transition），之后每次切换都会走 states/transitions。
    Timer {
        id: reenterTimer
        interval: 1200
        repeat: true
        onTriggered: {
            root.settingsOpen = !root.settingsOpen
            console.info("[ui] reenter toggle ->", root.settingsOpen)
        }
    }

    Component.onCompleted: {
        // 配色方案：后端是唯一真源，启动时先同步一次
        Theme.scheme = root.colorScheme
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
        // --ui-reenter：进 → 退 → 再进，验证"第二次进入是否还有过渡"（截图/验收用）
        if (Qt.application.arguments.indexOf("--ui-reenter") >= 0) {
            root.settingsVersionId = b ? b.selectedVersion : ""
            root.settingsOpen = true
            reenterTimer.start()
        }
        // --ui-prefs [key]：全局设置页（截图/验收用；key 由 SettingsPage 自己解析 --ui-pane）
        if (Qt.application.arguments.indexOf("--ui-prefs") >= 0) {
            root.prefsOpen = true
            sideBar.currentLabel = "设置"
        }
        if (Qt.application.arguments.indexOf("--ui-account") >= 0) root.accountOpen = true
        // --update-check：启动后自动点一次「检查更新」（验收用，与按钮同一路径）
        if (Qt.application.arguments.indexOf("--update-check") >= 0) updateCheckTimer.start()
        // --scheme-flip：1.5s 后切换一次配色（验收用：走与外观页卡片完全相同的
        //   b.setColorScheme 路径，验证切换即时生效、无需重启）
        if (Qt.application.arguments.indexOf("--scheme-flip") >= 0) schemeFlipTimer.start()
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

    // 点空白释放文本焦点的实现已移到 C++ 窗口层（src/main_release.cpp 的 FocusClearFilter）：
    // 这一层在 QML 里做不可靠 —— 版本设置页每个 pane 都是 anchors.fill 的 Flickable，
    // 它会把 press 吃掉，挂在这里的 MouseArea / TapHandler 收不到，等于没装。

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
                root.prefsOpen = false
                root.downloadOpen = true
                root.progressOpen = false
                root.multiplayerOpen = false
            } else if (label === "下载进度") {
                // 侧栏「下载进度」：独立页面，与「下载」互不捆绑
                root.prefsOpen = false
                root.progressOpen = true
                root.downloadOpen = false
                root.multiplayerOpen = false
                sideBar.currentLabel = "下载进度"
            } else if (label === "联机") {
                // 联机页：与下载页同级，侧栏常驻
                root.prefsOpen = false
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = true
            } else if (label === "设置") {
                // 设置 = 全局默认值（独立全屏页）
                // 记住进来之前停在哪一项（点「设置」时 currentLabel 已经被 SideBar 改掉了，
                // 所以趁还没改记录原值）
                root.prefsPrevLabel = sideBar.previousLabel
                console.info("[ui] 进入设置，记住上一项: " + root.prefsPrevLabel)
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = false
                root.prefsOpen = true
            } else if (label === "启动") {
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = false
                root.prefsOpen = false
            } else if (label === "帮助文档") {
                // 帮助文档 = 官网上的 VitePress 站点（shadowlauncher.cn/docs），
                // 不在启动器里另做一份：内容、截图、更新节奏跟官网保持同一份，
                // 也免得打包体积和「文档与官网不一致」的问题。
                // 侧栏这一项是子项（isMain=false），点它不会改高亮，页面也不需要切。
                console.info("[ui] 打开帮助文档: " + root.helpDocsUrl)
                Qt.openUrlExternally(root.helpDocsUrl)
            }
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

    // 窗口拖动已移到各页面 topBar 内部（见 DownloadPage / AccountPage 等的 topBar MouseArea →
    // backend.beginWindowMove()）。
    //
    // 这里原来有一条"拖动带"（2026-11-05）：anchors.left 从侧栏右缘铺到窗口右边、高度 Theme.topH，
    // 但它声明在页面之前 —— 后面的 stageHost / 各全屏页整个盖在它上面，不只是按钮。
    // 结果就是它一次也收不到 press，窗口从来拖不动（owner 2026-11-10 实测报"顶栏拖不动"）。
    // 另外它用 window.x += 手算位移，高 DPI 下会漂移、也拿不到贴边吸附。
    // 两处都已被页面内 topBar 的 backend.beginWindowMove() 取代，故删除。

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
        // 外观页「只剩预览」时，下面这层启动页必须**原样归位**（不位移、不缩放），
        // 否则全屏页的 -22px 位移会在右边留下一条 22px 的纯色黑边（用户实测）。
        readonly property bool previewing: root.prefsOpen && prefsPage.livePreview
        Rectangle {
            anchors.fill: parent
            color: previewing ? "transparent" : Theme.bg
        }
        Item {
            anchors.fill: parent
            // 历史教训（都别再走回去）：
            //   · 位移(-22)/缩放(0.99) 会在页面四周留 1~22px 的缝，缝里露窗口外 → 「一圈白边」；
            //   · 整页 opacity 动画会变成一块只在切回时出现的「阴影」，切出时没有，很突兀。
            // 所以页面本体彻底不做动画，动感全部交给页内组件（StagePage.playEnter）。
            readonly property bool shifted: (root.downloadOpen || root.progressOpen
                                             || root.fullOpen || root.multiplayerOpen)
            // 页面本体**不做任何透明度/几何动画**：
            //   · 几何（位移/缩放）会在边缘留缝，缝里露的是窗口外 → 白边；
            //   · 整页透明度会变成一块突然出现又消失的「阴影」，切出时没有、切回时有，很突兀。
            // 回启动页的动感全部交给页内组件（StagePage.playEnter）。
            opacity: 1.0

            // 全屏页全部关掉的那一刻，让启动页里的组件重放入场
            onShiftedChanged: {
                if (!shifted) stagePage.playEnter()
            }
            StagePage {
                id: stagePage
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
            id: versionsSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.versionsOpen
                PropertyChanges { target: versionsSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: versionsSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: versionsSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
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
            id: settingsSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.settingsOpen
                PropertyChanges { target: settingsSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: settingsSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: settingsSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
            VersionSettingsPage {
                id: settingsPage
                anchors.fill: parent
                versionId: root.settingsVersionId
                toast: toastHost
                onClose: root.settingsOpen = false
            }
        }
    }

    // 全局设置（全窗覆盖；与版本设置页同一套入场）
    Item {
        id: prefsHost
        anchors.fill: parent
        visible: root.prefsOpen
        clip: true
        // 外观页「实时预览」：隐藏工作交给页面自己做（SettingsPage.chromeOpacity + 外观页 solo），
        // 这里保持不透明 —— 整页压透明度会让两层文字叠在一起，读不清也难看。
        // 但**这层宿主底色也必须一起让开**，否则设置页透明后露出来的是这层纯色（实测黑屏）。
        Rectangle {
            anchors.fill: parent
            color: (root.prefsOpen && prefsPage.livePreview) ? "transparent" : Theme.bg
            Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
        }
        Item {
            id: prefsSurface
            anchors.fill: parent
            // 收起态即出厂位置；打开时由 state 归位。
            // 不用「Behavior + duration: open ? durPage : 0」—— 时长与位移同帧求值，
            // 第二次打开会拿上一次的 0 直接瞬移。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.prefsOpen
                PropertyChanges { target: prefsSurface; x: 0; scale: 1 }
            }
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: prefsSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: prefsSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
            SettingsPage {
                id: prefsPage
                anchors.fill: parent
                toast: toastHost
                onClose: {
                    root.prefsOpen = false
                    // 还原侧栏选中项，否则退出后仍高亮「设置」
                    var back = root.prefsPrevLabel
                    sideBar.currentLabel = back
                    // 进设置时把所有页面都关掉了（设置是全屏页，声明顺序上联机/下载宿主在它前面，
                    // 不关就会被压在设置底下继续显示）。所以退出时必须**按还原的侧栏项把页面开回来** ——
                    // 之前只还原了侧栏高亮，于是「联机页进设置再退出」会变成
                    // 侧栏高亮联机、画面却是启动页（影报的正是这个）。
                    root.multiplayerOpen = (back === "联机")
                    root.downloadOpen = (back === "下载")
                    root.progressOpen = (back === "下载进度")
                    console.info("[ui] 退出设置，还原页面: " + back)
                }
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
            id: accountSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            y: 40
            scale: 0.988
            states: State {
                name: "shown"
                when: root.accountOpen
                PropertyChanges { target: accountSurface; y: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: accountSurface; property: "y"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: accountSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
        AccountPage {
            id: accountPage
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
            id: downloadSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.downloadOpen
                PropertyChanges { target: downloadSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: downloadSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: downloadSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
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
            id: multiplayerSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.multiplayerOpen
                PropertyChanges { target: multiplayerSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: multiplayerSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: multiplayerSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
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
            id: resDetailSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            y: 12
            scale: 0.988
            states: State {
                name: "shown"
                when: root.resDetailOpen
                PropertyChanges { target: resDetailSurface; y: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: resDetailSurface; property: "y"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: resDetailSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
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
            id: progressSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            y: 12
            scale: 0.988
            states: State {
                name: "shown"
                when: root.progressOpen
                PropertyChanges { target: progressSurface; y: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: progressSurface; property: "y"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: progressSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
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
