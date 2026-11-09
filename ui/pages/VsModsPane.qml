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

    function reload() {
        if (!pane.b || pane.versionId.length === 0) return
        if (!pane.loading) { pane.loading = true; pane.busyChanged(true) }
        pane.b.listModsAsync(pane.versionId)
    }
    Component.onCompleted: pane.reload()

    onLoadingChanged: pane.busyChanged(pane.loading)

    // 拖入 jar 后回到窗口时重新扫一遍（外部文件系统变化没有信号）
    Connections {
        target: Qt.application
        ignoreUnknownSignals: true
        function onActiveChanged() { if (Qt.application.active) pane.reload() }
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
                        pane.reload()
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

        Flickable {
            width: parent.width
            height: parent.height - 48
            clip: true
            contentWidth: width
            contentHeight: modCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: modCol
                width: parent.width
                spacing: 8

                Repeater {
                    model: pane.shown
                    delegate: Item {
                        width: modCol.width
                        height: 68
                        readonly property bool on: modelData.enabled === true
                        readonly property bool bad: modelData.valid === false

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.rMd
                            color: hov.hovered ? "#101419" : "#0b0d12"
                            border.width: 1
                            border.color: bad ? "#2a2118" : (hov.hovered ? "#333a47" : Theme.line2)
                            Behavior on color { ColorAnimation { duration: Theme.durFast } }
                            Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
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
                                    color: parent.parent.parent.on ? "#f2f5fa" : "#a8b1be"
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
                }

                Text {
                    width: modCol.width
                    topPadding: 24
                    visible: pane.shown.length === 0 && !pane.loading
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.allMods.length === 0 ? "此版本还没有 Mod" : "没有匹配的 Mod"
                    color: "#5d6673"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                Text {
                    width: modCol.width
                    topPadding: 24
                    visible: pane.loading
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
