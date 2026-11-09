// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 导出整合包（定稿甲：左内容树 / 右设置与导出）
//
// 层级约定（这是本页唯一的设计重点）：
//   父项一行（44 高，加粗，右侧状态 tag）
//   子项缩进 22px + 左侧竖线连接（32 高，普通字重）
// 父项勾选 = 该类整体导出；子项（资源包/光影/存档的具体文件）勾选后只导这些。
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null
    property bool loading: false
    signal busyChanged(bool busy)

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var ex: b ? b.modpackExporter : null

    // ── 状态 ──
    property int format: 0                 // 0=Modrinth .mrpack  1=CurseForge .zip
    property string packName: ""
    property string packVersion: "1.0.0"
    property var ctx: ({})                 // exportContext 结果
    property var checkedIds: []            // 父项 + 子项 id
    property var checkedSaves: []          // 存档名
    property var modList: []               // mods/ 全部文件（listMods）
    property var excludedMods: []          // 取消勾选的 mod（默认全导，只记排除项）
    property string modQuery: ""
    property bool modExpanded: true
    property string outPath: ""
    property bool hostedOnly: false
    property bool mrOnly: false
    property bool includeJava: false

    property bool exporting: false
    property real prog: 0
    property string statusText: ""
    property int lookupPlatform: -1        // -1 无待确认
    property string lookupDetail: ""

    readonly property string suffix: pane.format === 1 ? ".zip" : ".mrpack"

    function optById(id) {
        var list = pane.ctx.options || []
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id) return list[i]
        return null
    }
    function has(id) { return pane.optById(id) !== null }
    function isChecked(id) { return pane.checkedIds.indexOf(id) >= 0 }
    function setChecked(id, on) {
        var out = pane.checkedIds.slice()
        var i = out.indexOf(id)
        if (on && i < 0) out.push(id)
        if (!on && i >= 0) out.splice(i, 1)
        pane.checkedIds = out
    }
    function toggle(id) { pane.setChecked(id, !pane.isChecked(id)) }

    // 子项 id 规则与后端一致：resourcepacks:<file> / resourcepacks:dir:<name>
    function subId(optId, item) {
        return optId + ":" + (item.type === "dir" ? "dir:" : "") + item.name
    }
    function subChecked(optId, item) { return pane.isChecked(pane.subId(optId, item)) }
    function toggleSub(optId, item) { pane.toggle(pane.subId(optId, item)) }
    function subCount(optId, items) {
        var n = 0
        for (var i = 0; i < (items || []).length; ++i)
            if (pane.subChecked(optId, items[i])) n++
        return n
    }
    function setAllSubs(optId, items, on) {
        for (var i = 0; i < (items || []).length; ++i) {
            var id = pane.subId(optId, items[i])
            var already = pane.isChecked(id)
            if (on !== already) pane.setChecked(id, on)
        }
    }

    // 父项勾选/取消时，连带其子项（主流启动器子项面板语义）
    function toggleParent(id, subItems) {
        var on = !pane.isChecked(id)
        pane.setChecked(id, on)
        if (id === "mod" && on) pane.excludedMods = []
        if (subItems && subItems.length > 0) pane.setAllSubs(id, subItems, on)
    }

    // mod：默认全选；只记「被排除」的，导出那一刻才展开成 mod:<文件名>
    function modPicked(name) { return pane.isChecked("mod") && pane.excludedMods.indexOf(name) < 0 }
    function toggleMod(name) {
        if (!pane.isChecked("mod")) return
        var out = pane.excludedMods.slice()
        var i = out.indexOf(name)
        if (i >= 0) out.splice(i, 1); else out.push(name)
        pane.excludedMods = out
    }
    function modPickedCount() {
        if (!pane.isChecked("mod")) return 0
        return Math.max(0, pane.modList.length - pane.excludedMods.length)
    }
    readonly property var modShown: {
        var q = pane.modQuery.trim().toLowerCase()
        var src = pane.modList || []
        if (q.length === 0) return src
        var out = []
        for (var i = 0; i < src.length; ++i)
            if (String(src[i].name).toLowerCase().indexOf(q) >= 0) out.push(src[i])
        return out
    }

    function toggleSave(name, on) {
        var out = pane.checkedSaves.slice()
        var i = out.indexOf(name)
        if (on && i < 0) out.push(name)
        if (!on && i >= 0) out.splice(i, 1)
        pane.checkedSaves = out
    }

    function refresh() {
        if (!pane.ex || pane.versionId.length === 0) return
        pane.ctx = pane.ex.exportContext(pane.versionId)
        // 默认勾选 = optionDefs 的 defaultChecked
        var out = []
        var list = pane.ctx.options || []
        for (var i = 0; i < list.length; ++i)
            if (list[i].defaultChecked) out.push(list[i].id)
        // 勾了资源包/光影父项时，子项默认也全选（否则父项勾选却导出 0 个文件）
        var rp = pane.ctx.rpItems || []
        for (var j = 0; j < rp.length; ++j) {
            if (out.indexOf("resourcepacks") >= 0) out.push(pane.subId("resourcepacks", rp[j]))
        }
        var sp = pane.ctx.shaderItems || []
        for (var k = 0; k < sp.length; ++k) {
            if (out.indexOf("shaderpacks") >= 0) out.push(pane.subId("shaderpacks", sp[k]))
        }
        pane.checkedIds = out
        pane.checkedSaves = []
        pane.excludedMods = []
        pane.modQuery = ""
        pane.modList = pane.ex.listMods(pane.versionId)
        pane.ensureDefaults()
    }

    function ensureDefaults() {
        if (pane.packName.length === 0) pane.packName = pane.versionId
        pane.buildOutPath()
    }

    function safeName() {
        return pane.packName.replace(/[\\/:*?"<>|]/g, "_")
    }

    function buildOutPath() {
        if (!pane.ex || pane.packName.length === 0) return
        const dir = pane.ex.defaultExportDir ? pane.ex.defaultExportDir() : ""
        if (!dir || dir.length === 0) return
        pane.outPath = dir + "/" + pane.safeName() + pane.suffix
    }

    // 产物绝不能落在游戏目录里（会被当成游戏文件，还难找）
    function pathInsideGameDir(p) {
        if (!pane.b) return false
        const gd = String(pane.b.gameDir || "").replace(/\\\\/g, "/").toLowerCase()
        if (gd.length === 0) return false
        const f = p.replace(/\\\\/g, "/").toLowerCase()
        return f === gd || f.indexOf(gd + "/") === 0
    }

    Component.onCompleted: pane.refresh()
    onVersionIdChanged: pane.refresh()
    onFormatChanged: pane.buildOutPath()
    onPackNameChanged: pane.buildOutPath()

    // 打包 JS 对象给后端（QML 的 JS 数组直接传 QVariantList）
    function doExport() {
        if (!pane.ex || pane.exporting) return
        if (pane.packName.length === 0) {
            if (pane.toast) pane.toast.show("先填整合包名称", -1, "error", true)
            return
        }
        if (pane.outPath.length === 0) {
            if (pane.toast) pane.toast.show("先选择输出位置", -1, "error", true)
            return
        }
        if (pane.pathInsideGameDir(pane.outPath)) {
            const dir = pane.ex && pane.ex.defaultExportDir ? pane.ex.defaultExportDir() : ""
            if (dir && dir.length > 0) {
                pane.outPath = dir + "/" + pane.safeName() + pane.suffix
                if (pane.toast)
                    pane.toast.show("输出位置在游戏目录里，已改为 " + dir, -1, "info", true)
            } else {
                if (pane.toast) pane.toast.show("不能导出到游戏目录，请换个位置", -1, "error", true)
                return
            }
        }
        var opts = pane.checkedIds.slice()
        // mod 只勾了一部分时，展开成 mod:<文件名>（全选则保持空，后端走整目录规则）
        if (pane.isChecked("mod") && pane.excludedMods.length > 0) {
            for (var mi = 0; mi < pane.modList.length; ++mi) {
                var mn = pane.modList[mi].name
                if (pane.excludedMods.indexOf(mn) < 0) opts.push("mod:" + mn)
            }
        }
        // 存档：勾了 saves 父项才带子项；一个没选时后端会整目录导出（见导出端规则）
        var saves = pane.checkedSaves.slice()
        pane.failedHint = ""
        pane.exporting = true
        pane.prog = 0
        pane.statusText = "准备导出…"
        pane.ex.exportVersion(pane.versionId, pane.packName, pane.packVersion,
                              opts, saves, pane.mrOnly, pane.hostedOnly,
                              pane.includeJava, pane.format, pane.outPath)
    }

    property string failedHint: ""

    Connections {
        target: pane.ex
        ignoreUnknownSignals: true
        function onProgressChanged() {
            pane.prog = pane.ex.progress
            pane.statusText = pane.ex.statusText
        }
        function onLookupFailed(platform, detail) {
            pane.lookupPlatform = platform
            pane.lookupDetail = detail
            lookupPop.open()
        }
        function onFinished(ok, path, err) {
            pane.exporting = false
            pane.prog = ok ? 1 : 0
            if (ok) {
                pane.statusText = "导出完成"
                if (pane.toast)
                    pane.toast.show("已导出到 " + path, 4000, "info", true)
            } else {
                pane.statusText = "导出失败"
                pane.failedHint = err
                if (pane.toast)
                    pane.toast.show(err.length > 0 ? err : "导出失败", 5000, "error", true)
            }
        }
    }

    // ═══════════ 布局 ═══════════
    Column {
        anchors.fill: parent
        spacing: 0

        // 顶部：格式二选一
        Item {
            width: parent.width
            height: 56
            SSegmented {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                width: 300
                height: 32
                currentIndex: pane.format
                items: ["Modrinth .mrpack", "CurseForge .zip"]
                onActivated: (i) => pane.format = i
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 344
                anchors.verticalCenter: parent.verticalCenter
                text: pane.format === 0 ? "引用在线来源，包体最小" : "CurseForge 清单，部分文件只能直接打包"
                color: "#5d6673"
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            SButton {
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                kind: 1
                height: 32
                radius: 2
                text: "恢复默认"
                onClicked: {
                    pane.refresh()
                    if (pane.toast) pane.toast.show("已恢复默认勾选", -1, "info", true)
                }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.line
            }
        }

        Row {
            width: parent.width
            height: parent.height - 56
            spacing: 0

            // ── 左：内容树 ──
            Item {
                width: parent.width - 352
                height: parent.height

                Row {
                    id: treeHead
                    x: 28
                    y: 14
                    spacing: 10
                    Text {
                        text: "导出内容"
                        color: "#98a1ae"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "已选 " + pane.checkedIds.length + " 项"
                        color: "#5d6673"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Flickable {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: treeHead.bottom
                    anchors.topMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 28
                    anchors.rightMargin: 20
                    clip: true
                    contentWidth: width
                    contentHeight: treeCol.implicitHeight + 12
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 6
                        contentItem: Rectangle {
                            radius: 3
                            color: "#2b323d"
                            implicitWidth: 6
                        }
                    }

                    Column {
                        id: treeCol
                        width: parent.width
                        spacing: 6

                        // —— 基础 ——
                        Text { text: "基础"; color: "#3f4753"; font.family: Theme.fontFamily; font.pixelSize: 10; topPadding: 6 }
                        Repeater {
                            model: ["options", "personal", "optifine", "license"]
                            delegate: parentRow
                        }

                        // —— Mod 与配置 ——
                        Text { text: "Mod 与配置"; color: "#3f4753"; font.family: Theme.fontFamily; font.pixelSize: 10; topPadding: 10 }
                        Loader {
                            width: treeCol.width
                            sourceComponent: modGroup
                        }
                        Repeater {
                            model: ["mod-disabled", "packdata", "config", "tacz", "immersive", "mapdata", "jei", "emi", "patchouli"]
                            delegate: parentRow
                        }

                        // —— 资源包（带真实子项）——
                        Text { text: "资源"; color: "#3f4753"; font.family: Theme.fontFamily; font.pixelSize: 10; topPadding: 10 }
                        Loader {
                            width: treeCol.width
                            sourceComponent: packGroup
                            onLoaded: item.optId = "resourcepacks"
                        }
                        Loader {
                            width: treeCol.width
                            sourceComponent: packGroup
                            onLoaded: item.optId = "shaderpacks"
                        }

                        // —— 存档（带真实子项）——
                        Text { text: "存档"; color: "#3f4753"; font.family: Theme.fontFamily; font.pixelSize: 10; topPadding: 10 }
                        Loader {
                            width: treeCol.width
                            sourceComponent: savesGroup
                        }

                        // —— 其他 ——
                        Text { text: "其他（默认不导出）"; color: "#3f4753"; font.family: Theme.fontFamily; font.pixelSize: 10; topPadding: 10 }
                        Repeater {
                            model: ["screenshots", "schematics", "replay", "servers"]
                            delegate: parentRow
                        }
                    }
                }
            }

            Rectangle { width: 1; height: parent.height; color: Theme.line }

            // ── 右：设置 + 导出 ──
            Item {
                width: 351
                height: parent.height

                Column {
                    id: rightCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: exportBar.top
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.topMargin: 14
                    spacing: 14

                    SCard {
                        width: parent.width
                        title: "打包信息"
                        SRow {
                            width: parent.width
                            label: "名称"
                            SInput {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 32
                                text: pane.packName
                                onEdited: (v) => pane.packName = v
                            }
                        }
                        SRow {
                            width: parent.width
                            label: "版本"
                            divider: false
                            SInput {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 32
                                text: pane.packVersion
                                onEdited: (v) => pane.packVersion = v
                            }
                        }
                    }

                    SCard {
                        width: parent.width
                        title: "高级"
                        SRow {
                            width: parent.width
                            label: "仅包内资源"
                            SSwitch {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: pane.hostedOnly
                                onToggled: pane.hostedOnly = checked
                            }
                        }
                        SRow {
                            width: parent.width
                            label: "仅 Modrinth"
                            SSwitch {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: pane.mrOnly
                                onToggled: pane.mrOnly = checked
                            }
                        }
                        SRow {
                            width: parent.width
                            label: "打包 Java"
                            divider: false
                            SSwitch {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: pane.includeJava
                                onToggled: pane.includeJava = checked
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: (pane.format === 0 ? "Modrinth .mrpack" : "CurseForge .zip")
                              + "  ·  已选 " + pane.checkedIds.length + " 项"
                              + (pane.isChecked("saves")
                                 ? "  ·  存档 " + (pane.checkedSaves.length > 0 ? pane.checkedSaves.length + " 个" : "全部")
                                 : "")
                        color: "#cfd6e1"
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    Text {
                        width: parent.width
                        text: "导出时会先计算文件哈希并联网匹配来源，仅匹配到的文件用下载链接，其余直接打进包。"
                        color: "#4b5462"
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                // 底部导出条
                Item {
                    id: exportBar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: pane.exporting ? 132 : 108

                    Rectangle {
                        anchors.fill: parent
                        color: "#0a0b0f"
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Theme.line2
                    }

                    // 路径行
                    Row {
                        id: pathRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 8
                        Text {
                            width: parent.width - 52
                            text: pane.outPath.length > 0 ? pane.outPath : "未选择输出位置"
                            color: "#7b8494"
                            elide: Text.ElideMiddle
                            font.family: "Consolas"
                            font.pixelSize: 11
                        }
                        Text {
                            text: "更改"
                            color: "#7fa9f5"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: saveDialog.open()
                            }
                        }
                    }

                    // 导出中：状态 + 进度
                    Column {
                        visible: pane.exporting
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: pathRow.bottom
                        anchors.topMargin: 8
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 6
                        Rectangle {
                            width: parent.width
                            height: 3
                            radius: 2
                            color: "#151a22"
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, pane.prog))
                                height: parent.height
                                radius: 2
                                color: Theme.accent
                            }
                        }
                        Text {
                            width: parent.width
                            text: pane.statusText
                            color: "#7b8494"
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    SButton {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        height: 38
                        radius: Theme.rSm
                        kind: pane.exporting ? 1 : 0
                        text: pane.exporting ? "取消导出" : "开始导出"
                        onClicked: {
                            if (!pane.ex) return
                            if (pane.exporting) {
                                pane.ex.cancel()
                                pane.exporting = false
                                pane.statusText = "正在取消…"
                                return
                            }
                            pane.doExport()
                        }
                    }
                }
            }
        }
    }

    // ── 父项行（可带子项）──
    Component {
        id: parentRow
        Loader {
            width: treeCol.width
            height: 36
            sourceComponent: pane.has(modelData) ? simpleRow : null
            onLoaded: { item.optId = modelData }
            visible: pane.has(modelData)
        }
    }

    // 无子项的普通父行
    Component {
        id: simpleRow
        Item {
            id: rowItem
            property string optId: ""
            readonly property var o: pane.optById(optId)
            width: parent ? parent.width : 0
            height: 36
            visible: pane.has(optId)

            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm
                color: hov.hovered ? "#101419" : "transparent"
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                // 方形勾选（自绘：No emoji / 图标一律 SVG）
                Rectangle {
                    width: 15
                    height: 15
                    radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: pane.isChecked(rowItem.optId) ? Theme.accent : "#0d1016"
                    border.width: 1
                    border.color: pane.isChecked(rowItem.optId) ? Theme.accent : "#39414f"
                    SIcon {
                        anchors.centerIn: parent
                        width: 10
                        height: 10
                        name: "check"
                        visible: pane.isChecked(rowItem.optId)
                        color: "#ffffff"
                    }
                }
                Text {
                    text: rowItem.o ? rowItem.o.title : ""
                    color: "#dfe5ee"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rowItem.o && rowItem.o.privacy
                    text: "含个人数据"
                    color: Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }
            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: pane.toggle(rowItem.optId)
            }
        }
    }

    // Mod：父行（勾选=全选/全不选）+ 可展开的真实模组列表（带搜索）
    // 注意：这里一律绝对定位，不用 Row 的弹性占位——Row 内子项宽度反绑 Row 宽度会触发 polish 死循环，整页布局会崩。
    Component {
        id: modGroup
        Item {
            id: modItem
            width: parent ? parent.width : 0
            height: 44 + (pane.modExpanded ? 4 + 34 + 26 + 240 : 0)

            Rectangle {
                id: modHead
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 44
                radius: Theme.rMd
                color: modHov.hovered ? "#101419" : "#0b0d12"
                border.width: 1
                border.color: Theme.line2
            }
            HoverHandler { id: modHov }

            Rectangle {
                id: modCb
                x: 14
                width: 15
                height: 15
                radius: 4
                anchors.verticalCenter: modHead.verticalCenter
                color: pane.isChecked("mod") ? Theme.accent : "#0d1016"
                border.width: 1
                border.color: pane.isChecked("mod") ? Theme.accent : "#39414f"
                SIcon {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    name: "check"
                    visible: pane.isChecked("mod")
                    color: "#ffffff"
                }
                TapHandler { acceptedButtons: Qt.LeftButton
                    onTapped: pane.toggleParent("mod", []) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            Text {
                id: modTitle
                x: 39
                anchors.verticalCenter: modHead.verticalCenter
                text: "模组 (mods/)"
                color: "#eef2f8"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                TapHandler { acceptedButtons: Qt.LeftButton
                    onTapped: pane.toggleParent("mod", []) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            Text {
                id: modPick
                anchors.right: modHead.right
                anchors.rightMargin: 14
                anchors.verticalCenter: modHead.verticalCenter
                text: pane.modExpanded ? "收起" : "挑选"
                color: "#7fa9f5"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                TapHandler { acceptedButtons: Qt.LeftButton
                    onTapped: pane.modExpanded = !pane.modExpanded }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            Text {
                anchors.right: modPick.left
                anchors.rightMargin: 14
                anchors.verticalCenter: modHead.verticalCenter
                text: pane.modList.length + " 个 · 已选 " + pane.modPickedCount()
                color: "#6b7686"
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            // 展开区：搜索 + 全选/全不选 + 虚拟化列表
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: modHead.bottom
                anchors.topMargin: 4
                height: parent.height - 48
                visible: pane.modExpanded

                Rectangle { x: 21; y: 0; width: 1; height: parent.height - 6; color: "#1b2029" }

                SField {
                    id: modSearch
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.top: parent.top
                    height: 30
                    label: "搜索模组"
                    text: pane.modQuery
                    onEdited: (v) => pane.modQuery = v
                }

                Text {
                    id: allOn
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.top: modSearch.bottom
                    anchors.topMargin: 6
                    text: "全选"
                    color: "#7fa9f5"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: pane.excludedMods = [] }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Text {
                    id: allOff
                    anchors.left: allOn.right
                    anchors.leftMargin: 14
                    anchors.top: allOn.top
                    text: "全不选"
                    color: "#7fa9f5"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    TapHandler { acceptedButtons: Qt.LeftButton
                        onTapped: {
                            var arr = []
                            for (var i = 0; i < pane.modList.length; ++i) arr.push(pane.modList[i].name)
                            pane.excludedMods = arr
                        } }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Text {
                    anchors.left: allOff.right
                    anchors.leftMargin: 14
                    anchors.top: allOn.top
                    text: pane.modShown.length + " / " + pane.modList.length
                    color: "#4b5462"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                ListView {
                    id: modList
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.top: allOn.bottom
                    anchors.topMargin: 4
                    anchors.bottom: parent.bottom
                    clip: true
                    model: pane.modShown
                    reuseItems: true
                    cacheBuffer: 300
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 6
                        contentItem: Rectangle { radius: 3; color: "#2b323d"; implicitWidth: 6 }
                    }

                    delegate: Item {
                        id: modRow
                        width: ListView.view ? ListView.view.width : 0
                        height: 32

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: rowHov.hovered ? "#11161d" : "transparent"
                        }
                        Rectangle {
                            id: rowCb
                            x: 8
                            width: 14
                            height: 14
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: pane.modPicked(modelData.name) ? Theme.accent : "#0d1016"
                            border.width: 1
                            border.color: pane.modPicked(modelData.name) ? Theme.accent : "#39414f"
                            SIcon {
                                anchors.centerIn: parent
                                width: 9
                                height: 9
                                name: "check"
                                visible: pane.modPicked(modelData.name)
                                color: "#ffffff"
                            }
                        }
                        Text {
                            id: rowName
                            x: 30
                            width: parent.width - 30 - 58
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: pane.modPicked(modelData.name) ? "#cfd6e1" : "#7b8494"
                            elide: Text.ElideMiddle
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.sizeDisplay || ""
                            color: "#4b5462"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        HoverHandler { id: rowHov }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: pane.toggleMod(modelData.name)
                        }
                    }
                }
            }
        }
    }

    // 资源包 / 光影：父行 + 真实文件子项
    Component {
        id: packGroup
        Item {
            id: grpItem
            property string optId: "resourcepacks"
            readonly property var items: optId === "resourcepacks"
                ? (pane.ctx.rpItems || []) : (pane.ctx.shaderItems || [])
            readonly property var o: pane.optById(optId)
            width: parent ? parent.width : 0
            height: pane.has(optId) ? (44 + (items.length > 0 ? 30 + items.length * 32 : 30)) : 0
            visible: pane.has(optId)

            Rectangle {
                id: grpHead
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 44
                radius: Theme.rMd
                color: hov2.hovered ? "#101419" : "#0b0d12"
                border.width: 1
                border.color: Theme.line2
            }
            Rectangle {
                x: 14
                width: 15
                height: 15
                radius: 4
                anchors.verticalCenter: grpHead.verticalCenter
                color: pane.isChecked(grpItem.optId) ? Theme.accent : "#0d1016"
                border.width: 1
                border.color: pane.isChecked(grpItem.optId) ? Theme.accent : "#39414f"
                SIcon {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    name: "check"
                    visible: pane.isChecked(grpItem.optId)
                    color: "#ffffff"
                }
            }
            Text {
                x: 39
                anchors.verticalCenter: grpHead.verticalCenter
                text: grpItem.o ? grpItem.o.title : grpItem.optId
                color: "#eef2f8"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors.right: grpHead.right
                anchors.rightMargin: 14
                anchors.verticalCenter: grpHead.verticalCenter
                text: grpItem.items.length + " 个"
                color: "#6b7686"
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            HoverHandler { id: hov2; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: pane.toggleParent(grpItem.optId, grpItem.items)
            }

            // 子项列表（缩进 + 竖线）
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: grpHead.bottom
                anchors.topMargin: 4
                height: grpItem.height - 48

                Rectangle {
                    x: 21
                    y: 0
                    width: 1
                    height: parent.height - 8
                    color: "#1b2029"
                }

                Column {
                    anchors.fill: parent
                    spacing: 0

                    // 全选 / 全不选
                    Row {
                        width: parent.width
                        height: 30
                        x: 32
                        spacing: 12
                        Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "全选"
                        color: "#7fa9f5"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { acceptedButtons: Qt.LeftButton
                            onTapped: pane.setAllSubs(grpItem.optId, grpItem.items, true) }
                    }
                        Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "全不选"
                        color: "#7fa9f5"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { acceptedButtons: Qt.LeftButton
                            onTapped: pane.setAllSubs(grpItem.optId, grpItem.items, false) }
                    }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: grpItem.items.length === 0 ? "此版本没有内容" : ""
                            color: "#4b5462"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    Repeater {
                        model: grpItem.items
                        delegate: Item {
                            width: parent.width
                            height: 32
                            x: 32
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                spacing: 9
                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: pane.subChecked(grpItem.optId, modelData) ? Theme.accent : "#0d1016"
                                    border.width: 1
                                    border.color: pane.subChecked(grpItem.optId, modelData) ? Theme.accent : "#39414f"
                                    SIcon {
                                        anchors.centerIn: parent
                                        width: 9
                                        height: 9
                                        name: "check"
                                        visible: pane.subChecked(grpItem.optId, modelData)
                                        color: "#ffffff"
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name + (modelData.type === "dir" ? "/" : "")
                                    color: pane.subChecked(grpItem.optId, modelData) ? "#cfd6e1" : "#7b8494"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: pane.toggleSub(grpItem.optId, modelData)
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }
            }
        }
    }

    // 存档：父行 + 真实世界名
    Component {
        id: savesGroup
        Item {
            id: saveItem
            readonly property var items: pane.savesList
            width: parent ? parent.width : 0
            height: pane.has("saves") ? (44 + 30 + items.length * 32) : 0
            visible: pane.has("saves")

            Rectangle {
                id: saveHead
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 44
                radius: Theme.rMd
                color: hov3.hovered ? "#101419" : "#0b0d12"
                border.width: 1
                border.color: Theme.line2
            }
            Rectangle {
                x: 14
                width: 15
                height: 15
                radius: 4
                anchors.verticalCenter: saveHead.verticalCenter
                color: pane.isChecked("saves") ? Theme.accent : "#0d1016"
                border.width: 1
                border.color: pane.isChecked("saves") ? Theme.accent : "#39414f"
                SIcon {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    name: "check"
                    visible: pane.isChecked("saves")
                    color: "#ffffff"
                }
            }
            Text {
                x: 39
                anchors.verticalCenter: saveHead.verticalCenter
                text: "单机游戏存档"
                color: "#eef2f8"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors.right: saveHead.right
                anchors.rightMargin: 14
                anchors.verticalCenter: saveHead.verticalCenter
                text: saveItem.items.length + " 个"
                color: "#6b7686"
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            HoverHandler { id: hov3; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: pane.toggle("saves")
            }

            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: saveHead.bottom
                anchors.topMargin: 4
                height: saveItem.height - 48
                Rectangle { x: 21; y: 0; width: 1; height: parent.height - 8; color: "#1b2029" }
                Column {
                    anchors.fill: parent
                    spacing: 0
                    Row {
                        width: parent.width
                        height: 30
                        x: 32
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "全选"
                            color: "#7fa9f5"; font.family: Theme.fontFamily; font.pixelSize: 11
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var out = []
                                    for (var i = 0; i < saveItem.items.length; ++i) out.push(saveItem.items[i].name)
                                    pane.checkedSaves = out
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "全不选"
                            color: "#7fa9f5"; font.family: Theme.fontFamily; font.pixelSize: 11
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: pane.checkedSaves = []
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: saveItem.items.length === 0
                            text: "此版本没有存档"
                            color: "#4b5462"; font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                    }
                    Repeater {
                        model: saveItem.items
                        delegate: Item {
                            width: parent.width
                            height: 32
                            x: 32
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                spacing: 9
                                Rectangle {
                                    width: 14; height: 14; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: pane.checkedSaves.indexOf(modelData.name) >= 0 ? Theme.accent : "#0d1016"
                                    border.width: 1
                                    border.color: pane.checkedSaves.indexOf(modelData.name) >= 0 ? Theme.accent : "#39414f"
                                    SIcon { anchors.centerIn: parent; width: 9; height: 9; name: "check"
                                        visible: pane.checkedSaves.indexOf(modelData.name) >= 0; color: "#ffffff" }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: pane.checkedSaves.indexOf(modelData.name) >= 0 ? "#cfd6e1" : "#7b8494"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.modified || ""
                                    color: "#4b5462"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: pane.toggleSave(modelData.name, pane.checkedSaves.indexOf(modelData.name) < 0)
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }
            }
        }
    }

    // 存档列表（懒加载，只在首次进入/版本变化时读）
    property var savesList: []
    Timer {
        interval: 60
        running: true
        repeat: false
        onTriggered: {
            if (pane.ex && pane.versionId.length > 0)
                pane.savesList = pane.ex.listSaves(pane.versionId)
        }
    }

    // 选择输出位置
    FileDialog {
        id: saveDialog
        title: "导出到"
        fileMode: FileDialog.SaveFile
        nameFilters: pane.format === 1 ? ["CurseForge 整合包 (*.zip)"] : ["Modrinth 整合包 (*.mrpack)"]
        onAccepted: {
            var p = String(selectedFile).replace(/^file:\/\//, "")
            if (p.length > 0) pane.outPath = p
        }
    }

    // 联网查询失败确认
    Popup {
        id: lookupPop
        parent: pane
        anchors.centerIn: parent
        width: 400
        modal: true
        padding: 0
        closePolicy: Popup.NoAutoClose
        background: Rectangle {
            radius: Theme.rMd
            color: "#0b0d12"
            border.width: 1
            border.color: Theme.line2
        }
        contentItem: Column {
            width: 400
            padding: 18
            spacing: 12
            Text {
                text: pane.lookupPlatform === 0 ? "Modrinth 查询失败"
                     : pane.lookupPlatform === 1 ? "CurseForge 查询失败"
                     : "联网查询失败"
                color: "#eef2f8"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width - 36
                text: pane.lookupDetail + "\n\n继续导出的话，查不到来源的文件会直接打进包里。"
                color: "#9aa3b0"
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Row {
                spacing: 8
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    text: "取消导出"
                    onClicked: {
                        lookupPop.close()
                        if (pane.ex) pane.ex.continueAfterLookupFailure(false)
                    }
                }
                SButton {
                    kind: 0
                    height: 32
                    radius: 2
                    text: "继续导出"
                    onClicked: {
                        lookupPop.close()
                        if (pane.ex) pane.ex.continueAfterLookupFailure(true)
                    }
                }
            }
        }
    }
}
