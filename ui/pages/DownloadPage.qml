// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import ShadowLauncher.Next

// 下载页（2026-11-05 重做版）
// 结构严格对齐旧 UI：
//   · 顶部横向 tab pills（不是侧边导航）
//   · 带计数的筛选 pills + 最新正式版高亮卡 + 版本卡列表
//   · 点卡 → 安装配置：返回栏 + MC 版本卡（名称输入/冲突提示）+ 每个加载器一张可展开卡 + 底部固定操作栏
//   · 进度视图已拆到独立页 ui/pages/ProgressPage.qml（2026-11-05），本页只负责列表与配置
// 边距照 DESIGN_SPEC：1375 下左右 64；顶栏 52；小窗 28/24
Item {
    id: page
    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null
    // 窗口宽度而非自身宽度：侧栏收起/展开时自身宽度会变，用它判断会在动画最后一帧
    // 突然从宽布局切到窄布局（用户看到的「最后一刻震动卡一下」）
    readonly property bool narrow: (Window.window ? Window.window.width : width) < 900
    // 宽布局边距 72 → 48：1100 窗口下内容区从 748 加到 796，三列卡片才不至于挤成一团
    readonly property int padH: narrow ? 32 : 48
    readonly property int padR: narrow ? 28 : 48
    readonly property int topH: narrow ? 56 : 64
    signal close()
    /// 资源库点了卡片：交给外壳打开详情页
    signal openResourceDetail(string kind, var item)
    /// 资源库是否有在途请求（外壳顶部加载条聚合用）
    // 必须带 visible：resourceView 是常驻对象、靠 tabIndex 复用（Mod/光影/资源包/整合包/数据包同一页），
    // 切到 MC 版本页时它只是隐藏，Mod 的扫描还在跑，busy 仍为 true —— 少了这个判断就会出现
    // 「进 Mod 又迅速切到版本页，顶部光条还在转」。
    readonly property bool resourceBusy: (resourceView && resourceView.visible) ? resourceView.busy : false
    // 安装已启动：交给外壳切到独立的「下载进度」页（本页不再持有进度视图）
    signal openProgress()

    readonly property var releaseV: b ? b.releaseVersions : []
    readonly property var snapshotV: b ? b.snapshotVersions : []
    readonly property var oldV: b ? b.oldVersions : []
    readonly property var aprilV: b ? b.aprilFoolVersions : []
    readonly property var installedV: b ? b.installedVersions : []

    property int tab: 0
    // 分段控件几何表（key → {x,w}）。delegate 上报比 itemAt 可靠：首帧就能拿到。
    property var segGeom: ({})
    function reportSegGeom(key, item) {
        var m = {}
        for (var k in page.segGeom) m[k] = page.segGeom[k]
        m[key] = { x: item.x, w: item.width }
        page.segGeom = m
    }
    // 列表入场序号：每次页面显示时 +1，让所有已存在的行重播一次入场
    property var tabGeom: ({})
    function reportTabGeom(idx, item) {
        var m = {}
        for (var k in page.tabGeom) m[k] = page.tabGeom[k]
        m[idx] = { x: item.x, w: item.width }
        page.tabGeom = m
    }
    property int mode: 0        // 0 列表 1 配置
    property int filter: 0      // 0 正式版 1 快照版 2 远古版 3 愚人节版
    property string search: ""
    property string picked: ""
    property string instName: ""
    property bool nameConflict: false
    // 安装名自动生成：用户没手动改过时，跟随「MC 版本 + 加载器」自动变化
    property bool nameEdited: false
    // 程序回写 TextInput 时置真，避免把"自动改名"误判成"用户手动编辑"
    property bool syncingName: false
    // 自动改名序号：只有"程序改写安装名"（选加载器 / 选 Fabric API）才让输入框脉冲，
    // 用户自己打字时不闪（否则每敲一个字边框都在跳，很吵）。
    property int autoNameTick: 0
    property string activeLoader: ""
    property string selectedVersion: ""
    property string fabricApiVersion: ""
    property string fabricApiUrl: ""
    property string fabricApiFile: ""

    // 加载器版本（信号回填）
    property var forgeList: []
    property var neoforgeList: []
    property var fabricList: []
    property var fabricApiList: []
    property var optifineList: []
    property string expandedLoader: ""

    readonly property var tabs: ["MC 版本", "Mod", "光影", "资源包", "整合包", "数据包", "Java"]

    // 资源库搜索防抖：不用每敲一个字就发一次请求
    Timer {
        id: resourceTimer
        interval: 450
        onTriggered: if (resourceView) resourceView.doSearch(0)
    }
    readonly property var filters: [
        { key: 0, label: "正式版" },
        { key: 1, label: "快照版" },
        { key: 2, label: "远古版" },
        { key: 3, label: "愚人节版" }
    ]

    function countFor(k) {
        if (k === 0) return releaseV.length
        if (k === 1) return snapshotV.length
        if (k === 2) return oldV.length
        return aprilV.length
    }

    function listFor(k) {
        if (k === 0) return releaseV
        if (k === 1) return snapshotV
        if (k === 2) return oldV
        return aprilV
    }

    function isInstalled(id) { return installedV.indexOf(id) >= 0 }

    function visibleList() {
        var src = listFor(page.filter)
        if (page.search.trim().length === 0) return src
        var q = page.search.trim().toLowerCase()
        var out = []
        for (var i = 0; i < src.length; ++i)
            if (src[i].toLowerCase().indexOf(q) >= 0) out.push(src[i])
        return out
    }
    readonly property var rows: visibleList()

    function typeLabel() {
        if (page.filter === 1) return "快照"
        if (page.filter === 2) return "旧版"
        if (page.filter === 3) return "愚人节"
        return "正式版"
    }

    function typeColor() {
        if (page.filter === 1) return "#f5c451"
        if (page.filter === 2) return "#a9b3c2"
        if (page.filter === 3) return "#f5c451"
        return "#5ee08f"
    }

    // Sidebar 再次点"下载"时回到列表（已在本页时）
    function resetToList() { page.mode = 0; page.search = "" }

    // 版本发布日期（后端 versionList 已带 date，缺省为空不显示）
    function dateOf(id) { return page.dateMap[id] || "" }

    // QML 里 QVariantList 是"序列包装"：逐项访问 vl[i] 会每次回调 C++ getter，
    // 907 个版本就是 907 次 × 重建 907 条 → O(n²) ≈ 7 s 卡死。
    // 后端已提供一次性构造的 id→date 表（QVariantMap，转 JS 对象一次完成）。
    readonly property var dateMap: (b ? b.versionDateMap : ({}))

    function pickVersion(vid) {
        page.picked = vid
        page.nameEdited = false
        page.activeLoader = ""
        page.selectedVersion = ""
        page.clearFabricApi()
        page.expandedLoader = ""
        page.applyName(vid)      // 自动名 = MC 版本（还没选加载器）
        page.loaderQuery(vid)
        page.mode = 1
    }

    function loaderQuery(mc) {
        if (!b) return
        page.forgeList = []; page.neoforgeList = []; page.fabricList = []
        page.fabricApiList = []; page.optifineList = []
        b.queryForgeVersions(mc)
        b.queryNeoForgeVersions(mc)
        b.queryFabricVersions(mc)
        b.queryFabricApiVersions(mc)
        b.queryOptifineVersions(mc)
    }

    function checkName(v) {
        var name = (v === undefined || v === null) ? "" : String(v).trim()
        page.nameConflict = name.length > 0 && page.isInstalled(name)
    }

    // ── 安装名自动生成（旧 UI 语义）──
    // 加载器后缀沿用后端命名约定：OptiFine 的 installName 必须含 "OptiFine_<版本>"，
    // mod_loader_installer 会从 installName 反解加载器版本（见 installer.cpp 469 行）。
    // 命名与旧 UI InstallPage.versionSuffix 完全一致：
    //   <mc>-forge-<ver> / <mc>-neoforge-<ver> / <mc>-fabric-<ver>[-fabric-api-<apiVer>] / <mc>-OptiFine_<ver>
    // 之前只拼了加载器 key（"26.2-fabric"），既丢了加载器版本，也完全没带 Fabric API，
    // 所以选中 Fabric API 时名字不动 —— 这就是用户报的那条。
    function loaderSuffix() {
        var parts = []
        if (page.activeLoader === "forge" && page.selectedVersion.length > 0) {
            parts.push("forge-" + page.selectedVersion)
        } else if (page.activeLoader === "neoforge" && page.selectedVersion.length > 0) {
            parts.push("neoforge-" + page.selectedVersion)
        } else if (page.activeLoader === "fabric") {
            if (page.selectedVersion.length > 0) parts.push("fabric-" + page.selectedVersion)
            if (page.fabricApiVersion.length > 0) parts.push("fabric-api-" + page.fabricApiVersion)
        } else if (page.activeLoader === "optifine") {
            parts.push("OptiFine_" + (page.selectedVersion.length > 0 ? page.selectedVersion : "latest"))
        } else if (page.activeLoader.length > 0) {
            parts.push(page.activeLoader)
        }
        return parts.join("-")
    }

    function autoName() {
        if (page.picked.length === 0) return ""
        var suffix = page.loaderSuffix()
        return suffix.length > 0 ? (page.picked + "-" + suffix) : page.picked
    }

    // 同时写属性与输入框：TextInput.text 一旦被用户编辑过，绑定就断了，
    // 只改 instName 不会回显，所以这里显式双写。
    function applyName(n) {
        if (page.instName !== n) {
            page.instName = n
            page.autoNameTick++
        }
        if (nameInput.text !== n) {
            page.syncingName = true
            nameInput.text = n
            page.syncingName = false
        }
        page.checkName(n)
    }

    function refreshName() {
        if (page.nameEdited) return
        page.applyName(page.autoName())
    }

    // ── 加载器选择（可取消）──
    // Fabric API 只在 Fabric 被选中时成立；离开 Fabric / 取消 Fabric 时一并清掉，
    // 否则卡片会靠 "fabricApiVersion.length > 0" 继续挂着。
    function clearFabricApi() {
        if (page.fabricApiVersion.length === 0) return
        page.fabricApiVersion = ""
        page.fabricApiUrl = ""
        page.fabricApiFile = ""
        page.refreshName()
    }

    function deselectLoader() {
        if (page.activeLoader === "fabric") page.clearFabricApi()
        page.activeLoader = ""
        page.selectedVersion = ""
        page.refreshName()
    }

    // 再点一次已选中的版本 = 取消选中（返回 false 表示这次是取消）
    function selectLoader(key, ver) {
        if (page.activeLoader === key && page.selectedVersion === ver) {
            page.deselectLoader()
            return false
        }
        page.activeLoader = key
        page.selectedVersion = ver
        if (key !== "fabric") page.clearFabricApi()
        page.refreshName()
        return true
    }

    // ── 加载器互斥（原 UI 语义）──
    function loaderDisabled(key) {
        if (page.activeLoader.length === 0) return ""
        if (key === page.activeLoader) return ""
        if (key === "fabric_api") return page.activeLoader === "fabric" ? "" : "仅 Fabric 可用"
        if (key === "optifine")
            return (page.activeLoader === "fabric" || page.activeLoader === "neoforge")
                   ? ("与 " + page.activeLoader + " 不兼容") : ""
        if (page.activeLoader === "optifine" && key !== "fabric_api")
            return "与 OptiFine 不兼容"
        return "已选 " + page.activeLoader
    }

    function typeText(t) {
        if (t === "version" || t === "vanilla") return "原版"
        if (t === "merged") return "整合安装"
        return t
    }

    function canInstall() {
        if (page.nameConflict) return false
        if (page.activeLoader.length === 0) return true
        return page.selectedVersion.length > 0
    }

    function startInstall() {
        if (!b) return
        // 名称被清空时用自动名兜底（带加载器后缀），不再退回裸 MC 版本号
        var fallback = page.autoName().length > 0 ? page.autoName() : page.picked
        var name = page.instName.trim().length > 0 ? page.instName.trim() : fallback
        if (page.activeLoader === "forge" || page.activeLoader === "neoforge"
                || page.activeLoader === "fabric") {
            b.installModLoader(page.picked, page.activeLoader, page.selectedVersion, name,
                               page.fabricApiVersion, page.fabricApiUrl, page.fabricApiFile, "", "")
        } else if (page.activeLoader === "optifine") {
            var found = null
            for (var i = 0; i < page.optifineList.length; ++i)
                if (page.optifineList[i].version === page.selectedVersion) found = page.optifineList[i]
            b.installOptifine(page.picked, page.selectedVersion, "",
                              name,
                              found ? (found.bmclType || "") : "",
                              found ? (found.bmclPatch || "") : "")
        } else {
            b.installVersion(page.picked)
        }
        if (toast) toast.show("已开始安装 " + name, 2600, "info")
        page.openProgress()
    }

    // ── 高光扫过（最新版卡）──
    // 相位由页面统一推进：卡片自己不持有动画，换 tab / 重排都不会留下半截动画
    property real sheenPhase: 0
    NumberAnimation {
        id: sheenAnim
        target: page; property: "sheenPhase"
        from: 0; to: 1
        duration: Theme.durSheen
        easing.type: Theme.easeLoop
    }
    Timer {
        id: sheenTimer
        interval: 9000
        repeat: true
        triggeredOnStart: true
        running: page.visible && page.mode === 0 && page.tab === 0
        onTriggered: sheenAnim.restart()
    }

    // 手动刷新的一次性状态：等后端 versionRefreshFinished 回来再提示
    property bool refreshPending: false
    Timer {
        id: refreshTimer
        interval: 20000
        repeat: false
        onTriggered: page.refreshPending = false   // 超时静默放弃，避免卡住后续提示
    }

    Component.onCompleted: {
        // 版本列表由 VersionBackend 在启动时自己刷新（日志"开始刷新版本列表"）；
        // 这里再同步调一次会让 QML 加载被后端解析阻塞 7 秒（首屏卡死的根因），故不再调用。
        if (Qt.application.arguments.indexOf("--ui-config") >= 0 && page.releaseV.length > 0)
            page.pickVersion(page.releaseV[0])
        // 调试/验收钩子：--ui-tab N 直接落到指定 tab（0=MC 1=Mod … 5=数据包）
        var ti = Qt.application.arguments.indexOf("--ui-tab")
        if (ti >= 0 && ti + 1 < Qt.application.arguments.length)
            page.tab = parseInt(Qt.application.arguments[ti + 1]) || 0
    }

    Connections {
        target: page.b
        function onForgeVersionsReady(v) { page.forgeList = v }
        function onNeoForgeVersionsReady(v) { page.neoforgeList = v }
        function onFabricVersionsReady(v) { page.fabricList = v }
        function onFabricApiVersionsReady(v) { page.fabricApiList = v }
        function onOptifineVersionsReady(v) { page.optifineList = v }
        function onInstalledVersionsChanged() { }

        // 手动刷新版本列表的收尾提示（只响应用户手动点击，启动期自动刷新不弹）
        function onVersionRefreshFinished(ok, message, count) {
            if (!page.refreshPending) return
            page.refreshPending = false
            refreshTimer.stop()
            if (page.toast)
                page.toast.show(ok ? "版本列表刷新成功" : "版本列表刷新失败", 2200, ok ? "info" : "warning")
        }
        function onCancelNotification(installId, message) {
            if (page.toast && message && message.length > 0)
                page.toast.show(message, 3000, "warning")
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // 点空白处收起搜索框焦点（放在最底层，只有没被其它控件吃掉的点击才会到这里）
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            if (globalSearch) globalSearch.blur()
            if (nameInput) nameInput.focus = false
        }
    }

    // ══════════ 顶部栏（两种状态共用同一高度，避免切换跳动）══════════
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: page.topH

        // 空白处拖动窗口。无边框窗口没有系统标题栏，必须显式请求系统接管移动
        // （backend.beginWindowMove 内部走 QWindow::startSystemMove，保留贴边吸附）。
        // 放在最前面声明：后面的标题 / tab / 搜索框 / 窗口按钮都盖在它上面，
        // 所以只有真正的空白区能走到这里，控件仍按原样响应。
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: { if (backend) backend.beginWindowMove() }
        }

        Row {
            id: topLeft
            anchors.left: parent.left
            anchors.leftMargin: page.padH
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            // 仅配置页需要"回列表"（列表页本身由侧栏进入，不需要返回）
            Rectangle {
                visible: page.mode === 1
                width: 30; height: 30; radius: Theme.rSm
                color: cfgBackHover.containsMouse ? "#12151c" : "transparent"
                SIcon { anchors.centerIn: parent; name: "arrow-left"; size: 16; color: Theme.fg2 }
                MouseArea {
                    id: cfgBackHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.mode = 0
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.mode === 1 ? "安装配置" : "下载"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.weight: Font.Bold
            }
        }

        // tab pills（只在列表态显示）
        // 放在裁剪容器里：宽布局下 7 个 tab 加上搜索框会挤到重叠，
        // 这里让 tab 区右边界锁在搜索框左侧，超了裁掉也不压搜索框。
        Item {
            id: tabClip
            visible: page.mode === 0
            anchors.left: topLeft.right
            anchors.leftMargin: 16
            anchors.right: headerSearch.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            // 必须要高度：clip 容器高度默认 0 时，里面整排 tab 会被裁没（表现为"tab 消失"）
            height: parent.height
            clip: true

            // 选中滑块：先铺在下面，tab 只负责文字与 hover。
            // 之前选中态是"每个 tab 自己的底色"，切换永远是一硬切；
            // 现在是一块底色从旧 tab 滑到新 tab，切页有方向感。
            Rectangle {
                id: tabPill
                z: 0
                height: 28
                radius: Theme.rSm
                color: "#1b2433"
                anchors.verticalCenter: parent.verticalCenter
                readonly property var sel: page.tabGeom[page.tab] || null
                x: tabsRow.x + (sel ? sel.x : 0)
                width: sel ? sel.w : 0
                Behavior on x { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                Behavior on width { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
            }

            Row {
                id: tabsRow
                z: 1
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Repeater {
                    id: tabRep
                    model: page.tabs
                    delegate: Rectangle {
                        height: 28
                        width: tabTxt.implicitWidth + 14
                    radius: Theme.rSm
                    function syncTabGeom() { page.reportTabGeom(index, this) }
                    Component.onCompleted: syncTabGeom()
                    onXChanged: syncTabGeom()
                    onWidthChanged: syncTabGeom()
                    color: tabHover.containsMouse && page.tab !== index ? "#12151c" : "transparent"
                    Text {
                        id: tabTxt
                        anchors.centerIn: parent
                        text: modelData
                        color: page.tab === index ? "#ffffff" : Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: page.tab === index ? Font.DemiBold : Font.Normal
                    }
                        MouseArea {
                            id: tabHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { globalSearch.blur(); page.tab = index }
                        }
                    }
                }
            }
        }

        // 搜索 + 刷新（列表态）：搜索框全 tab 常驻，位置固定在顶栏右侧
        Row {
            id: headerSearch
            visible: page.mode === 0
            anchors.right: parent.right
            anchors.rightMargin: page.padR + 96
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            SField {
                id: globalSearch
                width: 220; height: 34
                anchors.verticalCenter: parent.verticalCenter
                label: page.tab === 6 ? "Java 无需搜索"
                     : page.tab === 0 ? "搜索版本号"
                     : page.tab === 1 ? "搜索 Mod"
                     : page.tab === 2 ? "搜索光影"
                     : page.tab === 3 ? "搜索资源包"
                     : page.tab === 4 ? "搜索整合包" : "搜索数据包"
                onEdited: (v) => {
                    if (page.tab === 0) page.search = v
                    else if (resourceView) { resourceView.query = v; resourceTimer.restart() }
                }
                onAccepted: {
                    if (page.tab !== 0 && resourceView) resourceView.doSearch(0)
                }
            }
            // 外部状态 → 输入框（聚焦时不覆盖，避免打断输入）
            Binding {
                target: globalSearch
                property: "text"
                value: page.tab === 0 ? page.search
                     : (resourceView ? resourceView.query : "")
                when: !globalSearch.input.activeFocus
                restoreMode: Binding.RestoreNone
            }
            Rectangle {
                width: 32; height: 32; radius: Theme.rSm
                color: refreshHover.containsMouse ? "#12151c" : "transparent"
                border.color: Theme.line2
                border.width: 1
                SIcon { anchors.centerIn: parent; name: "refresh-cw"; size: 14; color: Theme.fg2 }
                MouseArea {
                    id: refreshHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // 点击后不弹「正在刷新」：只等后端回结果，再提示一次（成功/失败），
                    // 避免"弹个开始提示然后什么都没有"的反直觉反馈。
                    onClicked: if (page.b) { page.refreshPending = true; refreshTimer.restart(); page.b.refreshVersionList() }
                }
            }
        }
    }

    // ══════════ 列表态 ══════════
    // 列表 ↔ 配置是一次"横向推拉"：进入配置时列表左移退场，返回列表时右移回来。
    // 之前列表是 visible 硬切，只有配置页单向淡入 —— 返回时"啪"一下就换了，方向感为零。
    Item {
        id: listLayer
        visible: page.mode === 0 || opacity > 0.01
        opacity: page.mode === 0 ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: page.mode === 0 ? Theme.durBase : Theme.durFast
                easing.type: page.mode === 0 ? Theme.easeEnter : Theme.easeExit
            }
        }
        transform: Translate {
            x: page.mode === 0 ? 0 : -22
            Behavior on x { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
        }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: page.padH
        anchors.rightMargin: page.padR
        anchors.topMargin: 20
        anchors.bottomMargin: 24

        // 资源库五类（Mod / 光影 / 资源包 / 整合包 / 数据包）：同一页参数化
        // ── Java Tab（2026-11-07）──
        JavaPage {
            id: javaView
            anchors.fill: parent
            visible: page.tab === 6
            toast: page.toast
        }

        ResourcePage {
            id: resourceView
            anchors.fill: parent
            visible: page.tab !== 0 && page.tab !== 6
            tabIndex: page.tab
            toast: page.toast
            onOpenDetail: (kind, item) => page.openResourceDetail(kind, item)
        }

        // 筛选：分段控件（与主页其它页的 seg 同语言，不用旧 UI 的圆胶囊）
        Rectangle {
            id: filterRow
            visible: page.tab === 0
            width: segContent.width + 4
            height: 32
            radius: Theme.rSm
            color: "#0d1016"
            border.color: Theme.line2
            border.width: 1

            // 选中滑块（与 tab 同一套语言）：一块底色在分段控件里平移。
            // x/width 用 delegate 上报的几何，而不是 Repeater.itemAt：
            // itemAt 在首帧可能还是 null，滑块宽度会是 0，整排"选中态"就消失了（用户报的"正式版 Tab 缺失"）。
            Rectangle {
                id: segPill
                height: 28
                radius: 6
                color: "#20262f"
                readonly property var sel: page.segGeom[page.filter] || null
                x: segContent.x + (sel ? sel.x : 0)
                y: segContent.y
                width: sel ? sel.w : 0
                Behavior on x { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                Behavior on width { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
            }

            Row {
                id: segContent
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    id: segRep
                    model: page.filters
                    delegate: Rectangle {
                        height: 28
                        width: segLabel.implicitWidth + segCnt.implicitWidth + 24
                        radius: 6
                        color: "transparent"
                        // 几何上报（首帧即写入，滑块不会出现"宽度 0"的空窗）
                        function syncGeom() { page.reportSegGeom(modelData.key, this) }
                        Component.onCompleted: syncGeom()
                        onXChanged: syncGeom()
                        onWidthChanged: syncGeom()
                        Row {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                id: segLabel
                                text: modelData.label
                                color: page.filter === modelData.key ? "#ffffff" : Theme.fg2
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: page.filter === modelData.key ? Font.DemiBold : Font.Normal
                            }
                            Text {
                                id: segCnt
                                text: page.countFor(modelData.key)
                                color: page.filter === modelData.key ? "#9fb6d8" : Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { globalSearch.blur(); page.filter = modelData.key }
                        }
                    }
                }
            }
        }

        // 最新正式版高亮卡
        Rectangle {
            id: latestCard
            visible: page.tab === 0 && page.filter === 0 && page.search.length === 0 && page.releaseV.length > 0
            anchors.top: filterRow.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            height: 72
            radius: 10
            color: "#0b0d12"
            border.color: Theme.line2
            border.width: 1
            clip: true

            // 高光扫过：进页面时扫一次，之后每 9 秒一次（像被"擦亮"）。
            // 用页面级 phase 驱动，自己不跑动画；扫光被卡片 clip 住，不会越到相邻卡片。
            SShimmer {
                anchors.fill: parent
                phase: page.sheenPhase
                bandWidth: 180
                strength: 0.055
                tint: "#ffffff"
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.top: parent.top
                anchors.topMargin: 14
                text: "最新正式版"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 13
                text: page.releaseV.length > 0 ? page.releaseV[0] : ""
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    text: "安装"
                    color: "#8fb6f8"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
                SIcon { name: "chevron-right"; size: 15; color: "#8fb6f8"; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: hoverLatest
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // hover 立刻扫一道（之前只把强度 0.045→0.10，光带多数时间在卡片外，肉眼看不到）
                onContainsMouseChanged: if (containsMouse) sheenAnim.restart()
                onClicked: {
                    latestRipple.burst(hoverLatest.mouseX, hoverLatest.mouseY)
                    page.pickVersion(page.releaseV[0])
                }
            }
            // 点击涟漪：从按下的点扩散，作为"要进配置页了"的确认
            SRipple {
                id: latestRipple
                anchors.fill: parent
                color: "#8fb6f8"
                maxRadius: 160
            }
        }

        // 版本卡列表
        ListView {
            id: vlist
            visible: page.tab === 0
            anchors.top: latestCard.visible ? latestCard.bottom : filterRow.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: page.rows
            delegate: Rectangle {
                id: vcard
                width: vlist.width
                height: 48
                radius: Theme.rSm
                color: hoverCard.containsMouse ? "#101419" : "#0b0d12"
                border.color: hoverCard.containsMouse ? "#243040" : "#161a21"
                border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

                // hover 时左侧强调条从中间长出来（不是整条变色，视线先落在这里）
                Rectangle {
                    width: 2
                    radius: 1
                    color: Theme.accent
                    anchors.left: parent.left
                    anchors.leftMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    height: hoverCard.containsMouse ? parent.height - 16 : 0
                    Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    // 固定 16px 槽位：有没有绿点，版本号都在同一条左边线上
                    Item {
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            visible: page.isInstalled(modelData)
                            width: 5; height: 5; radius: 3
                            color: "#4ade80"
                            anchors.centerIn: parent
                        }
                    }
                    Text {
                        text: modelData
                        color: "#e8ebf2"
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // 发布日期（真实字段；缺失时留空）
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 250
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.dateOf(modelData)
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        height: 18
                        width: typeTxt.implicitWidth + 12
                        radius: 4
                        color: "transparent"
                        border.color: page.typeColor()
                        border.width: 1
                        Text {
                            id: typeTxt
                            anchors.centerIn: parent
                            text: page.typeLabel()
                            color: page.typeColor()
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                    SIcon {
                        name: "chevron-right"; size: 14
                        color: hoverCard.containsMouse ? Theme.fg2 : Theme.fg3
                        anchors.verticalCenter: parent.verticalCenter
                        transform: Translate {
                            x: hoverCard.containsMouse ? 3 : 0
                            Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
                        }
                    }
                }

                MouseArea {
                    id: hoverCard
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { globalSearch.blur(); page.pickVersion(modelData) }
                }
            }

            Text {
                visible: page.rows.length === 0
                anchors.centerIn: parent
                text: "没有匹配的版本"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
    }

    // ══════════ 配置态 ══════════
    Item {
        id: cfgLayer
        visible: page.mode === 1 || opacity > 0.01
        opacity: page.mode === 1 ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: page.mode === 1 ? Theme.durBase : Theme.durFast
                easing.type: page.mode === 1 ? Theme.easeEnter : Theme.easeExit
            }
        }
        transform: Translate {
            x: page.mode === 1 ? 0 : 22
            Behavior on x { NumberAnimation { duration: Theme.durPage; easing.type: Theme.easeEnter } }
        }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom

        Flickable {
            id: cfgFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: actionBar.top
            anchors.leftMargin: page.padH
            anchors.rightMargin: page.padR
            clip: true
            contentHeight: cfgCol.height + 24
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: cfgCol
                width: cfgFlick.width
                spacing: 12

                // CARD 1：MC 版本 + 安装名称
                Rectangle {
                    width: parent.width
                    height: 118
                    radius: 10
                    color: "#0b0d12"
                    border.color: page.nameConflict ? "#7a3b45" : Theme.line2
                    border.width: 1

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        text: "Minecraft " + page.picked
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                    Rectangle {
                        id: nameBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        height: 34
                        radius: Theme.rSm
                        color: "#0d1016"
                        border.color: page.nameConflict ? "#b3454f"
                                    : (nameInput.activeFocus || pulse.running ? Theme.accent : Theme.line2)
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }

                        // 抖动：横向 3 次小位移，幅度递减。只在"第一次检测到冲突"时跑，
                        // 打字过程中持续冲突不重复抖（否则输入会疯）。
                        transform: Translate {
                            id: nameShift
                            x: 0
                        }
                        SequentialAnimation {
                            id: shake
                            NumberAnimation { target: nameShift; property: "x"; to: -6; duration: Theme.durPress; easing.type: Theme.easeStandard }
                            NumberAnimation { target: nameShift; property: "x"; to: 5;  duration: Theme.durPress; easing.type: Theme.easeStandard }
                            NumberAnimation { target: nameShift; property: "x"; to: -3; duration: Theme.durPress; easing.type: Theme.easeStandard }
                            NumberAnimation { target: nameShift; property: "x"; to: 0;  duration: Theme.durFast; easing.type: Theme.easeEnter }
                        }
                        // 边框脉冲：安装名被自动改写（选加载器 / 选 Fabric API）时闪一下，
                        // 明确告诉用户"这个名字变了，是程序改的，不是你打错了"
                        property bool pulseOn: false
                        SequentialAnimation {
                            id: pulse
                            running: false
                            PropertyAction { target: nameBox; property: "pulseOn"; value: true }
                            PauseAnimation { duration: Theme.durBase }
                            PropertyAction { target: nameBox; property: "pulseOn"; value: false }
                        }
                        Connections {
                            target: page
                            function onAutoNameTickChanged() { pulse.restart() }
                            function onNameConflictChanged() {
                                if (page.nameConflict) shake.restart()
                            }
                        }
                        TextInput {
                            id: nameInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            text: page.instName
                            color: Theme.fg
                            selectionColor: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            clip: true
                            onTextChanged: {
                                if (page.syncingName) return
                                page.instName = text
                                // 内容等于自动名 → 仍算"没手动改过"，后续选加载器继续自动跟随
                                page.nameEdited = text.trim().length > 0 && text !== page.autoName()
                                page.checkName(text)
                            }
                        }
                    }
                    Text {
                        visible: page.nameConflict
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.top: parent.top
                        anchors.topMargin: 18
                        text: "名称已存在"
                        color: "#f0a0a0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                // 加载器分段标题
                Text {
                    text: "Mod 加载器"
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    leftPadding: 4
                    topPadding: 6
                }

                // 每加载器一张可展开卡（结构复刻旧 ModLoaderCard：标题行 + 可展开版本列表 + 不使用）
                Repeater {
                    model: [
                        { key: "forge", label: "Forge" },
                        { key: "neoforge", label: "NeoForge" },
                        { key: "fabric", label: "Fabric" },
                        { key: "fabric_api", label: "Fabric API" },
                        { key: "optifine", label: "OptiFine" }
                    ]
                    delegate: Rectangle {
                        id: loaderCard
                        width: cfgCol.width
                        height: page.expandedLoader === modelData.key
                                ? 40 + Math.min(6, loaderCard.loaderVersions.length) * 30 + 8 : 44
                        radius: 10
                        color: "#0b0d12"
                        border.color: (page.activeLoader === modelData.key && modelData.key !== "fabric_api")
                                      ? Qt.rgba(0.231, 0.510, 0.965, .55) : Theme.line2
                        border.width: 1
                        clip: true

                        readonly property string lkey: modelData.key
                        readonly property string llabel: modelData.label
                        readonly property string offReason: page.loaderDisabled(lkey)
                        readonly property bool off: offReason.length > 0
                        // Fabric API 只在 Fabric 被选中（或已选过版本）时才有意义
                        visible: lkey !== "fabric_api" || page.activeLoader === "fabric"
                                 || page.fabricApiVersion.length > 0
                        opacity: off ? 0.62 : 1
                        Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
                        property var loaderVersions: (function() {
                            if (lkey === "forge") return page.forgeList
                            if (lkey === "neoforge") return page.neoforgeList
                            if (lkey === "fabric") return page.fabricList
                            if (lkey === "fabric_api") return page.fabricApiList
                            return page.optifineList
                        })()

                        Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }

                        // 标题行（点整行展开/收起）
                        Item {
                            id: lhead
                            width: parent.width
                            height: 44
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: loaderCard.llabel
                                color: "#e8ebf2"
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 34
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                // 禁用原因做成小标签：比整行红字更轻，也更像状态而不是报错
                                Rectangle {
                                    visible: loaderCard.off
                                    height: 20
                                    width: offTxt.implicitWidth + 16
                                    radius: 4
                                    color: Qt.rgba(0.973, 0.443, 0.443, 0.08)
                                    border.color: Qt.rgba(0.973, 0.443, 0.443, 0.22)
                                    border.width: 1
                                    Text {
                                        id: offTxt
                                        anchors.centerIn: parent
                                        text: loaderCard.offReason
                                        color: "#c99a9a"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                }
                                Text {
                                    visible: !loaderCard.off
                                    text: loaderCard.lkey === "fabric_api"
                                          ? (page.fabricApiVersion.length > 0 ? page.fabricApiVersion : "可选")
                                          : (page.activeLoader === loaderCard.lkey && page.selectedVersion.length > 0
                                             ? page.selectedVersion : "不使用")
                                    color: ((page.activeLoader === loaderCard.lkey && loaderCard.lkey !== "fabric_api")
                                            || (loaderCard.lkey === "fabric_api" && page.fabricApiVersion.length > 0))
                                           ? "#8fb6f8" : Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }
                            SIcon {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron-down"
                                size: 14
                                color: page.expandedLoader === loaderCard.lkey ? Theme.fg2 : Theme.fg3
                                rotation: page.expandedLoader === loaderCard.lkey ? 180 : 0
                                // 展开/收起时箭头转过去，而不是瞬间翻面
                                Behavior on rotation { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: loaderCard.off ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (loaderCard.off) return
                                    // 展开中优先收起；已选中的加载器卡片再点一次 = 取消选中
                                    // （旧 UI 里卡片本身就是开关，新 UI 之前只能靠展开后的"不使用"）
                                    if (page.expandedLoader === loaderCard.lkey) {
                                        page.expandedLoader = ""
                                        return
                                    }
                                    if (loaderCard.lkey !== "fabric_api" && page.activeLoader === loaderCard.lkey) {
                                        page.deselectLoader()
                                        return
                                    }
                                    page.expandedLoader = loaderCard.lkey
                                }
                            }
                        }

                        // 展开区：版本行
                        Column {
                            visible: page.expandedLoader === loaderCard.lkey
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: lhead.bottom
                            spacing: 2

                            Repeater {
                                model: loaderCard.loaderVersions.slice(0, 6)
                                delegate: Rectangle {
                                    width: loaderCard.width - 20 - (lvHover.containsMouse ? 3 : 0)
                                    height: 28
                                    radius: 6
                                    readonly property string ver: (typeof modelData === "string") ? modelData : (modelData.version || "")
                                    // 展开瞬间逐条落下（按行号错峰），收起时同时淡出
                                    readonly property bool opened: page.expandedLoader === loaderCard.lkey
                                    opacity: opened ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
                                    transform: Translate {
                                        y: opened ? 0 : -4
                                        Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
                                    }
                                    // hover 时整行向右轻推一点（列表有"被摸到"的手感）
                                    x: 10 + (lvHover.containsMouse ? 3 : 0)
                                    Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                    color: ((loaderCard.lkey === "fabric_api" ? page.fabricApiVersion : page.selectedVersion) === ver
                                            && (loaderCard.lkey === "fabric_api" || page.activeLoader === loaderCard.lkey))
                                           ? Qt.rgba(0.231, 0.510, 0.965, .16) : (lvHover.containsMouse ? "#12151c" : "transparent")
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.ver
                                        color: "#dfe5ee"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }
                                    MouseArea {
                                        id: lvHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: loaderCard.off ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        onClicked: {
                                            if (loaderCard.off) return
                                            if (loaderCard.lkey === "fabric_api") {
                                                // 再点已选的 Fabric API 版本 = 取消
                                                if (page.fabricApiVersion === parent.ver) {
                                                    page.clearFabricApi()
                                                    return
                                                }
                                                page.fabricApiVersion = parent.ver
                                                if (typeof modelData === "object") {
                                                    page.fabricApiUrl = modelData.url || ""
                                                    page.fabricApiFile = modelData.filename || ""
                                                }
                                                page.refreshName()   // 选中 Fabric API 也要改安装名
                                                page.expandedLoader = ""
                                            } else if (page.selectLoader(loaderCard.lkey, parent.ver)) {
                                                page.expandedLoader = ""
                                                if (page.toast)
                                                    page.toast.show(loaderCard.llabel + " " + parent.ver, 1600, "info")
                                            }
                                        }
                                    }
                                }
                            }

                            // 空态：查询完成但没有版本
                            Text {
                                visible: loaderCard.loaderVersions.length === 0
                                width: loaderCard.width - 20
                                x: 10
                                height: 28
                                text: "没有可用版本"
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                            }

                            // 不使用
                            Rectangle {
                                width: loaderCard.width - 20
                                x: 10
                                height: 28
                                radius: 6
                                color: noHover.containsMouse ? "#12151c" : "transparent"
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "不使用"
                                    color: Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: noHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // Fabric API 的"不使用"只清它自己，别把已选的 Fabric 一起清掉
                                        if (loaderCard.lkey === "fabric_api") page.clearFabricApi()
                                        else page.deselectLoader()
                                        page.expandedLoader = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 底部固定操作栏
        Rectangle {
            id: actionBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 72
            color: "#0a0b0f"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: page.padH
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                SIcon { name: "folder"; size: 14; color: Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "versions/" + (page.instName.length > 0 ? page.instName : page.picked)
                    color: Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                id: installBtn
                width: 120; height: 40; radius: Theme.rSm
                anchors.right: parent.right
                anchors.rightMargin: page.padR
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool ready: page.canInstall()
                color: ready ? (installPress.containsMouse ? Theme.accent : Theme.accentTop) : "#2a2f3a"
                border.width: ready ? 0 : 1
                border.color: "#333b48"
                clip: true
                // 可用 / 不可用之间有颜色与轻微缩放过渡（选择加载器版本后按钮"亮起来"）
                Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                scale: (ready && installPress.pressed) ? 0.965 : (ready ? 1.0 : 0.985)
                Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easePop } }
                Text {
                    anchors.centerIn: parent
                    text: installBtn.ready ? "开始安装"
                          : (page.activeLoader.length > 0 && page.selectedVersion.length === 0
                             ? "请选择版本" : "开始安装")
                    color: installBtn.ready ? "#ffffff" : Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                }
                SRipple {
                    id: installRipple
                    anchors.fill: parent
                    color: "#ffffff"
                    maxRadius: 140
                }
                MouseArea {
                    id: installPress
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: page.canInstall()
                    onClicked: {
                        installRipple.burst(installPress.mouseX, installPress.mouseY)
                        page.startInstall()
                    }
                }
            }
        }
    }
}
