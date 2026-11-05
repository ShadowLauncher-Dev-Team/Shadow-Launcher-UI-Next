// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
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
    readonly property bool narrow: width < 900
    readonly property int padH: narrow ? 32 : 72
    readonly property int padR: narrow ? 28 : 72
    readonly property int topH: narrow ? 56 : 64
    signal close()
    // 安装已启动：交给外壳切到独立的「下载进度」页（本页不再持有进度视图）
    signal openProgress()

    readonly property var releaseV: b ? b.releaseVersions : []
    readonly property var snapshotV: b ? b.snapshotVersions : []
    readonly property var oldV: b ? b.oldVersions : []
    readonly property var aprilV: b ? b.aprilFoolVersions : []
    readonly property var installedV: b ? b.installedVersions : []

    property int tab: 0
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

    // 已安装版本能反推出它用了哪些加载器（26.2-Forge_65.1.1 → Forge）。
    // 全量 chips 需要后端全局映射表，这里先给"已知"的，未知就不显示。
    function loadersOf(mc) {
        var out = []
        var ids = page.installedV
        for (var i = 0; i < ids.length; ++i) {
            var id = ids[i]
            if (id === mc) continue
            if (id.indexOf(mc + "-") !== 0) continue
            var suffix = id.substring(mc.length + 1).toLowerCase()
            if (suffix.indexOf("neoforge") >= 0 && out.indexOf("NeoForge") < 0) out.push("NeoForge")
            else if (suffix.indexOf("forge") >= 0 && out.indexOf("Forge") < 0) out.push("Forge")
            if (suffix.indexOf("fabric") >= 0 && out.indexOf("Fabric") < 0) out.push("Fabric")
            if (suffix.indexOf("optifine") >= 0 && out.indexOf("OptiFine") < 0) out.push("OptiFine")
        }
        return out
    }
    readonly property var dateMap: (function() {
        var m = {}
        var vl = page.b ? page.b.versionList : []
        for (var i = 0; i < vl.length; ++i) {
            var v = vl[i]
            if (v && v.id) m[v.id] = v.date || ""
        }
        return m
    })()

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
    function loaderSuffix() {
        if (page.activeLoader === "optifine")
            return "OptiFine_" + (page.selectedVersion.length > 0 ? page.selectedVersion : "latest")
        return page.activeLoader
    }

    function autoName() {
        if (page.picked.length === 0) return ""
        var suffix = page.loaderSuffix()
        return suffix.length > 0 ? (page.picked + "-" + suffix) : page.picked
    }

    // 同时写属性与输入框：TextInput.text 一旦被用户编辑过，绑定就断了，
    // 只改 instName 不会回显，所以这里显式双写。
    function applyName(n) {
        if (page.instName !== n) page.instName = n
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
        page.fabricApiVersion = ""
        page.fabricApiUrl = ""
        page.fabricApiFile = ""
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

    Component.onCompleted: {
        // 版本列表由 VersionBackend 在启动时自己刷新（日志"开始刷新版本列表"）；
        // 这里再同步调一次会让 QML 加载被后端解析阻塞 7 秒（首屏卡死的根因），故不再调用。
        if (Qt.application.arguments.indexOf("--ui-config") >= 0 && page.releaseV.length > 0)
            page.pickVersion(page.releaseV[0])
    }

    Connections {
        target: page.b
        function onForgeVersionsReady(v) { page.forgeList = v }
        function onNeoForgeVersionsReady(v) { page.neoforgeList = v }
        function onFabricVersionsReady(v) { page.fabricList = v }
        function onFabricApiVersionsReady(v) { page.fabricApiList = v }
        function onOptifineVersionsReady(v) { page.optifineList = v }
        function onInstalledVersionsChanged() { }
        function onCancelNotification(installId, message) {
            if (page.toast && message && message.length > 0)
                page.toast.show(message, 3000, "warning")
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ══════════ 顶部栏（两种状态共用同一高度，避免切换跳动）══════════
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: page.topH

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
        Row {
            visible: page.mode === 0
            anchors.left: topLeft.right
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: page.tabs
                delegate: Rectangle {
                    height: 30
                    width: tabTxt.implicitWidth + 22
                    radius: Theme.rSm
                    color: page.tab === index ? "#1b2433" : (tabHover.containsMouse ? "#12151c" : "transparent")
                    Text {
                        id: tabTxt
                        anchors.centerIn: parent
                        text: modelData
                        color: page.tab === index ? "#ffffff" : Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: page.tab === index ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: tabHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.tab = index
                    }
                }
            }
        }

        // 搜索 + 刷新（列表态）
        Row {
            visible: page.mode === 0 && page.tab === 0
            anchors.right: parent.right
            anchors.rightMargin: page.padR + 96
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                width: 200; height: 32; radius: Theme.rSm
                color: "#0d1016"
                border.color: searchInput.activeFocus ? Theme.accent : Theme.line2
                border.width: 1
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7
                    SIcon { name: "search"; size: 14; color: Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
                    TextInput {
                        id: searchInput
                        width: parent.width - 26
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.search
                        color: Theme.fg
                        selectionColor: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        clip: true
                        onTextChanged: page.search = text
                        Text {
                            visible: parent.text.length === 0
                            text: "搜索版本号"
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                    }
                }
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
                    onClicked: if (page.b) { page.b.refreshVersionList(); if (page.toast) page.toast.show("正在刷新版本列表", 1800, "info") }
                }
            }
        }
    }

    // ══════════ 列表态 ══════════
    Item {
        visible: page.mode === 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: page.padH
        anchors.rightMargin: page.padR
        anchors.topMargin: 20
        anchors.bottomMargin: 24

        // 未接入的 tab：只说事实
        Text {
            visible: page.tab !== 0
            anchors.centerIn: parent
            text: page.tabs[page.tab] + " 分类还未接入"
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 13
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

            Row {
                id: segContent
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: page.filters
                    delegate: Rectangle {
                        height: 28
                        width: segLabel.implicitWidth + segCnt.implicitWidth + 24
                        radius: 6
                        color: page.filter === modelData.key ? "#20262f" : "transparent"
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
                            onClicked: page.filter = modelData.key
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
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: page.pickVersion(page.releaseV[0])
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

                // 加载器 chips（仅显示已安装版本能确认的）
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 340
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: page.loadersOf(modelData)
                        delegate: Rectangle {
                            height: 18
                            width: lchip.implicitWidth + 12
                            radius: 4
                            color: "#101319"
                            border.color: "#242b36"
                            border.width: 1
                            Text {
                                id: lchip
                                anchors.centerIn: parent
                                text: modelData
                                color: "#9fa8b5"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
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
                    SIcon { name: "chevron-right"; size: 14; color: Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
                }

                MouseArea {
                    id: hoverCard
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.pickVersion(modelData)
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
        visible: page.mode === 1 || opacity > 0.01
        opacity: page.mode === 1 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: page.mode === 1 ? Theme.easeEnter : Theme.easeExit } }
        transform: Translate {
            x: page.mode === 1 ? 0 : 16
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
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        height: 34
                        radius: Theme.rSm
                        color: "#0d1016"
                        border.color: nameInput.activeFocus ? Theme.accent : Theme.line2
                        border.width: 1
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
                                color: Theme.fg3
                                rotation: page.expandedLoader === loaderCard.lkey ? 180 : 0
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
                                    width: loaderCard.width - 20
                                    x: 10
                                    height: 28
                                    radius: 6
                                    readonly property string ver: (typeof modelData === "string") ? modelData : (modelData.version || "")
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
                width: 120; height: 40; radius: Theme.rSm
                anchors.right: parent.right
                anchors.rightMargin: page.padR
                anchors.verticalCenter: parent.verticalCenter
                color: page.canInstall() ? Theme.accentTop : "#2a2f3a"
                Text {
                    anchors.centerIn: parent
                    text: page.canInstall() ? "开始安装"
                          : (page.activeLoader.length > 0 && page.selectedVersion.length === 0
                             ? "请选择版本" : "开始安装")
                    color: page.canInstall() ? "#ffffff" : Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: page.canInstall()
                    onClicked: page.startInstall()
                }
            }
        }
    }
}
