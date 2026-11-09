// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · Mod 管理（定稿甲：单列卡片）
//
// 卡片形态借下载页，但配色、容器、行距全部用版本设置 v2 的令牌。
// 开关 = setModEnabled（真实改名 jar ↔ jar.disabled），批量 = setAllModsEnabled。
import QtQuick
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property var allMods: []
    property string query: ""

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
        pane.b.listModsAsync(pane.versionId)
    }
    Component.onCompleted: pane.reload()

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onModsListReady(vid, list) { if (vid === pane.versionId) pane.allMods = list || [] }
    }

    Column {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        spacing: 12

        // ── 控制行：搜索 + 批量 + 导入 ──
        Item {
            width: Math.min(720, parent.width)
            height: 36
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                SField {
                    width: 260
                    height: 36
                    label: "搜索 Mod"
                    onEdited: (v) => pane.query = v
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pane.allMods.length + " 个 · 启用 " + pane.enabledCount
                    color: "#4b5462"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    text: "全部启用"
                    onClicked: {
                        if (!pane.b) return
                        var n = pane.b.setAllModsEnabled(pane.versionId, true)
                        if (pane.toast) pane.toast.show("已启用 " + n + " 个")
                        pane.reload()
                    }
                }
                SButton {
                    kind: 1
                    height: 32
                    radius: 2
                    text: "全部禁用"
                    onClicked: {
                        if (!pane.b) return
                        var n = pane.b.setAllModsEnabled(pane.versionId, false)
                        if (pane.toast) pane.toast.show("已禁用 " + n + " 个")
                        pane.reload()
                    }
                }
                SButton {
                    kind: 0
                    height: 32
                    radius: 2
                    implicitWidth: 92
                    iconName: "package-plus"
                    text: "导入"
                    onClicked: importDialog.open()
                }
            }
        }

        // ── 列表 ──
        Flickable {
            width: Math.min(720, parent.width)
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
                        height: 66
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
                        // 图标：有 iconPath 用图，否则取首字母
                        Rectangle {
                            id: ico
                            width: 44
                            height: 44
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
                                sourceSize.width: 88
                                sourceSize.height: 88
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: modelData.iconPath === undefined || modelData.iconPath === ""
                                text: modelData.modName ? modelData.modName.charAt(0).toUpperCase() : "?"
                                color: parent.parent.on ? "#7fa9f5" : "#4b5462"
                                font.family: Theme.fontFamily
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                        }
                        Column {
                            anchors.left: ico.right
                            anchors.leftMargin: 11
                            anchors.right: sw.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Row {
                                spacing: 7
                                Text {
                                    text: modelData.modName || modelData.fileName || ""
                                    color: parent.parent.parent.on ? "#eef2f8" : "#8a94a3"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.version || ""
                                    color: "#5d6673"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                            Text {
                                width: parent.width
                                text: modelData.description || ""
                                color: "#7b8494"
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Text {
                                width: parent.width
                                text: (modelData.fileName || "") + " · " + (modelData.fileSizeText || "")
                                color: "#3f4753"
                                elide: Text.ElideMiddle
                                font.family: "Consolas"
                                font.pixelSize: 10
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
                    topPadding: 20
                    visible: pane.shown.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.allMods.length === 0 ? "此版本还没有 Mod" : "没有匹配的 Mod"
                    color: "#3f4753"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
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
            if (pane.toast) pane.toast.show(ok ? "已导入" : "导入失败")
            pane.reload()
        }
    }
}
