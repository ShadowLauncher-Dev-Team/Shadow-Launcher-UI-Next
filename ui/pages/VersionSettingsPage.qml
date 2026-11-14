// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置（全屏页）—— 顶栏 + 左栏（按版本能力过滤）+ 内容区
//
// 承载：StageShell 的全屏页宿主（与版本页/账户页同一套：侧栏收起、页面右滑入、返回回版本列表）
// 动效：左栏选中胶囊继承主菜单 SideBar（单个 Item 的 y 用 durSlow+easeEnter 滑到新位置）；
//       内容区分区切换用 durBase 淡入+上移 6px，与壳的整页切换（durPage）分层，不互相干扰
import QtQuick
import ShadowLauncher.Next

Item {
    id: page
    property string versionId: ""
    property var toast: null
    // 分区页在扫盘/批量改名时把顶部光条点亮（StageShell 读这个）
    property bool busy: false
    signal close()

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property string currentKey: "quick"

    // ── 换版本 / 重新进入时必须重建分区页（2026-11-14）──
    // 本页在 StageShell 里是**常驻实例**，打开/关闭只切宿主的 visible，
    // 页面对象和它里面的分区页都不会被销毁。而每个分区页（VsModsPane 等）
    // 只在自己 Component.onCompleted 里加载一次数据 —— 于是从版本列表打开
    // **另一个版本**的版本设置时，Mod 管理显示的还是上一个版本的内容。
    // （10 个分区里只有 VsExportPane 自己写了 onVersionIdChanged。）
    // 修法：版本变了 / 页面重新打开时，让 Loader 销毁并重建分区实例。
    // 顺带把搜索词、滚动位置、选中项这些**属于旧版本**的界面状态一起清掉，
    // 而不是让它们跨版本残留。
    property bool opened: true
    property int paneEpoch: 0
    function reloadPanes() {
        // 防抖：打开时 versionId 与 opened 会先后各触发一次，用 epoch 合并成一次重建
        page.paneEpoch++
        var token = page.paneEpoch
        Qt.callLater(function() {
            if (token !== page.paneEpoch) return
            page.busy = false
            page.ensureKeyVisible()      // 新版本可能不支持当前分区（原版没有 mods/）
            if (paneLoader.active) { paneLoader.active = false; paneLoader.active = true }
        })
    }
    onVersionIdChanged: page.reloadPanes()
    onOpenedChanged: if (opened) page.reloadPanes()

    // ── 当前版本能开哪些内容区（2026-11-13）──
    // 原版没有 mods/、shaderpacks/（游戏根本不会去读），这两个入口以前无条件摆着，
    // 点进去永远是空列表 —— 那是错的。这里按版本实际能力过滤。
    // 数据只读自 backend.versionDetails（ShadowBackend::refreshVersionDetails 异步扫 versions/
    // 的结果，字段 id / loaderType；VsOverviewPane 用的是同一份数据），不改 version_backend。
    readonly property var versionDetail: {
        if (!page.b || !page.b.versionDetails) return null
        var arr = page.b.versionDetails
        for (var i = 0; i < arr.length; ++i)
            if (arr[i] && arr[i].id === page.versionId) return arr[i]
        return null
    }
    // 后端给的 loaderType 是展示名：Fabric / Forge / NeoForge / Quilt / OptiFine / LiteLoader；
    // 原版给的是 tr("原版")——英文界面会被翻成 Vanilla，所以不能拿中文字面量去比。
    // 这里只认"已知加载器白名单"，不在名单里的一律按原版处理（中/繁/英界面都成立）。
    readonly property var loaderNames: ["Fabric", "Forge", "NeoForge", "Quilt", "OptiFine", "LiteLoader"]
    // versionDetails 还没扫到时的兜底：从版本目录名认加载器（1.20.1-Forge_47.2.0）。
    // 注意 neoforge 必须先于 forge 判断，否则 NeoForge 会被认成 Forge。
    readonly property string idLoaderHint: {
        var s = page.versionId.toLowerCase()
        if (s.indexOf("neoforge") >= 0) return "NeoForge"
        if (s.indexOf("forge") >= 0) return "Forge"
        if (s.indexOf("quilt") >= 0) return "Quilt"
        if (s.indexOf("fabric") >= 0) return "Fabric"
        if (s.indexOf("optifine") >= 0) return "OptiFine"
        if (s.indexOf("liteloader") >= 0) return "LiteLoader"
        return ""
    }
    readonly property string loaderKind: {
        var det = page.versionDetail
        // 详情扫到了就以它为准：loaderType 不在白名单里 = 原版（后端用 tr("原版")，中英文都对得上）。
        // 只有详情还没到（versionDetails 为空）才退回版本名线索，避免把有加载器的版本误判成原版。
        if (det) return page.loaderNames.indexOf(det.loaderType || "") >= 0 ? det.loaderType : ""
        return page.idLoaderHint
    }
    // Mod 只对四个真正的模组加载器开放：OptiFine / LiteLoader 没有 mods/ 语义。
    readonly property bool supportsMods: ["Fabric", "Forge", "NeoForge", "Quilt"].indexOf(page.loaderKind) >= 0
    // 光影：四个加载器 + OptiFine（它自带光影支持）。原版没有任何 shader 加载能力，不显示。
    readonly property bool supportsShaders: ["Fabric", "Forge", "NeoForge", "Quilt", "OptiFine"].indexOf(page.loaderKind) >= 0

    // 左栏行：t = "g" 分组小字 / "i" 分区项（全量，含按能力隐藏的项）
    readonly property var baseRows: [
        { t: "i", k: "quick",    label: qsTr("快捷入口"),   icon: "zap" },
        { t: "i", k: "overview", label: qsTr("概览"),       icon: "info" },
        { t: "g", label: qsTr("启动") },
        { t: "i", k: "launch",   label: qsTr("启动配置"),   icon: "sliders-horizontal" },
        { t: "i", k: "memory",   label: qsTr("内存设置"),   icon: "cpu" },
        { t: "g", label: qsTr("内容") },
        { t: "i", k: "mods",     label: qsTr("Mod 管理"),   icon: "puzzle" },
        { t: "i", k: "shaders",  label: qsTr("光影管理"),   icon: "sparkles" },
        { t: "i", k: "packs",    label: qsTr("资源包"),     icon: "package" },
        { t: "i", k: "saves",    label: qsTr("存档"),       icon: "box" },
        { t: "g", label: qsTr("维护") },
        { t: "i", k: "tools",    label: qsTr("工具与维护"), icon: "wrench" },
        { t: "i", k: "export",   label: qsTr("导出整合包"), icon: "package-plus" }
    ]

    // 实际渲染的左栏：按能力把 mods / shaders 拿掉，其余原样（分组小字保留：
    // 「内容」下面还有资源包和存档，原版也照常显示）。
    // navY() 与 selPill 都读 page.rows，所以过滤后选中胶囊的位置自动跟着算对。
    readonly property var rows: {
        var out = []
        for (var i = 0; i < page.baseRows.length; ++i) {
            var r = page.baseRows[i]
            if (r.t === "i" && r.k === "mods" && !page.supportsMods) continue
            if (r.t === "i" && r.k === "shaders" && !page.supportsShaders) continue
            out.push(r)
        }
        return out
    }
    // 分区被隐藏（含 --ui-pane 指定了不可用分区、概览页点了 Mod 管理）时，
    // 不能让内容区停在一个左栏里不存在的 key 上，退回快捷入口。
    onRowsChanged: page.ensureKeyVisible()
    function keyVisible(k) {
        for (var i = 0; i < page.rows.length; ++i)
            if (page.rows[i].t === "i" && page.rows[i].k === k) return true
        return false
    }
    function ensureKeyVisible() {
        // 待切分区优先：--ui-pane 指定分区的可见性是分两拍到达的
        // （先按版本目录名猜加载器 → 再等 versionDetails 扫到）。
        // 旧实现在第一拍把 currentKey 打回 quick、同时 pendingPaneKey 已被消费，
        // 于是指定分区永远进不去。这里让待切分区优先，且消费时才清空。
        if (page.pendingPaneKey.length > 0 && page.keyVisible(page.pendingPaneKey)) {
            page.currentKey = page.pendingPaneKey
            page.pendingPaneKey = ""
            return
        }
        if (!page.keyVisible(page.currentKey)) page.currentKey = "quick"
    }
    // 统一入口：可用就切过去，不可用就说明原因（不静默跳走）。
    // quiet=true 给 --ui-pane 用：启动时静默失败，等版本详情扫到再补一次（见 pendingPaneKey）。
    function goTo(k, quiet) {
        if (page.keyVisible(k)) { page.currentKey = k; return }
        if (quiet === true) return
        if (page.toast) page.toast.show(qsTr("这个版本不支持该内容类型（原版没有对应目录）"), -1, "info", true)
    }
    // --ui-pane <key> 指定的分区：版本详情可能还没扫到（那时按原版过滤会拒绝），
    // 先记下来，等 versionDetails 到了再补切一次，截图/验收入口不依赖时序。
    property string pendingPaneKey: ""
    onVersionDetailChanged: {
        if (page.pendingPaneKey.length === 0) return
        if (page.keyVisible(page.pendingPaneKey)) {
            page.currentKey = page.pendingPaneKey
            page.pendingPaneKey = ""
        }
    }

    function paneFor(k) {
        if (k === "quick") return quickComp
        if (k === "overview") return overviewComp
        if (k === "launch") return launchComp
        if (k === "memory") return memoryComp
        if (k === "tools") return toolsComp
        if (k === "mods") return modsComp
        if (k === "shaders") return shadersComp
        if (k === "packs") return packsComp
        if (k === "saves") return savesComp
        if (k === "export") return exportComp
        return placeholderComp
    }
    function paneTitle(k) {
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].t === "i" && rows[i].k === k) return rows[i].label
        return ""
    }

    // 左栏选中胶囊的目标位置：分组 34 / 分区项 40，位置纯计算（不用 mapToItem，避免 Loader 未完成时算错）
    readonly property int navGroupH: 34
    readonly property int navItemH: 40
    function navY(k) {
        var y = 0
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].t === "i" && rows[i].k === k) return y
            y += (rows[i].t === "g" ? navGroupH : navItemH)
        }
        return -1
    }

    // --ui-pane <key> 直接落在某个分区（截图/验收用）
    Component.onCompleted: {
        var args = Qt.application.arguments
        var i = args.indexOf("--ui-pane")
        if (i >= 0 && i + 1 < args.length && args[i + 1].indexOf("--") !== 0) {
            page.pendingPaneKey = args[i + 1]
            page.goTo(page.pendingPaneKey, true)
        }
        // 版本详情可能还没扫到（本页比版本页先打开 / 直接 --ui-pane 进来）：
        // 补一次只读扫描，扫完 versionDetails 一变，左栏按真实加载器自己刷新。
        // refreshVersionDetails 自身有 m_isScanningVersions 去重，重复调用安全。
        if (!page.versionDetail && page.b) page.b.refreshVersionDetails()
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---------- 顶栏 ----------
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 56

        // 空白处拖动窗口（无边框窗口没有系统标题栏，必须显式请求系统接管移动）。
        // 放在子项最前面：后面的按钮 / 搜索框都盖在它上面，控件照常响应，只有空白区能走到这里。
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: { if (backend) backend.beginWindowMove() }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }

        SButton {
            id: backBtn
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: qsTr("返回")
            onClicked: page.close()
        }

        Row {
            anchors.left: backBtn.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                text: qsTr("版本设置")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.versionId
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }

    // ---------- 左栏 ----------
    Rectangle {
        id: nav
        anchors.left: parent.left
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        width: Theme.sideW
        color: Theme.sidebar

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.line
        }

        Flickable {
            id: navFlick
            anchors.fill: parent
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            clip: true
            contentHeight: navHost.height
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: navHost
                width: navFlick.width
                height: navCol.implicitHeight

                // 选中胶囊：继承主菜单 SideBar 的做法 —— 一整块从旧位置滑到新位置，
                // 而不是"旧的竖条缩回去、新的竖条长出来"两段互不相关的动作。
                Item {
                    id: selPill
                    z: 0
                    x: 10
                    width: Math.max(0, navHost.width - 20)
                    visible: page.navY(page.currentKey) >= 0
                    y: Math.max(0, page.navY(page.currentKey)) + 2
                    height: page.navItemH - 4

                    Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: Theme.bgCard
                    }
                    // 左侧强调条跟着胶囊一起走
                    Rectangle {
                        width: 2
                        radius: 1
                        anchors.left: parent.left
                        anchors.leftMargin: -8
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height * 0.55
                        color: Theme.accent
                    }
                }

                Column {
                    id: navCol
                    z: 1
                    width: parent.width

                    Repeater {
                        model: page.rows
                        delegate: Loader {
                            width: navCol.width
                            sourceComponent: modelData.t === "g" ? groupComp : itemComp
                            property var rowData: modelData
                        }
                    }
                }
            }
        }
    }

    Component {
        id: groupComp
        Item {
            width: navCol.width
            height: 34
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                text: rowData.label
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1.1
            }
        }
    }

    Component {
        id: itemComp
        Item {
            id: itemRoot
            width: navCol.width
            height: 40
            readonly property bool active: page.currentKey === rowData.k

            // 选中高亮由外层 selPill 承担（滑动的那一块）。这里只做 hover，
            // 否则会出现"胶囊在滑、行背景自己也在亮灭"的两套高亮打架。
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                radius: Theme.rSm
                color: Theme.bgCard2
                opacity: (hover.hovered && !itemRoot.active) ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                SIcon {
                    name: rowData.icon
                    size: 15
                    color: itemRoot.active ? Theme.accentText : Theme.line3
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowData.label
                    color: itemRoot.active ? Theme.fg : Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                    }
                }
            }

            HoverHandler { id: hover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: page.currentKey = rowData.k
            }
        }
    }

    // ---------- 内容区 ----------
    Item {
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom

        Loader {
            id: paneLoader
            anchors.fill: parent
            sourceComponent: page.paneFor(page.currentKey)
            // 分区页自报 busy（扫盘/批量改名），转给壳的顶部光条
            onLoaded: {
                var it = paneLoader.item
                if (it && it.busyChanged !== undefined) {
                    it.busyChanged.connect(function(b) { page.busy = b })
                    page.busy = (it.loading === true)
                } else {
                    page.busy = false
                }
            }
            onSourceComponentChanged: {
                page.busy = false
                if (paneIn) paneIn.restart()
            }

            // 分区切换：新页淡入 + 上移 6px。
            // 只做入场不做交叉淡出——旧页在同一帧被替换掉，底色一致不会闪；
            // 壳的整页切换用 durPage(320)，这里 durBase(180)，两级动效层次分明不抢戏。
            transform: Translate { id: paneSlide; y: 0 }

            ParallelAnimation {
                id: paneIn
                NumberAnimation {
                    target: paneLoader; property: "opacity"
                    from: 0; to: 1
                    duration: Theme.durBase
                    easing.type: Theme.easeEnter
                }
                NumberAnimation {
                    target: paneSlide; property: "y"
                    from: 6; to: 0
                    duration: Theme.durBase
                    easing.type: Theme.easeEnter
                }
            }
        }
    }

    Component {
        id: quickComp
        VsQuickPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: overviewComp
        VsOverviewPane {
            versionId: page.versionId
            toast: page.toast
            // 概览页的「管理」行是无条件写死的（原版也会画 Mod 行），
            // 这里统一走 goTo，隐藏分区不切过去，避免内容区停在不存在的 key 上。
            onRequestPane: (k) => page.goTo(k)
        }
    }
    Component {
        id: launchComp
        VsLaunchPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: memoryComp
        VsMemoryPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: toolsComp
        VsToolsPane {
            versionId: page.versionId
            toast: page.toast
            // 版本被删掉后它的设置页没有意义，直接退回版本列表
            onRequestClose: page.close()
        }
    }
    Component {
        id: modsComp
        VsModsPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: shadersComp
        VsShadersPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: packsComp
        VsPacksPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: savesComp
        VsSavesPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: exportComp
        VsExportPane {
            versionId: page.versionId
            toast: page.toast
        }
    }
    Component {
        id: placeholderComp
        VsPlaceholderPane {
            versionId: page.versionId
            title: page.paneTitle(page.currentKey)
        }
    }
}
