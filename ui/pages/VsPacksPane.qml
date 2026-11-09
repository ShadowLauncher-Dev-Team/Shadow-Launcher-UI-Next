// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 资源包（定稿甲：单列）
// 资源包没有启用/禁用接口（游戏内选），卡片右侧只有删除；删除有确认。
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null
    property bool loading: false
    signal busyChanged(bool busy)

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property var allPacks: []
    property string query: ""
    property string pendingDelete: ""

    readonly property var shown: {
        if (pane.query.length === 0) return pane.allPacks
        var q = pane.query.toLowerCase()
        var out = []
        for (var i = 0; i < pane.allPacks.length; ++i) {
            var p = pane.allPacks[i]
            var hay = ((p.displayName || "") + " " + (p.fileName || "")).toLowerCase()
            if (hay.indexOf(q) >= 0) out.push(p)
        }
        return out
    }

    // silent = 切回窗口时的后台重扫：不点亮全局加载光条，也不显示"正在读取"占位
    property bool silent: false

    // ── 列表入场 ──
    // 只有"首次载入 / 用户点刷新"发一轮入场预算（enterRows 个），其余重扫（导入、删除、
    // 切回窗口）都不发：这些动作本身已有 toast 做反馈，再让整列重播一遍就成了噪音。
    // 预算由 delegate 一次性消费，只会命中当次重建出来的可见行。
    readonly property int enterRows: 8
    property int enterBudget: 0
    // 过滤不动画：输入时清零剩余预算（列表为空时预算可能还没被消费掉）
    onQueryChanged: pane.enterBudget = 0

    function reload(silentReload, withEntrance) {
        if (!pane.b || pane.versionId.length === 0) return
        pane.silent = (silentReload === true)
        if (!pane.silent && !pane.loading) { pane.loading = true; pane.busyChanged(true) }
        if (withEntrance === true) pane.enterBudget = pane.enterRows
        pane.b.listResourcePacksAsync(pane.versionId)
    }
    Component.onCompleted: pane.reload(false, true)
    onLoadingChanged: pane.busyChanged(pane.loading)

    Connections {
        target: Qt.application
        ignoreUnknownSignals: true
        function onActiveChanged() { if (Qt.application.active) pane.reload(true) }
    }

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onResourcePacksListReady(vid, list) {
            if (vid !== pane.versionId) return
            pane.allPacks = list || []
            pane.loading = false
        }
    }

    Column {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        spacing: 12

        Item {
            width: parent.width
            height: 36
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                SField {
                    width: 250
                    height: 36
                    label: "搜索资源包"
                    onEdited: (v) => pane.query = v
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pane.allPacks.length + " 个"
                    color: "#6b7686"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    iconName: "refresh-cw"
                    text: "刷新"
                    onClicked: {
                        pane.reload(false, true)
                        if (pane.toast) pane.toast.show("正在重新扫描资源包", -1, "info", true)
                    }
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    iconName: "folder-open"
                    text: "文件夹"
                    onClicked: if (pane.b) pane.b.openResourcePacksFolder(pane.versionId)
                }
            }
            SButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                kind: 1
                height: 32
                radius: 2
                iconName: "package-plus"
                text: "导入"
                onClicked: importDialog.open()
            }
        }

        // 同 Mod 页：ListView 虚拟化，避免一次性实例化所有资源包行
        ListView {
            id: packList
            width: parent.width
            height: parent.height - 48
            clip: true
            model: pane.shown
            spacing: 8
            reuseItems: true
            cacheBuffer: 400
            boundsBehavior: Flickable.StopAtBounds

            // 这里故意不挂 add / remove 过渡：model 是"整表替换的数组"——后端每来一次数据
            // 就换一个新数组，ListView 收到的是 reset（只走 populate），add/remove 永远不触发。
            // 行入场因此交给 delegate 自己播（见 delegate 里的 enterAnim）。

            delegate: Item {
                id: packRow
                width: packList.width
                height: 68
                readonly property bool bad: modelData.valid === false

                // 入场：淡入 + 从下 4px 归位，前 enterRows 行按 staggerStep 错开。
                // 没拿到预算的行（过滤、复用、删除/导入后的重扫）直接到位，不闪。
                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { duration: Math.min(index, pane.enterRows - 1) * Theme.staggerStep }
                    ParallelAnimation {
                        NumberAnimation { target: packRow; property: "opacity"; from: 0; to: 1; duration: Theme.durSlow; easing.type: Theme.easeEnter }
                        NumberAnimation { target: enterShift; property: "y"; from: 4; to: 0; duration: Theme.durSlow; easing.type: Theme.easeEnter }
                    }
                }
                Component.onCompleted: {
                    if (pane.enterBudget > 0) {
                        pane.enterBudget -= 1
                        packRow.opacity = 0
                        enterShift.y = 4
                        enterAnim.start()
                    }
                }
                transform: Translate { id: enterShift }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rMd
                    color: hov.hovered ? "#0f131a" : "#0b0d12"
                    border.width: 1
                    border.color: bad ? "#2a2118" : (hov.hovered ? "#333a47" : Theme.line2)
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                }
                Rectangle {
                    id: ico
                    width: 46
                    height: 46
                    radius: Theme.rSm
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    color: bad ? "#1a1410" : "#141a22"
                    clip: true
                    Image {
                        anchors.fill: parent
                        visible: modelData.iconPath !== undefined && modelData.iconPath !== ""
                        source: (modelData.iconPath !== undefined && modelData.iconPath !== "") ? modelData.iconPath : ""
                        sourceSize.width: 92
                        sourceSize.height: 92
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: modelData.iconPath === undefined || modelData.iconPath === ""
                        text: modelData.displayName ? modelData.displayName.charAt(0).toUpperCase() : "?"
                        color: bad ? "#c9a25a" : "#8fb4ff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }
                Column {
                    anchors.left: ico.right
                    anchors.leftMargin: 12
                    anchors.right: del.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Row {
                        spacing: 8
                        Text {
                            text: modelData.displayName || modelData.fileName || ""
                            color: "#f2f5fa"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.versionLabel || ""
                            color: "#7b8494"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: modelData.description || ""
                        color: "#9aa3b0"
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    Text {
                        width: parent.width
                        text: (modelData.fileName || "") + (modelData.fileSizeText ? (" · " + modelData.fileSizeText) : "")
                        color: "#6b7686"
                        elide: Text.ElideMiddle
                        font.family: "Consolas"
                        font.pixelSize: 11
                    }
                }
                SButton {
                    id: del
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    kind: 1
                    danger: true
                    height: 28
                    radius: 2
                    text: "删除"
                    onClicked: {
                        pane.pendingDelete = modelData.fileName
                        confirmPop.open()
                    }
                }
                HoverHandler { id: hov }
            }

            footer: Column {
                width: packList.width
                Text {
                    width: parent.width
                    topPadding: 24
                    visible: packList.count === 0 && !pane.loading
                    // 文案"出现"给一点重量，硬切 visible 会闪
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.allPacks.length === 0 ? "此版本还没有资源包" : "没有匹配的资源包"
                    color: "#5d6673"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    topPadding: 24
                    visible: pane.loading
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    horizontalAlignment: Text.AlignHCenter
                    text: "正在读取资源包列表…"
                    color: "#6b7686"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }
        }
    }

    // 删除确认：删文件不可撤销，必须先问一句
    Popup {
        id: confirmPop
        parent: pane
        anchors.centerIn: parent
        width: 360
        modal: true
        padding: 0
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            radius: Theme.rMd
            color: "#0b0d12"
            border.width: 1
            border.color: Theme.line2
        }
        contentItem: Column {
            width: 360
            padding: 18
            spacing: 12
            Text {
                text: "删除资源包？"
                color: "#eef2f8"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width - 36
                text: pane.pendingDelete + "\n这个操作不能撤销。"
                color: "#9aa3b0"
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Row {
                spacing: 8
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    text: "取消"
                    onClicked: confirmPop.close()
                }
                SButton {
                    kind: 1
                    danger: true
                    height: 32
                    radius: 2
                    text: "删除"
                    onClicked: {
                        if (pane.b) pane.b.deleteResourcePack(pane.pendingDelete, pane.versionId)
                        confirmPop.close()
                        if (pane.toast) pane.toast.show("已删除 " + pane.pendingDelete, -1, "info", true)
                        pane.pendingDelete = ""
                        pane.reload()
                    }
                }
            }
        }
    }

    FileDialog {
        id: importDialog
        title: "导入资源包"
        fileMode: FileDialog.OpenFile
        nameFilters: ["资源包 (*.zip)", "所有文件 (*)"]
        onAccepted: {
            if (!pane.b) return
            var p = String(selectedFile).replace(/^file:\/\//, "")
            var ok = pane.b.importResourcePack(p, pane.versionId)
            if (pane.toast) pane.toast.show(ok ? "已导入" : "导入失败", -1, ok ? "info" : "error", true)
            pane.reload()
        }
    }
}
