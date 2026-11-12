// SPDX-License-Identifier: AGPL-3.0-or-later
// 启动页 —— 首屏只回答：玩哪个 / 要不要启动
import QtQuick
import ShadowLauncher.Next

Item {
    id: page
    property Window hostWindow: null
    /// 打开版本管理（由 StageShell 接管：侧栏收起 + 版本页全宽）
    signal openVersions()
    /// 打开账户页（点右上胶囊 / 未登录时点主按钮）
    signal openAccount()
    signal openSettings(string versionId)
    readonly property var yg: (b && b.yggdrasil) ? b.yggdrasil : null
    /// 有可用账号：正版在线登录 / 设置过离线名 / 外置账号已登录。
    /// 少了外置这一条时，切到外置账号后首页会一直显示「还没有登录账号」+「先登录」，
    /// 而账户页明明显示已登录（影报的就是这个）。
    // 单一真源：当前账号类型 + 该类型的会话（由 ShadowBackend::activeAccount* 统一回答）。
    // 以前这里自己拼 isOnline / offlineUsername / yg.loggedIn，三处分支注定和账户页、
    // 启动预检对不上（选了账号A首页却不认A，就是这个）。
    readonly property bool hasAccount: b ? (b.activeAccountMode >= 0 && (b.activeAccountName || "").length > 0) : false

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property var toast: null          // StageShell 注入的 ToastHost
    // narrow 必须由整窗宽度决定（StageShell 注入）。页面自己的 width 是"内容区宽"
    // （已扣掉侧栏），拿它和 900 比会让 1100 宽的窗口被判成窄窗、标题从 58 掉到 34。
    property bool narrow: false
    readonly property string ver: (b && b.selectedVersion) ? b.selectedVersion : ""
    readonly property string userName: b ? (b.activeAccountName || "") : ""
    // 演示态：--ui-demo-launch 由后端假状态机驱动真实浮层组件（不检测 Java、不拉文件、
    // 不起进程），--ui-demo-fail 走失败分支。演示走的是与真机同一条管线代码路径。
    readonly property bool demoMode: Qt.application.arguments.indexOf("--ui-demo-launch") >= 0
    readonly property bool demoFail: Qt.application.arguments.indexOf("--ui-demo-fail") >= 0
    readonly property bool demoOnline: Qt.application.arguments.indexOf("--ui-demo-online") >= 0

    readonly property bool launching: b ? b.launching : false
    readonly property bool running: b ? b.isRunning : false
    // C3：运行中实例列表（多开 / 逐进程结束）。runningCount 变化时整体重取。
    property var runningList: []
    property bool procOpen: false
    property double nowSec: Date.now() / 1000

    function refreshRunningList() {
        page.runningList = (b && b.runningCount > 0) ? b.runningGames() : []
        if (page.runningList.length === 0) page.procOpen = false
    }
    // startedAt 是后端新补的字段（epoch 秒）；没有就只显示 PID
    function uptimeText(row) {
        var st = (row && row.startedAt) ? Number(row.startedAt) : 0
        if (st <= 0) return ""
        var s = Math.max(0, Math.floor(page.nowSec - st))
        if (s < 60) return s + " 秒"
        if (s < 3600) return Math.floor(s / 60) + " 分钟"
        return Math.floor(s / 3600) + " 小时 " + Math.floor((s % 3600) / 60) + " 分"
    }
    readonly property string statusText: b ? (b.launchStatus || "") : ""

    readonly property int padL: narrow ? 28 : Theme.padL
    readonly property int padR: narrow ? 24 : 64


    // "1.20.1-Fabric_0.16.9" → 主 [1.20.1] / 副 [Fabric 0.16.9]
    readonly property var verParts: {
        if (ver.length === 0) return ["", ""]
        var i = ver.indexOf("-")
        if (i < 0) i = ver.indexOf("_")
        if (i <= 0) return [ver, ""]
        return [ver.substring(0, i), ver.substring(i + 1).split("_").join(" ")]
    }

    Component.onCompleted: {
        console.info("[ui] StagePage size", width, "x", height, "narrow=", narrow)
        page.refreshRunningList()
        if (page.demoMode && page.b)
            page.b.demoLaunch((page.demoFail ? 1 : 0) + (page.demoOnline ? 2 : 0))
        // 验收钩子：--launch-now 自动点一次「启动游戏」（走与按钮完全相同的路径，用于
        // 三种账号类型各跑一遍预检/身份，不必手点）。只在传参时触发。
        if (Qt.application.arguments.indexOf("--launch-now") >= 0) {
            launchNowTimer.start()
        }
    }

    Timer {
        id: launchNowTimer
        interval: 1200
        onTriggered: {
            if (!page.b) return
            if (!page.ver || page.ver.length === 0) {
                console.info("[ui] --launch-now: 没有选中版本，跳过")
                return
            }
            console.info("[ui] --launch-now: 启动", page.ver, "身份=", page.userName)
            page.b.launch(page.ver, page.b.activeAccountOnline)
        }
    }

    Connections {
        target: page.b
        ignoreUnknownSignals: true
        function onRunningCountChanged() { page.refreshRunningList() }
    }

    // 面板开着时每 15 秒刷新一次"运行了多久"
    Timer {
        interval: 15000
        repeat: true
        running: page.procOpen
        onTriggered: page.nowSec = Date.now() / 1000
    }

    // ---------- 底色 ----------
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    // ---------- 背景 ----------
    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: (page.b && page.b.customBgPath && page.b.customBgPath.length > 0)
                ? ("file:///" + page.b.customBgPath)
                : "qrc:/ui/stage-aurora.jpg"
    }

    // ---------- 遮罩 ----------
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.70
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#0005080e" }
            GradientStop { position: 0.30; color: "#2805080e" }
            GradientStop { position: 0.62; color: "#8c05080e" }
            GradientStop { position: 1.00; color: "#f005080e" }
        }
    }
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: parent.width * (page.narrow ? 0.72 : 0.62)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.00; color: "#b805080e" }
            GradientStop { position: 0.46; color: "#2e05080e" }
            GradientStop { position: 1.00; color: "#0005080e" }
        }
    }
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.40
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#a005080e" }
            GradientStop { position: 0.34; color: "#1a05080e" }
            GradientStop { position: 0.80; color: "#0005080e" }
        }
    }

    // ---------- 顶栏：账户 ----------
    SAcctChip {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: page.narrow ? 96 : Theme.padR
        anchors.topMargin: page.narrow ? 7 : 10
        backend: page.b
        name: page.userName
        // 「在线」要包含外置登录：外置账号的后端 isOnline 是 false（那是微软会话的标志），
        // 只读它会把外置账号显示成离线 —— 橙点 + 字母头像（影报的正是这个）。
        online: page.b ? page.b.activeAccountOnline : false
        status: (page.b && page.b.activeAccountOnline) ? 0 : 1
        // 原始皮肤优先（后端 renderHead3D 对部分皮肤会渲染出错误的头图）；只有正版有
        rawSkinSource: page.b ? (page.b.activeAccountSkin || "") : ""
        skinSource: page.b ? (page.b.activeAccountAvatar || "") : ""
        onClicked: page.openAccount()
    }

    // 窗口按钮由 StageShell 统一挂在最上层（版本页 / 账户页这类全屏页也要能用）

    // ---------- 底：操作 ----------
    Row {
        id: actionsRow
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: page.padL
        anchors.bottomMargin: page.narrow ? 34 : Theme.padB
        spacing: 10

        SButton {
            id: launchBtn
            kind: 0
            busy: page.launching
            // 未登录：灰态但可点（点了去登录），不是 dimmed（dimmed 是不可点）
            muted: !page.hasAccount && !page.launching
            dimmed: page.launching || page.ver.length === 0
            // C3：有实例在跑时按钮本身变成"运行中 N"，点它=再开一个，
            // 看/结束具体进程走右边的箭头。
            text: page.launching ? "取消启动"
                  : (page.runningList.length > 0 ? ("运行中 " + page.runningList.length)
                     : (!page.hasAccount ? "先登录" : "启动游戏"))
            iconName: page.launching ? "x" : (!page.hasAccount ? "lock" : "play")
            onClicked: {
                if (!page.b) return
                if (page.launching) { page.b.cancelLaunch(); return }
                if (!page.hasAccount) { page.openAccount(); return }
                if (page.ver.length === 0) return
                page.b.launch(page.ver, page.b.activeAccountOnline)   // 允许多开：再开一个该版本
            }
        }
        // 只留箭头、不画方框：方框和主按钮圆角/边框都不是一套，怎么摆都像错位。
        // 点击区仍然是 32x48（够大），但视觉上只有一枚会翻转的箭头。
        Item {
            id: procBtn
            visible: page.runningList.length > 0
            width: 32
            height: launchBtn.height

            // 不用 rotation 翻转：SIcon 内部是 MultiEffect 离屏着色，转父项会把图层裁一半。
            // 改用 up/down 两张图标交叉淡入，观感等价且不会裁切。
            SIcon {
                id: chevDown
                anchors.centerIn: parent
                name: "chevron-down"
                size: 15
                color: procHover.containsMouse ? Theme.fg : Theme.fg3
                opacity: page.procOpen ? 0 : 1
                Behavior on color {
                    ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
            }
            SIcon {
                anchors.centerIn: parent
                name: "chevron-up"
                size: 15
                color: procHover.containsMouse ? Theme.fg : Theme.fg3
                opacity: page.procOpen ? 1 : 0
                Behavior on color {
                    ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
            }
            MouseArea {
                id: procHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.procOpen = !page.procOpen
            }
        }
        SButton { kind: 1; text: "版本"; iconName: "list"; onClicked: page.openVersions() }
        SButton {
        kind: 1
        text: "设置"
        iconName: "settings"
        // 之前这里是 console.info 空实现，点了没反应
        onClicked: page.openSettings(page.b ? page.b.selectedVersion : "")
    }
    }

    // ---------- C3：运行中进程面板 ----------
    MouseArea {
        anchors.fill: parent
        visible: page.procOpen
        // 点外部关闭：必须压住标题/按钮，但要让下面的面板（z 更高）继续可点
        z: 100
        onClicked: page.procOpen = false
    }

    Rectangle {
        id: procPanel
        z: 110
        visible: opacity > 0.01
        opacity: page.procOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durFast
                easing.type: page.procOpen ? Theme.easeEnter : Theme.easeExit
            }
        }
        transform: Translate {
            y: page.procOpen ? 0 : 6
            Behavior on y {
                NumberAnimation {
                    duration: Theme.durFast
                    easing.type: page.procOpen ? Theme.easeEnter : Theme.easeExit
                }
            }
        }
        anchors.left: actionsRow.left
        anchors.bottom: actionsRow.top
        anchors.bottomMargin: 10
        width: 330
        height: procCol.height + 16
        color: "#0c0f14"
        border.width: 1
        border.color: "#262d38"
        radius: 2

        Column {
            id: procCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 8
            spacing: 0

            Text {
                width: procCol.width - 24
                leftPadding: 12
                height: 18
                verticalAlignment: Text.AlignVCenter
                text: "正在运行的实例"
                color: "#4f5866"
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Repeater {
                model: page.runningList
                delegate: Item {
                    width: procCol.width
                    height: 44
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        width: parent.width - 84
                        text: modelData.displayVersion
                        color: "#d7dfea"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 23
                        text: "PID " + modelData.pid
                              + (page.uptimeText(modelData).length > 0
                                 ? " · " + page.uptimeText(modelData) : "")
                        color: "#5f6875"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    SButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        kind: 1
                        text: "结束"
                        onClicked: { if (page.b) page.b.killGameByPid(modelData.pid) }
                    }
                }
            }

            Rectangle { width: procCol.width; height: 1; color: "#161b22" }

            Item {
                width: procCol.width
                height: 42
                SButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    kind: 1
                    danger: true
                    text: "全部结束"
                    onClicked: {
                        page.procOpen = false
                        if (page.b) page.b.killGameProcess()
                    }
                }
            }
        }
    }

    // ---------- 中：标题 ----------
    Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: actionsRow.top
        anchors.leftMargin: page.padL
        anchors.rightMargin: page.padR
        anchors.bottomMargin: page.narrow ? 20 : 34
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: {
            if (page.verParts[0].length === 0) return "未选择版本"
            if (page.verParts[1].length === 0) return page.verParts[0]
            return page.verParts[0] + " <font color=\"#9fb4cf\">" + page.verParts[1] + "</font>"
        }
        color: "#ffffff"
        font.family: Theme.fontFamily
        font.pixelSize: page.narrow ? 34 : 58
        font.weight: Font.Bold
        font.letterSpacing: page.narrow ? -0.6 : -1.6
    }

    // ---------- 标题上方那一行（kicker） ----------
    // 同一处只放一件事，按优先级取第一个有意义的：
    //   启动中 → 后端当前阶段原串；游戏中 → 游戏运行中；常态 → 上次游玩（真实记录，没有就不显示）
    // 绝不显示"准备就绪/加载完成"这类状态噪音（README 第 6 条）；失败原因由浮层负责。
    readonly property string lastPlayed: (b && b.lastPlayedLabel) ? b.lastPlayedLabel : ""
    readonly property string kicker: {
        if (page.launching) return page.statusText.length > 0 ? page.statusText : "正在准备启动"
        if (page.running) return "游戏运行中"
        if (!page.hasAccount) return "还没有登录账号"
        if (page.lastPlayed.length > 0) return "上次游玩 · " + page.lastPlayed
        return ""
    }
    readonly property bool kickerWarn: !page.hasAccount && !page.launching && !page.running

    Row {
        anchors.left: parent.left
        anchors.bottom: titleText.top
        anchors.leftMargin: page.padL
        anchors.bottomMargin: 15
        spacing: 9
        visible: page.kicker.length > 0

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 1
            color: page.launching ? Theme.accent
                   : (page.running ? Theme.ok
                      : (page.kickerWarn ? Theme.warn : Theme.fg3))
        }
        Text {
            text: page.kicker
            color: page.kickerWarn ? "#d8a24a" : Theme.fg2
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1.0
        }
    }
}