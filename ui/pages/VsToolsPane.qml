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
    property bool verifying: b ? b.verifyRunning : false
    property int checkedCount: b ? b.verifyChecked : 0
    property int totalCount: b ? b.verifyTotal : 0
    property bool hasResult: b && b.verifyResultText && b.verifyResultText.length > 0
    property bool resultOk: b ? b.verifyResultOk : false
    property int repairing: 0
    property bool renaming: false
    property string renameText: ""

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onVerifyRunningChanged() { pane.verifying = pane.b.verifyRunning }
        function onVerifyCheckedChanged() { pane.checkedCount = pane.b.verifyChecked }
        function onVerifyTotalChanged() { pane.totalCount = pane.b.verifyTotal }
        function onVerifyFailedFiles(files) {
            pane.failedFiles = files || []
            pane.hasResult = true
            pane.resultOk = pane.failedFiles.length === 0
        }
        function onVerifyFinished(allPassed) {
            pane.verifying = false
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
        if (pane.verifying) return "已扫描 " + pane.checkedCount + " / " + pane.totalCount
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
            width: Math.min(720, pane.width - 56)
            spacing: 16

            // ── 状态卡 ──
            SCard {
                width: col.width
                title: ""
                Rectangle {
                    width: parent.width
                    height: 1
                    color: "transparent"
                }
                Item {
                    width: parent.width
                    height: 58
                    Rectangle {
                        id: dot
                        width: 8
                        height: 8
                        radius: 4
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: 16
                        color: pane.verifying ? "#4b5462"
                             : (pane.failedFiles.length > 0 ? Theme.warn
                             : (pane.hasResult ? Theme.ok : "#4b5462"))
                    }
                    Text {
                        anchors.left: dot.right
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        text: pane.statusTitle()
                        color: "#eef2f8"
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.left: dot.right
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 33
                        text: pane.statusSub()
                        color: "#4b5462"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    SButton {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        kind: 1
                        height: 30
                        radius: 2
                        iconName: pane.verifying ? "x" : "refresh-cw"
                        text: pane.verifying ? "取消" : "重新校验"
                        onClicked: {
                            if (!pane.b) return
                            if (pane.verifying) { pane.b.cancelVerify(); return }
                            pane.failedFiles = []
                            pane.hasResult = false
                            pane.b.verifyVersion(pane.versionId)
                        }
                    }
                }
                SRow {
                    width: parent.width
                    label: ""
                    divider: false
                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pane.failedFiles.length > 0
                            text: "共 " + pane.failedFiles.length + " 项待修复"
                            color: "#8a94a3"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        SButton {
                            visible: pane.failedFiles.length > 0
                            kind: 0
                            height: 32
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
                    color: "#3f4753"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
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
