// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · Mod 管理（定稿甲：单列卡片）
import QtQuick
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null
    property bool loading: false
    signal busyChanged(bool busy)

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property var allMods: []
    property string query: ""
    property bool wasLoading: false

    readonly property var shown: {
        if (pane.query.length === 0) return pane.allMods
        var q = pane.query.toLowerCase()
        var out = []
        for (var i = 0; i < pane.allMods.length; ++i) {
            var m = pane.allMods[i]
            var hay = ((m.modName || "") + " " + (m.fileName || "") + " " + (m.modId || "")).toLowerCase()
            if (hay.indexOf(q) >= 0) out.push(m)
        }
        return out
    }
    readonly property int enabledCount: {
        var n = 0
        for (var i = 0; i < pane.allMods.length; ++i) if (pane.allMods[i].enabled) n++
        return n
    }

    // silent = 切回窗口时的后台重扫：不点亮全局加载光条，也不显示"正在读取"占位
    property bool silent: false

    // ── 列表入场 ──
    // 只有"首次载入 / 用户点刷新"发一轮入场预算（enterRows 个），其余重扫（启停、导入、
    // 删除、切回窗口）都不发：这些动作本身已有 toast / 开关动效做反馈，再让整列重播一遍
    // 就成了噪音。预算由 delegate 一次性消费，所以只会命中当次重建出来的可见行。
    readonly property int enterRows: 8
    property int enterBudget: 0
    // 过滤不动画：输入时清零剩余预算（列表为空时预算可能还没被消费掉）
    onQueryChanged: pane.enterBudget = 0

    function reload(silentReload, withEntrance) {
        if (!pane.b || pane.versionId.length === 0) return
        pane.silent = (silentReload === true)
        if (!pane.silent && !pane.loading) { pane.loading = true; pane.busyChanged(true) }
        if (withEntrance === true) pane.enterBudget = pane.enterRows
        pane.b.listModsAsync(pane.versionId)
    }
    Component.onCompleted: pane.reload(false, true)

    onLoadingChanged: pane.busyChanged(pane.loading)

    // 拖入 jar 后回到窗口时重新扫一遍（外部文件系统变化没有信号）
    Connections {
        target: Qt.application
        ignoreUnknownSignals: true
        function onActiveChanged() { if (Qt.application.active) pane.reload(true) }
    }

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onModsListReady(vid, list) {
            if (vid !== pane.versionId) return
            pane.allMods = list || []
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
                    label: "搜索 Mod"
                    onEdited: (v) => pane.query = v
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pane.allMods.length + " 个 · 启用 " + pane.enabledCount
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
                        if (pane.toast) pane.toast.show("正在重新扫描 Mod", -1, "info", true)
                    }
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    iconName: "folder-open"
                    text: "文件夹"
                    onClicked: if (pane.b) pane.b.openModsFolder(pane.versionId)
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    text: "全部启用"
                    onClicked: pane.bulk(true)
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    text: "全部禁用"
                    onClicked: pane.bulk(false)
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    iconName: "package-plus"
                    text: "导入"
                    onClicked: importDialog.open()
                }
            }
        }

        // 用 ListView 而不是 Repeater + Column：425 个 Mod 时 Repeater 会一次性
        // 创建 425 个 delegate（每个含 Image/Switch/HoverHandler），首帧直接卡住。
        // ListView 只实例化可见行 + cacheBuffer，reuseItems 让滚动时复用而不是重建。
        ListView {
            id: modList
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
                id: modRow
                width: modList.width
                height: 68
                readonly property bool on: modelData.enabled === true
                readonly property bool bad: modelData.valid === false

                // 入场：淡入 + 从下 4px 归位，前 enterRows 行按 staggerStep 错开。
                // 没拿到预算的行（过滤、复用、启停后的重扫）直接到位，不闪。
                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { duration: Math.min(index, pane.enterRows - 1) * Theme.staggerStep }
                    ParallelAnimation {
                        NumberAnimation { target: modRow; property: "opacity"; from: 0; to: 1; duration: Theme.durSlow; easing.type: Theme.easeEnter }
                        NumberAnimation { target: enterShift; property: "y"; from: 4; to: 0; duration: Theme.durSlow; easing.type: Theme.easeEnter }
                    }
                }
                Component.onCompleted: {
                    if (pane.enterBudget > 0) {
                        pane.enterBudget -= 1
                        modRow.opacity = 0
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
                    color: parent.on ? "#141a22" : "#10141a"
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
                        text: modelData.modName ? modelData.modName.charAt(0).toUpperCase() : "?"
                        color: parent.parent.on ? "#8fb4ff" : "#6b7686"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }
                Column {
                    anchors.left: ico.right
                    anchors.leftMargin: 12
                    anchors.right: sw.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Row {
                        spacing: 8
                        Text {
                            text: modelData.modName || modelData.fileName || ""
                            color: parent.parent.on ? "#f2f5fa" : "#a8b1be"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.version || ""
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
                SSwitch {
                    id: sw
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    checked: parent.on
                    onToggled: (v) => {
                        if (!pane.b) return
                        pane.b.setModEnabled(modelData.fileName, pane.versionId, v)
                        pane.reload()
                    }
                }
                HoverHandler { id: hov }
            }

            footer: Column {
                width: modList.width
                Text {
                    width: parent.width
                    topPadding: 24
                    visible: modList.count === 0 && !pane.loading
                    // 文案"出现"这件事本身需要一点重量：硬切 visible 会闪
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.allMods.length === 0 ? "此版本还没有 Mod" : "没有匹配的 Mod"
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
                    text: "正在读取 Mod 列表…"
                    color: "#6b7686"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }
        }
    }

    // 批量启停：先给"正在…"，再给结果 —— 几百个 jar 改名要几秒
    function bulk(enable) {
        if (!pane.b) return
        var total = pane.allMods.length
        pane.loading = true
        if (pane.toast)
            pane.toast.show((enable ? "正在启用 " : "正在禁用 ") + total + " 个 Mod…", -1, "info", true)
        Qt.callLater(function() {
            var n = pane.b.setAllModsEnabled(pane.versionId, enable)
            if (pane.toast)
                pane.toast.show((enable ? "已启用 " : "已禁用 ") + n + " / " + total + " 个 Mod", -1, "info", true)
            pane.reload()
        })
    }

    FileDialog {
        id: importDialog
        title: "导入 Mod"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Mod 文件 (*.jar)", "所有文件 (*)"]
        onAccepted: {
            if (!pane.b) return
            var p = String(selectedFile).replace(/^file:\/\//, "")
            var ok = pane.b.importMod(p, pane.versionId)
            if (pane.toast) pane.toast.show(ok ? "已导入" : "导入失败", -1, ok ? "info" : "error", true)
            pane.reload()
        }
    }
}
