// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import ShadowLauncher.Next

// 资源库列表（A 方案「货架式」）：五类共用，按 tabIndex 参数化
//   1=Mod 2=光影 3=资源包 4=整合包 5=数据包
// 数据全部走已验证的后端池子接口：池子已经是去重+全局加权排序的全量，本页只负责切片渲染。
// 加载中间态统一：busy 上报给外壳 → 顶部 SLoadingBar（StageShell.root.loading）。
Item {
    id: page
    property int tabIndex: 1
    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null

    readonly property var kindList: ["", "mod", "shader", "resourcepack", "modpack", "datapack"]
    readonly property string kind: kindList[tabIndex] || "mod"
    readonly property bool narrow: (Window.window ? Window.window.width : (parent ? parent.width : width)) < 900

    property string query: ""
    property int source: 0           // 0 全部 1 Modrinth 2 CurseForge
    // 筛选按后端能力分档：加载器/环境只有 Mod 有查询参数；排序只有数据包有
    property string loader: ""
    property string env: ""
    property string dpSort: ""
    property int pageNo: 0
    readonly property int pageSize: tabIndex === 2 ? 20 : (tabIndex === 2 ? 20 : 30)
    property var pool: []
    property bool busy: false
    property bool _autoOpened: false

    // ── 动效：入场预算 ──
    // 后端是渐进式推送：一次搜索会多次 applyPool（清空+重填），如果每批都跑逐条入场，
    // 网格会反复"抖"一遍。所以只给每次新搜索的前 staggerMax 个 delegate 发放延迟预算，
    // 后续渐进补进来的条目直接到位。
    property int staggerBudget: 0
    // 骨架屏 / 卡片高光共用的相位（0..1），由本页统一推进，delegate 不各自持有动画
    property real shinePhase: 0
    NumberAnimation {
        target: page; property: "shinePhase"
        from: 0; to: 1
        duration: Theme.marquee
        loops: Animation.Infinite
        running: page.busy || listModel.count > 0
        easing.type: Theme.easeLoop
    }

    signal openDetail(string kind, var item)

    // ══ 拖入导入（2026-11-13 恢复）══
    // 只在这三类分类里接受拖入：Mod(.jar) / 资源包(.zip) / 光影(.zip)。
    // MC 版本(0)、整合包(4)、数据包(5) 天然不支持（tabIndex 不在集合里就 active=false）；
    // DownloadPage 的 Java(6)/MC 版本(0) 也不会命中，见 DownloadPage 里的 dropEnabled。
    //
    // 落地目录 = 当前选中实例（backend.selectedVersion）：
    //   Mod    → importMod(path, versionId)          → mods/
    //   资源包 → importResourcePack(path, versionId)  → resourcepacks/
    //   光影   → importShaderPack(path, versionId)    → shaderpacks/（与 VsShadersPane 同一接口）
    // 接口返回 bool；多个文件一起拖进来时逐个调用，全部处理完再只弹一条汇总 toast。
    readonly property bool dropKindSupported: tabIndex === 1 || tabIndex === 2 || tabIndex === 3
    // 扩展名过滤交给 SDropZone（它按 accept 过滤，不合格的根本不会触发 dropped）
    readonly property var dropAccept: tabIndex === 1 ? [".jar"] : [".zip"]
    // 宿主可关（DownloadPage 在「安装配置态」里关掉：那时拖文件进来语义不清）
    property bool dropEnabled: true
    readonly property bool dropActive: page.dropEnabled && page.dropKindSupported
    readonly property string dropKindLabel: tabIndex === 1 ? qsTr("Mod")
                                           : (tabIndex === 2 ? qsTr("光影包") : qsTr("资源包"))
    readonly property string dropDirName: tabIndex === 1 ? "mods"
                                        : (tabIndex === 2 ? "shaderpacks" : "resourcepacks")
    readonly property string dropVersionId: (page.b && page.b.selectedVersion) ? page.b.selectedVersion : ""
    // 入口是否就绪：光影导入是后端新接口，没编进来时给一句明确提示，而不是静默失败
    readonly property bool dropBackendReady: {
        if (!page.b) return false
        if (tabIndex === 1) return typeof page.b.importMod === "function"
        if (tabIndex === 3) return typeof page.b.importResourcePack === "function"
        if (tabIndex === 2) return typeof page.b.importShaderPack === "function"
        return false
    }
    readonly property string dropHintTitle: page.dropVersionId.length > 0
        ? qsTr("松开以导入%1").arg(page.dropKindLabel)
        : qsTr("请先选择一个实例")
    readonly property string dropHintBody: page.dropVersionId.length > 0
        ? qsTr("导入到实例 %1 的 %2 目录 · 只接受 %3")
              .arg(page.dropVersionId).arg(page.dropDirName).arg(page.dropAccept.join(" / "))
        : qsTr("拖入的文件会写进当前选中实例的目录，请先在版本页选择实例")

    // 拖入链接统一转本地路径：资源管理器给的是 file:///D:/x.jar，中文/空格是百分号转义。
    // 两种形态都要认：file:///D:/x（本地盘）与 file://server/share/x（UNC，去掉协议后要补 //）。
    function dropLocalPath(u) {
        var s = String(u)
        var m = /^file:(\/{2,3})([\s\S]*)$/i.exec(s)
        if (!m) return s
        var rest = m[2]
        if (m[1].length === 2) rest = "//" + rest
        try { rest = decodeURIComponent(rest) } catch (e) {}
        return rest
    }

    function dropImportOne(path) {
        if (!page.b || path.length === 0) return false
        var vid = page.dropVersionId
        try {
            if (page.tabIndex === 1) return page.b.importMod(path, vid) === true
            if (page.tabIndex === 3) return page.b.importResourcePack(path, vid) === true
            if (page.tabIndex === 2) return page.b.importShaderPack(path, vid) === true
        } catch (e) {
            console.warn("[drop] import failed: " + e)
        }
        return false
    }

    /** SDropZone.dropped(urls) 的落地处理：多文件全处理，结果合成一条 toast */
    function handleDropped(urls) {
        if (!page.dropActive || !urls || urls.length === 0) return
        var label = page.dropKindLabel
        if (!page.dropBackendReady) {
            if (page.toast) page.toast.show(qsTr("当前版本暂不支持导入%1").arg(label), 4200, "warning", true)
            return
        }
        if (page.dropVersionId.length === 0) {
            if (page.toast) page.toast.show(qsTr("请先在版本页选择一个实例，再拖入文件"), 4200, "warning", true)
            return
        }
        var okCount = 0
        var failCount = 0
        for (var i = 0; i < urls.length; ++i) {
            if (page.dropImportOne(page.dropLocalPath(urls[i]))) okCount++
            else failCount++
        }
        if (!page.toast) return
        if (okCount > 0 && failCount === 0)
            page.toast.show(qsTr("已导入 %1 个%2").arg(okCount).arg(label), -1, "info", true)
        else if (okCount > 0)
            page.toast.show(qsTr("已导入 %1 个%2，%3 个失败").arg(okCount).arg(label).arg(failCount),
                            4200, "warning", true)
        else
            page.toast.show(qsTr("导入失败：文件内容不是有效的%1").arg(label),
                            4200, "warning", true)
    }

    // 列数按「侧栏展开时的内容宽度」决定，而不是自身实时宽度。
    // 侧栏收起/展开属于整页切换：若按自身宽度算，1100 窗口下 3 列会在中途跳到 4 列，
    // 卡片瞬间从 278 宽缩到 206 宽（高度不变）——看起来就是"所有卡片一下变长"。
    // 用固定基准后，无论侧栏在动与否，列数恒定，只有卡片宽度平滑变化。
    readonly property int cols: {
        var winW = Window.window ? Window.window.width : (width + Theme.sideW)
        var ref = winW - Theme.sideW - 96         // 96 = DownloadPage 宽布局左右内边距之和（48+48）
        return ref >= 860 ? 4 : (ref >= 600 ? 3 : 2)
    }

    function sourceArg() { return page.source === 1 ? "modrinth" : (page.source === 2 ? "curseforge" : "") }

    // 加载器下拉选项：只从本轮实际返回的条目里取（不写死 fabric/forge/neoforge）
    readonly property var loaderOptions: {
        var set = {}
        for (var i = 0; i < page.pool.length; ++i) {
            var r = page.pool[i] || ({})
            if (r.loader) set[r.loader] = true
            var ll = r.loadersList
            if (ll && ll.length) {
                for (var k = 0; k < ll.length; ++k) if (ll[k]) set[ll[k]] = true
            }
        }
        var keys = []
        for (var key in set) keys.push(key)
        keys.sort()
        var out = [{ label: qsTr("全部加载器"), value: "" }]
        for (var n = 0; n < keys.length; ++n)
            out.push({ label: keys[n].charAt(0).toUpperCase() + keys[n].slice(1), value: keys[n] })
        return out
    }

    // 顶栏搜索框输入 → 防抖后再发请求（外部改 query 也走这里）
    onQueryChanged: queryTimer.restart()

    function doSearch(pageNum) {
        if (!page.b) return
        page.pageNo = (pageNum === undefined) ? 0 : Math.max(0, pageNum)
        page.busy = true
        // 必须清零：ticks 原来只在 running 由 false 变 true 时归零，而连续搜索/翻页时
        // busy 一直是 true，计数会跨搜索一路累加 —— 后面某次搜索一上来就撞上限、条立刻关掉。
        settleTimer.ticks = 0
        page.staggerBudget = Theme.staggerMax
        var q = page.query.trim()
        var off = page.pageNo * page.pageSize
        if (page.tabIndex === 1) {
            page.b.searchModsEx(q, page.loader, "", [], page.env, "", off, page.pageSize, page.sourceArg())
        } else if (page.tabIndex === 2) {
            page.b.searchShadersEx(q, [], [], [], [], off, page.pageSize, page.sourceArg())
        } else if (page.tabIndex === 3) {
            page.b.searchResourcepacks(q, "", off, [], page.sourceArg())
        } else if (page.tabIndex === 4) {
            page.b.searchModpacksEx(q, "", "", [], off, page.pageSize, page.sourceArg())
        } else if (page.tabIndex === 5) {
            page.b.searchDatapacksEx(q, "", [], page.dpSort, off, page.pageSize, page.sourceArg())
        }
        settleTimer.restart()
    }

    // 结果到达：按池子切片（后端已经是全量有序池）
    function applyPool(items) {
        page.pool = items || []
        listModel.clear()
        var start = page.pageNo * page.pageSize
        var end = Math.min(start + page.pageSize, page.pool.length)
        for (var i = start; i < end; ++i) {
            var r = page.pool[i] || ({})
            // 图标走司南缓存（原始 cdn .webp Qt 解不了，会整片空白）
            var iconUrl = r.icon || ""
            if (iconUrl && page.b) iconUrl = page.b.resolveIconUrl(iconUrl)
            listModel.append({
                title: r.title || r.slug || "",
                zh: r.zh || "",
                desc: r.desc || "",
                icon: iconUrl,
                iconRaw: r.icon || "",
                slug: r.slug || "",
                downloads: r.downloads || 0,
                source: r.source || "Modrinth",
                dateModified: r.dateModified || ""
            })
        }
        // 验收钩子：--ui-detail-first 自动打开第一条（截图用，不影响正常交互）
        if (!page._autoOpened && listModel.count > 0
                && Qt.application.arguments.indexOf("--ui-detail-first") >= 0) {
            page._autoOpened = true
            var r0 = page.pool[page.pageNo * page.pageSize] || ({})
            page.openDetail(page.kind, {
                slug: r0.slug || "", title: r0.title || "", zh: r0.zh || "",
                desc: r0.desc || "", icon: r0.icon || "", downloads: r0.downloads || 0,
                source: r0.source || "Modrinth", dateModified: r0.dateModified || ""
            })
        }
    }

    function hasMore() {
        try {
            var st = page.b ? page.b.resourcePoolState(page.kind) : null
            if (st && st.hasMore !== undefined) return !!st.hasMore
        } catch (e) {}
        return page.pool.length > (page.pageNo + 1) * page.pageSize
    }

    onTabIndexChanged: {
        listModel.clear(); page.pool = []; page.pageNo = 0; page.query = ""; page.source = 0
        page.doSearch(0)
    }

    Component.onCompleted: page.doSearch(0)

    // 顶栏搜索防抖
    Timer {
        id: queryTimer
        interval: 450
        onTriggered: page.doSearch(0)
    }

    // 后端还在拉（progressive emit）：轮询 pending，归零才关条
    Timer {
        id: settleTimer
        interval: 300; repeat: true
        running: page.busy
        property int ticks: 0
        onTriggered: {
            ticks++
            var pending = 0
            try {
                var st = page.b ? page.b.resourcePoolState(page.kind) : null
                pending = st ? st.pending : 0
            } catch (e) {}
            // 关条的唯一依据是 pending 归零（后端确定没有在途请求了）。
            // 上限提到 100 tick（30s）纯粹是防后端彻底卡死的最后保险，必须**大于**
            // 后端自己的 25s 最终兜底，否则前端会先关条、后端稍后还发一次数据 —— 列表就「蹦」了。
            if (pending === 0 || ticks > 100) {
                // 每次搜索只打一行，用来回查「条是什么时候关的、当时还有没有在途请求」
                console.info("[settle] close ticks=" + ticks + " pool=" + page.pool.length
                             + " timeout=" + (ticks > 100))
                ticks = 0
                page.busy = false
                running = false
            }
        }
        onRunningChanged: if (running) ticks = 0
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onModSearchResultsReady(results) { if (page.tabIndex === 1) page.applyPool(results) }
        function onShaderSearchResultsReady(results) { if (page.tabIndex === 2) page.applyPool(results) }
        function onResourcepackSearchCompleted(results, totalHits) { if (page.tabIndex === 3) page.applyPool(results) }
        function onModpackSearchResultsReady(results) { if (page.tabIndex === 4) page.applyPool(results) }
        function onDatapackSearchResultsReady(results) { if (page.tabIndex === 5) page.applyPool(results) }
        // 司南异步下完图标 → 回填对应行（原始 URL 命中则换成本地路径）
        function onIconReady(url, localPath) {
            for (var i = 0; i < listModel.count; ++i) {
                if (listModel.get(i).iconRaw === url)
                    listModel.setProperty(i, "icon", localPath)
            }
        }
    }

    ListModel { id: listModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ── 来源 + 重置 ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [{ t: qsTr("全部来源"), v: 0 }, { t: "Modrinth", v: 1 }, { t: "CurseForge", v: 2 }]
                delegate: Rectangle {
                    Layout.preferredHeight: 28
                    implicitWidth: srcTxt.implicitWidth + 22
                    radius: 14
                    color: page.source === modelData.v ? Theme.accentSoft : "transparent"
                    border.width: 1
                    border.color: page.source === modelData.v ? Theme.line2 : Theme.line2
                    Text {
                        id: srcTxt
                        anchors.centerIn: parent
                        text: modelData.t
                        color: page.source === modelData.v ? Theme.fg : Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { page.source = modelData.v; page.doSearch(0) }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // ── 筛选下拉：选项来自本轮实际返回的数据，不写死 ──
            LoaderDropdown {
                visible: page.loaderOptions.length > 1
                label: qsTr("加载器")
                placeholder: qsTr("全部加载器")
                current: page.loader
                options: page.loaderOptions
                onPicked: (v) => { page.loader = v; page.doSearch(0) }
            }

            LoaderDropdown {
                visible: page.tabIndex === 1
                label: qsTr("环境")
                placeholder: qsTr("全部环境")
                current: page.env
                options: [{ label: qsTr("全部环境"), value: "" }, { label: qsTr("客户端"), value: "client" }, { label: qsTr("服务端"), value: "server" }]
                onPicked: (v) => { page.env = v; page.doSearch(0) }
            }

            LoaderDropdown {
                visible: page.tabIndex === 5
                label: qsTr("排序")
                placeholder: qsTr("下载量")
                current: page.dpSort
                options: [{ label: qsTr("下载量"), value: "" }, { label: qsTr("最近更新"), value: "updated" }, { label: qsTr("名称"), value: "name" }]
                onPicked: (v) => { page.dpSort = v; page.doSearch(0) }
            }

            Rectangle {
                Layout.preferredHeight: 28
                implicitWidth: resetTxt.implicitWidth + 22
                radius: 14
                color: resetHover.containsMouse ? Theme.bgCard : "transparent"
                border.width: 1
                border.color: Theme.line2
                Text {
                    id: resetTxt
                    anchors.centerIn: parent
                    text: qsTr("重置")
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                MouseArea {
                    id: resetHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.query = ""; page.source = 0; page.loader = ""; page.env = ""; page.dpSort = ""; page.doSearch(0) }
                }
            }
        }

        // ── 网格（宿主：承载网格本体 + 骨架屏 + 上下渐隐）──
        // 三者必须叠在同一个 fillHeight 槽位里：如果各自作为 ColumnLayout 的 fillHeight 子项，
        // 可用高度会被平分，网格和骨架屏各拿一半（历史上就是这种"半屏"bug）。
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
            id: grid
            anchors.fill: parent
            clip: true
            model: listModel
            readonly property int gap: 10
            // GridView 按 cellWidth 决定换行，所以 cellWidth 必须 ≤ width/cols（否则第 3 张会被挤到下一行）。
            // 但 delegate 一律按 cellWidth-gap 算宽，最后又会空出「一个 gap + 取整余数」——
            // 就是用户看到的「三列没铺满、右边留一条」。折中：非最后一列扣 gap，最后一列吃满 cellWidth。
            cellWidth: Math.floor(width / page.cols)
            cellHeight: 156

            delegate: Item {
                id: cell
                readonly property bool lastCol: (index % page.cols) === (page.cols - 1)
                width: grid.cellWidth - (lastCol ? 0 : grid.gap)
                height: grid.cellHeight - grid.gap

                // 入场：从下方 14px + 0 透明浮上来，按格子序号错峰
                property bool shown: false
                opacity: cell.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                transform: Translate {
                    y: cell.shown ? 0 : 14
                    Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                }
                Timer {
                    id: cellDelay
                    onTriggered: cell.shown = true
                }
                Component.onCompleted: {
                    if (page.staggerBudget > 0) {
                        page.staggerBudget--
                        cellDelay.interval = Math.min(index, Theme.staggerMax) * Theme.staggerStep
                        cellDelay.start()
                    } else {
                        cell.shown = true
                    }
                }

                ResourceTile {
                    anchors.fill: parent
                    title: model.title
                    zh: model.zh
                    description: model.desc
                    iconUrl: model.icon
                    slug: model.slug
                    downloads: model.downloads
                    source: model.source
                    dateModified: model.dateModified
                    shimmerPhase: page.shinePhase
                    onClicked: page.openDetail(page.kind, {
                        slug: model.slug, title: model.title, zh: model.zh,
                        desc: model.desc, icon: model.icon, downloads: model.downloads,
                        source: model.source, dateModified: model.dateModified
                    })
                }
            }
            }   // GridView

        // ── 骨架屏：首次加载时用"形状"占位，而不是一片空白 ──
        // 只在列表还空的时候出现，已有内容时用顶部进度条表示在拉数据（不闪掉已有卡片）。
        Grid {
            id: skeleton
            readonly property bool on: page.busy && listModel.count === 0
            visible: on
            anchors.fill: parent
            anchors.leftMargin: 0
            columns: page.cols
            columnSpacing: 10
            rowSpacing: 10
            Repeater {
                model: page.cols * 3
                delegate: Rectangle {
                    width: (skeleton.width - (page.cols - 1) * 10) / page.cols
                    height: 146
                    radius: Theme.rMd
                    color: Theme.bgCard2
                    border.width: 1
                    border.color: Theme.line
                    clip: true

                    // 图标块
                    Rectangle {
                        x: 12; y: 12
                        width: 40; height: 40; radius: Theme.rSm
                        color: Theme.bgCard
                    }
                    // 标题 / 副标题 / 简介两行
                    Column {
                        x: 62; y: 14
                        spacing: 8
                        Rectangle { width: Math.min(120, parent.parent.width - 90); height: 12; radius: 6; color: Theme.bgCard }
                        Rectangle { width: Math.min(76, parent.parent.width - 120); height: 9; radius: 5; color: Theme.bgCard2 }
                    }
                    Column {
                        x: 12; y: 66
                        spacing: 7
                        Rectangle { width: parent.parent.width - 24; height: 9; radius: 5; color: Theme.bgCard2 }
                        Rectangle { width: (parent.parent.width - 24) * 0.72; height: 9; radius: 5; color: Theme.bgCard2 }
                    }
                    Column {
                        x: 12; y: 116
                        spacing: 6
                        Rectangle { width: 54; height: 8; radius: 4; color: Theme.bgCard2 }
                    }
                    // 扫光（统一相位，不各自跑动画）
                    SShimmer {
                        anchors.fill: parent
                        phase: page.shinePhase
                        bandWidth: 140
                        strength: 0.05
                    }
                }
            }
        }

            // ── 上下渐隐：网格贴边滚动时内容不是被硬切断，而是淡进背景 ──
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 18
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.bg }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 22
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Theme.bg }
                }
            }
        }   // 网格宿主

        // ── 空态 / 加载态 ──
        Column {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            visible: listModel.count === 0 && !page.busy
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.busy ? qsTr("正在加载…") : qsTr("没有找到匹配的资源")
                color: page.busy ? Theme.fg2 : Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !page.busy
                width: 96; height: 30
                radius: Theme.rSm
                color: retryHover.containsMouse ? Theme.bgCard : "transparent"
                border.width: 1
                border.color: Theme.line2
                Text {
                    anchors.centerIn: parent
                    text: qsTr("重新加载")
                    color: Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                MouseArea {
                    id: retryHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.doSearch(page.pageNo)
                }
            }
        }

        // ── 分页 ──
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            // 分页按钮的间距。原来没显式设，靠 Layout 默认值，
            // 中文下偶然不重叠，英文下就挤在一起。
            spacing: 8
            visible: listModel.count > 0
            Item { Layout.fillWidth: true }
            Text {
                text: (page.pageNo + 1) + " / " + Math.max(1, Math.ceil(page.pool.length / page.pageSize))
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            // ── 2026-11-14：按钮宽度必须随文案自适应 ──
            // 原来写死 Layout.preferredWidth: 64；中文「上一页」三个字正好装得下，
            // 但英文「Previous page」比 64px 宽 —— Text 居中后溢出矩形，
            // 直接压在左侧「1 / 4」上（实测截图反馈）。
            // 现在按文案 implicitWidth + 左右留白取大，并保留 64px 作为最小宽。
            Rectangle {
                Layout.preferredWidth: Math.max(64, prevLabel.implicitWidth + 24)
                Layout.preferredHeight: 28
                radius: Theme.rSm
                color: prevHover.containsMouse ? Theme.bgCard : "transparent"
                border.width: 1; border.color: Theme.line2
                Text {
                    id: prevLabel
                    anchors.centerIn: parent
                    text: qsTr("上一页")
                    color: page.pageNo > 0 ? Theme.fg2 : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 11
                }
                MouseArea {
                    id: prevHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (page.pageNo > 0) page.doSearch(page.pageNo - 1)
                }
            }
            Rectangle {
                Layout.preferredWidth: Math.max(64, nextLabel.implicitWidth + 24)
                Layout.preferredHeight: 28
                radius: Theme.rSm
                color: nextHover.containsMouse ? Theme.bgCard : "transparent"
                border.width: 1; border.color: Theme.line2
                Text {
                    id: nextLabel
                    anchors.centerIn: parent
                    text: qsTr("下一页")
                    color: page.hasMore() ? Theme.fg2 : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 11
                }
                MouseArea {
                    id: nextHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (page.hasMore()) page.doSearch(page.pageNo + 1)
                }
            }
        }
    }

    // 拖入由 StageShell 的全局投放区统一接管。
    // 本页保留 dropActive / dropAccept / handleDropped 这套判断，是为了让
    // "当前分类是什么、目标目录是哪、允许哪些扩展名"这套产品逻辑仍然集中在一处；
    // 全局入口判定类型后会复用同样的后端导入接口。

    // 下拉筛选：触发器 + 挂在触发器上的弹层（不会盖住自己）
    component LoaderDropdown: Rectangle {
        id: dd
        property string label: ""
        property string placeholder: ""
        property string current: ""
        property var options: []
        signal picked(string value)

        readonly property string shown: {
            for (var i = 0; i < options.length; ++i)
                if (options[i].value === current) return options[i].label
            return placeholder
        }

        implicitHeight: 28
        implicitWidth: ddTxt.implicitWidth + 30
        radius: 14
        color: ddHover.containsMouse || ddPop.visible ? Theme.bgCard : "transparent"
        border.width: 1
        border.color: current.length > 0 ? Theme.line2 : Theme.line2

        Text {
            id: ddTxt
            anchors.left: parent.left; anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: dd.shown
            color: dd.current.length > 0 ? Theme.fg : Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
        SIcon {
            anchors.right: parent.right; anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"; size: 10; color: Theme.fg3
        }
        MouseArea {
            id: ddHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ddPop.open()
        }

        Popup {
            id: ddPop
            parent: dd
            x: 0
            y: dd.height + 6
            width: Math.max(dd.width, 150)
            height: Math.min(260, dd.options.length * 32 + 8)
            padding: 4
            closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
            background: Rectangle { color: Theme.bgCard2; border.width: 1; border.color: Theme.line2; radius: Theme.rSm }
            contentItem: ListView {
                clip: true
                model: dd.options
                delegate: Rectangle {
                    width: ddPop.width - 8; height: 32; radius: 4
                    color: (dd.current === modelData.value) ? Theme.accentSoft : (optHover.containsMouse ? Theme.accentSoft : "transparent")
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 10
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: dd.current === modelData.value ? Theme.fg : Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: optHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { dd.picked(modelData.value); ddPop.close() }
                    }
                }
            }
        }
    }
}
