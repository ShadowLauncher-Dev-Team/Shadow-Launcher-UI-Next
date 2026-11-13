// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import ShadowLauncher.Next

// 资源详情页（全屏独立页，2026-11-06）
// 交互：① 选游戏版本 → ② 选加载器（只列该版本有文件的）→ 展示该组合最新文件 + 折叠旧版 + 前置
// 全页独立：打开时侧栏收起（StageShell 里 resDetailOpen 计入 fullOpen），整页 anchors.fill 整窗，
// 自带不透明底 + 全屏拦截层，不存在"点空白穿透到底层页面"。
Item {
    id: page
    property string kind: "mod"
    property var item: ({})
    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null
    signal back()
    // 本页发起的文件下载全部提交完毕（保存对话框都走完了）
    signal downloadsStarted()

    readonly property string slug: item.slug || ""
    readonly property int padL: narrow ? 32 : Theme.padL
    readonly property int padR: narrow ? 32 : Theme.padR
    // 窗口宽度而非自身宽度：侧栏收起/展开时自身宽度会变，用它判断会在动画最后一帧
    // 突然从宽布局切到窄布局（用户看到的「最后一刻震动卡一下」）
    readonly property bool narrow: (Window.window ? Window.window.width : width) < 900

    property var versions: []
    property var gameList: []
    property var loaderList: []
    property string selGame: ""
    property string selLoader: ""
    property bool loadingVersions: false
    property bool showOld: false
    property var deps: []
    property var depChecked: ({})
    property bool depsLoading: false
    property var fileCache: ({})
    property var dlQueue: []
    property var pendingJob: null
    property string status: ""
    // 批量下载：一次选文件夹，全部文件按各自文件名落盘（保存对话框一次只能选一个文件，
    // 逐个弹框既慢又不符合"一起下载"的语义）。
    property string targetDir: ""
    // 批量模式：第一份走"另存为"，其余用它的目录
    property bool batchMode: false
    property bool batchStarted: false
    property bool batchFilling: false
    property int planTotal: 0
    property bool dialogBusy: false
    property var planJobs: []
    property var pendingDeps: ({})
    // 入场：三段错峰浮现（选择器 → 文件卡 → 右栏），每段间隔 staggerStep。
    // 之前用一个 bool 在 visible 变化的同一帧里翻 true/false：组件先被打回 0 再抬起来，
    // 视觉上就是"整页抖一下"。现在用递增的段号，只往上走，不会来回翻。
    property int revealStep: 0
    function playReveal() {
        page.revealStep = 0
        revealTimer.restart()
    }
    onVisibleChanged: if (visible) page.playReveal()
    else page.revealStep = 0
    Timer {
        id: revealTimer
        interval: Theme.staggerStep
        repeat: true
        onTriggered: {
            if (page.revealStep < 3) page.revealStep++
            else revealTimer.stop()
        }
    }
    // 本页发起的文件下载（id 由 downloadModFile 返回）；数据表在 StageShell 里统一收
    property var fileDl: []
    property var myIds: []
    property int submitted: 0
    readonly property var myDls: {
        var out = []
        for (var i = 0; i < fileDl.length; ++i)
            if (myIds.indexOf(fileDl[i].id) >= 0) out.push(fileDl[i])
        return out
    }
    function dlLine(d) {
        if (d.state === "done") return qsTr("已完成 %1").arg(d.name || "")
        if (d.state === "fail") return qsTr("失败 %1").arg(d.name || "")
        var pct = d.total > 0 ? Math.round(d.received / d.total * 100) : 0
        var sp = d.speed > 0 ? (" · " + (d.speed / 1048576).toFixed(1) + " MB/s") : ""
        return qsTr("下载中 %1%2 %3").arg(pct).arg(sp).arg(d.name || "")
    }

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
    readonly property int checkedCount: {
        var n = 0
        for (var i = 0; i < deps.length; ++i)
            if (depChecked[deps[i].project_id]) n++
        return n
    }

    // 全屏拦截：底下的资源库列表不该收不到点击
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => { w.accepted = true } }

    Rectangle { anchors.fill: parent; color: Theme.bg; z: -1 }

    onItemChanged: Qt.callLater(page.loadVersions)
    Component.onCompleted: if (slug.length > 0) Qt.callLater(page.loadVersions)

    function loadVersions() {
        page.versions = []
        page.gameList = []
        page.loaderList = []
        page.deps = []
        page.depChecked = {}
        page.selGame = ""
        page.selLoader = ""
        if (!page.b || slug.length === 0) return
        page.loadingVersions = true
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
            arr.push({
                id: d.id || "",
                version: d.version_number || key,
                date: (d.date_published || "").substring(0, 10),
                gameVersions: gv,
                loaders: page.joinList(d.loaders),
                url: d.url || "",
                filename: d.filename || "",
                size: d.size || 0,
                sha1: d.sha1 || ""
            })
            if (gv.length > 0) gset[gv] = true
        }
        page.versions = arr
        page.loadingVersions = false
        var gs = []
        for (var g in gset) gs.push(g)
        gs.sort(function(a, c) {
            var aSnap = /[a-zA-Z]/.test(a)
            var cSnap = /[a-zA-Z]/.test(c)
            if (aSnap !== cSnap) return aSnap ? 1 : -1
            var pa = a.split("."), pc = c.split(".")
            for (var i2 = 0; i2 < Math.max(pa.length, pc.length); ++i2) {
                var na = parseInt(pa[i2]) || 0, nc = parseInt(pc[i2]) || 0
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

    function refreshDeps() {
        page.deps = []
        page.depChecked = {}
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
            // 必需项默认勾选；可选不勾
            for (var i = 0; i < page.deps.length; ++i)
                if (page.deps[i].dependency_type === "required") m[page.deps[i].project_id] = true
            page.depChecked = m
        }
        function onVersionFileResolved(versionId, file) {
            var m = {}
            for (var k in page.fileCache) m[k] = page.fileCache[k]
            m[versionId] = file || ({})
            page.fileCache = m
            // 有等待中的前置就入队（这是"模组 + 前置一起下载"真正被触发的地方）
            var pend = page.pendingDeps[versionId]
            if (pend && file && file.url) {
                var rest = {}
                for (var k2 in page.pendingDeps) if (k2 !== versionId) rest[k2] = page.pendingDeps[k2]
                page.pendingDeps = rest
                page.pushJob(file.url, file.filename || pend.filename, file.size || 0, file.sha1 || "", pend.label)
            }
        }
    }

    function capLoader(s) { return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s }
    function fmtSize(n) {
        if (!n || n <= 0) return ""
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024) return (n / 1024).toFixed(0) + " KB"
        return n + " B"
    }
    function fmtDl(n) {
        n = n || 0
        if (n >= 100000000) return qsTr("%1 亿").arg((n / 100000000).toFixed(1))
        if (n >= 10000) return qsTr("%1 万").arg((n / 10000).toFixed(0))
        return String(n)
    }

    function toggleDep(pid) {
        var m = {}
        for (var k in page.depChecked) m[k] = page.depChecked[k]
        m[pid] = !m[pid]
        page.depChecked = m
    }

    function installLatest() {
        page.submitted = 0
        page.dialogBusy = false
        page.dlQueue = []
        page.batchMode = false
        page.targetDir = ""          // 单文件：仍然走"另存为"
        var v = page.latest
        if (!v || v.url.length === 0) { page.status = qsTr("该组合没有可下载文件"); return }
        page.pushJob(v.url, v.filename, v.size, v.sha1, v.version)
    }

    // 本次要下载的全部条目（主文件 + 勾选的前置）。url 为空表示元数据还没解析出来。
    function buildJobs() {
        var jobs = []
        var v = page.latest
        if (v && v.url.length > 0)
            jobs.push({ versionId: "", label: v.version || "",
                        url: v.url, filename: v.filename || "download.jar",
                        size: v.size || 0, sha1: v.sha1 || "" })
        for (var i = 0; i < page.deps.length; ++i) {
            var d = page.deps[i]
            if (!page.depChecked[d.project_id]) continue
            var cached = page.fileCache[d.version_id] || null
            // 后端现在会直接带回前置文件（Modrinth 对多数前置不给 version_id，
            // 后端按 game_versions + loaders 自己查了版本 → url/filename/size/sha1）。
            // fileCache 是"用户点过前置卡片"时的补充来源。
            jobs.push({
                versionId: d.version_id || "",
                label: d.version_number || d.project_id || "",
                url: (cached && cached.url) ? cached.url : (d.url || ""),
                filename: (cached && cached.filename) ? cached.filename : (d.filename || ""),
                size: cached ? (cached.size || 0) : (d.size || 0),
                sha1: cached ? (cached.sha1 || "") : (d.sha1 || "")
            })
        }
        return jobs
    }

    function installAll() {
        page.submitted = 0
        // 复位上一次可能残留的对话框占用与队列（强行关闭对话框时回调可能不触发）
        page.dialogBusy = false
        page.dlQueue = []
        page.pendingJob = null
        if (page.depsLoading) { page.status = qsTr("前置还在解析，请稍候"); return }
        var jobs = page.buildJobs()
        if (jobs.length === 0) { page.status = qsTr("该组合没有可下载文件"); return }
        if (jobs.length === 1) {
            page.batchMode = false
            page.targetDir = ""
            page.planJobs = jobs
            page.startPlan()
            return
        }
        // 多个文件：弹一次"选择保存文件夹"（原生 QFileDialog，由后端 pickFolder 提供），
        // 选完目录后所有文件按各自文件名写进去，不再逐个弹框。
        page.planJobs = jobs
        page.planTotal = jobs.length
        var dir = page.b ? page.b.pickFolder(page.lastDir) : ""
        if (dir.length === 0) { page.planJobs = []; page.status = qsTr("已取消"); return }
        page.batchMode = true
        page.targetDir = dir
        page.lastDir = dir
        page.startPlan()
    }

    function startPlan() {
        var jobs = page.planJobs || []
        // 先把整批任务全部压进队列，再统一开跑：
        // 之前 pushJob 会立刻把"队列长度为 1"的任务发出去，于是第一个文件下载时队列又空了
        // → finishBatch() 提前触发（跳进度页），后续前置还没入队就被打断。
        page.batchFilling = true
        var missing = 0
        for (var i = 0; i < jobs.length; ++i) {
            var j = jobs[i]
            if (j.url.length > 0) {
                page.pushJob(j.url, j.filename, j.size, j.sha1, j.label)
            } else if (j.versionId.length > 0) {
                // 前置文件元数据未解析 → 先取，回来再入队
                var m = {}
                for (var k in page.pendingDeps) m[k] = page.pendingDeps[k]
                m[j.versionId] = j
                page.pendingDeps = m
                page.b.fetchVersionFile(j.versionId)
            } else {
                missing++
            }
        }
        page.batchFilling = false
        page.planJobs = []
        if (page.dlQueue.length > 0) page.nextInQueue()
        else page.status = missing > 0 ? qsTr("有前置缺少下载信息") : qsTr("没有可下载的文件")
    }

    function pushJob(url, filename, size, sha1, label) {
        var q = page.dlQueue.slice()
        q.push({ url: url, filename: filename || "download.jar", size: size || 0, sha1: sha1 || "", label: label || "" })
        page.dlQueue = q
        // 批量装填阶段不要自动开跑（由 startPlan 装完统一启动）
        if (q.length === 1 && !page.batchFilling) page.nextInQueue()
    }

    function nextInQueue() {
        if (page.dlQueue.length === 0 || page.dialogBusy) return
        var j = page.dlQueue[0]
        // 批量模式：目录已经选过，直接按文件名写盘，不再逐个弹对话框
        if (page.targetDir.length > 0) {
            var path = page.targetDir + "/" + j.filename
            var dlId = page.b.downloadModFile(j.url, path, j.filename, j.size, j.sha1)
            if (dlId > 0) { page.myIds = page.myIds.concat([dlId]); page.submitted++ }
            page.dlQueue = page.dlQueue.slice(1)
            page.pendingJob = null
            if (page.dlQueue.length > 0) page.nextInQueue()
            else page.finishBatch()
            return
        }
        page.pendingJob = j
        page.dialogBusy = true
        // 预填文件名：selectedFile 可写（Qt 6.8 FileDialog 暴露 setSelectedFile）
        saveDialog.selectedFile = "file:///" + (page.lastDir.length > 0 ? page.lastDir + "/" : "") + j.filename
        saveDialog.open()
    }

    function finishBatch() {
        page.batchMode = false
        page.status = qsTr("已提交 %1 个文件").arg(page.submitted)
        if (page.submitted > 0) page.downloadsStarted()
    }

    property string lastDir: ""
    function popQueue() {
        page.dialogBusy = false
        var q = page.dlQueue.slice(1)
        page.dlQueue = q
        page.pendingJob = null
        if (q.length > 0) page.nextInQueue()
        else {
            page.status = qsTr("已提交下载")
            if (page.submitted > 0) page.downloadsStarted()
        }
    }

    FileDialog {
        id: saveDialog
        fileMode: FileDialog.SaveFile
        // 批量时标题要说明"其余文件会存到同一目录"，避免用户以为还要再选 N 次
        title: page.batchMode
               ? qsTr("选择保存位置（共 %1 个文件，其余存入同一文件夹）").arg(page.planTotal)
               : qsTr("选择保存位置")
        onAccepted: {
            var j = page.pendingJob
            var p = String(selectedFile)
            var path = p.replace(/^file:\/{2,3}/i, "")
            var cut = path.lastIndexOf("/")
            if (cut > 0) {
                page.lastDir = path.substring(0, cut)
                // 批量模式：这一份选在哪，其余就写在哪，不再逐个弹框
                if (page.batchMode) page.targetDir = path.substring(0, cut)
            }
            if (j && page.b) {
                var dlId = page.b.downloadModFile(j.url, path, j.filename, j.size, j.sha1)
                if (dlId > 0) { page.myIds = page.myIds.concat([dlId]); page.submitted++ }
                if (page.toast) page.toast.show(qsTr("开始下载 %1").arg(j.filename), 2400, "info")
            }
            page.popQueue()
        }
        onRejected: {
            page.batchMode = false
            page.targetDir = ""
            page.dlQueue = []
            page.pendingJob = null
            page.dialogBusy = false
            page.status = qsTr("已取消")
        }
    }

    // ══ 顶栏：返回 ══
    Item {
        id: topBar
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 52

        // 空白处拖动窗口（无边框窗口没有系统标题栏，必须显式请求系统接管移动）。
        // 放在子项最前面：后面的按钮 / 搜索框都盖在它上面，控件照常响应，只有空白区能走到这里。
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: { if (backend) backend.beginWindowMove() }
        }

        Rectangle {
            id: backBtn
            anchors.left: parent.left; anchors.leftMargin: page.padL
            anchors.verticalCenter: parent.verticalCenter
            width: backRow.width + 20; height: 28; radius: Theme.rSm
            color: backHover.containsMouse ? Theme.bgCard : "transparent"
            border.width: 1; border.color: backHover.containsMouse ? Theme.line2 : Theme.line
            Row {
                id: backRow
                anchors.centerIn: parent
                spacing: 6
                SIcon { name: "arrow-left"; size: 13; color: Theme.fg2; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: qsTr("返回"); color: Theme.fg2
                    font.family: Theme.fontFamily; font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea { id: backHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.back() }
        }
    }

    // ══ 头部：身份 ══
    Item {
        id: head
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: topBar.bottom; anchors.topMargin: 4
        anchors.leftMargin: page.padL; anchors.rightMargin: page.padR
        height: 76

        Rectangle {
            id: headIcon
            width: 76; height: 76; radius: Theme.rMd; color: Theme.bgCard; clip: true
            Image {
                anchors.fill: parent
                source: page.item.icon || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        Text {
            id: headTitle
            anchors.left: headIcon.right; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 2
            text: page.item.zh && page.item.zh.length > 0 ? page.item.zh : (page.item.title || "")
            color: Theme.fg; font.family: Theme.fontFamily
            font.pixelSize: 22; font.weight: Font.Bold
        }
        Rectangle {
            id: srcBadge
            anchors.left: headTitle.right; anchors.leftMargin: 10
            anchors.verticalCenter: headTitle.verticalCenter
            width: srcTxt.implicitWidth + 16; height: 20; radius: 10
            color: page.item.source === "CurseForge" ? Theme.warn : Theme.bgCard2
            Text {
                id: srcTxt
                anchors.centerIn: parent
                text: page.item.source === "CurseForge" ? "CurseForge" : "Modrinth"
                color: page.item.source === "CurseForge" ? Theme.warn : Theme.ok
                font.family: Theme.fontFamily; font.pixelSize: 10
            }
        }
        Text {
            id: headDesc
            anchors.left: headIcon.right; anchors.leftMargin: 16
            anchors.top: headTitle.bottom; anchors.topMargin: 8
            anchors.right: headStats.left; anchors.rightMargin: 24
            text: page.item.desc || ""
            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 12
            elide: Text.ElideRight; maximumLineCount: 1
        }
        Row {
            id: headStats
            anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 4
            spacing: 18
            Column {
                spacing: 2
                Text { text: page.fmtDl(page.item.downloads); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 13 }
                Text { text: qsTr("下载量"); color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10 }
            }
            Column {
                spacing: 2
                Text { text: page.versions.length.toString(); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 13 }
                Text { text: qsTr("版本"); color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10 }
            }
            Column {
                spacing: 2
                Text {
                    text: (page.item.dateModified || "").substring(0, 10)
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 13
                }
                Text { text: qsTr("更新"); color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10 }
            }
        }
    }

    // ══ 内容 ══
    Item {
        id: content
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: head.bottom; anchors.topMargin: 12
        anchors.bottom: parent.bottom; anchors.bottomMargin: 24
        anchors.leftMargin: page.padL; anchors.rightMargin: page.padR

        // ── 右栏：本次安装 ──
        Item {
            id: rightRail
            anchors.right: parent.right; anchors.top: parent.top
            width: page.narrow ? 232 : 280
            height: installCard.height + 4
            opacity: page.revealStep >= 3 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
            transform: Translate {
                x: page.revealStep >= 3 ? 0 : 16
                Behavior on x { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
            }

            Rectangle {
                id: installCard
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 168 + Math.min(4, page.myDls.length) * 15; radius: Theme.rSm
                color: Theme.bgCard2; border.width: 1; border.color: Theme.line

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 16
                    text: qsTr("本次安装"); color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.top: parent.top; anchors.topMargin: 42
                    text: page.latest ? (page.latest.filename || "") : qsTr("未选择版本")
                    color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 12
                    elide: Text.ElideMiddle
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 16
                    anchors.top: parent.top; anchors.topMargin: 62
                    visible: page.reqCount > 0
                    text: qsTr("+ %1 个必需前置").arg(page.reqCount)
                    color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11
                }
                SButton {
                    anchors.left: parent.left; anchors.leftMargin: 16
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.top: parent.top; anchors.topMargin: 88
                    implicitHeight: 38
                    text: page.reqCount > 0 ? qsTr("下载 %1 个文件").arg(page.reqCount + 1) : qsTr("下载")
                    enabled: page.latest !== null
                    onClicked: page.installAll()
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.top: parent.top; anchors.topMargin: 136
                    visible: page.myDls.length === 0
                    text: page.status.length > 0 ? page.status
                          : (page.reqCount > 0 ? qsTr("多文件：选一次文件夹，全部存入") : qsTr("下载时由你选择保存位置"))
                    color: Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 10
                    elide: Text.ElideRight
                }
                // 本页发起的下载：就地显示，不用退出去看下载进度
                Column {
                    anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.top: parent.top; anchors.topMargin: 136
                    spacing: 3
                    Repeater {
                        model: page.myDls.slice(0, 4)
                        delegate: Text {
                            width: parent.width
                            text: page.dlLine(modelData)
                            color: modelData.state === "done" ? Theme.ok
                                 : (modelData.state === "fail" ? Theme.dangerText : Theme.accentText)
                            font.family: Theme.fontFamily; font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // ── 左列 ──
        Item {
            id: leftCol
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.right: rightRail.left; anchors.rightMargin: 20

            // ①② 选择器
            Rectangle {
                id: pickCard
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 124; radius: Theme.rSm
                color: Theme.bgCard2; border.width: 1; border.color: Theme.line
                opacity: page.revealStep >= 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                transform: Translate {
                    y: page.revealStep >= 1 ? 0 : 12
                    Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                }

                Text {
                    id: gLabel
                    anchors.left: parent.left; anchors.leftMargin: 18; anchors.top: parent.top; anchors.topMargin: 16
                    text: qsTr("游戏版本"); color: Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 11
                }
                Rectangle {
                    id: gameBox
                    anchors.left: parent.left; anchors.leftMargin: 18; anchors.top: gLabel.bottom; anchors.topMargin: 8
                    width: (parent.width - 46) * 0.5; height: 40; radius: Theme.rSm
                    color: Theme.bgCard2; border.width: 1
                    border.color: gameHover.containsMouse ? Theme.line2 : Theme.line
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        text: page.selGame.length > 0 ? page.selGame : qsTr("选择版本")
                        color: page.selGame.length > 0 ? Theme.fg : Theme.fg3
                        font.family: Theme.fontFamily; font.pixelSize: 13
                    }
                    SIcon {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down"; size: 12; color: Theme.fg3
                    }
                    MouseArea {
                        id: gameHover; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // 再点一次收起（之前只会 open，closePolicy 又不覆盖触发框本身 → 永远展不开/收不回）
                        onClicked: gamePopup.opened ? gamePopup.close() : gamePopup.open()
                    }
                }
                Text {
                    id: lLabel
                    anchors.left: gameBox.right; anchors.leftMargin: 18; anchors.top: parent.top; anchors.topMargin: 16
                    text: qsTr("加载器"); color: page.selGame.length === 0 ? Theme.fg3 : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 11
                }
                Rectangle {
                    id: loaderBox
                    anchors.left: gameBox.right; anchors.leftMargin: 18
                    anchors.right: parent.right; anchors.rightMargin: 18
                    anchors.top: lLabel.bottom; anchors.topMargin: 8
                    height: 40; radius: Theme.rSm
                    color: Theme.bgCard2; border.width: 1
                    border.color: loaderHover.containsMouse ? Theme.line2 : Theme.line
                    opacity: page.selGame.length === 0 ? 0.45 : 1
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        text: page.selLoader.length > 0 ? page.capLoader(page.selLoader) : qsTr("先选版本")
                        color: page.selLoader.length > 0 ? Theme.fg : Theme.fg3
                        font.family: Theme.fontFamily; font.pixelSize: 13
                    }
                    SIcon {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down"; size: 12; color: Theme.fg3
                    }
                    MouseArea {
                        id: loaderHover; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: page.selGame.length > 0
                        onClicked: loaderPopup.opened ? loaderPopup.close() : loaderPopup.open()
                    }
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 18
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                    text: page.loadingVersions ? qsTr("正在读取版本…")
                        : (page.selGame.length === 0 ? qsTr("选择版本后，加载器只列出该版本实际有文件的项")
                           : qsTr("%1 个加载器 · 该组合 %2 个版本").arg(page.loaderList.length).arg(page.comboList.length))
                    color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10
                }
            }

            // 可下载版本
            Rectangle {
                id: fileCard
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: pickCard.bottom; anchors.topMargin: 12
                height: 92; radius: Theme.rSm
                color: Theme.bgCard2; border.width: 1; border.color: Theme.line
                opacity: (page.revealStep >= 2 ? 1 : 0)
                Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                transform: Translate {
                    y: page.revealStep >= 2 ? 0 : 12
                    Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                }

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 18; anchors.top: parent.top; anchors.topMargin: 14
                    text: qsTr("可下载版本"); color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 98; anchors.top: parent.top; anchors.topMargin: 16
                    text: page.oldCount > 0 ? qsTr("最新 · 另有 %1 个旧版").arg(page.oldCount) : qsTr("最新")
                    color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 18; anchors.top: parent.top; anchors.topMargin: 16
                    text: page.latest ? ((page.latest.date || "") + "   " + page.fmtSize(page.latest.size)) : ""
                    color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10
                }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 40
                    height: 1; color: Theme.line
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 18
                    anchors.top: parent.top; anchors.topMargin: 54
                    anchors.right: dlBtn.left; anchors.rightMargin: 16
                    text: page.latest ? (page.latest.filename || page.latest.version) : qsTr("没有匹配的文件")
                    color: page.latest ? Theme.fg : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 12
                    elide: Text.ElideMiddle
                }
                SButton {
                    id: dlBtn
                    anchors.right: parent.right; anchors.rightMargin: 18
                    anchors.top: parent.top; anchors.topMargin: 50
                    implicitWidth: 88; implicitHeight: 32
                    radius: Theme.rSm
                    text: qsTr("下载")
                    enabled: page.latest !== null
                    onClicked: page.installLatest()
                }
            }

            // 旧版本：折叠，点开才显示（不再把 30+ 个版本一次铺出来）
            Item {
                id: oldBox
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: fileCard.bottom; anchors.topMargin: 10
                visible: page.oldCount > 0
                height: page.oldCount > 0 ? (oldHead.height + (page.showOld ? Math.min(6, page.oldCount) * 38 : 0)) : 0

                Rectangle {
                    id: oldHead
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    height: 38; radius: Theme.rSm
                    color: oldHover.containsMouse ? Theme.bgCard2 : Theme.bgCard2
                    border.width: 1; border.color: oldHover.containsMouse ? Theme.line2 : Theme.line
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("该组合下还有 %1 个旧版本").arg(page.oldCount)
                        color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.showOld ? qsTr("收起") : qsTr("展开")
                        color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 11
                    }
                    MouseArea {
                        id: oldHover
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.showOld = !page.showOld
                    }
                }

                ListView {
                    id: oldList
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: oldHead.bottom; anchors.topMargin: 4
                    height: page.showOld ? Math.min(6, page.oldCount) * 38 : 0
                    visible: page.showOld
                    clip: true
                    model: page.showOld ? page.comboList.slice(1) : []
                    interactive: false
                    delegate: Item {
                        width: oldList.width; height: 38
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 18
                            anchors.right: oldDl.left; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.filename || modelData.version
                            color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.date
                            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                        SButton {
                            id: oldDl
                            anchors.right: parent.right; anchors.rightMargin: 78
                            anchors.verticalCenter: parent.verticalCenter
                            visible: false
                            text: qsTr("下载")
                        }
                    }
                }
            }

            // 前置（没有就不显示）
            Rectangle {
                id: depCard
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: oldBox.bottom; anchors.topMargin: 12
                height: 44 + page.deps.length * 44
                visible: page.deps.length > 0
                radius: Theme.rSm
                color: Theme.bgCard2; border.width: 1; border.color: Theme.line

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 18; anchors.top: parent.top; anchors.topMargin: 14
                    text: qsTr("前置模组"); color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                ListView {
                    id: depList
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 44
                    height: page.deps.length * 44
                    clip: true
                    model: page.deps
                    interactive: false
                    delegate: Item {
                        width: depList.width; height: 44
                        Rectangle {
                            anchors.left: parent.left; anchors.leftMargin: 18
                            anchors.right: parent.right; anchors.rightMargin: 18
                            height: 1; color: Theme.line
                        }
                        Rectangle {
                            id: cb
                            x: 18; anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 4
                            color: page.depChecked[modelData.project_id] ? Theme.accent : "transparent"
                            border.width: page.depChecked[modelData.project_id] ? 0 : 1
                            border.color: Theme.line2
                            SIcon {
                                anchors.centerIn: parent
                                name: "check"; size: 11; color: Theme.accentFg
                                visible: page.depChecked[modelData.project_id] === true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.toggleDep(modelData.project_id)
                            }
                        }
                        Rectangle {
                            x: 44; anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: Theme.rSm; color: Theme.bgCard; clip: true
                            Image {
                                anchors.fill: parent
                                // 原始 cdn 是 .webp，Qt 解不了 → 走司南缓存换成可解码的本地路径
                                source: (page.b && modelData.icon_url)
                                        ? page.b.resolveIconUrl(modelData.icon_url) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 78
                            anchors.right: depVer.left; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title || modelData.project_id || ""
                            color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            id: depVer
                            anchors.right: depType.left; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.version_number || ""
                            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                        Text {
                            id: depType
                            anchors.right: parent.right; anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.dependency_type === "required" ? qsTr("必需") : qsTr("可选")
                            color: modelData.dependency_type === "required" ? Theme.warn : Theme.fg3
                            font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    // ══ 下拉：Popup 挂在触发框上，位置天然跟随，不会盖住触发框 ══
    Popup {
        id: gamePopup
        parent: gameBox
        x: 0
        y: gameBox.height + 6
        width: gameBox.width
        height: Math.min(300, page.gameList.length * 34 + 8)
        padding: 4
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
        // 开合动效：淡入 + 从触发框下方 6px 落下（原先 Popup 直接弹出来，没有任何过渡）
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { target: gamePopup.contentItem; property: "opacity"; from: 0; to: 1; duration: Theme.durFast; easing.type: Theme.easeEnter }
                NumberAnimation { target: gamePopup; property: "y"; from: gameBox.height; to: gameBox.height + 6; duration: Theme.durBase; easing.type: Theme.easeEnter }
            }
        }
        exit: Transition {
            NumberAnimation { target: gamePopup.contentItem; property: "opacity"; from: 1; to: 0; duration: Theme.durFast; easing.type: Theme.easeExit }
        }
        background: Rectangle { color: Theme.bgCard2; border.width: 1; border.color: Theme.line2; radius: Theme.rSm }
        contentItem: ListView {
            clip: true
            model: page.gameList
            delegate: Rectangle {
                width: gamePopup.width - 8; height: 34; radius: 4
                color: page.selGame === modelData ? Theme.accentSoft : (gHover.containsMouse ? Theme.accentSoft : "transparent")
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: page.selGame === modelData ? Theme.fg : Theme.fg2
                    font.family: Theme.fontFamily; font.pixelSize: 12
                }
                MouseArea {
                    id: gHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.selGame = modelData; page.refreshLoaders(); gamePopup.close() }
                }
            }
        }
    }

    Popup {
        id: loaderPopup
        parent: loaderBox
        x: 0
        y: loaderBox.height + 6
        width: loaderBox.width
        height: Math.min(220, page.loaderList.length * 34 + 8)
        padding: 4
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { target: loaderPopup.contentItem; property: "opacity"; from: 0; to: 1; duration: Theme.durFast; easing.type: Theme.easeEnter }
                NumberAnimation { target: loaderPopup; property: "y"; from: loaderBox.height; to: loaderBox.height + 6; duration: Theme.durBase; easing.type: Theme.easeEnter }
            }
        }
        exit: Transition {
            NumberAnimation { target: loaderPopup.contentItem; property: "opacity"; from: 1; to: 0; duration: Theme.durFast; easing.type: Theme.easeExit }
        }
        background: Rectangle { color: Theme.bgCard2; border.width: 1; border.color: Theme.line2; radius: Theme.rSm }
        contentItem: ListView {
            clip: true
            model: page.loaderList
            delegate: Rectangle {
                width: loaderPopup.width - 8; height: 34; radius: 4
                color: page.selLoader === modelData ? Theme.accentSoft : (lHover.containsMouse ? Theme.accentSoft : "transparent")
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.capLoader(modelData)
                    color: page.selLoader === modelData ? Theme.fg : Theme.fg2
                    font.family: Theme.fontFamily; font.pixelSize: 12
                }
                MouseArea {
                    id: lHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.selLoader = modelData; page.refreshDeps(); loaderPopup.close() }
                }
            }
        }
    }
}
