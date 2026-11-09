// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 资源包（定稿甲：单列）
//
// 资源包没有启用/禁用接口（游戏内选），所以卡片右侧只有删除。
import QtQuick
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    property var allPacks: []
    property string query: ""

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

    function reload() {
        if (!pane.b || pane.versionId.length === 0) return
        pane.b.listResourcePacksAsync(pane.versionId)
    }
    Component.onCompleted: pane.reload()

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onResourcePacksListReady(vid, list) { if (vid === pane.versionId) pane.allPacks = list || [] }
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
                    width: 260
                    height: 36
                    label: "搜索资源包"
                    onEdited: (v) => pane.query = v
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pane.allPacks.length + " 个"
                    color: "#4b5462"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
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

        Flickable {
            width: parent.width
            height: parent.height - 48
            clip: true
            contentWidth: width
            contentHeight: packCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: packCol
                width: parent.width
                spacing: 8

                Repeater {
                    model: pane.shown
                    delegate: Item {
                        width: packCol.width
                        height: 66
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
                            width: 44
                            height: 44
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
                                sourceSize.width: 88
                                sourceSize.height: 88
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: modelData.iconPath === undefined || modelData.iconPath === ""
                                text: modelData.displayName ? modelData.displayName.charAt(0).toUpperCase() : "?"
                                color: bad ? "#8a6d33" : "#7fa9f5"
                                font.family: Theme.fontFamily
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                        }
                        Column {
                            anchors.left: ico.right
                            anchors.leftMargin: 11
                            anchors.right: del.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Row {
                                spacing: 7
                                Text {
                                    text: modelData.displayName || modelData.fileName || ""
                                    color: "#eef2f8"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.versionLabel || ""
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
                                if (!pane.b) return
                                pane.b.deleteResourcePack(modelData.fileName, pane.versionId)
                                if (pane.toast) pane.toast.show("已删除")
                                pane.reload()
                            }
                        }
                        HoverHandler { id: hov }
                    }
                }

                Text {
                    width: packCol.width
                    topPadding: 20
                    visible: pane.shown.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.allPacks.length === 0 ? "此版本还没有资源包" : "没有匹配的资源包"
                    color: "#3f4753"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
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
            if (pane.toast) pane.toast.show(ok ? "已导入" : "导入失败")
            pane.reload()
        }
    }
}
