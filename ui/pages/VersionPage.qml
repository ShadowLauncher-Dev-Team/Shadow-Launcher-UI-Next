// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本管理（第一版：主从详情）
// 数据全部来自 backend.versionDetails（后端扫 versions/ 目录得到）：
//   id / mcVersion / loaderType / loaderVersion / versionType / sizeBytes / modCount
//   / isModpack / modpackIconPath / releaseTimeMs
// 上次游玩逐版本来自 backend.lastPlayedLabelFor(id)（只有启动器真起过游戏才有记录）
// 本页不写死任何版本名，不做动效（等动效系统统一接入）
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: page

    signal close()

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var details: (b && b.versionDetails) ? b.versionDetails : []
    readonly property string selId: (b && b.selectedVersion) ? b.selectedVersion : ""
    readonly property bool busy: b ? b.launching : false
    property string query: ""
    property string hint: ""
    property int rev: 0            // 递增以强制重算"上次游玩"等非绑定字段

    readonly property bool narrow: width < 900
    readonly property int leftW: narrow ? 268 : 336
    readonly property real coverH: narrow ? 128 : 200
    readonly property int infoRowH: narrow ? 34 : 44

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
            if (list[i] && list[i].id === selId) return list[i]
        return list.length > 0 ? list[0] : null
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
        if (lt.length === 0) return "原版"
        var lv = v.loaderVersion || ""
        return lv.length > 0 ? (lt + " " + lv) : lt
    }
    function typeText(v) {
        if (!v) return ""
        if (v.versionType === "snapshot") return "快照版"
        if (v.versionType === "old") return "旧版"
        return "正式版"
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
    function flash(msg) { page.hint = msg; hintTimer.restart() }

    Timer { id: hintTimer; interval: 2600; onTriggered: page.hint = "" }
    // 进入本页必须主动触发扫描：versionDetails 是异步扫 versions/ 得到的，
    // 后端不会自己开始扫（旧 UI 也是进版本页时才调 refreshVersionDetails）。
    Component.onCompleted: {
        page.rev++
        if (page.b) page.b.refreshVersionDetails()
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onVersionDetailsReady() { page.rev++ }
        function onSelectedVersionChanged() { page.rev++ }
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

        SButton {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 18 : 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: "返回"
            onClicked: page.close()
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 108 : 120
            anchors.verticalCenter: parent.verticalCenter
            text: "版本管理"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 182 : 196
            anchors.verticalCenter: parent.verticalCenter
            text: page.details.length + " 个已安装"
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: page.narrow ? 18 : 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.hint.length > 0
                text: page.hint
                color: Theme.ok
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            SButton {
                kind: 1
                radius: 2
                height: 32
                iconName: "refresh-cw"
                text: "刷新"
                onClicked: {
                    if (!page.b) return
                    page.b.refreshVersionDetails()
                    page.b.refreshVersionList()
                    page.flash("已刷新版本列表")
                }
            }
            SButton {
                kind: 1
                radius: 2
                height: 32
                iconName: "external-link"
                text: "打开游戏目录"
                onClicked: { if (page.b) page.b.openGameDir("") }
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
                text: "已安装"
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: page.narrow ? 16 : 20
                anchors.verticalCenter: listTitle.verticalCenter
                text: page.rows.length !== page.details.length
                      ? (page.rows.length + " / " + page.details.length)
                      : "按发布时间"
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
                color: "#11141b"
                border.width: 1
                border.color: "#1c2029"

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
                        text: "搜索版本 / 加载器"
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
                spacing: 2

                // 打开页面时把当前选中版本滚进视野（列表按发布时间排序，选中项可能不在首屏）
                function scrollToCurrent() {
                    for (var i = 0; i < page.rows.length; ++i) {
                        if (page.rows[i] && page.rows[i].id === page.selId) {
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
                    height: 60
                    readonly property bool cur: !!modelData && modelData.id === page.selId

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: row.cur ? "#151a23" : "transparent"
                    }
                    Rectangle {
                        visible: row.cur
                        width: 2
                        height: parent.height - 18
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        color: Theme.accent
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
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                            width: parent.width
                            text: (modelData && modelData.id) ? modelData.id : ""
                            color: row.cur ? "#ffffff" : "#e3e8ef"
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
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page.b && modelData && modelData.id)
                                page.b.setSelectedVersion(modelData.id)
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
                          ? "还没有可用的版本\n在「下载」页安装一个版本后回到这里"
                          : "没有匹配「" + page.query + "」的版本"
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    lineHeight: 1.5
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
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: page.narrow ? 20 : 32
                    anchors.rightMargin: page.narrow ? 20 : 32
                    anchors.bottomMargin: 14
                    spacing: 6

                    Text {
                        width: parent.width
                        text: page.selTitle
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: page.narrow ? 24 : 30
                        font.weight: Font.Bold
                        font.letterSpacing: -0.5
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: page.sel ? page.loaderOf(page.sel) : ""
                        color: "#9fb4cf"
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

                Repeater {
                    model: {
                        var s = page.sel
                        if (!s) return []
                        var lp = page.lastPlayedOf(s)
                        return [
                            { k: "版本名", v: s.id || "" },
                            { k: "MC 版本", v: page.mcOf(s).length > 0 ? page.mcOf(s) : "未识别" },
                            { k: "加载器", v: page.loaderOf(s) },
                            { k: "版本类型", v: page.typeText(s) + (s.isModpack ? " · 整合包" : "") },
                            { k: "模组", v: (Number(s.modCount) > 0 ? s.modCount + " 个" : "无模组") },
                            { k: "大小", v: page.sizeText(s.sizeBytes) },
                            { k: "上次游玩", v: lp.length > 0 ? lp : "没有记录" },
                            { k: "游戏目录", v: page.b ? page.b.getVersionGameDir(s.id) : "" }
                        ]
                    }
                    delegate: Item {
                        width: infoCol.width
                        height: page.infoRowH
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#101319"
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.k
                            color: "#6d7684"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 104
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.v
                            color: "#d8dde5"
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
                        text: "打开目录"
                        onClicked: { if (page.b && page.sel) page.b.openVersionDir(page.sel.id) }
                    }
                    SButton {
                        kind: 1
                        radius: 2
                        height: 34
                        iconName: "copy"
                        text: "复制版本"
                        onClicked: {
                            if (!page.b || !page.sel) return
                            var before = page.details.length
                            page.b.cloneVersion(page.sel.id)
                            page.flash("已复制 " + page.sel.id + "（完成后会出现在列表里）")
                        }
                    }
                }

                SButton {
                    anchors.right: parent.right
                    anchors.rightMargin: page.narrow ? 20 : 32
                    anchors.verticalCenter: parent.verticalCenter
                    kind: 0
                    height: 40
                    iconName: page.busy ? "x" : "play"
                    text: page.busy ? "取消启动" : "启动游戏"
                    busy: page.busy
                    dimmed: !page.sel
                    onClicked: {
                        if (!page.b || !page.sel) return
                        if (page.busy) { page.b.cancelLaunch(); return }
                        page.b.launch(page.sel.id, page.b.isOnline)
                    }
                }
            }
        }
    }
}
