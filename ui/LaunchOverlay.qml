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
    readonly property string userName: b ? (b.username || "") : ""
    readonly property bool debugOverlay: Qt.application.arguments.indexOf("--ui-overlay-debug") >= 0

    // 失败 / 完成态也要留在屏幕上：只认 launching 会把错误连同原因一起藏掉
    visible: b ? (b.launching || b.launchFailed || b.launchFinishedOk) : false
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
        return d.length > 0 && (r.status === 1 || r.status === 3)
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
                Text {
                    id: titleTx
                    anchors.left: parent.left
                    text: "启动 " + root.verName
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
                    text: "第 " + root.stepNo + " / " + root.stepTotal + " 步"
                    color: "#4f5866"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            // ---- 总进度（阶段级） ----
            Item {
                width: body.width
                height: 38
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
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                }
            }

            Item { width: body.width; height: 16 }

            // ---- 节点清单 ----
            // 用 ListView 而不是 Repeater：Repeater 的委托是被塞进父 Column 的 children 里的，
            // 模型整体替换时重建的委托会改变 Column 的子项顺序 → 底部元素跑到顶部（2026-11-04 实测）。
            // ListView 自己在内部管模型，Column 只看见它一个子项，顺序永远稳定。
            ListView {
                id: stepList
                width: body.width
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
                    }
                    Rectangle {   // 8x8 直角方点
                        x: 0
                        y: 4
                        width: 8
                        height: 8
                        color: root.nodeColor(modelData.status)
                    }
                    Text {   // 节点名
                        x: 20
                        y: 0
                        width: nodeRow.width - 96
                        text: modelData.name
                        color: root.nodeTextColor(modelData.status)
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
                        visible: text.length > 0 && (modelData.status === 1 || modelData.status === 3)
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
                    width: parent.width - (root.failed ? 190 : 110)
                    text: root.failed
                          ? "已停止推进，修正后可重试"
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
                        text: "查看日志"
                        onClicked: { if (root.b) root.b.openLauncherLogsFolder() }
                    }
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        danger: true
                        text: "重试"
                        onClicked: { if (root.b && root.verName.length > 0) root.b.launch(root.verName, root.b.isOnline) }
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
