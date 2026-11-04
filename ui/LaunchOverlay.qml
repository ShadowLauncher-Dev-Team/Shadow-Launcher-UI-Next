// SPDX-License-Identifier: AGPL-3.0-or-later
// 启动浮层：主界面中央，总进度条 + 真实阶段节点（节点全部来自 backend.launchPipeline）
import QtQuick
import ShadowLauncher.Next

Item {
    id: root

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var pipe: b ? b.launchPipeline : null
    readonly property var steps: pipe ? pipe.model : null
    readonly property real overall: b ? b.launchOverallProgress : 0
    readonly property int stepNo: b ? b.launchStepNumber : 0
    readonly property int stepTotal: b ? b.launchStepCount : 0

    visible: b ? b.launching : false
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
        return "#4f5866"
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

    // 遮罩：启动中点击不关闭
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
        height: body.implicitHeight + 38
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
                    text: "启动 " + ((root.b && root.b.selectedVersion) ? root.b.selectedVersion : "")
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.left: titleTx.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: titleTx.verticalCenter
                    text: root.b ? (root.b.username || "") : ""
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

            // ---- 总进度 ----
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
                    color: "#cbd5e3"
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
                        color: "#3b82f6"
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                }
            }

            Item { width: body.width; height: 16 }

            // ---- 节点清单（数量/名称全部来自后端） ----
            Repeater {
                model: root.steps
                delegate: Item {
                    id: nodeRow
                    width: body.width
                    height: model.hidden ? 0 : 42
                    visible: !model.hidden

                    Rectangle {   // 竖线
                        x: 3.5
                        y: 14
                        width: 1
                        height: 34
                        visible: index < (root.steps ? root.steps.count - 1 : 0)
                        color: (model.statusInt === 2) ? "#24405f" : "#1c222c"
                    }
                    Rectangle {   // 方点
                        x: 0
                        y: 4
                        width: 8
                        height: 8
                        color: root.nodeColor(model.statusInt)
                    }
                    Text {   // 节点名
                        id: nameTx
                        x: 20
                        y: 0
                        text: model.name
                        color: root.nodeTextColor(model.statusInt)
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: model.statusInt === 1 ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        width: parent.width - 100
                    }
                    Text {   // 节点内子状态（后端原串）
                        x: 20
                        y: 19
                        width: parent.width - 100
                        text: model.detail
                        visible: model.detail !== undefined && model.detail.length > 0
                                 && (model.statusInt === 1 || model.statusInt === 3)
                        color: model.statusInt === 3 ? "#e0847f" : "#7fa8e0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {   // 右侧状态
                        anchors.right: parent.right
                        y: 1
                        text: root.statusText(model.statusInt)
                        color: root.statusColor(model.statusInt)
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
                    text: "正在按阶段推进，取消后可重新启动"
                    color: "#4f5866"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                SButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    kind: 1
                    text: "取消启动"
                    onClicked: { if (root.b) root.b.cancelLaunch() }
                }
            }
        }
    }
}