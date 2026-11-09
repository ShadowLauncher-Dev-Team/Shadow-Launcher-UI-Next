// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 概览（定稿甲：无装饰 kv 单列）
//
// 这一页只回答"这个版本是什么状况"：身份、运行参数、内容数量、目录位置。
// 所有计数走异步接口（listMods 同步版会逐个解 jar，会把 UI 卡住）。
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null
    /// 行尾动作请求切到另一分区
    signal requestPane(string key)

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    // settings 是 Q_INVOKABLE 方法（无参），QML 里必须调用才拿到对象
    readonly property var s: b ? b.settings() : null

    property var mods: []
    property var packs: []
    property var saves: []

    readonly property var detail: {
        if (!b || !b.versionDetails) return null
        var arr = b.versionDetails
        for (var i = 0; i < arr.length; ++i)
            if (arr[i] && arr[i].id === pane.versionId) return arr[i]
        return null
    }
    // 版本详情还没扫到时，从 id 兜底切分（1.20.1-Forge_47.2.0 → 1.20.1 / Forge 47.2.0）
    readonly property int dashAt: pane.versionId.indexOf("-")
    readonly property string loaderText: {
        if (detail && (detail.loaderType || "").length > 0) {
            var lv = detail.loaderVersion || ""
            return lv.length > 0 ? (detail.loaderType + " " + lv) : detail.loaderType
        }
        if (!detail && pane.dashAt > 0) return pane.versionId.substring(pane.dashAt + 1).split("_").join(" ")
        return "原版"
    }
    readonly property string mcText: {
        if (detail && (detail.mcVersion || "").length > 0) return detail.mcVersion
        if (pane.dashAt > 0) return pane.versionId.substring(0, pane.dashAt)
        return "—"
    }
    readonly property string lastPlayed: (b && pane.versionId.length > 0)
        ? b.lastPlayedLabelFor(pane.versionId) : ""

    readonly property string javaText: {
        if (!pane.s) return "—"
        var mode = pane.s.versionJavaMode(pane.versionId)
        var ver = pane.s.javaVersion || ""
        if (mode === 0) return (ver.length > 0 ? ver : "未就绪") + " · 跟随全局"
        if (mode === 1) return "版本目录内 Java"
        return (ver.length > 0 ? ver : "未就绪") + " · 已指定"
    }
    readonly property string memText: {
        if (!pane.s) return "—"
        var mode = pane.s.versionMemoryMode(pane.versionId)
        if (mode === 0) return (pane.s.maxMemoryMB || 0) + " MB · 跟随全局"
        return pane.s.versionMemoryManualMB(pane.versionId) + " MB · 已覆盖"
    }
    readonly property int modOn: {
        var n = 0
        for (var i = 0; i < pane.mods.length; ++i) if (pane.mods[i].enabled) n++
        return n
    }

    function refreshCounts() {
        if (!pane.b || pane.versionId.length === 0) return
        pane.b.listModsAsync(pane.versionId)
        pane.b.listResourcePacksAsync(pane.versionId)
        pane.b.listSavesAsync(pane.versionId)
    }

    Component.onCompleted: pane.refreshCounts()

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onModsListReady(vid, list) { if (vid === pane.versionId) pane.mods = list || [] }
        function onResourcePacksListReady(vid, list) { if (vid === pane.versionId) pane.packs = list || [] }
        function onSavesListReady(vid, list) { if (vid === pane.versionId) pane.saves = list || [] }
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 56
        boundsBehavior: Flickable.StopAtBounds

        // 点内容空白处清焦点。必须挂在 Flickable 自己身上：
        // 页面根层收不到（这个 Flickable 铺满内容区、会吃掉 press），挂在子项上又会挡拖拽。
        // tap 与 drag 不冲突：只有按下抬起位置基本不变的点击才触发。
        TapHandler {
            onTapped: pane.forceActiveFocus()
        }

        Column {
            id: col
            x: 28
            y: 22
            width: Math.max(360, pane.width - 56)

            // ── 身份条 ──
            Item {
                width: col.width
                height: 40
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 22
                    Text {
                        text: "加载器"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.loaderText
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    Item { width: 1; height: 1 }
                    Text {
                        text: "游戏"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.mcText
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pane.lastPlayed.length > 0
                    text: pane.lastPlayed
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            // ── 运行 ──
            KvGroupLabel { text: "运行"; width: col.width }
            KvRow {
                width: col.width
                order: 0
                k: "Java"
                v: pane.javaText
                a: "去指定"
                onAct: pane.requestPane("launch")
            }
            KvRow {
                width: col.width
                order: 1
                k: "内存"
                v: pane.memText
                a: "去设置"
                onAct: pane.requestPane("memory")
            }

            // ── 内容 ──
            KvGroupLabel { text: "内容"; width: col.width }
            KvRow {
                width: col.width
                order: 2
                k: "Mod"
                v: pane.mods.length + " 个 · 启用 " + pane.modOn
                a: "管理"
                onAct: pane.requestPane("mods")
            }
            KvRow {
                width: col.width
                order: 3
                k: "资源包"
                v: pane.packs.length + " 个"
                a: "管理"
                onAct: pane.requestPane("packs")
            }
            KvRow {
                width: col.width
                order: 4
                k: "存档"
                v: pane.saves.length + " 个"
                a: "管理"
                onAct: pane.requestPane("saves")
            }

            // ── 存储 ──
            // 占用：后端没有版本目录大小的接口，这一行不做（不写"计算中"糊弄）
            KvGroupLabel { text: "存储"; width: col.width }
            KvRow {
                width: col.width
                order: 5
                k: "版本目录"
                v: "versions\\" + pane.versionId
                mono: true
                a: "打开"
                onAct: if (pane.b) pane.b.openVersionDir(pane.versionId)
            }
            KvRow {
                width: col.width
                order: 6
                k: "游戏目录"
                v: ".minecraft"
                mono: true
                a: "打开"
                onAct: if (pane.b) pane.b.openGameDir(pane.versionId)
            }
        }
    }

    // 分区小标题
    component KvGroupLabel: Text {
        topPadding: 16
        bottomPadding: 4
        color: "#6b7686"
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.letterSpacing: 1.1
    }

    // kv 行：左标签 96 + 值 + 行尾动作
    component KvRow: Item {
        id: kv
        height: 44
        // 全页行号，入场按它错峰（行与行之间连续，不按分组重新计时）
        property int order: 0
        property string k: ""
        property string v: ""
        property string a: ""
        property bool mono: false
        signal act()

        // 入场：整行淡入 + 上浮 6px；行内元素不各自入场，否则文字会散着浮上来。
        // 位移走 Translate：行由 Column 定位，直接动 y 会被 positioner 覆盖。
        property bool shown: false
        opacity: kv.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
        }
        transform: Translate {
            y: kv.shown ? 0 : 6
            Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
        }
        Timer {
            interval: Math.min(kv.order, Theme.staggerMax) * Theme.staggerStep
            running: true
            onTriggered: kv.shown = true
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: "#11141d"
        }
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: kv.k
            color: "#7b8494"
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 96
            anchors.right: actText.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: kv.v
            color: kv.mono ? "#b6c0cd" : "#cfd6e1"
            elide: Text.ElideMiddle
            font.family: kv.mono ? "Consolas" : Theme.fontFamily
            font.pixelSize: 12
        }
        Text {
            id: actText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: kv.a
            visible: kv.a.length > 0
            color: "#7fa9f5"
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
        MouseArea {
            anchors.right: parent.right
            width: actText.visible ? 70 : 0
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: kv.act()
        }
    }
}
