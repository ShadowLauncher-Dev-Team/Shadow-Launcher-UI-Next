// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本管理（第一版：主从详情）
// 数据全部来自 backend.versionDetails（后端扫 versions/ 目录得到）：
//   id / mcVersion / loaderType / loaderVersion / versionType / sizeBytes / modCount
//   / isModpack / modpackIconPath / releaseTimeMs
// 上次游玩逐版本来自 backend.lastPlayedLabelFor(id)（只有启动器真起过游戏才有记录）
// 本页不写死任何版本名，不做动效（等动效系统统一接入）
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: page

    signal close()
    /// 打开某个版本的版本设置（StageShell 接管为全屏页）
    signal openSettings(string versionId)

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var details: (b && b.versionDetails) ? b.versionDetails : []
    // 选择器语义：点列表只改「待选」，点「确定」才写回 selectedVersion；返回 = 取消
    property string pendingId: (b && b.selectedVersion) ? b.selectedVersion : ""
    readonly property string currentId: (b && b.selectedVersion) ? b.selectedVersion : ""
    property bool folderMenuOpen: false
    readonly property bool busy: b ? b.launching : false
    property string query: ""
    property var toast: null          // StageShell 注入的 ToastHost：反馈统一走 Toast
    property int rev: 0            // 递增以强制重算"上次游玩"等非绑定字段

    // ── 整合包导入 ──
    // ShadowBackend 以 Q_PROPERTY(QObject* modpackImporter) 暴露 ModpackImporter 实例，
    // gameDir / VersionBackend / 隔离策略都已由后端注入，这里只负责「选文件 → startImport」。
    readonly property var importer: (b && b.modpackImporter) ? b.modpackImporter : null
    readonly property bool importing: page.importer ? page.importer.busy === true : false
    readonly property real importProgress: {
        if (!page.importing) return 0
        var p = Number(page.importer.progress)
        if (!(p >= 0)) return 0
        return p > 1 ? 1 : p
    }
    readonly property string importStatus: page.importing ? String(page.importer.statusText || "") : ""
    // 导入成功后要自动选中的版本 id：等 versionDetails 新数据到达再落地，
    // 否则会被 syncPendingFromList（rows 变化时把不存在的 pendingId 退回第一项）冲掉。
    property string selectAfterRefresh: ""

    // ── 自动刷新（进入页面拉一次，避免"装完新版本回来还是旧列表"）──
    // 这个页面实例是常驻的（StageShell 只切宿主 visible），Component.onCompleted 只在启动时跑一次，
    // 所以真正的刷新时机是「变可见」。用陈旧阈值节流：窗口期内反复进出不再重复请求后端。
    readonly property int staleMs: 10000
    property double lastRefreshAt: 0
    // 后端自己的扫描状态（ShadowBackend::isScanningVersions）：扫描还在飞时不再叠请求，
    // 否则页面上反复进出会排队打一堆 refreshVersionDetails。
    readonly property bool scanning: page.b !== null && page.b.isScanningVersions === true
    // 扫描中没排上的"强制刷新"（装完/导入完必须看到新版本），等扫描结束再补一次
    property bool forceRefreshPending: false

    readonly property bool narrow: width < 900
    readonly property int leftW: narrow ? 268 : 336
    readonly property real coverH: narrow ? 128 : 200
    readonly property int infoRowH: narrow ? 34 : 44
    // 列表行高/间距：滑动指示条要靠这两个值算位置，所以提取成常量（delegate 与指示条共用）
    readonly property int listRowH: 60
    readonly property int listRowGap: 2

    // ── 过滤 + 排序（版本发布时间倒序）──
    readonly property var rows: {
        rev
        var src = details || []
        var q = query.trim().toLowerCase()
        var out = []
        for (var i = 0; i < src.length; i++) {
            var v = src[i]
            if (!v) continue
            if (q.length > 0) {
                var hay = ((v.id || "") + " " + (v.mcVersion || "") + " "
                           + (v.loaderType || "") + " " + (v.loaderVersion || "")).toLowerCase()
                if (hay.indexOf(q) < 0) continue
            }
            out.push(v)
        }
        out.sort(function (a, c) { return (c.releaseTimeMs || 0) - (a.releaseTimeMs || 0) })
        return out
    }

    // ── 当前选中的版本详情 ──
    readonly property var sel: {
        rev
        var list = rows
        for (var i = 0; i < list.length; i++)
            if (list[i] && list[i].id === page.pendingId) return list[i]
        return list.length > 0 ? list[0] : null
    }

    // ---- 右侧信息的"显示态" ----
    // pendingId 一变，文本绑定会当场换成新内容；如果这时才去播"压暗→淡回"，
    // 看到的就是新内容先亮一下再闪一下（用户形容为"向上抽搐"）。
    // 所以拆成 shownId：先淡出 → 在透明时换 shownId → 再淡入，全程不闪。
    property string shownId: ""
    readonly property var shownSelLive: {
        rev
        var list = rows
        for (var i = 0; i < list.length; i++)
            if (list[i] && list[i].id === page.shownId) return list[i]
        return list.length > 0 ? list[0] : null
    }
    // 后端刷新详情时 rows 会整段重算，过程中可能出现一瞬 shownSelLive 为空；
    // 记住最后一次有效选中，避免右侧"最后一帧闪一下空白"。
    property var shownSnapshot: null
    readonly property var shownSel: shownSelLive || shownSnapshot
    onShownSelLiveChanged: if (shownSelLive) page.shownSnapshot = shownSelLive

    // 右侧信息行：模型用"固定键数组"，行只建一次；
    // 数值变化走绑定（infoValue），不重建 delegate —— 之前每次刷新都会整列重建才闪。
    readonly property var infoKeys: ["version", "mc", "loader", "type", "mods", "size", "last", "dir"]
    function infoLabel(key) {
        if (key === "version") return qsTr("版本名")
        if (key === "mc") return qsTr("MC 版本")
        if (key === "loader") return qsTr("加载器")
        if (key === "type") return qsTr("版本类型")
        if (key === "mods") return qsTr("模组")
        if (key === "size") return qsTr("大小")
        if (key === "last") return qsTr("上次游玩")
        if (key === "dir") return qsTr("游戏目录")
        return key
    }
    function infoValue(key) {
        var s = page.shownSel
        if (!s) return ""
        if (key === "version") return s.id || ""
        if (key === "mc") {
            var mc = page.mcOf(s)
            return mc.length > 0 ? mc : qsTr("未识别")
        }
        if (key === "loader") return page.loaderOf(s)
        if (key === "type") return s.isModpack ? qsTr("%1 · 整合包").arg(page.typeText(s)) : page.typeText(s)
        if (key === "mods") return Number(s.modCount) > 0 ? qsTr("%1 个").arg(s.modCount) : qsTr("无模组")
        if (key === "size") return page.sizeText(s.sizeBytes)
        if (key === "last") {
            var lp = page.lastPlayedOf(s)
            return lp.length > 0 ? lp : qsTr("没有记录")
        }
        if (key === "dir") return page.b ? page.b.getVersionGameDir(s.id) : ""
        return ""
    }

    // 切文件夹后后端会重扫版本列表，原来选中的 id 可能不存在了 ——
    // 这时后端会退回"列表第一个"，但 QML 的 pendingId 还是旧 id，
    // 于是右侧显示第一个版本、左侧却一根选中条都没有。这里跟着同步。
    function syncPendingFromList() {
        if (page.rows.length === 0) return
        if (page.rowIndex(page.pendingId) >= 0) return
        page.pendingId = page.rows[0].id
    }

    // ── 游戏文件夹（多个 .minecraft 之间切换）──
    readonly property var mcFolder: (b && b.mcFolder) ? b.mcFolder : null
    readonly property var folders: {
        page.rev
        return page.mcFolder ? (page.mcFolder.folders || []) : []
    }
    readonly property string folderLabel: {
        page.rev
        var fs = page.folders
        for (var i = 0; i < fs.length; ++i)
            if (fs[i] && fs[i].active) return fs[i].name || fs[i].path
        return (page.b && page.b.gameDir) ? page.b.gameDir : qsTr("游戏文件夹")
    }
    function switchFolder(path, isDefault) {
        if (!page.mcFolder || !page.b) return
        page.folderMenuOpen = false
        // setActiveFolder 是有返回值的：目录不存在 / 识别不出 .minecraft 会返回 false。
        // 以前不管成败都提示"已切换"，失败时用户会以为切了但其实没切。
        var ok = true
        if (isDefault) page.mcFolder.revertToDefault()
        else ok = page.mcFolder.setActiveFolder(path)
        if (!ok) { page.flash(qsTr("切换失败：这个文件夹不是有效的游戏目录")); return }
        page.b.refreshVersionDetails()
        page.rev++
        page.flash(isDefault ? qsTr("已切回默认游戏目录") : qsTr("已切换游戏文件夹"))
    }
    function addFolder() {
        if (!page.mcFolder) return
        var p = page.mcFolder.pickFolderDialog()
        if (!p || p.length === 0) return
        var nm = String(p).replace(/\\/g, "/").split("/").pop()
        page.mcFolder.addGameFolder(p, nm)
        page.mcFolder.refreshFolders()
        page.folderMenuOpen = false
        page.flash(qsTr("已添加文件夹 %1").arg(nm))
    }
    function commit() {
        if (!page.b || !page.sel) return
        if (page.pendingId !== page.currentId) {
            page.b.setSelectedVersion(page.pendingId)
            // 页面随即关闭，Toast 是唯一的"确实换了"的确认
            page.flash(qsTr("已切换到 %1").arg(page.pendingId))
        }
        page.close()
    }

    // ── 格式化 ──
    function sizeText(bytes) {
        var n = Number(bytes) || 0
        if (n <= 0) return "—"
        if (n < 1024 * 1024) return (n / 1024).toFixed(0) + " KB"
        if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(0) + " MB"
        return (n / (1024 * 1024 * 1024)).toFixed(1) + " GB"
    }
    // MC 版本：后端认不出时为空（不拿目录名冒充）。空就只显示加载器。
    function mcOf(v) {
        if (!v || !v.mcVersion) return ""
        return v.mcVersion
    }
    function subOf(v) {
        var mc = page.mcOf(v)
        var ldr = page.loaderOf(v)
        return mc.length > 0 ? (mc + " · " + ldr) : ldr
    }
    // 详情大标题：优先 MC 版本；认不出时退回版本名（那是真实存在的那个名字）
    readonly property string selTitle: {
        if (!sel) return "—"
        var mc = page.mcOf(sel)
        return mc.length > 0 ? mc : (sel.id || "—")
    }
    function loaderOf(v) {
        if (!v) return ""
        var lt = v.loaderType || ""
        if (lt.length === 0) return qsTr("原版")
        var lv = v.loaderVersion || ""
        return lv.length > 0 ? (lt + " " + lv) : lt
    }
    function typeText(v) {
        if (!v) return ""
        if (v.versionType === "snapshot") return qsTr("快照版")
        if (v.versionType === "old") return qsTr("旧版")
        return qsTr("正式版")
    }
    function lastPlayedOf(v) {
        rev
        if (!v || !b) return ""
        return b.lastPlayedLabelFor(v.id)
    }
    function iconOf(v) {
        if (!v) return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/Grass.png"
        if (v.isModpack && v.modpackIconPath && v.modpackIconPath.length > 0) return v.modpackIconPath
        var lt = v.loaderType || ""
        if (lt === "Fabric") return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/Fabric.png"
        if (lt === "Quilt") return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/RedstoneBlock.png"
        if (lt === "Forge") return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/Anvil.png"
        if (lt === "NeoForge") return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/NeoForge.png"
        if (lt === "OptiFine" || lt === "OptiFabric") return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/OptiFabric.png"
        if (v.versionType === "snapshot") return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/CommandBlock.png"
        if (v.versionType === "old") return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/CobbleStone.png"
        return "qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/Grass.png"
    }
    // 反馈统一走 Toast：以前写进顶栏 label，一出现就把右侧按钮挤走（控件错位），
    // 而且返回启动页后再也看不到"到底刷新了什么"。
    function flash(msg) { if (page.toast) page.toast.show(msg) }

    // ── 刷新：手动 / 自动共用 ──
    // 自动只扫本地 versions/（远端清单只有手动刷新才需要），并受陈旧阈值 + in-flight 双重节流。
    // force=true 用于"数据一定变了"的场合（导入完整合包），会绕过陈旧阈值。
    function refreshLocal(force) {
        if (!page.b) return false
        // 上一次扫描还没结束：不并发发起第二次；强制刷新记下来，等扫描完补发
        if (page.scanning) {
            if (force) page.forceRefreshPending = true
            return false
        }
        var now = Date.now()
        if (!force && page.details.length > 0 && (now - page.lastRefreshAt) < page.staleMs) return false
        page.lastRefreshAt = now
        page.b.refreshVersionDetails()
        return true
    }
    function refreshAll() {
        if (!page.b) return false
        page.lastRefreshAt = Date.now()
        page.b.refreshVersionList()
        // 扫描中不叠请求：记下来等本次扫描结束再补一次（否则手动点刷新会"看起来没反应"）
        if (page.scanning) page.forceRefreshPending = true
        else page.b.refreshVersionDetails()
        return true
    }
    // 页面被 StageShell 宿主切到可见：补一次数据对齐
    function onPageShown() {
        if (!page.b) return
        page.rev++
        if (page.mcFolder) page.mcFolder.refreshFolders()
        page.refreshLocal(false)
        Qt.callLater(page.syncPendingFromList)
    }

    // ── 整合包：路径转换 + 导入 ──
    // url → 本地路径：FileDialog 给的是 file:///D:/a%20b.zip，拖入的 url 也是同一形态。
    // 注意 decodeURIComponent：中文/空格目录（C:/Users/张三/Downloads）不解码是打不开的。
    function localPathOf(u) {
        var s = String(u === undefined || u === null ? "" : u)
        if (s.length === 0) return ""
        if (s.indexOf("file:") === 0) s = s.substring(5)
        if (s.indexOf("///") === 0) s = s.substring(2)                              // ///D:/x → /D:/x
        else if (s.indexOf("//") === 0) s = "\\\\" + s.substring(2).replace(/\//g, "\\")  // UNC
        if (s.charAt(0) === "/" && s.charAt(2) === ":") s = s.substring(1)           // /D:/x → D:/x
        try { s = decodeURIComponent(s) } catch (e) { }
        return s
    }
    function fileNameOf(path) {
        var s = String(path || "")
        var i = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"))
        return i >= 0 ? s.substring(i + 1) : s
    }
    // 导入入口：按钮（FileDialog）与拖入（SDropZone）共用，扩展名校验也只做一处
    function importModpackPath(path) {
        if (!page.importer) { page.flash(qsTr("后端未就绪，无法导入整合包")); return }
        var p = String(path === undefined || path === null ? "" : path)
        if (p.length === 0) return
        var low = p.toLowerCase()
        if (low.lastIndexOf(".zip") !== low.length - 4 && low.lastIndexOf(".mrpack") !== low.length - 7) {
            page.flash(qsTr("只支持 .zip / .mrpack 整合包"))
            return
        }
        if (page.importing) { page.flash(qsTr("已有整合包正在导入，请等它完成")); return }
        page.selectAfterRefresh = ""
        page.flash(qsTr("开始导入整合包：%1").arg(page.fileNameOf(p)))
        // 外部导入没有来源图标（空 url → 任务侧用占位图）；版本名留空让任务按包名自动生成
        page.importer.startImport(p, "", false, "")
    }
    function handleDrop(urls) {
        if (!urls || urls.length === 0) return
        page.importModpackPath(page.localPathOf(urls[0]))
    }

    // 当前待选版本在列表里的行号（-1 = 不在列表里）。滑动指示条靠它定位。
    function rowIndex(id) {
        if (!id) return -1
        for (var i = 0; i < page.rows.length; ++i)
            if (page.rows[i] && page.rows[i].id === id) return i
        return -1
    }
    // 页面实例是常驻的（StageShell 只切宿主 visible，不销毁本组件），所以 Component.onCompleted
    // 只在启动时跑一次 —— 之前"扫描只在这里发"就导致装完新版本回来还是旧列表。
    // 真正该刷新的时机是「变可见」，见下面的 onVisibleChanged；这里只做一次性初始化 + 兜底首屏可见的情况。
    Component.onCompleted: {
        page.rev++
        page.shownId = page.pendingId
        if (page.mcFolder) page.mcFolder.refreshFolders()
        // 调试/截图用：--ui-folder-menu 直接展开文件夹选择面板
        if (Qt.application.arguments.indexOf("--ui-folder-menu") >= 0)
            page.folderMenuOpen = true
        Qt.callLater(page.syncPendingFromList)
        if (page.visible) page.onPageShown()
    }

    // 进入版本页（宿主 visible: versionsOpen 由 false → true 时，本项的有效可见性随之变化）
    // 自动对齐一次数据：版本装完 / 整合包导入完回来，列表不再是旧快照。
    // 频次由 refreshLocal 的陈旧阈值 + 后端 isScanningVersions 双重节流兜住。
    onVisibleChanged: if (visible) page.onPageShown()

    Connections {
        target: page
        function onRowsChanged() { Qt.callLater(page.syncPendingFromList) }
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onVersionDetailsReady() {
            page.rev++
            // 导入完成时记下的"待选中版本"等新数据到齐再落地（提前设会被 syncPendingFromList 冲掉）
            if (page.selectAfterRefresh.length > 0) {
                var want = page.selectAfterRefresh
                page.selectAfterRefresh = ""
                if (page.rowIndex(want) >= 0) page.pendingId = want
            }
        }
        function onSelectedVersionChanged() { page.rev++ }
        // 扫描结束：补发之前因"扫描中"没排上的强制刷新（导入完成那一刻常常正撞上扫描）
        function onScanningChanged() {
            if (page.scanning) return
            if (!page.forceRefreshPending) return
            page.forceRefreshPending = false
            page.refreshLocal(true)
        }
    }

    // 整合包导入结果：成功就强制刷一次并把新版本选中；失败只提示，不打断当前浏览
    Connections {
        target: page.importer
        enabled: page.importer !== null
        function onImportFinished(ok, name, info) {
            if (ok) {
                page.flash(qsTr("整合包已导入：%1").arg(name))
                // info 在成功分支是注册后的版本 id（ModpackImporter::resultVersionId 同值）
                page.selectAfterRefresh = String(info || "")
                page.refreshLocal(true)
            } else {
                page.flash(qsTr("整合包导入失败：%1").arg(info))
            }
        }
    }

    // ---------- 底色 ----------
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

        SButton {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 18 : 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: qsTr("返回")
            onClicked: page.close()
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 108 : 120
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("选择版本")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 182 : 196
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("%1 个已安装").arg(page.details.length)
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Row {
            anchors.right: parent.right
            // 给 StageShell 的全局窗口按钮让位（否则全屏页会重叠）
            anchors.rightMargin: page.narrow ? 96 : 112
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // 游戏文件夹切换（决定版本列表来自哪个 .minecraft）
            Rectangle {
                id: folderChip
                height: 32
                radius: 2
                color: Theme.bgCard2
                border.width: 1
                border.color: Theme.line2
                width: Math.min(210, folderChipRow.implicitWidth + 22)
                Row {
                    id: folderChipRow
                    anchors.centerIn: parent
                    spacing: 6
                    SIcon { name: "folder"; size: 13; color: Theme.fg2 }
                    Text {
                        text: page.folderLabel
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: Math.min(140, implicitWidth)
                    }
                    SIcon { name: "chevron-down"; size: 12; color: Theme.fg3 }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.folderMenuOpen = !page.folderMenuOpen
                }
            }

            // 导入整合包：外部 .zip / .mrpack 文件，走后端已有的 ModpackImporter 全套流程
            // （解析清单 → 解压 overrides → 下模组 → 装 MC+加载器 → 注册版本）。
            SButton {
                kind: 1
                radius: 2
                height: 32
                iconName: "package-plus"
                text: qsTr("导入整合包")
                dimmed: page.importing
                onClicked: {
                    if (!page.importer) { page.flash(qsTr("后端未就绪，无法导入整合包")); return }
                    modpackDialog.open()
                }
            }

            SButton {
                kind: 1
                radius: 2
                height: 32
                iconName: "refresh-cw"
                text: qsTr("刷新")
                onClicked: if (page.refreshAll()) page.flash(qsTr("已刷新版本列表"))
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        height: 1
        color: Theme.line
    }

    // ---------- 整合包导入进度（只在导入中出现；盖在列表顶部，不挤压布局）----------
    // 导入要下模组/装加载器，耗时可能是分钟级；没有反馈的话按钮看起来像没反应。
    Rectangle {
        id: importBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        height: 38
        // 收起时等淡完再隐藏，避免硬切（与文件夹下拉面板同一套做法）
        visible: page.importing || opacity > 0.01
        opacity: page.importing ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
        }
        color: Theme.bgCard2
        z: 200

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }
        SIcon {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 16 : 20
            anchors.verticalCenter: parent.verticalCenter
            name: "package-plus"
            size: 14
            color: Theme.accent
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: (page.narrow ? 16 : 20) + 22
            anchors.right: importCancel.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: page.importStatus.length > 0 ? page.importStatus : qsTr("正在导入整合包…")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        SButton {
            id: importCancel
            anchors.right: parent.right
            anchors.rightMargin: page.narrow ? 16 : 20
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 26
            text: qsTr("取消")
            onClicked: if (page.importer) page.importer.cancelImport()
        }
        // 细进度条贴底边，不再多占一行高度
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: Theme.bgHover
            Rectangle {
                width: parent.width * page.importProgress
                height: parent.height
                color: Theme.accent
            }
        }
    }

    // ---------- 主体 ----------
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom

        // ===== 左：版本列表 =====
        Item {
            id: leftPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: page.leftW

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 1
                color: Theme.line
            }

            Text {
                id: listTitle
                anchors.left: parent.left
                anchors.leftMargin: page.narrow ? 16 : 20
                anchors.top: parent.top
                anchors.topMargin: 14
                text: qsTr("已安装")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: page.narrow ? 16 : 20
                anchors.verticalCenter: listTitle.verticalCenter
                visible: page.rows.length !== page.details.length
                text: page.rows.length + " / " + page.details.length
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            // 搜索
            Rectangle {
                id: searchBox
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: listTitle.bottom
                anchors.topMargin: 10
                anchors.leftMargin: page.narrow ? 16 : 20
                anchors.rightMargin: page.narrow ? 16 : 20
                height: 32
                radius: Theme.rSm
                color: Theme.bgCard2
                border.width: 1
                border.color: Theme.bgInput

                SIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 13
                    color: Theme.fg3
                }
                TextInput {
                    id: searchInput
                    anchors.left: parent.left
                    anchors.leftMargin: 31
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.query
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    selectionColor: Theme.accent
                    clip: true
                    onTextChanged: page.query = text

                    Text {
                        anchors.fill: parent
                        visible: searchInput.text.length === 0
                        text: qsTr("搜索版本 / 加载器")
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // 列表
            ListView {
                id: vlist
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: searchBox.bottom
                anchors.topMargin: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                model: page.rows
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: page.listRowGap

                // 打开页面时把当前选中版本滚进视野（列表按发布时间排序，选中项可能不在首屏）
                function scrollToCurrent() {
                    for (var i = 0; i < page.rows.length; ++i) {
                        if (page.rows[i] && page.rows[i].id === page.pendingId) {
                            positionViewAtIndex(i, ListView.Contain)
                            return
                        }
                    }
                }
                Component.onCompleted: Qt.callLater(scrollToCurrent)
                onModelChanged: Qt.callLater(scrollToCurrent)

                delegate: Item {
                    id: row
                    width: vlist.width
                    height: page.listRowH
                    readonly property bool cur: !!modelData && modelData.id === page.pendingId
                    // hover 用 HoverHandler：子项（齿轮）盖在上面时 containsMouse 会变 false，
                    // 导致"鼠标一移到齿轮上齿轮就消失、根本点不到"
                    // HoverHandler 覆盖整行：鼠标落在齿轮（子项）上时它仍然是 true，
                    // 不用再去引用齿轮自己的 id（那是后声明的，会报 undefined 转 bool）
                    readonly property bool hov: rowHH.hovered
                    HoverHandler { id: rowHH }

                    // 逐条入场：每行按 index 延迟淡入，滚动时新出现的行也会播一次
                    // 延迟封顶 120ms，避免长列表把整段拖过 300ms
                    opacity: 0
                    Component.onCompleted: {
                        rowDelay.interval = Math.min(index * 16, 72)
                        rowDelay.restart()
                    }
                    Timer {
                        id: rowDelay
                        onTriggered: rowIn.restart()
                    }
                    NumberAnimation {
                        id: rowIn
                        target: row
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.durBase
                        easing.type: Theme.easeEnter
                    }

                    // hover / 选中的底色都走过渡，不留硬切
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: row.cur ? Theme.bgCard : (row.hov ? Theme.bgCard2 : "transparent")
                        Behavior on color {
                            ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                        }
                    }
                    Image {
                        id: rowIcon
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        sourceSize.width: 60
                        sourceSize.height: 60
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        source: page.iconOf(modelData)
                    }
                    Column {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 42
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                            width: parent.width
                            text: (modelData && modelData.id) ? modelData.id : ""
                            color: row.cur ? Theme.fg : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: row.cur ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: page.subOf(modelData)
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData && modelData.id)
                                page.pendingId = modelData.id
                        }
                    }

                    // 行尾「设置」：hover 或选中时出现。自绘而不用 SButton ——
                    // 30x26 这么小的尺寸里 RowLayout 的居中会偏，齿轮看着不在框中央
                    Rectangle {
                        id: gearArea
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 4
                        color: gearHover.hovered ? Theme.bgInput : "transparent"
                        border.width: 1
                        border.color: gearHover.hovered ? Theme.line2 : Theme.bgInput
                        opacity: (row.hov || row.cur) ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        SIcon {
                            anchors.centerIn: parent
                            name: "settings"
                            size: 15
                            color: gearHover.hovered ? Theme.fg : Theme.fg2
                        }
                        HoverHandler { id: gearHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData && modelData.id)
                                    page.openSettings(modelData.id)
                            }
                        }
                    }
                }

                // 空态
                Text {
                    anchors.centerIn: parent
                    visible: page.rows.length === 0
                    width: parent.width - 32
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: page.details.length === 0
                          ? qsTr("还没有可用的版本\n在「下载」页安装一个版本后回到这里")
                          : qsTr("没有匹配「%1」的版本").arg(page.query)
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    lineHeight: 1.5
                }
            }

            // 选中指示条（唯一一根）：换选中项时从旧行滑到新行，
            // 而不是每行各长一根（那样只有"变大变小"，没有"上下移动"）。
            Item {
                id: selBarLayer
                anchors.fill: vlist
                clip: true
                z: 2

                Rectangle {
                    id: listSelBar
                    // 用行号做动画值：行号变化时滑过去；contentY 变化时直接跟（滚动不加动画）
                    property real animIdx: page.rowIndex(page.pendingId)
                    Behavior on animIdx {
                        NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter }
                    }
                    visible: page.rowIndex(page.pendingId) >= 0
                    x: 8
                    width: 2
                    height: 42
                    radius: 1
                    color: Theme.accent
                    y: animIdx * (page.listRowH + page.listRowGap) - vlist.contentY
                       + (page.listRowH - height) / 2
                }
            }
        }

        // ===== 右：详情 =====
        Item {
            id: rightPane
            anchors.left: leftPane.right
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            // 换版本：淡出（120ms）→ 在完全透明时换 shownId → 淡入 + 6px 上浮（180ms）。
            // 不能在内容已经换掉之后才压暗，那样会"新文字先亮一下再闪一下"。
            Connections {
                target: page
                function onPendingIdChanged() {
                    if (page.shownId === page.pendingId) return
                    infoSwap.restart()
                }
            }
            SequentialAnimation {
                id: infoSwap
                NumberAnimation {
                    targets: [coverInfo, infoCol]
                    property: "opacity"; to: 0
                    duration: Theme.durFast; easing.type: Theme.easeExit
                }
                ScriptAction { script: page.shownId = page.pendingId }
                ParallelAnimation {
                    NumberAnimation {
                        targets: [coverInfo, infoCol]
                        property: "opacity"; from: 0; to: 1
                        duration: Theme.durBase; easing.type: Theme.easeEnter
                    }
                    NumberAnimation {
                        target: infoShift; property: "y"; from: 6; to: 0
                        duration: Theme.durBase; easing.type: Theme.easeEnter
                    }
                }
            }

            // 封面
            Item {
                id: cover
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: page.coverH
                clip: true

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: "qrc:/ui/stage-aurora.jpg"
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.00; color: "#4005080e" }
                        GradientStop { position: 0.55; color: "#8c05080e" }
                        GradientStop { position: 1.00; color: "#f205080e" }
                    }
                }

                Column {
                    id: coverInfo
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: page.narrow ? 20 : 32
                    anchors.rightMargin: page.narrow ? 20 : 32
                    anchors.bottomMargin: 14
                    spacing: 6

                    Text {
                        width: parent.width
                        text: page.shownSel ? (page.shownSel.id || "—") : "—"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: page.narrow ? 24 : 30
                        font.weight: Font.Bold
                        font.letterSpacing: -0.5
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: page.shownSel ? page.subOf(page.shownSel) : ""
                        color: Theme.accentText
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
            }

            // 信息行
            Column {
                id: infoCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: cover.bottom
                anchors.leftMargin: page.narrow ? 20 : 32
                anchors.rightMargin: page.narrow ? 20 : 32
                anchors.topMargin: 6
                transform: Translate { id: infoShift; y: 0 }

                Repeater {
                    // 固定 8 行、固定顺序：行不会被销毁重建，详情刷新只改文字
                    model: page.infoKeys
                    delegate: Item {
                        width: infoCol.width
                        height: page.infoRowH
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.bgCard2
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.infoLabel(modelData)
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 104
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.infoValue(modelData)
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // 底部操作
            Item {
                id: actionBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 64

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: Theme.line
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: page.narrow ? 20 : 32
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    SButton {
                        kind: 1
                        radius: 2
                        height: 34
                        iconName: "folder-open"
                        text: qsTr("打开目录")
                        onClicked: { if (page.b && page.sel) page.b.openVersionDir(page.sel.id) }
                    }
                }

                SButton {
                    anchors.right: parent.right
                    anchors.rightMargin: page.narrow ? 20 : 32
                    anchors.verticalCenter: parent.verticalCenter
                    kind: 0
                    height: 40
                    iconName: "check"
                    text: qsTr("确定")
                    dimmed: !page.sel
                    onClicked: page.commit()
                }
            }
        }
    }

    // ---------- 游戏文件夹选择（覆盖层，点外部关闭） ----------
    Item {
        id: folderPop
        anchors.fill: parent
        // 关闭时等淡完再隐藏，否则会硬切
        visible: page.folderMenuOpen || opacity > 0.01
        opacity: page.folderMenuOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
        }
        z: 300

        MouseArea { anchors.fill: parent; onClicked: page.folderMenuOpen = false }

        Rectangle {
            id: folderPanel
            anchors.right: parent.right
            anchors.rightMargin: page.narrow ? 18 : 24
            anchors.top: parent.top
            anchors.topMargin: 60
            width: Math.min(380, page.width - 36)
            height: Math.min(page.height - 76, 16 + Math.max(1, page.folders.length) * 46 + 44)
            radius: 2
            color: Theme.bgCard2
            // 下拉面板：从上方 6px 落下
            transform: Translate {
                y: page.folderMenuOpen ? 0 : -6
                Behavior on y {
                    NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter }
                }
            }
            border.width: 1
            border.color: Theme.bgHover

            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: page.folders
                    delegate: Item {
                        width: parent.width
                        height: 44
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: (modelData && modelData.active) ? Theme.bgCard : "transparent"
                        }
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 56
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: (modelData && modelData.name && modelData.name.length > 0)
                                      ? modelData.name : ((modelData && modelData.path) ? modelData.path : "")
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: modelData ? (modelData.path || "") : ""
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }
                        }
                        Text {
                            visible: modelData && modelData.active
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("使用中")
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.switchFolder(modelData.path, modelData.isDefault === true)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 40
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("浏览其他文件夹…")
                        color: Theme.accentText
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.addFolder()
                    }
                }
            }
        }
    }

    // 拖入整合包由 StageShell 的全局投放区统一接管（见 StageShell.handleGlobalDrop）：
    // 那里会用后端打开压缩包判断是整合包还是别的，本页不再自己挂 DropArea，
    // 否则两个投放区会抢同一个拖拽事件。

    // ---------- 选择整合包文件 ----------
    // 用 QtQuick.Dialogs（与 VsModsPane「导入 Mod」同一套，走系统原生对话框）；
    // selectedFile 是 url，交给 localPathOf 转成本地路径（含解码与盘符处理）。
    FileDialog {
        id: modpackDialog
        title: qsTr("选择整合包")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("整合包 (*.zip *.mrpack)"), qsTr("所有文件 (*)")]
        onAccepted: page.importModpackPath(page.localPathOf(selectedFile))
    }
}
