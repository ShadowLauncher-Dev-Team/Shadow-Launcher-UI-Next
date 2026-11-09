// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 工具与维护（定稿甲：状态优先单列）
//
// 这一页只做三件事：看校验状态、修损坏文件、对版本本身动手。
// 进度（校验/修复的字节进度）不在这里画 —— 归「下载进度」页，与先前定稿一致。
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var s: b ? b.settings() : null

    property var failedFiles: []
    // 乐观标志：点下去到后端第一条信号之间，本页也要立刻显示"校验中"
    property bool verifyingLocal: false
    readonly property bool verifying: verifyingLocal || (b ? b.verifyRunning : false)
    readonly property int checkedCount: b ? b.verifyChecked : 0
    readonly property int totalCount: b ? b.verifyTotal : 0
    readonly property real verifyRatio: totalCount > 0
        ? Math.min(1, Math.max(0, checkedCount / totalCount)) : 0
    property bool hasResult: b && b.verifyResultText && b.verifyResultText.length > 0
    property bool resultOk: b ? b.verifyResultOk : false
    property int repairing: 0
    property bool renaming: false
    property string renameText: ""

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        // 只清乐观标志；checkedCount/totalCount 是只读绑定，不能再赋值（会抛 TypeError）
        function onVerifyRunningChanged() { pane.verifyingLocal = false }
        function onVerifyFailedFiles(files) {
            pane.failedFiles = files || []
            pane.hasResult = true
            pane.resultOk = pane.failedFiles.length === 0
        }
        function onVerifyFinished(allPassed) {
            pane.hasResult = true
            pane.resultOk = allPassed
            if (pane.failedFiles.length === 0 && allPassed) pane.failedFiles = []
            if (pane.toast)
                pane.toast.show(allPassed ? "校验通过" : ("发现 " + pane.failedFiles.length + " 个文件异常"))
        }
    }

    function statusTitle() {
        if (pane.verifying) return "正在校验…"
        if (!pane.hasResult) return "尚未校验此版本"
        if (pane.failedFiles.length > 0) return "发现 " + pane.failedFiles.length + " 个文件异常"
        return "未发现异常"
    }
    function statusSub() {
        if (pane.verifying) return "正在逐个核对版本文件，可随时取消"
        if (!pane.hasResult) return "校验会逐个核对版本文件是否齐全"
        return "本次扫描 " + pane.totalCount + " 个文件"
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 56
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 28
            y: 22
            width: Math.max(360, pane.width - 56)
            spacing: 16

            // ── 状态卡 ──
            // 不用 SCard：它的高度靠 body.implicitHeight 累加，无标题卡片算出来的
            // 高度比内容大一圈，文字就悬在中间。这里直接给高度、内容垂直居中。
            Item {
                id: statusCard
                width: col.width
                readonly property bool hasIssues: pane.failedFiles.length > 0
                height: pane.verifying ? 118 : (hasIssues ? 128 : 86)
                // 高度只在"未校验 86 / 校验中 118 / 有异常 128"之间切换，
                // 过渡一下，底下几张卡就不会跟着整块跳。内部定位一个字都没动。
                Behavior on height {
                    NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rWin
                    color: "#0b0d12"
                    border.width: 1
                    border.color: Theme.line2
                }

                // 左：状态点 + 标题 / 副标题
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.right: verifyAction.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Row {
                        spacing: 10
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: pane.verifying ? "#4b5462"
                                 : (statusCard.hasIssues ? Theme.warn
                                 : (pane.hasResult ? Theme.ok : "#4b5462"))
                        }
                        Text {
                            text: pane.statusTitle()
                            color: "#eef2f8"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        text: pane.statusSub()
                        color: "#7b8494"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        leftPadding: 18
                    }
                    // 校验中：细进度条 + 已扫描计数（跟标题同一条垂直流，别再单独锚底）
                    // 左缩进 18 = 状态点 8 + 间距 10，跟标题文字起始线对齐
                    Column {
                        visible: pane.verifying
                        x: 18
                        width: parent.width - 18
                        spacing: 6
                        Rectangle {
                            width: parent.width
                            height: 3
                            radius: 2
                            color: "#151a22"
                            Rectangle {
                                // 宽度直接绑定，绝不加 Behavior on width：
                                // 后端校验信号频率很高，每条信号都会把动画重置回起点，进度条永远追不上真实进度。
                                width: parent.width * (pane.totalCount > 0
                                       ? Math.min(1, pane.checkedCount / pane.totalCount) : 0)
                                height: parent.height
                                radius: 2
                                color: Theme.accent
                            }
                        }
                        Text {
                            text: pane.totalCount > 0
                                  ? ("已扫描 " + pane.checkedCount + " / " + pane.totalCount + " 个文件")
                                  : "正在统计文件…"
                            color: "#7b8494"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                // 校验中 ↔ 重新校验：两块同尺寸按钮叠在同一位置做 opacity 交叉淡入。
                // 不改 SButton 内部（hover/按下都在控件里），也不做宽度动画 ——
                // 宽度固定取两者较宽值，切换时左侧文字块不会重排。
                Item {
                    id: verifyAction
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(recheck.implicitWidth, cancelBtn.implicitWidth)
                    height: 32

                    SButton {
                        id: recheck
                        anchors.fill: parent
                        kind: 1
                        radius: 2
                        iconName: "refresh-cw"
                        text: "重新校验"
                        enabled: !pane.verifying
                        // visible 跟着 opacity 走：淡出后彻底不再接收 hover/点击，
                        // 否则隐藏的按钮会把 hover 状态带到下一次出现
                        visible: opacity > 0
                        opacity: pane.verifying ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                        }
                        onClicked: {
                            if (!pane.b) return
                            // 先本地进"校验中"，后端信号来了再校准 ——
                            // 否则点下去到第一条进度之间是完全无反馈的
                            pane.failedFiles = []
                            pane.hasResult = false
                            pane.verifyingLocal = true
                            pane.b.verifyVersion(pane.versionId)
                            if (pane.toast) pane.toast.show("开始校验版本文件", -1, "info", true)
                        }
                    }
                    SButton {
                        id: cancelBtn
                        anchors.fill: parent
                        kind: 1
                        radius: 2
                        iconName: "x"
                        text: "取消"
                        enabled: pane.verifying
                        visible: opacity > 0
                        opacity: pane.verifying ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                        }
                        onClicked: {
                            if (!pane.b) return
                            pane.b.cancelVerify()
                            pane.verifyingLocal = false
                        }
                    }
                }

                // 有异常时才出现的第二行
                Row {
                    visible: statusCard.hasIssues && !pane.verifying
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 16
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "共 " + pane.failedFiles.length + " 项待修复"
                        color: "#8a94a3"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    SButton {
                        kind: 0
                        height: 30
                        radius: 2
                        text: "修复"
                        onClicked: {
                            if (!pane.b) return
                            pane.b.repairVersion(pane.versionId)
                            if (pane.toast) pane.toast.show("已开始修复，进度见「下载进度」")
                        }
                    }
                }
            }

            // ── 异常文件 ──
            SCard {
                width: col.width
                title: "异常文件"
                visible: pane.failedFiles.length > 0
                Repeater {
                    model: pane.failedFiles.slice(0, 8)
                    delegate: Item {
                        width: col.width - 40
                        height: 34
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: "#a9b2c0"
                            elide: Text.ElideMiddle
                            font.family: "Consolas"
                            font.pixelSize: 11
                        }
                    }
                }
                Text {
                    width: parent.width
                    topPadding: 6
                    bottomPadding: pane.failedFiles.length > 8 ? 10 : 0
                    visible: pane.failedFiles.length > 8
                    text: "另有 " + (pane.failedFiles.length - 8) + " 项未列出"
                    color: "#6b7686"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            // ── 版本操作 ──
            SCard {
                width: col.width
                title: "版本操作"
                Row {
                    topPadding: 4
                    bottomPadding: 12
                    spacing: 8
                    SButton {
                        kind: 1
                        height: 32
                        radius: 2
                        text: "打开版本目录"
                        onClicked: if (pane.b) pane.b.openVersionDir(pane.versionId)
                    }
                    SButton {
                        kind: 1
                        height: 32
                        radius: 2
                        text: "克隆版本"
                        onClicked: {
                            if (!pane.b) return
                            var ok = pane.b.cloneVersion(pane.versionId)
                            if (pane.toast) pane.toast.show(ok ? "已创建副本" : "克隆失败")
                        }
                    }
                    SButton {
                        kind: 1
                        height: 32
                        radius: 2
                        text: "重命名"
                        onClicked: {
                            pane.renameText = pane.versionId
                            pane.renaming = true
                        }
                    }
                    SButton {
                        kind: 1
                        height: 32
                        radius: 2
                        text: "导出用户数据"
                        onClicked: saveDialog.open()
                    }
                }
                Item {
                    width: parent.width
                    height: 1
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: "#11141d"
                    }
                }
                Row {
                    topPadding: 12
                    bottomPadding: 10
                    spacing: 8
                    SButton {
                        kind: 1
                        danger: true
                        height: 32
                        radius: 2
                        text: "删除该版本"
                        onClicked: {
                            if (!pane.b) return
                            pane.b.deleteVersion(pane.versionId)
                            if (pane.toast) pane.toast.show("已删除版本")
                        }
                    }
                }
            }
        }
    }

    // 重命名弹层：只有这一个字段，不做整页对话框
    Popup {
        id: renamePop
        parent: pane
        anchors.centerIn: parent
        width: 340
        modal: true
        padding: 0
        visible: pane.renaming
        closePolicy: Popup.CloseOnEscape | Popup.OnPressOutside
        background: Rectangle {
            radius: Theme.rMd
            color: "#0b0d12"
            border.width: 1
            border.color: Theme.line2
        }
        contentItem: Column {
            width: 340
            padding: 16
            spacing: 12
            Text {
                text: "重命名版本"
                color: "#eef2f8"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            SInput {
                width: parent.width - 32
                text: pane.renameText
                placeholder: "新的版本 ID"
                onEdited: (t) => pane.renameText = t
            }
            Row {
                spacing: 8
                SButton {
                    kind: 1
                    height: 30
                    radius: 2
                    text: "取消"
                    onClicked: pane.renaming = false
                }
                SButton {
                    kind: 0
                    height: 30
                    radius: 2
                    text: "确认"
                    dimmed: pane.renameText.length === 0
                    onClicked: {
                        if (!pane.b || pane.renameText.length === 0) return
                        var ok = pane.b.renameVersion(pane.versionId, pane.renameText)
                        pane.renaming = false
                        if (pane.toast) pane.toast.show(ok ? "已重命名" : "重命名失败")
                    }
                }
            }
        }
    }

    FileDialog {
        id: saveDialog
        title: "导出用户数据"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Zip 压缩包 (*.zip)"]
        defaultSuffix: "zip"
        onAccepted: {
            if (!pane.b) return
            var gameDir = pane.s ? pane.s.getVersionGameDir(pane.versionId) : ""
            pane.b.userDataBackend.exportUserData(gameDir, pane.versionId,
                String(selectedFile).replace(/^file:\/\//, ""))
            if (pane.toast) pane.toast.show("已开始导出用户数据")
        }
    }
}
