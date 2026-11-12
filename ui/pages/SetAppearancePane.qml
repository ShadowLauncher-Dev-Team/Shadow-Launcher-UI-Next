// SPDX-License-Identifier: AGPL-3.0-or-later
// 外观：配色方案（黑/白）+ 启动页图片自定义（选图 / 取景 / 恢复默认）
//
// 数据流（单一真源）：
//   SettingsBackend   colorScheme / customBgPath / bgZoom / cropX / cropY
//   ShadowBackend     b.colorScheme（Theme.scheme 由 StageShell 同步）、b.customBgUrl、b.bgPresets()…
//   预览与启动页共用 SBgImage，取景公式只此一处，避免"预览和实际不一样"。
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null
    property bool busy: false

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property string scheme: (pane.b && pane.b.colorScheme) ? pane.b.colorScheme : "dark"
    readonly property var presets: (pane.b && pane.b.bgPresets) ? pane.b.bgPresets() : []
    readonly property bool usingCustom: (pane.b && pane.b.customBgUrl) ? pane.b.customBgUrl.length > 0 : false

    // 取景本地态：拖动/滚轮时先改本地，节流后再写后端，
    // 否则每移动一像素都落一次 QSettings 并触发全局 customBgChanged。
    property real viewZoom: 1.0
    property real viewCx: 0.5
    property real viewCy: 0.5

    function syncFromBackend() {
        if (!pane.b) return
        pane.viewZoom = pane.b.bgZoom !== undefined ? pane.b.bgZoom : 1.0
        pane.viewCx = pane.b.cropX !== undefined ? pane.b.cropX : 0.5
        pane.viewCy = pane.b.cropY !== undefined ? pane.b.cropY : 0.5
    }

    Component.onCompleted: pane.syncFromBackend()

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        // 后端改图/恢复默认时把本地取景拉回来（避免预览停在旧图的缩放上）
        function onCustomBgChanged() { pane.syncFromBackend() }
    }

    Timer {
        id: applyTimer
        interval: 150
        onTriggered: {
            if (!pane.b) return
            pane.b.setBgZoom(pane.viewZoom)
            pane.b.updateCrop(pane.viewCx, pane.viewCy)
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.height + 60
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        TapHandler { onTapped: pane.forceActiveFocus() }

        Column {
            id: col
            x: 40
            y: 4
            width: Math.min(900, flick.width - 80)
            spacing: 26

            // ── 配色方案 ──────────────────────────────────────
            SetGroup {
                width: parent.width
                title: "配色方案"

                SetStack {
                    width: parent.width
                    label: "主题"
                    desc: "切换后立即生效。两套方案的所有文字都使用与背景对比度足够的颜色，不会出现文字与背景同色。"

                    Row {
                        spacing: 12

                        Repeater {
                            model: [
                                { id: "dark",  name: "黑色",  bg: "#0d1016", card: "#12151c", fg: "#e8ebf2", fg2: "#98a1ae", line: "#2b3240" },
                                { id: "light", name: "白色",  bg: "#eef1f6", card: "#ffffff", fg: "#101827", fg2: "#3d4859", line: "#cfd7e3" }
                            ]

                            delegate: Item {
                                width: 236
                                height: 108

                                Rectangle {
                                    id: cardBox
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    color: modelData.card
                                    border.width: (pane.scheme === modelData.id) ? 2 : 1
                                    border.color: (pane.scheme === modelData.id) ? Theme.accent : Theme.line2
                                    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 12
                                    spacing: 6

                                    Row {
                                        spacing: 8
                                        Rectangle {
                                            width: 22
                                            height: 22
                                            radius: 6
                                            color: modelData.bg
                                            border.width: 1
                                            border.color: modelData.line
                                        }
                                        Rectangle {
                                            width: 10
                                            height: 22
                                            radius: 3
                                            color: Theme.accent
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name
                                            color: modelData.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        text: "正文示例 The quick brown fox"
                                        color: modelData.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: "次要文字 / 说明"
                                        color: modelData.fg2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                // 选中角标
                                Rectangle {
                                    visible: pane.scheme === modelData.id
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: 10
                                    anchors.topMargin: 10
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: Theme.accent
                                    SIcon {
                                        anchors.centerIn: parent
                                        name: "check"
                                        size: 11
                                        color: Theme.accentFg
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!pane.b) return
                                        pane.b.setColorScheme(modelData.id)
                                        if (pane.toast) pane.toast.show("已切换到" + modelData.name + "配色", 1800)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── 启动页图片 ────────────────────────────────────
            SetGroup {
                width: parent.width
                title: "启动页图片"

                SetStack {
                    width: parent.width
                    label: "图片来源"
                    desc: "启动器自带的默认图永久保留，随时可恢复；也可以选择本地图片。"

                    Row {
                        spacing: 12

                        // 内置预设（后续新增预设会自动多出卡片）
                        Repeater {
                            model: pane.presets

                            delegate: Item {
                                width: 176
                                height: 104
                                readonly property bool selected: !pane.usingCustom
                                    && modelData.builtin === true

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    color: Theme.bgCard2
                                    border.width: selected ? 2 : 1
                                    border.color: selected ? Theme.accent : Theme.line2
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: selected ? 2 : 1
                                        source: modelData.source
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        opacity: 0.92
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 26
                                        color: Theme.scrim
                                        opacity: 0.62
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 8
                                        text: modelData.name
                                        color: Theme.imageFg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!pane.b) return
                                        pane.b.applyBgPreset(modelData.id)
                                        if (pane.toast) pane.toast.show("已使用「" + modelData.name + "」", 1800)
                                    }
                                }
                            }
                        }

                        // 自定义图片卡
                        Item {
                            width: 176
                            height: 104
                            readonly property bool selected: pane.usingCustom

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.rMd
                                color: Theme.bgCard2
                                border.width: selected ? 2 : 1
                                border.color: selected ? Theme.accent : Theme.line2
                                clip: true

                                SBgImage {
                                    anchors.fill: parent
                                    anchors.margins: selected ? 2 : 1
                                    visible: pane.usingCustom
                                    source: pane.b ? pane.b.customBgUrl : ""
                                    zoom: pane.b ? pane.b.bgZoom : 1.0
                                    cropX: pane.b ? pane.b.cropX : 0.5
                                    cropY: pane.b ? pane.b.cropY : 0.5
                                }

                                Column {
                                    visible: !pane.usingCustom
                                    anchors.centerIn: parent
                                    spacing: 6
                                    SIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        name: "image"
                                        size: 20
                                        color: Theme.fg3
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "选择本地图片"
                                        color: Theme.fg2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!pane.b) return
                                    // chooseBgImage 会复制到数据目录（原图被移走也不影响）
                                    if (pane.b.chooseBgImage()) {
                                        if (pane.toast) pane.toast.show("已更换启动页图片", 2000)
                                    }
                                }
                            }
                        }
                    }
                }

                SetStack {
                    width: parent.width
                    divider: false
                    label: "取景"
                    desc: "在预览框内拖动调整位置，滚轮或下方滑块缩放。这里的取景就是启动页实际显示的范围。"

                    SBgImage {
                        id: preview
                        width: parent.width
                        height: Math.max(180, Math.min(280, width * 0.4))
                        source: (pane.b && pane.b.customBgUrl && pane.b.customBgUrl.length > 0)
                                ? pane.b.customBgUrl
                                : (pane.presets.length > 0 ? pane.presets[0].source : "")
                        zoom: pane.viewZoom
                        cropX: pane.viewCx
                        cropY: pane.viewCy
                        interactive: true
                        onViewChanged: (z, cx, cy) => {
                            pane.viewZoom = z
                            pane.viewCx = cx
                            pane.viewCy = cy
                            applyTimer.restart()
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 14

                        SSlider {
                            id: zoomSlider
                            width: Math.max(180, preview.width - 300)
                            from: 100
                            to: 400
                            step: 5
                            value: Math.round(pane.viewZoom * 100)
                            onMoved: (v) => {
                                pane.viewZoom = v / 100.0
                                applyTimer.restart()
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(pane.viewZoom * 100) + "%"
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }

                        SButton {
                            kind: 1
                            radius: 2
                            height: 30
                            text: "重置取景"
                            onClicked: {
                                if (!pane.b) return
                                pane.b.resetBgView()
                                pane.syncFromBackend()
                                if (pane.toast) pane.toast.show("取景已重置", 1600)
                            }
                        }

                        SButton {
                            kind: 1
                            radius: 2
                            height: 30
                            text: "恢复默认背景"
                            onClicked: {
                                if (!pane.b) return
                                pane.b.restoreDefaultBg()
                                pane.syncFromBackend()
                                if (pane.toast) pane.toast.show("已恢复默认背景", 1800)
                            }
                        }
                    }
                }
            }

            SetNote {
                width: parent.width
                kind: "info"
                icon: "image"
                text: "支持 PNG / JPG / WEBP / BMP。图片会被复制到启动器数据目录，删除或移动原文件不会影响显示。"
            }
        }
    }
}
