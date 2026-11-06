// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Window
import ShadowLauncher.Next

// 下载进度（2026-11-05 从 DownloadPage 拆出的独立页）
// 结构对齐 design/e2 方案 B：顶部标题栏 + 顶部总览条（总进度/总速度/任务/剩余）+ 带步骤的任务卡列表。
// 数据：每 400ms 从 backend.installCardsModel 取快照，按 iid 原地 set/append/remove。
Item {
    id: page
    property var toast: null
    // 模组/资源「文件下载」：由 StageShell 统一收集，这里只负责显示
    property var fileDl: []
    function dlStateText(d) {
        if (d.state === "done") return "已完成"
        if (d.state === "fail") return d.error ? ("失败 · " + d.error) : "失败"
        var pct = d.total > 0 ? Math.round(d.received / d.total * 100) : 0
        return pct + "%" + (d.speed > 0 ? (" · " + (d.speed / 1048576).toFixed(1) + " MB/s") : "")
    }
    readonly property var b: (typeof backend !== "undefined") ? backend : null
    // 窗口宽度而非自身宽度：侧栏收起/展开时自身宽度会变，用它判断会在动画最后一帧
    // 突然从宽布局切到窄布局（用户看到的「最后一刻震动卡一下」）
    readonly property bool narrow: (Window.window ? Window.window.width : width) < 900
    readonly property int padH: narrow ? 32 : 72
    readonly property int padR: narrow ? 28 : 72
    readonly property int topH: narrow ? 56 : 64

    // 进度条流光相位：页面级 0..1，delegate 重建不会打断
    property real flowPhase: 0
    property bool downloading: cardModel.count > 0
    NumberAnimation on flowPhase {
        running: page.downloading
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: Theme.durLoop
    }

    function fmtEta(sec) {
        sec = Math.round(sec || 0)
        if (sec <= 0) return "—"
        if (sec < 60) return sec + " 秒"
        if (sec < 3600) return Math.round(sec / 60) + " 分钟"
        return Math.floor(sec / 3600) + " 小时 " + Math.round((sec % 3600) / 60) + " 分"
    }

    // steps 可能是数组，也可能被 QML 包装成 ListModel（有 get/length）——两种都兼容
    function stepField(src, idx, key) {
        var s = stepAt(src, idx)
        if (!s) return key === "pct" ? 0 : ""
        if (key === "status") return (s.status !== undefined && s.status !== null) ? String(s.status) : "pending"
        if (key === "detail") return (s.detail !== undefined && s.detail !== null) ? String(s.detail) : ""
        if (key === "pct") return (s.percentage !== undefined && s.percentage !== null) ? Number(s.percentage) : 0
        return (s.name !== undefined && s.name !== null) ? String(s.name) : ""
    }

    function stepAt(src, idx) {
        if (!src) return null
        var n = (typeof src.count === "number") ? src.count : (src.length || 0)
        var out = []
        for (var i = 0; i < n; ++i) {
            var it = (typeof src.get === "function") ? src.get(i) : src[i]
            if (it && it.show !== false) out.push(it)
        }
        return idx < out.length ? out[idx] : null
    }

    function countSteps(src) {
        if (!src) return 0
        var n = (typeof src.count === "number") ? src.count : (src.length || 0)
        var c = 0
        for (var i = 0; i < n; ++i) {
            var it = (typeof src.get === "function") ? src.get(i) : src[i]
            if (it && it.show !== false) c++
        }
        return c
    }

    function visibleSteps(src) {
        var out = []
        if (!src) return out
        var n = (typeof src.count === "number") ? src.count : (src.length || 0)
        for (var i = 0; i < n; ++i) {
            var it = (typeof src.get === "function") ? src.get(i) : src[i]
            if (it && it.show !== false) out.push(it)
        }
        return out
    }

    // 汇总
    property real totalSpeed: 0
    property real totalProgress: 0
    property int runningCount: 0
    property var cards: []
    property int tick: 0   // 每 400ms 自增，驱动卡片绑定重算（不重建 delegate，动画才不会被打断）
    property string remainText: "—"
    property var _doneAt: ({})
    Timer {
        interval: 400; repeat: true
        // 页面隐藏时停表：没打开过进度页就不该发"安装完成"通知。
        // 只看宿主可见性：若同时读 page.visible（本项自身），Qt 会报 running 的 binding loop。
        running: page.parent !== null && page.parent.visible
        onTriggered: page.recalc()
    }
    function recalc() {
        if (!b || !b.installCardsModel) return
        var m = b.installCardsModel
        if (!m.cardDataAt) return
        var list = [], sp = 0, run = 0, prog = 0, eta = 0
        for (var i = 0; i < m.count; ++i) {
            var r = m.cardDataAt(i)
            if (!r) continue
            var done = !r.failed && (r.progress || 0) >= 1
            if (done) {
                if (!page._doneAt[r.iid]) {
                    page._doneAt[r.iid] = Date.now()
                    if (page.toast) page.toast.show((r.name || "任务") + " 安装完成", 2600, "success")
                    if (page.b.refreshInstalled) page.b.refreshInstalled()
                }
                continue
            }
            list.push({
                iid: r.iid, name: r.name, phase: r.phase,
                progress: r.progress || 0, speed: r.speed || 0, eta: r.eta || 0,
                steps: (r.steps || []).map(function(s) {
                    return { name: s.name, detail: s.detail, status: s.status, percentage: s.percentage, show: s.show }
                }), failed: r.failed, error: r.error || "",
                canCancel: r.canCancel, canRetry: r.canRetry
            })
            if (!r.failed) {
                run++
                sp += (r.speed || 0)
                prog = Math.max(prog, r.progress || 0)
                eta = Math.max(eta, r.eta || 0)
            }
        }
        // 同步进 ListModel：已存在则原地 set（role 变化会通知 delegate），否则 append
        var seenIds = {}
        for (var n = 0; n < list.length; ++n) {
            var item = list[n]
            seenIds[item.iid] = true
            var row = -1
            for (var r = 0; r < cardModel.count; ++r) {
                if (cardModel.get(r).iid === item.iid) { row = r; break }
            }
            if (row < 0) {
                cardModel.append(item)
            } else {
                cardModel.set(row, item)
            }
        }
        for (var d = cardModel.count - 1; d >= 0; --d) {
            if (!seenIds[cardModel.get(d).iid]) cardModel.remove(d)
        }
        page.totalSpeed = sp
        page.totalProgress = prog
        page.runningCount = run
        page.remainText = page.fmtEta(eta)
    }

    Component.onCompleted: page.recalc()

    // 进度卡片的稳定模型：JS 数组每次替换会重建 delegate，动画被打断；ListModel 支持原地更新
    ListModel { id: cardModel }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // 顶部栏（与下载页同一高度/边距，避免切页跳动）
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: page.topH

        Text {
            anchors.left: parent.left
            anchors.leftMargin: page.padH
            anchors.verticalCenter: parent.verticalCenter
            text: "下载进度"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.weight: Font.Bold
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: page.padH
        anchors.rightMargin: page.padR
        anchors.topMargin: 12

        // 顶部总览条
        Rectangle {
            id: sumBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 76
            radius: 10
            color: "#0b0d12"
            border.color: Theme.line2
            border.width: 1

            // 三块统计各自固定宽度：速度/任务/剩余的数字变宽变窄都只发生在列内，
            // 列宽不参与布局，所以相邻列零位移（之前用 implicitWidth 的 Row，速度一变就互挤）。
            // 总进度列吃掉剩下的空间——它只随窗口宽度变化，与速度无关。
            Column {
                id: progCol
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.right: statsRow.left
                anchors.rightMargin: 36
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text { text: "总进度"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Text {
                    width: parent.width
                    text: Math.round(page.totalProgress * 100) + "%"
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignLeft
                }
                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 2
                    color: "#181c24"
                    Rectangle {
                        width: Math.max(0, Math.min(1, page.totalProgress)) * parent.width
                        height: 3
                        radius: 2
                        color: Theme.accent
                    }
                }
            }

            Row {
                id: statsRow
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 36

                // 固定列宽 + 数值 Text 固定 width 左对齐：数字长短只影响列内空白
                Column {
                    width: 150
                    spacing: 4
                    Text { text: "总速度"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text {
                        width: parent.width
                        text: (page.totalSpeed / 1048576).toFixed(1) + " MB/s"
                        color: "#dfe6f0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignLeft
                    }
                }
                Column {
                    width: 104
                    spacing: 4
                    Text { text: "任务"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text {
                        width: parent.width
                        text: page.runningCount + " 进行中"
                        color: "#dfe6f0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignLeft
                    }
                }
                Column {
                    width: 132
                    spacing: 4
                    Text { text: "剩余"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text {
                        width: parent.width
                        text: page.remainText
                        color: "#dfe6f0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignLeft
                    }
                }
            }
        }

        // 文件下载（模组/资源）：后端只发信号没有 model，条目来自 StageShell
        Item {
            id: dlBlock
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: sumBar.bottom
            anchors.topMargin: page.fileDl.length > 0 ? 12 : 0
            height: page.fileDl.length > 0 ? (24 + Math.min(4, page.fileDl.length) * 20) : 0
            visible: page.fileDl.length > 0

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "#0b0d12"
                border.color: Theme.line2
                border.width: 1
            }
            Column {
                anchors.left: parent.left; anchors.leftMargin: 18
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: page.fileDl.slice(-4).reverse()
                    delegate: Item {
                        width: parent.width
                        height: 14
                        Text {
                            anchors.left: parent.left
                            anchors.right: stText.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name || "文件"
                            color: Theme.fg2
                            elide: Text.ElideMiddle
                            font.family: Theme.fontFamily; font.pixelSize: 12
                        }
                        Text {
                            id: stText
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.dlStateText(modelData)
                            color: modelData.state === "done" ? "#5ee08f"
                                 : (modelData.state === "fail" ? "#e28a8a" : "#8fb6f8")
                            font.family: Theme.fontFamily; font.pixelSize: 12
                        }
                    }
                }
            }
        }

        // 任务卡
        ListView {
            id: taskList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: dlBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            clip: true
            spacing: 10
            boundsBehavior: Flickable.StopAtBounds
            model: cardModel
            delegate: Rectangle {
                id: tcard
                width: taskList.width
                // 高度只依赖 stepCount（计数），不依赖 cardSteps 数组，
                // 否则 height <-> cardSteps 会形成 binding loop，delegate 反复重建、动画被重置。
                height: 46 + 10 + 3 + 8 + stepCount * 23 + 12 + 32 + 12
                readonly property int stepCount: page.countSteps(steps)
                radius: 10
                color: tcard.isFailed ? "#141013" : "#0b0d12"
                border.color: tcard.isFailed ? "#4a2530" : Theme.line2
                border.width: 1

                // 角色名在 delegate 里直接可用（不是 model.xxx）。
                // 这里不再包一层 JS 对象：对象每次角色变化都会重建，
                // 与 height <- cardSteps.length 形成 binding loop，导致 delegate 反复刷新。
                readonly property bool isFailed: failed
                readonly property real pv: progress || 0
                readonly property real sp: speed || 0
                readonly property string ph: phase || ""
                readonly property string cardName: name || ""
                readonly property string cardError: error || ""
                readonly property string cardIid: iid
                readonly property bool cardCanRetry: canRetry
                readonly property bool cardCanCancel: canCancel

                // 速度归零持续 1.2s 才算"停滞"（避免刚开始还没测速时闪一下流光）
                property bool stalled: false
                Timer {
                    id: stallTimer
                    interval: 1200
                    repeat: false
                    running: { var t = page.tick; return !tcard.isFailed && tcard.pv < 1 && tcard.sp <= 0 }
                    onTriggered: tcard.stalled = (!tcard.isFailed && tcard.pv < 1 && tcard.sp <= 0)
                }
                onSpChanged: if (tcard.sp > 0) tcard.stalled = false

                // 头部
                Rectangle {
                    id: icBox
                    x: 14
                    anchors.verticalCenter: headRow.verticalCenter
                    width: 30
                    height: 30
                    radius: 8
                    color: tcard.isFailed ? Qt.rgba(0.973, 0.443, 0.443, .06) : "#12161d"
                    border.color: tcard.isFailed ? Qt.rgba(0.973, 0.443, 0.443, .25) : "#1c212a"
                    border.width: 1
                    SIcon {
                        anchors.centerIn: parent
                        name: tcard.isFailed ? "alert-triangle" : "box"
                        size: 15
                        color: tcard.isFailed ? "#e0a0a0" : "#9fb0c6"
                    }
                }
                Row {
                    id: headRow
                    anchors.left: icBox.right
                    anchors.leftMargin: 10
                    anchors.right: headRight.left
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    spacing: 0
                    Column {
                        spacing: 2
                        Text {
                            text: tcard.cardName
                            color: "#e8ebf2"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: tcard.isFailed ? "部分失败" : tcard.ph
                            color: tcard.isFailed ? "#f0a0a0" : Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }
                Row {
                    id: headRight
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: headRow.verticalCenter
                    spacing: 6
                    Text {
                        text: tcard.isFailed ? "0 MB/s"
                              : ((tcard.sp / 1048576).toFixed(1) + " MB/s · "
                                 + Math.round(tcard.pv * 100) + "%")
                        color: tcard.isFailed ? "#f0a0a0" : "#9fb6d8"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                // 总进度线（clip：流光只在轨道内走，越界部分被裁掉——"穿模"的根治手段）
                Rectangle {
                    id: bar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.top: parent.top
                    anchors.topMargin: 56
                    height: 3
                    radius: 2
                    clip: true
                    color: "#181c24"
                    // 已填充段：流光放在**这一层里面**，所以它永远只出现在已经走过的区域，
                    // 不可能穿到未填充的轨道上（clip 就是"不穿模"的保证，不是靠算位置）。
                    Rectangle {
                        id: fillBar
                        width: Math.max(0, Math.min(1, tcard.pv)) * parent.width
                        height: 3
                        radius: 2
                        color: tcard.isFailed ? "#f87171" : Theme.accent
                        clip: true
                        // 真实进度也要平滑地"走过去"，而不是每 400ms 跳一格
                        Behavior on width { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }

                        // Google 风格流光：整段下载期间一直跑，而不是只在停滞时闪一下。
                        // 宽度取自身宽度（父级），相位读页面级 flowPhase —— delegate 重建也不会打断。
                        Rectangle {
                            id: shine
                            visible: fillBar.width > 6 && !tcard.isFailed && (tcard.pv < 1)
                            width: Math.max(28, fillBar.width * 0.35)
                            height: parent.height
                            radius: height / 2
                            color: "#dce9ff"
                            opacity: 0.5
                            x: -shine.width + page.flowPhase * (fillBar.width + shine.width)
                        }
                    }
                }

                // 失败信息
                Text {
                    visible: tcard.isFailed
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.top: bar.bottom
                    anchors.topMargin: 8
                    text: tcard.cardError.length > 0 ? tcard.cardError : "安装失败，可重试"
                    color: "#f2a3a3"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                // 步骤列表
                Column {
                    id: stepsCol
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.top: bar.bottom
                    anchors.topMargin: tcard.isFailed ? 30 : 8
                    spacing: 0
                    Repeater {
                        // 固定 4 个槽位：step 数据每 400ms 变一次。
                        // 若模型是"数组"，数组一换 delegate 就重建，Canvas 动画会每 400ms 重启 → 抽搐。
                        model: 4
                        delegate: Item {
                            width: stepsCol.width
                            // 只绑原始值（字符串/数字），不绑对象：返回对象会让 QML 认为
                            // 每次求值都产生新值，触发 binding loop，delegate 反复刷新 → 动画重启。
                            readonly property string stepName: page.stepField(steps, index, "name")
                            readonly property string st: page.stepField(steps, index, "status")
                            readonly property string stepDetail: page.stepField(steps, index, "detail")
                            readonly property real stepPct: page.stepField(steps, index, "pct")
                            height: stepName.length > 0 ? 23 : 0
                            visible: stepName.length > 0
                            Item {
                                id: dot
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter

                                // 待开始 / 完成：静态环（完成带对勾，不再用实心点，避免圆心偏移）
                                Rectangle {
                                    visible: st !== "active"
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: st === "completed" ? Qt.rgba(0.290, 0.871, 0.502, 0.12) : "transparent"
                                    border.color: st === "completed" ? "#4ade80" : "#2a313c"
                                    border.width: 1.5
                                }

                                // 不确定环：C++ 场景图 item（QQuickItem + QSGNode，见 src/ui_next/dl_spinner_item.cpp）。
                                // 几何在 updatePaintNode 里重建，相位由节点自己的 16ms 定时器推进，
                                // QML 侧没有任何逐帧绑定——卡片数据每 400ms 刷新、delegate 重建都打断不了它。
                                DlSpinner {
                                    visible: st === "active"
                                    width: 16
                                    height: 16
                                    running: visible
                                    color: "#3b82f6"
                                    trackColor: "#232a34"
                                }
                            }
                            Text {
                                anchors.left: dot.right
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                text: stepName
                                color: st === "completed" ? "#95a1b0" : (st === "active" ? "#ffffff" : Theme.fg3)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: st === "completed" ? "完成" : (st === "active" ? (stepDetail.length > 0 ? stepDetail : (stepPct + "%")) : "")
                                color: st === "active" ? "#7cb0fb" : Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    text: tcard.isFailed ? "" : page.remainText
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                // 操作行
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    spacing: 8
                    // 与登录页统一：SButton ghost + 直角(radius 2) + 图标；
                    // 取消是危险动作 → danger 红镶边（kind 1 / radius 2 / height 30，与登录页同规格）
                    SButton {
                        visible: tcard.isFailed && tcard.cardCanRetry
                        kind: 1
                        radius: 2
                        height: 30
                        width: 84
                        danger: true
                        iconName: "rotate-ccw"
                        text: "重试"
                        onClicked: if (page.b && page.b.retryVersionInstall)
                                       page.b.retryVersionInstall(tcard.cardIid)
                    }
                    SButton {
                        visible: tcard.cardCanCancel && !tcard.isFailed
                        kind: 1
                        radius: 2
                        height: 30
                        width: 84
                        danger: true
                        iconName: "x"
                        text: "取消"
                        onClicked: if (page.b && page.b.cancelVersionInstall)
                                       page.b.cancelVersionInstall(tcard.cardIid)
                    }

                }
            }

            Text {
                anchors.centerIn: parent
                visible: cardModel.count === 0 && page.fileDl.length === 0
                text: "当前没有下载任务"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
    }
}
