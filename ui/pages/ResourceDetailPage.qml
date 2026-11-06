// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import ShadowLauncher.Next

// 资源详情页（V2 定稿 2026-11-06）
// 交互顺序：① 游戏版本 → ② 加载器（选项来自该版本实际有文件的项）→ 只展示该组合最新文件
// 旧版本折叠；前置模组取自「该版本」的 dependencies，支持勾选后一键安装。
// 后端事实：无正文/图集/作者/已安装状态；下载路径由系统文件对话框决定。
Item {
    id: page
    property string kind: "mod"
    property var item: ({})
    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null
    signal back()

    readonly property string slug: item.slug || ""
    clip: true

    // 覆盖层必须自己铺不透明底色，否则会与下面资源库网格叠字
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        z: -1
    }
    property var versions: []
    property var gameList: []
    property var loaderList: []
    property string selGame: ""
    property string selLoader: ""
    property bool loading: false
    property bool showOld: false
    property var deps: []
    property var depChecked: ({})
    property bool depsLoading: false
    property var fileCache: ({})
    property var dlQueue: []
    property var pendingJob: null
    property string status: ""
    property bool depsOpen: false

    readonly property var comboList: {
        var out = []
        for (var i = 0; i < versions.length; ++i) {
            var v = versions[i]
            if (selGame.length > 0 && v.gameVersions.indexOf(selGame) < 0) continue
            if (selLoader.length > 0 && v.loaders.indexOf(selLoader) < 0) continue
            out.push(v)
        }
        out.sort(function(a, c) { return a.date < c.date ? 1 : (a.date > c.date ? -1 : 0) })
        return out
    }
    readonly property var latest: comboList.length > 0 ? comboList[0] : null
    readonly property int oldCount: comboList.length > 1 ? comboList.length - 1 : 0
    readonly property int reqCount: {
        var n = 0
        for (var i = 0; i < deps.length; ++i)
            if (deps[i].dependency_type === "required" && depChecked[deps[i].project_id]) n++
        return n
    }

    onItemChanged: Qt.callLater(page.loadVersions)
    Component.onCompleted: if (slug.length > 0) Qt.callLater(page.loadVersions)

    function loadVersions() {
        page.versions = []
        page.gameList = []
        page.loaderList = []
        page.deps = []
        page.selGame = ""
        page.selLoader = ""
        if (!page.b || slug.length === 0) return
        page.loading = true
        var isCf = /^[0-9]+$/.test(slug)
        if (page.kind === "mod") {
            if (isCf) page.b.fetchModVersionsCf(slug); else page.b.fetchModVersions([slug])
        } else if (page.kind === "modpack") {
            page.b.fetchModpackVersions(slug)
        } else if (page.kind === "shader") {
            if (isCf) page.b.fetchShaderVersionsCf(slug); else page.b.fetchShaderVersions([slug])
        } else if (page.kind === "resourcepack") {
            if (isCf) page.b.fetchResourcepackVersionsCf(slug); else page.b.fetchResourcepackVersions([slug])
        }
        page.loading = false
    }

    function joinList(v) {
        if (!v) return ""
        if (typeof v === "string") return v
        if (Array.isArray(v)) return v.join(", ")
        if (typeof v.length === "number") {
            var out = []
            for (var i = 0; i < v.length; ++i) out.push(String(v[i]))
            return out.join(", ")
        }
        return String(v)
    }

    function applyVersions(s, vers, details) {
        if (s !== page.slug) return
        var list = vers || []
        var arr = []
        var gset = {}
        for (var i = 0; i < list.length; ++i) {
            var key = list[i]
            var d = details[key] || ({})
            var gv = d.game_version || ""
            var ld = page.joinList(d.loaders)
            arr.push({
                id: d.id || "",
                version: d.version_number || key,
                date: (d.date_published || "").substring(0, 10),
                gameVersions: gv,
                loaders: ld,
                url: d.url || "",
                filename: d.filename || "",
                size: d.size || 0,
                sha1: d.sha1 || ""
            })
            if (gv.length > 0) gset[gv] = true
        }
        page.versions = arr
        var gs = []
        for (var g in gset) gs.push(g)
        gs.sort(function(a, c) {
            var aSnap = /[a-zA-Z]/.test(a)
            var cSnap = /[a-zA-Z]/.test(c)
            if (aSnap !== cSnap) return aSnap ? 1 : -1     // 稳定版在前
            var pa = a.split("."), pc = c.split(".")
            for (var i = 0; i < Math.max(pa.length, pc.length); ++i) {
                var na = parseInt(pa[i]) || 0, nc = parseInt(pc[i]) || 0
                if (na !== nc) return nc - na
            }
            return 0
        })
        page.gameList = gs
        if (gs.length > 0) page.selGame = gs[0]
        page.refreshLoaders()
    }

    function refreshLoaders() {
        if (page.selGame.length === 0) { page.loaderList = []; page.selLoader = ""; page.refreshDeps(); return }
        var set = {}
        for (var i = 0; i < page.versions.length; ++i) {
            var v = page.versions[i]
            if (v.gameVersions.indexOf(page.selGame) < 0) continue
            var parts = v.loaders.split(",")
            for (var k = 0; k < parts.length; ++k) {
                var t = parts[k].trim()
                if (t.length > 0) set[t] = true
            }
        }
        var ls = []
        for (var key in set) ls.push(key)
        ls.sort()
        page.loaderList = ls
        if (ls.length > 0 && ls.indexOf(page.selLoader) < 0) page.selLoader = ls[0]
        page.refreshDeps()
    }

    function onLoaderChanged() { page.refreshDeps() }

    function refreshDeps() {
        page.deps = []
        page.depChecked = {}
        page.depsOpen = false
        var v = page.latest
        if (!v || !page.b || v.id.length === 0) return
        page.depsLoading = true
        page.b.fetchVersionDependencies(page.slug, v.id)
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onModVersionsPartial(s, vers, details) { page.applyVersions(s, vers, details) }
        function onShaderVersionsPartial(s, vers, details) { page.applyVersions(s, vers, details) }
        function onResourcepackVersionsPartial(s, vers, details) { page.applyVersions(s, vers, details) }
        function onVersionDependenciesResolved(versionId, deps) {
            if (!page.latest || versionId !== page.latest.id) return
            page.depsLoading = false
            page.deps = deps || []
            var m = {}
            for (var i = 0; i < page.deps.length; ++i)
                if (page.deps[i].dependency_type === "required") m[page.deps[i].project_id] = true
            page.depChecked = m
        }
        function onVersionFileResolved(versionId, file) {
            var m = {}
            for (var k in page.fileCache) m[k] = page.fileCache[k]
            m[versionId] = file || ({})
            page.fileCache = m
            page.nextInQueue()
        }
    }

    function capLoader(s) { return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s }
    function fmtDl(n) {
        n = n || 0
        if (n >= 100000000) return (n / 100000000).toFixed(1) + " 亿"
        if (n >= 10000) return (n / 10000).toFixed(0) + " 万"
        return String(n)
    }
    function fmtSize(n) {
        if (!n || n <= 0) return "—"
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024) return (n / 1024).toFixed(0) + " KB"
        return n + " B"
    }

    function installLatest() {
        var v = page.latest
        if (!v || v.url.length === 0) { page.status = "该组合没有可下载文件"; return }
        page.pushJob(v.url, v.filename, v.size, v.sha1, v.version)
    }

    function installAll() {
        var v = page.latest
        if (!v || v.url.length === 0) { page.status = "该组合没有可下载文件"; return }
        page.pushJob(v.url, v.filename, v.size, v.sha1, v.version)
        for (var i = 0; i < page.deps.length; ++i) {
            var d = page.deps[i]
            if (d.dependency_type !== "required") continue
            if (!page.depChecked[d.project_id]) continue
            var cached = page.fileCache[d.version_id]
            if (cached && cached.url) page.pushJob(cached.url, cached.filename, cached.size, cached.sha1, d.version_number || "")
            else if (d.version_id) page.b.fetchVersionFile(d.version_id)
        }
    }

    function pushJob(url, filename, size, sha1, label) {
        var q = page.dlQueue.slice()
        q.push({ url: url, filename: filename || "download.jar", size: size || 0, sha1: sha1 || "", label: label || "" })
        page.dlQueue = q
        if (q.length === 1) page.nextInQueue()
    }

    function nextInQueue() {
        if (page.dlQueue.length === 0) return
        page.pendingJob = page.dlQueue[0]
        saveDialog.open()
    }

    function popQueue() {
        var q = page.dlQueue.slice(1)
        page.dlQueue = q
        page.pendingJob = null
        if (q.length > 0) page.nextInQueue()
        else page.status = "已提交下载"
    }

    FileDialog {
        id: saveDialog
        fileMode: FileDialog.SaveFile
        title: "选择保存位置"
        onAccepted: {
            var j = page.pendingJob
            if (j && page.b) {
                var path = String(selectedFile).replace(/^(file:\/{2,3})/i, "")
                page.b.downloadModFile(j.url, path, j.filename, j.size, j.sha1)
            }
            page.popQueue()
        }
        onRejected: page.popQueue()
    }

    // ── 返回 ──
    Rectangle {
        id: backBtn
        anchors.left: parent.left; anchors.top: parent.top
        anchors.leftMargin: 28; anchors.topMargin: 8
        width: 84; height: 26; radius: Theme.rSm
        color: backHover.containsMouse ? "#141922" : "transparent"
        border.width: 1; border.color: Theme.line2
        Text { anchors.centerIn: parent; text: "返回列表"; color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 11 }
        MouseArea { id: backHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.back() }
    }

    // ── 头部身份信息 ──
    Item {
        id: head
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.leftMargin: 28; anchors.rightMargin: 28; anchors.topMargin: 44
        height: 68
        Rectangle {
            id: headIcon
            width: 68; height: 68; radius: Theme.rMd; color: "#12161c"; clip: true
            Image { anchors.fill: parent; source: page.item.icon || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
        }
        Text {
            id: headTitle
            anchors.left: headIcon.right; anchors.leftMargin: 14; anchors.top: parent.top
            text: page.item.zh && page.item.zh.length > 0 ? page.item.zh : (page.item.title || "")
            color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 21; font.weight: Font.Bold
        }
        Rectangle {
            anchors.left: headTitle.right; anchors.leftMargin: 10
            anchors.verticalCenter: headTitle.verticalCenter
            width: srcTxt.implicitWidth + 14; height: 18; radius: 9
            color: page.item.source === "CurseForge" ? "#1a1409" : "#0d1a13"
            Text { id: srcTxt; anchors.centerIn: parent
                text: page.item.source === "CurseForge" ? "CurseForge" : "Modrinth"
                color: page.item.source === "CurseForge" ? Theme.warn : Theme.ok
                font.family: Theme.fontFamily; font.pixelSize: 10 }
        }
        Text {
            anchors.left: headIcon.right; anchors.leftMargin: 14; anchors.top: headTitle.bottom; anchors.topMargin: 6
            anchors.right: parent.right; anchors.rightMargin: 320
            text: page.item.desc || ""
            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 12
            elide: Text.ElideRight; maximumLineCount: 1
        }
    }

    // ── 右栏：本次安装（固定宽，先声明便于左列引用）──
    Item {
        id: rightCol
        anchors.right: parent.right; anchors.rightMargin: 28; anchors.top: head.bottom; anchors.topMargin: 16
        width: 264; height: 190
        Rectangle {
            id: installCard
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 172; radius: Theme.rSm
            color: "#0b0e13"; border.width: 1; border.color: Theme.line
            Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 16
                text: "本次安装"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                anchors.top: parent.top; anchors.topMargin: 44
                text: page.latest ? (page.latest.filename || "") : "未选择版本"
                color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 12
                elide: Text.ElideMiddle
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 64
                text: page.reqCount > 0 ? ("+ " + page.reqCount + " 个必需前置") : "无必需前置"
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11
            }
            SButton {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                anchors.top: parent.top; anchors.topMargin: 86
                implicitHeight: 36
                text: page.reqCount > 0 ? ("安装全部 " + (page.reqCount + 1) + " 项") : "下载并安装"
                enabled: page.latest !== null
                onClicked: page.installAll()
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                anchors.top: parent.top; anchors.topMargin: 134
                text: "每项下载时弹系统对话框，由你选保存位置"
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10
                wrapMode: Text.Wrap
            }
        }
        Text {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: installCard.bottom; anchors.topMargin: 10
            text: page.status.length > 0 ? page.status : "安装态只有 未安装 / 下载中 / 失败"
            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10; wrapMode: Text.Wrap
        }
    }

    // ── 左列 ──
    Item {
        id: leftCol
        anchors.left: parent.left; anchors.leftMargin: 28
        anchors.right: rightCol.left; anchors.rightMargin: 16
        anchors.top: head.bottom; anchors.topMargin: 16
        anchors.bottom: parent.bottom; anchors.bottomMargin: 20

        // ① 版本 ② 加载器
        Rectangle {
            id: pickCard
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 118; radius: Theme.rSm
            color: "#0b0e13"; border.width: 1; border.color: Theme.line

            Row {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 16
                spacing: 8
                Rectangle { width: 16; height: 16; radius: 3; color: "transparent"; border.width: 1; border.color: Theme.line2
                    Text { anchors.centerIn: parent; text: "1"; color: Theme.fg2; font.pixelSize: 10; font.family: Theme.fontFamily } }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "游戏版本"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
            }
            Rectangle {
                id: gameBox
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 40
                width: (parent.width - 48) * 0.55; height: 42; radius: Theme.rSm
                color: "#0d1016"; border.width: 1; border.color: gameHover.containsMouse ? Theme.line2 : Theme.line
                Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: page.selGame.length > 0 ? page.selGame : "选择版本"
                    color: page.selGame.length > 0 ? Theme.fg : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 14 }
                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: page.gameList.length + " 个"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                MouseArea { id: gameHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: gamePopup.open() }
            }
            Row {
                anchors.left: gameBox.right; anchors.leftMargin: 20; anchors.top: parent.top; anchors.topMargin: 16
                spacing: 8
                Rectangle { width: 16; height: 16; radius: 3; color: "transparent"; border.width: 1; border.color: Theme.line2
                    Text { anchors.centerIn: parent; text: "2"; color: Theme.fg2; font.pixelSize: 10; font.family: Theme.fontFamily } }
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: page.selGame.length === 0 ? "加载器（先选版本）" : "加载器"
                    color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
            }
            Rectangle {
                id: loaderBox
                anchors.left: gameBox.right; anchors.leftMargin: 20
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.top: parent.top; anchors.topMargin: 40
                height: 42; radius: Theme.rSm
                color: "#0d1016"; border.width: 1; border.color: loaderHover.containsMouse ? Theme.line2 : Theme.line
                opacity: page.selGame.length === 0 ? 0.5 : 1
                Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: page.selLoader.length > 0 ? page.capLoader(page.selLoader) : "选择加载器"
                    color: page.selLoader.length > 0 ? Theme.fg : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 14 }
                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: page.loaderList.length + " 个"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                MouseArea { id: loaderHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; enabled: page.selGame.length > 0; onClicked: loaderPopup.open() }
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                text: "加载器选项随所选版本变化；未选版本时第二步不可用"
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11
            }
        }

        // 可下载版本
        Rectangle {
            id: fileCard
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: pickCard.bottom; anchors.topMargin: 14
            height: 96; radius: Theme.rSm
            color: "#0b0e13"; border.width: 1; border.color: Theme.line
            Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 14
                text: "可下载版本"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { anchors.left: parent.left; anchors.leftMargin: 104; anchors.top: parent.top; anchors.topMargin: 16
                text: "该组合最新"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
            Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.top: parent.top; anchors.topMargin: 16
                text: page.latest ? (page.latest.date + " · " + page.fmtSize(page.latest.size)) : ""
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 38
                height: 1; color: Theme.line }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 18
                anchors.right: fileDownload.left; anchors.rightMargin: 12
                text: page.latest ? (page.latest.filename || page.latest.version) : "没有匹配的版本"
                color: page.latest ? Theme.fg : Theme.fg3
                font.family: Theme.fontFamily; font.pixelSize: 12; elide: Text.ElideMiddle
            }
            SButton {
                id: fileDownload
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 18
                implicitWidth: 76; implicitHeight: 30
                text: "下载"; enabled: page.latest !== null
                onClicked: page.installLatest()
            }
        }

        // 旧版本折叠
        Rectangle {
            id: oldBar
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: fileCard.bottom; anchors.topMargin: 10
            height: page.oldCount > 0 ? 40 : 0
            visible: page.oldCount > 0
            radius: Theme.rSm; color: "#0b0e13"; border.width: 1; border.color: Theme.line
            Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                text: "该组合下还有 " + page.oldCount + " 个旧版本"
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 12 }
            Text { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                text: page.showOld ? "收起" : "展开"; color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.showOld = !page.showOld }
        }

        // 前置
        Rectangle {
            id: depCard
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: oldBar.bottom; anchors.topMargin: 14
            height: 40 + Math.min(6, Math.max(1, page.deps.length)) * 42 + 30
            radius: Theme.rSm; color: "#0b0e13"; border.width: 1; border.color: Theme.line
            Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 14
                text: "此版本要求的前置"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 130; anchors.top: parent.top; anchors.topMargin: 16
                text: page.depsLoading ? "解析中" : (page.deps.length === 0 ? "无" : (page.reqCount + " 必需 · " + (page.deps.length - page.reqCount) + " 可选"))
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11
            }
            ListView {
                id: depList
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.topMargin: 40
                height: Math.min(6, Math.max(1, page.deps.length)) * 42
                clip: true; model: page.deps; spacing: 0
                delegate: Item {
                    width: depList.width; height: 42
                    Rectangle { width: parent.width; height: 1; color: Theme.line }
                    Rectangle {
                        id: cb
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 15; height: 15; radius: 3
                        color: page.depChecked[modelData.project_id] ? Theme.accent : "#101720"
                        border.width: page.depChecked[modelData.project_id] ? 0 : 1
                        border.color: Theme.line2
                        Text { anchors.centerIn: parent; visible: page.depChecked[modelData.project_id] === true
                            text: "v"; color: "#ffffff"; font.pixelSize: 9; font.family: Theme.fontFamily }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var m = {}
                                for (var k in page.depChecked) m[k] = page.depChecked[k]
                                m[modelData.project_id] = !m[modelData.project_id]
                                page.depChecked = m
                            } }
                    }
                    Text { anchors.left: cb.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        anchors.right: verText.left; anchors.rightMargin: 10
                        text: modelData.title || modelData.project_id || ""
                        color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 12; elide: Text.ElideRight }
                    Text { id: verText; anchors.right: typeText.left; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.version_number || ""; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text { id: typeText; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.dependency_type === "required" ? "必需" : "可选"
                        color: modelData.dependency_type === "required" ? Theme.warn : Theme.fg3
                        font.family: Theme.fontFamily; font.pixelSize: 11 }
                }
            }
            Text {
                id: depNote
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                text: "前置版本取自该模组版本的 dependencies，不是项目最新版"
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10
            }
        }
    }

    Popup {
        id: gamePopup
        x: 28 + 16; y: head.height + 44 + 16 + 40
        width: 320; height: Math.min(320, page.gameList.length * 32 + 8); padding: 4
        background: Rectangle { color: "#0d1016"; border.width: 1; border.color: Theme.line2; radius: Theme.rSm }
        contentItem: ListView {
            clip: true; model: page.gameList
            delegate: Rectangle {
                width: gamePopup.width - 8; height: 32; radius: 4
                color: gHover.containsMouse ? "#141c28" : "transparent"
                Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    text: modelData; color: page.selGame === modelData ? Theme.fg : Theme.fg2
                    font.family: Theme.fontFamily; font.pixelSize: 12 }
                MouseArea { id: gHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { page.selGame = modelData; page.refreshLoaders(); gamePopup.close() } }
            }
        }
    }

    Popup {
        id: loaderPopup
        x: 28 + 16 + (page.width - 56 - 32) * 0.55 + 20
        y: head.height + 44 + 16 + 40
        width: 240; height: Math.min(240, page.loaderList.length * 32 + 8); padding: 4
        background: Rectangle { color: "#0d1016"; border.width: 1; border.color: Theme.line2; radius: Theme.rSm }
        contentItem: ListView {
            clip: true; model: page.loaderList
            delegate: Rectangle {
                width: loaderPopup.width - 8; height: 32; radius: 4
                color: lHover.containsMouse ? "#141c28" : "transparent"
                Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    text: modelData; color: page.selLoader === modelData ? Theme.fg : Theme.fg2
                    font.family: Theme.fontFamily; font.pixelSize: 12 }
                MouseArea { id: lHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { page.selLoader = modelData; page.refreshDeps(); loaderPopup.close() } }
            }
        }
    }
}
