// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 光影管理（定稿甲：单列卡片，行高/卡片/空状态与 Mod、资源包两页一致）
//
// 启/禁用为什么是"改名"：游戏只认 shaderpacks/*.zip（Iris 与 OptiFine 都是），
// 把 x.zip 改名成 x.zip.disabled 就等于让它从游戏的光影列表里消失——
// 和 Mod 的 jar ↔ jar.disabled 是同一套约定，不写游戏配置、不动 optionsshaders.txt。
// 解包态光影（OptiFine 支持 shaderpacks/<文件夹>/shaders）只列出、不给开关：
// OptiFine 认目录，把目录改名它照样读得到，给个假开关比不给更糟。
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
    property bool pendingDeleteIsFolder: false

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
    readonly property int enabledCount: {
        var n = 0
        for (var i = 0; i < pane.allPacks.length; ++i)
            if (pane.allPacks[i].enabled === true) n++
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
        pane.b.listShaderPacksAsync(pane.versionId)
    }
    Component.onCompleted: pane.reload(false, true)
    onLoadingChanged: pane.busyChanged(pane.loading)

    // 拖入 zip 后回到窗口时重新扫一遍（外部文件系统变化没有信号）
    Connections {
        target: Qt.application
        ignoreUnknownSignals: true
        function onActiveChanged() { if (Qt.application.active) pane.reload(true) }
    }

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onShaderPacksListReady(vid, list) {
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
                    label: qsTr("搜索光影包")
                    onEdited: (v) => pane.query = v
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("%1 个 · 启用 %2").arg(pane.allPacks.length).arg(pane.enabledCount)
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    iconName: "refresh-cw"
                    text: qsTr("刷新")
                    onClicked: {
                        pane.reload(false, true)
                        if (pane.toast) pane.toast.show(qsTr("正在重新扫描光影包"), -1, "info", true)
                    }
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    iconName: "folder-open"
                    text: qsTr("文件夹")
                    onClicked: if (pane.b) pane.b.openShaderPacksFolder(pane.versionId)
                }
            }
            SButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                kind: 1
                height: 32
                radius: 2
                iconName: "package-plus"
                text: qsTr("导入")
                onClicked: importDialog.open()
            }
        }

        // 同 Mod / 资源包页：ListView 虚拟化，避免一次性实例化所有光影包行
        ListView {
            id: spList
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
                id: spRow
                width: spList.width
                height: 68
                readonly property bool folder: modelData.isFolder === true
                readonly property bool on: modelData.enabled === true

                // 入场：淡入 + 从下 4px 归位，前 enterRows 行按 staggerStep 错开。
                // 没拿到预算的行（过滤、复用、启停/导入/删除后的重扫）直接到位，不闪。
                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { duration: Math.min(index, pane.enterRows - 1) * Theme.staggerStep }
                    ParallelAnimation {
                        NumberAnimation { target: spRow; property: "opacity"; from: 0; to: 1; duration: Theme.durSlow; easing.type: Theme.easeEnter }
                        NumberAnimation { target: enterShift; property: "y"; from: 4; to: 0; duration: Theme.durSlow; easing.type: Theme.easeEnter }
                    }
                }
                Component.onCompleted: {
                    if (pane.enterBudget > 0) {
                        pane.enterBudget -= 1
                        spRow.opacity = 0
                        enterShift.y = 4
                        enterAnim.start()
                    }
                }
                transform: Translate { id: enterShift }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rMd
                    color: hov.hovered ? Theme.bgCard2 : Theme.bgCard2
                    border.width: 1
                    border.color: hov.hovered ? Theme.line2 : Theme.line2
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                }

                // 图标位：光影包没有统一的图标规范（Iris / OptiFine 都不提供 pack.png），
                // 所以和"没有图标的 Mod"一样退回名称首字母；解包态用文件夹图标区分。
                Rectangle {
                    id: ico
                    width: 46
                    height: 46
                    radius: Theme.rSm
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    color: spRow.on ? Theme.bgCard : Theme.bgCard2
                    clip: true
                    SIcon {
                        anchors.centerIn: parent
                        visible: spRow.folder
                        name: "folder"
                        size: 18
                        color: Theme.fg3
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !spRow.folder
                        text: modelData.displayName ? modelData.displayName.charAt(0).toUpperCase() : "?"
                        color: spRow.on ? Theme.accentText : Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors.left: ico.right
                    anchors.leftMargin: 12
                    anchors.right: rightBox.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        // 名字过长时按行宽收，不钻到开关/删除按钮底下
                        width: parent.width
                        text: modelData.displayName || modelData.fileName || ""
                        color: spRow.on ? Theme.fg : Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: (modelData.fileName || "") + (modelData.fileSizeText ? (" · " + modelData.fileSizeText) : "")
                        color: Theme.fg3
                        elide: Text.ElideMiddle
                        font.family: "Consolas"
                        font.pixelSize: 11
                    }
                }

                // 右侧：解包态显示"文件夹"（没有可靠的启停手段），zip 给开关 + 删除。
                // 用一块固定区域承接子项 anchors，而不是在 Row 里用 anchors（positioner 里不成立）。
                Item {
                    id: rightBox
                    width: 132
                    height: 28
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    SButton {
                        id: delBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        kind: 1
                        danger: true
                        height: 28
                        radius: 2
                        text: qsTr("删除")
                        onClicked: {
                            pane.pendingDelete = modelData.fileName
                            pane.pendingDeleteIsFolder = spRow.folder
                            confirmPop.open()
                        }
                    }
                    SSwitch {
                        anchors.right: delBtn.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !spRow.folder
                        checked: spRow.on
                        onToggled: (v) => {
                            if (!pane.b) return
                            pane.b.setShaderPackEnabled(modelData.fileName, pane.versionId, v)
                            pane.reload()
                        }
                    }
                    Text {
                        anchors.right: delBtn.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: spRow.folder
                        text: qsTr("文件夹")
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
                HoverHandler { id: hov }
            }

            footer: Column {
                width: spList.width
                Text {
                    width: parent.width
                    topPadding: 24
                    visible: spList.count === 0 && !pane.loading
                    // 文案"出现"给一点重量，硬切 visible 会闪
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.allPacks.length === 0 ? qsTr("此版本还没有光影包") : qsTr("没有匹配的光影包")
                    color: Theme.fg3
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
                    text: qsTr("正在读取光影包列表…")
                    color: Theme.fg3
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
            color: Theme.bgCard2
            border.width: 1
            border.color: Theme.line2
        }
        contentItem: Column {
            width: 360
            padding: 18
            spacing: 12
            Text {
                text: pane.pendingDeleteIsFolder ? qsTr("删除光影包文件夹？") : qsTr("删除光影包？")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width - 36
                text: pane.pendingDeleteIsFolder
                      ? qsTr("%1\n整个文件夹会被删掉，这个操作不能撤销。").arg(pane.pendingDelete)
                      : qsTr("%1\n这个操作不能撤销。").arg(pane.pendingDelete)
                color: Theme.fg2
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
                    text: qsTr("取消")
                    onClicked: confirmPop.close()
                }
                SButton {
                    kind: 1
                    danger: true
                    height: 32
                    radius: 2
                    text: qsTr("删除")
                    onClicked: {
                        if (pane.b) pane.b.deleteShaderPack(pane.pendingDelete, pane.versionId)
                        confirmPop.close()
                        if (pane.toast) pane.toast.show(qsTr("已删除 %1").arg(pane.pendingDelete), -1, "info", true)
                        pane.pendingDelete = ""
                        pane.reload()
                    }
                }
            }
        }
    }

    FileDialog {
        id: importDialog
        title: qsTr("导入光影包")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("光影包 (*.zip)"), qsTr("所有文件 (*)")]
        onAccepted: {
            if (!pane.b) return
            var p = String(selectedFile).replace(/^file:\/\//, "")
            var zip = p.toLowerCase().lastIndexOf(".zip") === p.length - 4
            var ok = zip && pane.b.importShaderPack(p, pane.versionId)
            if (pane.toast)
                pane.toast.show(ok ? qsTr("已导入")
                                   : (zip ? qsTr("导入失败") : qsTr("光影包需要 .zip 文件")),
                                 -1, ok ? "info" : "warning", true)
            pane.reload()
        }
    }
}
