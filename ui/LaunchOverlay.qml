// SPDX-License-Identifier: AGPL-3.0-or-later
// 启动浮层：主界面中央，总进度条（上）+ 启动阶段节点清单（下）
// 节点数量/名称/顺序全部来自后端 launchStepRows，QML 不写死任何节点。
// 契约：design-2026-11-04/LAUNCH_OVERLAY_SPEC.md
//   · 面板 radius 2（视觉直角），内部一律直角，没有嵌套圆角
//   · 节点 8x8 直角方点，不用圆点
//   · 总进度是阶段级（已完成节点/可见节点），节点内字节进度只放子行
//   · 取消是唯一入口，且不用红色；失败态常驻到用户处理
import QtQuick
import ShadowLauncher.Next

Item {
    id: root

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var rows: b ? b.launchStepRows : []
    readonly property real overall: b ? b.launchOverallProgress : 0
    readonly property int stepNo: b ? b.launchStepNumber : 0
    readonly property int stepTotal: b ? b.launchStepCount : 0
    readonly property bool failed: b ? b.launchFailed : false
    readonly property bool done: b ? b.launchFinishedOk : false
    readonly property bool busy: b ? b.launching : false
    readonly property string failReason: (b && b.launchFailReason) ? b.launchFailReason : ""
    readonly property string verName: (b && b.selectedVersion) ? b.selectedVersion : ""
    readonly property string userName: b ? (b.activeAccountName || "") : ""
    readonly property bool debugOverlay: Qt.application.arguments.indexOf("--ui-overlay-debug") >= 0
    // A2「准备运行环境」的行数据：{key,name,detail,progress,state}，空=本次无需补全
    readonly property var repairs: b ? b.launchRepairs : []
    readonly property int repairRowH: 30

    function repairsCardHeight() {
        return root.repairs.length * root.repairRowH + 60
    }
    function repairPendingCount() {
        var n = 0
        for (var i = 0; i < root.repairs.length; ++i) {
            if (root.repairs[i].state !== 2) ++n
        }
        return n
    }
    // B1 失败面板：lastCrash 是后端两份诊断（预检失败 / 崩溃分析完成）的统一出口
    readonly property var crash: b ? b.lastCrash : ({})
    readonly property bool crashAnalyzing: b ? b.crashAnalyzing : false
    readonly property bool crashReady: crash && crash.isValid === true
    property string exportHint: ""

    function crashTypeText() {
        var t = (crash && crash.type) ? String(crash.type) : ""
        if (t === "precheck") return "启动前检查未通过"
        if (t === "jvm") return "JVM 崩溃"
        if (t === "minecraft") return "游戏崩溃"
        if (t.length > 0) return t
        return root.failReason.length > 0 ? "启动失败" : ""
    }
    function crashReasonText() {
        var r = (crash && crash.reason) ? String(crash.reason) : ""
        return r.length > 0 ? r : root.failReason
    }
    function crashModsText() {
        var list = (crash && crash.suspectedMods) ? crash.suspectedMods : []
        if (!list || list.length === 0) return ""
        var n = Math.min(list.length, 4)
        var parts = []
        for (var i = 0; i < n; ++i) parts.push(String(list[i]))
        var s = parts.join(" · ")
        if (list.length > n) s += " 等 " + list.length + " 个"
        return s
    }
    function crashKvRows() {
        var rows = []
        var t = crashTypeText()
        if (t.length > 0) rows.push({ k: "类型", v: t })
        var ts = (crash && crash.timestamp) ? String(crash.timestamp) : ""
        if (ts.length > 0) rows.push({ k: "时间", v: ts.replace("T", " ") })
        var m = crashModsText()
        if (m.length > 0) rows.push({ k: "疑似", v: m })
        return rows
    }
    function crashSuggestions() {
        var list = (crash && crash.suggestions) ? crash.suggestions : []
        if (!list) return []
        var out = []
        for (var i = 0; i < Math.min(list.length, 3); ++i) out.push(String(list[i]))
        return out
    }
    function crashCardHeight() {
        var h = 0
        h += reasonTx.implicitHeight + 16          // 原因条
        h += 10 + crashKvRows().length * 20        // 键值行
        var sug = crashSuggestions()
        if (sug.length > 0) h += 16 + 14 + sug.length * 22
        return h
    }

    function repairValueText(r) {
        var d = (r.detail === undefined || r.detail === null) ? "" : String(r.detail)
        if (r.state === 2) return "已就绪"
        if (r.state === 3) return d.length > 0 ? d : "失败"
        var pct = Math.round(r.progress)
        return pct + "%" + (d.length > 0 ? " · " + d : "")
    }

    // 失败 / 完成态也要留在屏幕上：只认 launching 会把错误连同原因一起藏掉
    readonly property bool active: b ? (b.launching || b.launchFailed || b.launchFinishedOk) : false
    // 关闭时等透明度真正降下去才隐藏，否则会硬切（/eval 读状态时也更好观察）
    visible: active || opacity > 0.01
    opacity: active ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Theme.durSlow; easing.type: root.active ? Theme.easeEnter : Theme.easeExit }
    }
    z: 200

    function statusText(s) {
        if (s === 2) return "完成"
        if (s === 1) return "进行中"
        if (s === 3) return "失败"
        if (s === 4) return "跳过"
        return ""
    }
    function statusColor(s) {
        if (s === 2) return "#5bbd85"
        if (s === 1) return "#8fbcf5"
        if (s === 3) return "#ff9a94"
        return "#3f4754"
    }
    function nodeColor(s) {
        if (s === 2) return "#3b82f6"
        if (s === 1) return "#60a5fa"
        if (s === 3) return "#ef4444"
        return "#2a3140"
    }
    function nodeTextColor(s) {
        if (s === 1) return "#ffffff"
        if (s === 3) return "#ffb4b0"
        if (s === 2) return "#8b96a4"
        return "#5f6875"
    }
    function rowDetail(d) {
        return (d === undefined || d === null) ? "" : String(d)
    }
    function rowHasDetail(r) {
        var d = rowDetail(r.detail)
        // 失败节点的原因现在由下方诊断块统一承载（红色原因条），
        // 子行再写一遍就是同一句话出现两次，因此只保留"进行中"的子行。
        return d.length > 0 && r.status === 1
    }
    // 面板高度必须立刻可算：ListView.contentHeight 要等委托建好才准，
    // 会让面板高度慢一拍（实测：6 节点时底部元素上移 18px）。
    function rowsHeight() {
        var h = 0
        for (var i = 0; i < root.rows.length; ++i)
            h += rowHasDetail(root.rows[i]) ? 52 : 38
        return h
    }

    // 遮罩：启动中点击不关闭（唯一出口是右下角按钮）
    Rectangle {
        anchors.fill: parent
        color: "#9e06080c"
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }
    }

    Rectangle {
        id: panel
        width: Math.min(600, root.width - 96)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: body.implicitHeight + 36
        color: "#0c0f14"
        border.width: 1
        border.color: "#262d38"
        radius: 2
        // 出现时从下方 12px 浮上来
        transform: Translate {
            y: root.active ? 0 : 12
            Behavior on y {
                NumberAnimation { duration: Theme.durSlow; easing.type: root.active ? Theme.easeEnter : Theme.easeExit }
            }
        }

        Column {
            id: body
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.top: parent.top
            anchors.topMargin: 20
            spacing: 0

            // ---- 标题行 ----
            Item {
                width: body.width
                height: 20
                Rectangle {
                    id: failMark
                    width: 12
                    height: 12
                    visible: root.failed
                    color: "transparent"
                    border.width: 1.5
                    border.color: "#ef4444"
                    anchors.left: parent.left
                    anchors.verticalCenter: titleTx.verticalCenter
                    Rectangle {
                        width: 1.5
                        height: 5
                        anchors.centerIn: parent
                        color: "#ef4444"
                    }
                }
                Text {
                    id: titleTx
                    // 失败时给左侧留出感叹号方块的位置
                    anchors.left: parent.left
                    anchors.leftMargin: root.failed ? 19 : 0
                    Behavior on anchors.leftMargin {
                        NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                    }
                    text: root.failed ? ("启动失败 · " + root.verName)
                                      : ("启动 " + root.verName)
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.left: titleTx.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: titleTx.verticalCenter
                    text: root.userName
                    color: "#5f6875"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: root.failed
                    text: root.crashAnalyzing ? "正在分析日志…"
                                               : (root.crashReady ? "崩溃报告已生成" : "")
                    color: root.crashAnalyzing ? "#c9a06a" : "#7b8593"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: !root.failed
                    text: "第 " + root.stepNo + " / " + root.stepTotal + " 步"
                    color: "#4f5866"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            // ---- 总进度（阶段级） ----
            // 失败后收起：失败态的信息是"原因/建议"，进度条只会挤地方（B1 稿）。
            Item {
                width: body.width
                height: root.failed ? 0 : 38
                opacity: root.failed ? 0 : 1
                clip: true
                Behavior on height {
                    NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    text: "总进度"
                    color: "#7b8593"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 1.2
                }
                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    text: Math.round(root.overall * 100) + "%"
                    color: root.failed ? "#ff9a94" : "#cbd5e3"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 4
                    color: "#14ffffff"
                    Rectangle {
                        height: 4
                        width: parent.width * root.overall
                        color: root.failed ? "#ef4444" : "#3b82f6"
                        Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    }
                }
            }

            // ---- 准备运行环境（A2）----
            // 启动时如果缺 Java / authlib，这里把"正在替你补什么、补到哪"单独列出来，
            // 不和下面的检查节点混在一起（节点子行只有 11px，容易被看漏）。
            Item {
                width: body.width
                height: (root.repairs.length > 0 && !root.failed)
                        ? root.repairsCardHeight() + 16 : 16
                // 有任务时从 16 长开：卡片是 top 锚定的，clip 后就是"向下展开"的观感
                clip: true
                Behavior on height {
                    NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
                }

                Rectangle {
                    id: repairsCard
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: root.repairs.length > 0 && !root.failed
                    height: root.repairsCardHeight()
                    color: "#0a1219"
                    border.width: 1
                    border.color: "#1d2a38"
                    radius: 2

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 12
                        spacing: 0

                        Item {   // 标题行
                            width: repairsCard.width - 28
                            height: 18
                            Rectangle {
                                width: 3
                                height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#e0a75e"
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "准备运行环境"
                                color: "#cfd7e3"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.repairPendingCount() + " 项待补全"
                                color: "#4f5866"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }

                        Repeater {
                            model: root.repairs
                            delegate: Item {
                                width: repairsCard.width - 28
                                height: root.repairRowH

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 168
                                    text: modelData.name
                                    color: modelData.state === 2 ? "#8b96a4" : "#c3ccd8"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 176
                                    anchors.right: valueTx.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 3
                                    color: "#12ffffff"
                                    Rectangle {
                                        height: 3
                                        width: parent.width * (modelData.state === 2 ? 1
                                                               : (modelData.state === 3 ? 1
                                                                  : modelData.progress / 100))
                                        color: modelData.state === 2 ? "#4f9d76"
                                               : (modelData.state === 3 ? "#8a4040" : "#60a5fa")
                                        Behavior on color {
                                            ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                                        }
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: Theme.durBase
                                                easing.type: Theme.easeStandard
                                            }
                                        }
                                    }
                                }
                                Text {
                                    id: valueTx
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 170
                                    horizontalAlignment: Text.AlignRight
                                    text: root.repairValueText(modelData)
                                    color: modelData.state === 2 ? "#5bbd85"
                                           : (modelData.state === 3 ? "#e0847f" : "#8fbcf5")
                                    Behavior on color {
                                        ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Text {
                            width: repairsCard.width - 28
                            height: 18
                            verticalAlignment: Text.AlignVCenter
                            text: root.repairPendingCount() > 0
                                  ? "下载完成后会自动继续启动"
                                  : "补全完成，正在继续启动"
                            color: "#6f8fb3"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // ---- 节点清单 ----
            // 用 ListView 而不是 Repeater：Repeater 的委托是被塞进父 Column 的 children 里的，
            // 模型整体替换时重建的委托会改变 Column 的子项顺序 → 底部元素跑到顶部（2026-11-04 实测）。
            // ListView 自己在内部管模型，Column 只看见它一个子项，顺序永远稳定。
            // 失败后节点清单收起：B1 的失败面板只留"原因 + 建议"
            Item {
                width: body.width
                height: root.failed ? 0 : root.rowsHeight()
                opacity: root.failed ? 0 : 1
                clip: true
                Behavior on height {
                    NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }

                ListView {
                    id: stepList
                    width: parent.width
                    height: root.rowsHeight()
                interactive: false
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows
                delegate: Item {
                    id: nodeRow
                    width: stepList.width
                    height: root.rowHasDetail(modelData) ? 52 : 38

                    Rectangle {   // 竖线（连到下一个节点；最后一行不画）
                        x: 3
                        y: 14
                        width: 1
                        height: nodeRow.height - 14
                        visible: modelData.isLast !== true
                        color: (modelData.status === 2) ? "#24405f" : "#1c222c"
                        Behavior on color {
                            ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                        }
                    }
                    Rectangle {   // 8x8 直角方点：状态变化时颜色渐变，节点推进才看得出"又过了一步"
                        x: 0
                        y: 4
                        width: 8
                        height: 8
                        color: root.nodeColor(modelData.status)
                        Behavior on color {
                            ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                        }
                    }
                    Text {   // 节点名
                        x: 20
                        y: 0
                        width: nodeRow.width - 96
                        text: modelData.name
                        color: root.nodeTextColor(modelData.status)
                        Behavior on color {
                            ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: modelData.status === 1 ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {   // 节点子行：后端原串（字节进度、具体原因都在这）
                        x: 20
                        y: 20
                        width: nodeRow.width - 96
                        text: root.rowDetail(modelData.detail)
                        visible: text.length > 0 && modelData.status === 1
                        color: modelData.status === 3 ? "#e0847f" : "#7fa8e0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {   // 右侧状态
                        anchors.right: parent.right
                        y: 1
                        text: root.statusText(modelData.status)
                        color: root.statusColor(modelData.status)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
                }
            }

            // ---- 失败诊断（B1）----
            // 失败后浮层原地变身：原因 / 类型 / 时间 / 疑似模组 / 建议，
            // 不另开窗口；诊断还在算的时候显示"正在分析日志…"。
            Item {
                width: body.width
                height: root.failed ? root.crashCardHeight() + 10 : 0
                visible: opacity > 0.01
                opacity: root.failed ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
                }
                Behavior on height {
                    NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                }
                transform: Translate {
                    y: root.failed ? 0 : 8
                    Behavior on y {
                        NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
                    }
                }

                Column {
                    id: crashCol
                    width: body.width
                    anchors.top: parent.top
                    anchors.left: parent.left
                    spacing: 0

                    Rectangle {   // 原因条：等宽字体 + 左侧红条，长原因自动换行
                        width: crashCol.width
                        height: reasonTx.implicitHeight + 16
                        color: "#150d0f"
                        Rectangle {
                            width: 2
                            height: parent.height
                            color: "#7a2f2f"
                        }
                        Text {
                            id: reasonTx
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.crashAnalyzing ? "正在分析日志，请稍候…" : root.crashReasonText()
                            color: "#ffc9c5"
                            font.family: "Consolas, Menlo, monospace"
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            lineHeight: 1.35
                        }
                    }

                    Item { width: crashCol.width; height: 10 }

                    Repeater {
                        model: root.crashKvRows()
                        delegate: Item {
                            width: crashCol.width
                            height: 20
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 56
                                text: modelData.k
                                color: "#4f5866"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 62
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.v
                                color: "#b9c6d6"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Item {
                        width: crashCol.width
                        height: root.crashSuggestions().length > 0 ? 16 : 0
                    }
                    Text {
                        width: crashCol.width
                        height: 14
                        visible: root.crashSuggestions().length > 0
                        verticalAlignment: Text.AlignVCenter
                        text: "建议"
                        color: "#4f5866"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.letterSpacing: 1
                    }
                    Repeater {
                        model: root.crashSuggestions()
                        delegate: Item {
                            width: crashCol.width
                            height: 22
                            Rectangle {
                                width: 3
                                height: 3
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.topMargin: 8
                                color: "#3b4a5c"
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                color: "#c3ccd8"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // ---- 底部 ----
            Item { width: body.width; height: 18 }
            Rectangle {
                width: body.width
                height: 1
                color: "#161b22"
            }
            Item {
                width: body.width
                height: 54
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (root.failed ? 300 : 110)
                    // 失败态只显示导出结果；没有结果就保持空，不塞无关文案
                    text: root.failed
                          ? root.exportHint
                          : (root.done ? "游戏已启动" : "正在按阶段推进，取消后可重新启动")
                    color: root.failed ? "#8a6a6a" : "#4f5866"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                // 失败态：查看日志 / 重试（重试描边走红，但"修正后重试"不是危险操作）
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    visible: root.failed
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: "导出日志"
                        onClicked: {
                            if (!root.b) return
                            var p = root.b.exportCrashLogs("")
                            root.exportHint = (p && p.length > 0) ? ("已导出: " + p) : "导出失败，可先查看日志文件夹"
                        }
                    }
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: "查看日志"
                        onClicked: { if (root.b) root.b.openLauncherLogsFolder() }
                    }
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        danger: true
                        text: "重试"
                        onClicked: { if (root.b && root.verName.length > 0) root.b.launch(root.verName, root.b.activeAccountOnline) }
                    }
                }

                // 正常推进：取消是唯一出口，不用红色
                SButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    kind: 1
                    radius: 2
                    height: 32
                    visible: !root.failed && !root.done
                    text: "取消启动"
                    onClicked: { if (root.b) root.b.cancelLaunch() }
                }
            }

        }
    }

    // ---- 诊断行（只在 --ui-overlay-debug 下出现）----
    // 刻意放在面板之外：它只是开发用的读数，绝不能参与面板布局，更不能把面板撑高。
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.bottomMargin: 8
        visible: root.debugOverlay
        text: "DBG rows=" + root.rows.length
              + " total=" + root.stepTotal
              + " no=" + root.stepNo
              + " pct=" + Math.round(root.overall * 100)
              + " busy=" + (root.busy ? "1" : "0")
              + " fail=" + (root.failed ? "1" : "0")
              + " ok=" + (root.done ? "1" : "0")
              + " panel=" + Math.round(panel.width) + "x" + Math.round(panel.height)
              + " panelY=" + Math.round(panel.y)
              + " listH=" + Math.round(stepList.height)
        color: "#ff9a94"
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}
