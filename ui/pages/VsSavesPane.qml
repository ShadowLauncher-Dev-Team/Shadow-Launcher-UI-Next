// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 存档（定稿甲：信息条 + 单列卡片）
// 存档里全是子目录，卡片显示 名称 / 大小 / 删除；删除不可撤销，必须二次确认。
import QtQuick
import QtQuick.Controls.Basic
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null
    property bool loading: false
    signal busyChanged(bool busy)

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property var saves: []
    property string query: ""
    property string pendingDelete: ""

    readonly property int totalBytes: {
        var n = 0
        for (var i = 0; i < pane.saves.length; ++i) n += (pane.saves[i].sizeBytes || 0)
        return n
    }

    readonly property var shown: {
        if (pane.query.length === 0) return pane.saves
        var q = pane.query.toLowerCase()
        var out = []
        for (var i = 0; i < pane.saves.length; ++i) {
            if (String(pane.saves[i].name || "").toLowerCase().indexOf(q) >= 0) out.push(pane.saves[i])
        }
        return out
    }

    function fmt(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + " KB"
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB"
    }

    // silent = 切回窗口时的后台重扫：不点亮全局加载光条，也不显示"正在读取"占位
    property bool silent: false
    function reload(silentReload) {
        if (!pane.b || pane.versionId.length === 0) return
        pane.silent = (silentReload === true)
        if (!pane.silent && !pane.loading) { pane.loading = true; pane.busyChanged(true) }
        pane.b.listSavesAsync(pane.versionId)
    }
    Component.onCompleted: pane.reload()
    onLoadingChanged: pane.busyChanged(pane.loading)

    Connections {
        target: Qt.application
        ignoreUnknownSignals: true
        function onActiveChanged() { if (Qt.application.active) pane.reload(true) }
    }

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onSavesListReady(vid, list) {
            if (vid !== pane.versionId) return
            pane.saves = list || []
            pane.loading = false
            pane.silent = false
        }
    }

    Column {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        spacing: 14

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
                    label: "搜索存档"
                    onEdited: (v) => pane.query = v
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pane.saves.length + " 个存档"
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
                        pane.reload()
                        if (pane.toast) pane.toast.show("正在重新读取存档", -1, "info", true)
                    }
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    iconName: "folder-open"
                    text: "文件夹"
                    onClicked: if (pane.b) pane.b.openSavesFolder(pane.versionId)
                }
            }
        }

        // ── 单列列表：ListView 虚拟化，存档目录大时也不一次性实例化 ──
        ListView {
            id: saveList
            width: parent.width
            height: parent.height - 48
            clip: true
            model: pane.shown
            spacing: 8
            reuseItems: true
            cacheBuffer: 400
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                width: saveList.width
                height: 76
                readonly property bool hasIcon: modelData.iconPath !== undefined && modelData.iconPath !== ""

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rMd
                    color: hov.hovered ? "#101419" : "#0b0d12"
                    border.width: 1
                    border.color: hov.hovered ? "#333a47" : Theme.line2
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
                }

                Rectangle {
                    id: ico
                    width: 56
                    height: 56
                    radius: Theme.rSm
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#141a22"
                    clip: true
                    Image {
                        anchors.fill: parent
                        visible: hasIcon
                        source: hasIcon ? modelData.iconPath : ""
                        sourceSize.width: 112
                        sourceSize.height: 112
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !hasIcon
                        text: (modelData.name && modelData.name.length > 0)
                              ? modelData.name.charAt(0).toUpperCase() : "?"
                        color: "#8fb4ff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors.left: ico.right
                    anchors.leftMargin: 14
                    anchors.right: del.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Text {
                        width: parent.width
                        text: modelData.name || ""
                        color: "#f2f5fa"
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: modelData.sizeDisplay || ""
                        color: "#6b7686"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                SButton {
                    id: del
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    kind: 1
                    danger: true
                    height: 28
                    radius: 2
                    text: "删除"
                    onClicked: {
                        pane.pendingDelete = modelData.name
                        confirmPop.open()
                    }
                }
                HoverHandler { id: hov }
            }

            footer: Column {
                width: saveList.width
                Text {
                    width: parent.width
                    topPadding: 26
                    visible: saveList.count === 0 && !pane.loading
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.saves.length === 0 ? "此版本还没有存档" : "没有匹配的存档"
                    color: "#5d6673"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    topPadding: 26
                    visible: pane.loading
                    horizontalAlignment: Text.AlignHCenter
                    text: "正在读取存档列表…"
                    color: "#6b7686"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }
        }
    }

    // 删存档目录不可撤销 —— 先问一句
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
                text: "删除存档？"
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
                        if (pane.b) pane.b.deleteSave(pane.pendingDelete, pane.versionId)
                        confirmPop.close()
                        if (pane.toast) pane.toast.show("已删除存档 " + pane.pendingDelete, -1, "info", true)
                        pane.pendingDelete = ""
                        // deleteSave 没有完成信号，等文件系统落定再重扫
                        Qt.callLater(function() { pane.reload(true) })
                    }
                }
            }
        }
    }
}
