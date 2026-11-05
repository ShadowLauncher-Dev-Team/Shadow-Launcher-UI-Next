// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

// 下载页（2026-11-05 第一版，不含进入/切换动效）
// 结构：二级导航（160）+ 内容区；三种模式：列表(0) / 安装配置(1) / 进度(2)
// 设计约束：
//   · 版本行只做选择，不带启动/下载按钮；点击进全屏配置
//   · 列表按发布时间从新到旧，已安装只做标记，不置顶
//   · 进度页顶部汇总条显示总进度/总速度；完成的任务自动消失并 toast
Item {
    id: page
    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null
    signal close()

    readonly property var releaseV: b ? b.releaseVersions : []
    readonly property var snapshotV: b ? b.snapshotVersions : []
    readonly property var oldV: b ? b.oldVersions : []
    readonly property var installedV: b ? b.installedVersions : []

    property int tab: 0          // 0 游戏版本 1 模组 2 光影 3 资源包 4 整合包 5 数据包 6 Java 7 进度
    property int mode: 0         // 0 列表 1 配置 2 进度
    property int filter: 0       // 0 正式版 1 快照 2 旧版 3 全部
    property bool onlyInstalled: false
    property string search: ""
    property string picked: ""
    property string loaderType: "vanilla"
    property string loaderVer: ""
    property string instName: ""
    property real totalSpeed: 0
    property real totalProgress: 0
    property int runningCount: 0

    readonly property var tabs: [
        { l: "游戏版本", ic: "box" },
        { l: "模组", ic: "puzzle" },
        { l: "光影", ic: "sparkles" },
        { l: "资源包", ic: "palette" },
        { l: "整合包", ic: "package" },
        { l: "数据包", ic: "scroll-text" },
        { l: "Java 运行时", ic: "cpu" },
        { l: "下载进度", ic: "list" }
    ]

    function isInstalled(id) { return installedV.indexOf(id) >= 0 }

    function rows() {
        var src = filter === 0 ? releaseV
                : filter === 1 ? snapshotV
                : filter === 2 ? oldV
                : releaseV.concat(snapshotV)
        var out = []
        var q = search.trim().toLowerCase()
        for (var i = 0; i < src.length; ++i) {
            var id = src[i]
            if (onlyInstalled && !isInstalled(id)) continue
            if (q.length > 0 && id.toLowerCase().indexOf(q) < 0) continue
            out.push({
                vid: id,
                kind: filter === 1 ? "快照" : (filter === 2 ? "旧版" : "正式版"),
                isNew: filter === 0 || filter === 3,
                inst: isInstalled(id)
            })
        }
        return out
    }
    readonly property var rowList: rows()

    function kindColor(kind) {
        if (kind === "快照") return "#f5c451"
        if (kind === "旧版") return "#a9b3c2"
        return "#5ee08f"
    }

    function pickVersion(vid) {
        page.picked = vid
        page.loaderType = "vanilla"
        page.loaderVer = ""
        page.instName = vid
        page.mode = 1
    }

    function startInstall() {
        if (!b) return
        if (loaderType !== "vanilla" && loaderVer.trim().length === 0) {
            if (toast) toast.show("请填写 " + loaderType + " 版本号", 2600, "warning")
            return
        }
        var name = instName.trim().length > 0 ? instName.trim() : picked
        if (loaderType === "vanilla") {
            b.installVersion(picked)
        } else {
            b.installModLoader(picked, loaderType, loaderVer.trim(), name)
        }
        if (toast) toast.show("已开始安装 " + name, 2600, "info")
        page.tab = 7
        page.mode = 2
    }

    // 汇总数据：每 400ms 重算（模型是 QAbstractListModel，无法直接绑定）
    Timer {
        interval: 400
        running: page.mode === 2
        repeat: true
        onTriggered: page.recalc()
    }

    function recalc() {
        if (!b || !b.installCardsModel) return
        var m = b.installCardsModel
        var sp = 0, run = 0, prog = 0
        for (var i = 0; i < m.count; ++i) {
            var r = m.get(i)
            if (r.failed) continue
            if (r.progress < 1) {
                run++
                sp += (r.speed || 0)
                prog = Math.max(prog, r.progress || 0)
            }
        }
        totalSpeed = sp
        totalProgress = prog
        runningCount = run
    }

    Component.onCompleted: {
        if (b && b.releaseVersions.length === 0) b.refreshVersionList()
        recalc()
        // 开发期直达进度页
        if (Qt.application.arguments.indexOf("--ui-progress") >= 0) {
            page.tab = 7
            page.mode = 2
        }
    }

    // 页面自带不透明底：背后还压着启动页，不铺底会把启动页透出来
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        z: -1
    }

    // ── 二级导航 ──
    Rectangle {
        id: nav
        width: 160
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "#0a0b0f"
        Rectangle { width: 1; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; color: Theme.line }

        Text {
            text: "下载"
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1.6
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 14
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 38
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 1
            Repeater {
                model: page.tabs
                delegate: Item {
                    id: trow
                    width: parent.width
                    height: 34
                    readonly property bool sel: page.tab === index
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: trow.sel ? "#151a23" : (thover.containsMouse ? "#12151c" : "transparent")
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        spacing: 9
                        SIcon { name: modelData.ic; size: 14; color: trow.sel ? "#ffffff" : Theme.fg2 }
                        Text {
                            text: modelData.l
                            color: trow.sel ? "#ffffff" : Theme.fg2
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: trow.sel ? Font.DemiBold : Font.Normal
                        }
                        Item { Layout.fillWidth: true }
                    }
                    MouseArea {
                        id: thover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            page.tab = index
                            page.mode = (index === 7) ? 2 : 0
                            if (index !== 0 && index !== 7 && toast)
                                toast.show("该分类暂未接入（下一批）", 2200, "info")
                        }
                    }
                }
            }
        }
    }

    // ── 内容区 ──
    Item {
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // 标题行（右侧留 96px 给窗口按钮）
        Item {
            id: head
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 56
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: page.mode === 1 ? "安装配置" : (page.mode === 2 ? "下载进度" : (page.tab === 0 ? "游戏版本" : page.tabs[page.tab].l))
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.weight: Font.Bold
            }
            // 搜索
            Rectangle {
                visible: page.mode === 0
                width: 220
                height: 32
                radius: Theme.rSm
                anchors.right: parent.right
                anchors.rightMargin: 104
                anchors.verticalCenter: parent.verticalCenter
                color: "#0d1016"
                border.color: Theme.line2
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7
                    SIcon { name: "search"; size: 14; color: Theme.fg3 }
                    TextInput {
                        Layout.fillWidth: true
                        text: page.search
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        selectionColor: Theme.accent
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
        }

        // ── 0：版本列表 ──
        Item {
            visible: page.mode === 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: head.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 22
            anchors.rightMargin: 22

            // 过滤条
            Row {
                id: filters
                spacing: 8
                anchors.top: parent.top
                height: 30
                Rectangle {
                    width: segRow.width + 4
                    height: 30
                    radius: Theme.rSm
                    color: "#0d1016"
                    border.color: Theme.line2
                    border.width: 1
                    Row {
                        id: segRow
                        anchors.centerIn: parent
                        Repeater {
                            model: ["正式版", "快照", "旧版", "全部"]
                            delegate: Rectangle {
                                width: segLabel.implicitWidth + 20
                                height: 26
                                radius: 6
                                color: page.filter === index ? "#20262f" : "transparent"
                                Text {
                                    id: segLabel
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: page.filter === index ? "#ffffff" : Theme.fg2
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: page.filter === index ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.filter = index
                                }
                            }
                        }
                    }
                }
                // 只看已安装
                Rectangle {
                    width: instTxt.implicitWidth + 34
                    height: 30
                    radius: Theme.rSm
                    color: page.onlyInstalled ? "#1b2433" : "#0d1016"
                    border.color: page.onlyInstalled ? Theme.accent : Theme.line2
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 11; height: 11; radius: 3
                            color: page.onlyInstalled ? Theme.accent : "transparent"
                            border.color: page.onlyInstalled ? Theme.accent : Theme.fg3
                            border.width: 1
                            SIcon {
                                anchors.centerIn: parent
                                visible: page.onlyInstalled
                                name: "check"
                                size: 9
                                color: "#ffffff"
                            }
                        }
                        Text {
                            id: instTxt
                            text: "只看已安装"
                            color: page.onlyInstalled ? "#cfe0fb" : Theme.fg2
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.onlyInstalled = !page.onlyInstalled
                    }
                }
            }

            // 列头
            Item {
                id: colHead
                anchors.top: filters.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                height: 26
                Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "版本"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Text { anchors.left: parent.left; anchors.leftMargin: 142; anchors.verticalCenter: parent.verticalCenter; text: "类型"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Text { anchors.right: parent.right; anchors.rightMargin: 34; anchors.verticalCenter: parent.verticalCenter; text: "已安装"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Theme.line }
            }

            ListView {
                id: vlist
                anchors.top: colHead.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                model: page.rowList
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: vrow
                    width: vlist.width
                    height: 46
                    Rectangle {
                        anchors.fill: parent
                        color: vhover.containsMouse ? "#0f1218" : "transparent"
                        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: "#10131a" }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 128
                        text: modelData.vid
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        width: kindText.implicitWidth + 12
                        height: 19
                        radius: 5
                        anchors.left: parent.left
                        anchors.leftMargin: 142
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"
                        border.color: page.kindColor(modelData.kind)
                        border.width: 1
                        Text {
                            id: kindText
                            anchors.centerIn: parent
                            text: modelData.kind
                            color: page.kindColor(modelData.kind)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                    Row {
                        visible: modelData.inst
                        anchors.right: parent.right
                        anchors.rightMargin: 34
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Rectangle { width: 5; height: 5; radius: 3; color: "#4ade80"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "已安装"; color: "#5ee08f"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                    }
                    SIcon {
                        name: "chevron-right"; size: 13; color: Theme.fg3
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MouseArea {
                        id: vhover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.pickVersion(modelData.vid)
                    }
                }
            }

            // 空态
            Text {
                visible: vlist.count === 0
                anchors.centerIn: parent
                text: "没有匹配的版本"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }

        // ── 1：安装配置 ──
        Item {
            visible: page.mode === 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: head.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 22
            anchors.rightMargin: 22

            // 返回
            Rectangle {
                id: backBtn
                width: backTxt.implicitWidth + 34
                height: 30
                radius: Theme.rSm
                color: backHover.containsMouse ? "#12151c" : "transparent"
                border.color: Theme.line2
                border.width: 1
                anchors.top: parent.top
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    SIcon { name: "arrow-left"; size: 13; color: Theme.fg2; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: backTxt; text: "返回列表"; color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    id: backHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.mode = 0
                }
            }

            // 左：版本信息
            Column {
                id: infoCol
                width: 300
                anchors.left: parent.left
                anchors.top: backBtn.bottom
                anchors.topMargin: 26
                spacing: 12
                Text {
                    text: page.picked
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 38
                    font.weight: Font.Bold
                }
                Text {
                    text: "正式版 · 安装后可在版本列表启动"
                    color: Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                Item { width: 1; height: 6 }
                Rectangle { width: 300; height: 1; color: Theme.line }
                Item { width: 1; height: 6 }
                Row {
                    spacing: 9
                    SIcon { name: "cpu"; size: 14; color: Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Java 运行时自动匹配"; color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }
                Row {
                    spacing: 9
                    SIcon { name: "folder"; size: 14; color: Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "写入 versions/" + (page.instName.length > 0 ? page.instName : page.picked)
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // 右：选项
            Column {
                anchors.left: infoCol.right
                anchors.leftMargin: 40
                anchors.right: parent.right
                anchors.top: backBtn.bottom
                anchors.topMargin: 22
                spacing: 18

                Text { text: "加载器"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 12 }
                Row {
                    spacing: 7
                    Repeater {
                        model: ["vanilla", "Fabric", "Forge", "NeoForge", "OptiFine"]
                        delegate: Rectangle {
                            width: lab.implicitWidth + 24
                            height: 32
                            radius: Theme.rSm
                            color: page.loaderType === modelData ? "#1b2433" : "#0d1016"
                            border.color: page.loaderType === modelData ? Theme.accent : Theme.line2
                            border.width: 1
                            Text {
                                id: lab
                                anchors.centerIn: parent
                                text: modelData === "vanilla" ? "原版" : modelData
                                color: page.loaderType === modelData ? "#ffffff" : Theme.fg2
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: page.loaderType === modelData ? Font.DemiBold : Font.Normal
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.loaderType = modelData }
                        }
                    }
                }

                Column {
                    visible: page.loaderType !== "vanilla"
                    spacing: 7
                    Text { text: "加载器版本"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 12 }
                    Rectangle {
                        width: 260
                        height: 34
                        radius: Theme.rSm
                        color: "#0d1016"
                        border.color: Theme.line2
                        border.width: 1
                        TextInput {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            verticalAlignment: TextInput.AlignVCenter
                            text: page.loaderVer
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            selectionColor: Theme.accent
                            clip: true
                            onTextChanged: page.loaderVer = text
                            Text {
                                visible: parent.text.length === 0
                                text: page.loaderType === "Fabric" ? "如 0.19.5" : (page.loaderType === "OptiFine" ? "如 HD_U_I6" : "如 47.4.10")
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                Column {
                    spacing: 7
                    Text { text: "安装名称"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 12 }
                    Rectangle {
                        width: 360
                        height: 34
                        radius: Theme.rSm
                        color: "#0d1016"
                        border.color: Theme.line2
                        border.width: 1
                        TextInput {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            verticalAlignment: TextInput.AlignVCenter
                            text: page.instName
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            selectionColor: Theme.accent
                            clip: true
                            onTextChanged: page.instName = text
                        }
                    }
                }
            }

            // 底部操作
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                height: 40
                spacing: 10
                Rectangle {
                    width: 110
                    height: 40
                    radius: Theme.rSm
                    color: Theme.accentTop
                    Text { anchors.centerIn: parent; text: "开始安装"; color: "#ffffff"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.startInstall() }
                }
                Rectangle {
                    width: 90
                    height: 40
                    radius: Theme.rSm
                    color: "transparent"
                    border.color: Theme.line2
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "取消"; color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 13 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.mode = 0 }
                }
            }
        }

        // ── 2：下载进度 ──
        Item {
            visible: page.mode === 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: head.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 22
            anchors.rightMargin: 22

            // 顶部汇总条
            Rectangle {
                id: sumBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 74
                radius: Theme.rSm
                color: "#0b0d12"
                border.color: Theme.line2
                border.width: 1

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text { text: "总进度"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text {
                        text: Math.round(page.totalProgress * 100) + "%"
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 150
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text { text: "总速度"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text {
                        text: (page.totalSpeed / 1048576).toFixed(1) + " MB/s"
                        color: "#dfe6f0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 300
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text { text: "进行中"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text {
                        text: page.runningCount + " 个任务"
                        color: "#dfe6f0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                }
            }

            // 任务列表
            ListView {
                id: cards
                anchors.top: sumBar.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                spacing: 10
                boundsBehavior: Flickable.StopAtBounds
                model: (page.b && page.b.installCardsModel) ? page.b.installCardsModel : null
                delegate: Item {
                    id: card
                    width: cards.width
                    height: card.dismissed ? 0 : 132
                    visible: !card.dismissed
                    property bool dismissed: false
                    property bool notified: false
                    // 模型角色不是属性，必须显式镜像出来才能监听变化
                    property real prog: (typeof progress !== "undefined") ? progress : 0
                    property bool failFlag: (typeof failed !== "undefined") ? failed : false
                    property string cardName: (typeof name !== "undefined" && name) ? name : "任务"
                    property string errText: (typeof error !== "undefined" && error) ? error : ""

                    onProgChanged: {
                        if (!card.notified && card.prog >= 1 && !card.failFlag) {
                            card.notified = true
                            if (page.toast) page.toast.show(card.cardName + " 下载完成", 2600, "success")
                            card.dismissTimer.start()
                        }
                    }
                    onFailFlagChanged: {
                        if (!card.notified && card.failFlag) {
                            card.notified = true
                            if (page.toast) page.toast.show(card.cardName + " 下载失败", 3200, "warning")
                        }
                    }
                    Component.onCompleted: {
                        if (card.failFlag && !card.notified) {
                            card.notified = true
                            if (page.toast) page.toast.show(card.cardName + " 下载失败", 3200, "warning")
                        }
                    }
                    Timer {
                        id: dismissTimer
                        interval: 1600
                        onTriggered: card.dismissed = true
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: failed ? "#141013" : "#0b0d12"
                        border.color: failed ? "#4a2530" : Theme.line2
                        border.width: 1

                        Text {
                            id: nm
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            text: (name || "") + (type ? " · " + type : "")
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.top: parent.top
                            anchors.topMargin: 13
                            text: failed ? "失败" : (progress >= 1 ? "已完成" : ((speed || 0) / 1048576).toFixed(1) + " MB/s")
                            color: failed ? "#f0a0a0" : (progress >= 1 ? "#8fe0aa" : "#9fb6d8")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        // 进度条
                        Rectangle {
                            id: track
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            anchors.top: nm.bottom
                            anchors.topMargin: 10
                            height: 3
                            radius: 2
                            color: "#181c24"
                            Rectangle {
                                width: Math.max(0, Math.min(1, progress || 0)) * track.width
                                height: 3
                                radius: 2
                                color: failed ? "#f87171" : Theme.accent
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.top: track.bottom
                            anchors.topMargin: 9
                            width: parent.width - 150
                            text: failed ? (card.errText.length > 0 ? card.errText : "下载失败，可重试") : (phase || "")
                            color: failed ? "#f0a0a0" : Theme.fg2
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                            spacing: 8
                            Rectangle {
                                visible: canCancel && progress < 1 && !failed
                                width: 66; height: 28; radius: 6
                                color: "transparent"
                                border.color: Theme.line2
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "取消"; color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (page.b && page.b.cancelVersionInstall)
                                            page.b.cancelVersionInstall(iid)
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 14
                            text: (remaining && remaining.length > 0) ? ("剩余 " + remaining) : ""
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !page.b || !page.b.installCardsModel || page.b.installCardsModel.count === 0
                text: "当前没有下载任务"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
    }
}
