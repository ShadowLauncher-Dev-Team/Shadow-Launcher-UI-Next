// SPDX-License-Identifier: AGPL-3.0-or-later
// 外观：配色方案（黑/白）+ 启动页图片自定义（选图 / 取景 / 恢复默认）
//
// 数据流（单一真源）：
//   SettingsBackend   colorScheme / customBgPath / bgZoom / cropX / cropY
//   ShadowBackend     b.colorScheme（Theme.scheme 由 StageShell 同步）、b.customBgUrl、b.bgPresets()…
//   预览与启动页共用 SBgImage，取景公式只此一处，避免"预览和实际不一样"。
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null
    property bool busy: false

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property string scheme: (pane.b && pane.b.colorScheme) ? pane.b.colorScheme : "dark"
    // 图库变化计数：bgPresets() 是普通函数调用（没有 NOTIFY 属性），
    // 不靠这个计数的话，切换背景后卡片的选中态不会刷新。
    property int bgRev: 0
    readonly property var presets: {
        pane.bgRev   // 建立依赖（读一下即可）
        return (pane.b && pane.b.bgPresets) ? pane.b.bgPresets() : []
    }
    // 内置预设 / 用户导入的分开渲染（导入的排在后面，且可以有多张）
    readonly property var builtinPresets: pane._pick(true)
    readonly property var userPresets: pane._pick(false)
    function _pick(builtin) {
        var out = []
        for (var i = 0; i < pane.presets.length; i++)
            if (!!pane.presets[i].builtin === builtin) out.push(pane.presets[i])
        return out
    }
    // 当前用的是哪张（内置 = 没在用自定义图）
    readonly property bool usingCustom: {
        for (var i = 0; i < pane.presets.length; i++)
            if (pane.presets[i].active) return !pane.presets[i].builtin
        return false
    }

    // 取景本地态：拖动/滚轮时先改本地，节流后再写后端，
    // 否则每移动一像素都落一次 QSettings 并触发全局 customBgChanged。
    property real viewZoom: 1.0
    property real viewCx: 0.5
    property real viewCy: 0.5

    // ── 取景框必须和「启动页内容区」同比例 ──────────────────────
    // 之前预览是 2.2:1 的宽条，而启动页内容区约 1.24:1 —— 在宽条里挪到边的位置，
    // 启动页上根本看不到，等于选不准（用户实测）。这里按真实窗口算比例：
    // 启动页内容区 = (窗口宽 - 侧栏宽) × 窗口高。
    readonly property var win: Window.window
    readonly property real stageAspect: {
        const w = pane.win ? pane.win.width : 1100
        const h = pane.win ? pane.win.height : 720
        const sw = (w < 900) ? Theme.sideWNarrow : Theme.sideW
        return Math.max(0.6, Math.min(3.0, (w - sw) / Math.max(1, h)))
    }
    readonly property real previewMaxH: 340   // 太高会把缩放条挤出可视区，用户得边滚边调

    // 「实时预览」：拖动/缩放的这段时间里，把设置页淡下去，让背后的启动页直接透出来。
    readonly property bool livePreview: previewHold.running || (preview && preview.dragActive)
    // 「只剩预览」：拖动/缩放期间，设置页里除预览图以外的内容全部淡出（背景/标题/左栏/卡片/说明/滑条），
    // 让启动页整页透出来。之前是把整页压到 0.22 透明度 —— 两层叠在一起很别扭（用户实测）。
    readonly property bool solo: livePreview

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
        // 后端改图/恢复默认时把本地取景拉回来（避免预览停在旧图的缩放上）。
        // 但拖动中我们自己正在写后端，那次信号不能反过来覆盖本地值（会抖）。
        function onCustomBgChanged() {
            pane.bgRev++
            if (preview && preview.dragActive) return
            pane.syncFromBackend()
        }
    }

    Timer {
        id: previewHold
        interval: 900
    }

    // 取景写后端：**节流**（不是防抖）。
    // 之前是 applyTimer.restart()：拖动中每次 mousemove 都把 150ms 定时器重置，
    // 于是整个拖动期间一次都不写 —— 启动页要等松手才动（用户实测）。现在：
    //   · 距上次写入 ≥ 80ms 就立即写（拖动中约 12fps，启动页跟手）
    //   · 不足 80ms 的零碎变更由定时器兜底，保证最后一次一定落盘
    property real _lastPushMs: 0

    function pushView() {
        if (!pane.b) return
        const now = Date.now()
        if (now - pane._lastPushMs >= 80) {
            pane._lastPushMs = now
            pane.b.setBgZoom(pane.viewZoom)
            pane.b.updateCrop(pane.viewCx, pane.viewCy)
        } else {
            applyTimer.restart()
        }
    }

    Timer {
        id: applyTimer
        interval: 80
        onTriggered: {
            if (!pane.b) return
            pane._lastPushMs = Date.now()
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
                title: qsTr("配色方案")
                opacity: pane.solo ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                enabled: !pane.solo

                SetStack {
                    width: parent.width
                    label: qsTr("主题")
                    // 白色方案暂时下线（影：切过去发现大量不适配）。恢复时把下面 model 里的白色项
                    // 加回来，并把 SettingsBackend 的 kEnableLightScheme 改成 true —— 两处一起开。
                    desc: qsTr("当前提供深色主题。所有文字都与背景保持足够对比，不会出现文字与背景同色。")

                    Row {
                        spacing: 12

                        Repeater {
                            model: [
                                { id: "dark",  name: qsTr("黑色"),  bg: "#0d1016", card: "#12151c", fg: "#e8ebf2", fg2: "#98a1ae", line: "#2b3240" }
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
                                        text: qsTr("正文示例 The quick brown fox")
                                        color: modelData.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: qsTr("次要文字 / 说明")
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
                                        if (pane.toast) pane.toast.show(qsTr("已切换到「%1」配色").arg(modelData.name), 1800)
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
                title: qsTr("启动页图片")
                bare: pane.solo

                SetStack {
                    width: parent.width
                    label: qsTr("图片来源")
                    opacity: pane.solo ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    enabled: !pane.solo
                    desc: qsTr("启动器自带的默认图永久保留；导入的图片会留在这里，每张各自记住自己的取景，随时切回来。")

                    // 图库：内置预设 + 每张导入的图 + 「选择本地图片」。
                    // 用 Flow 而不是 Row：导入多张时自动换行，不会把卡片挤到可视区外。
                    Flow {
                        width: parent.width
                        spacing: 12

                        // 内置预设（后续新增预设会自动多出卡片）
                        Repeater {
                            model: pane.builtinPresets

                            delegate: Item {
                                width: 176
                                height: 104
                                readonly property bool selected: modelData.active === true

                                // 图片容器：**不画边框**。图片是直角矩形，若边框画在它下面，
                                // 四个圆角处会被图片的直角盖掉一截 —— 看起来就是「边框缺角」。
                                // 所以边框单独抽成最上层一条（见下面 borderLayer），四角永远完整。
                                Rectangle {
                                    id: bPicFrame
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    color: Theme.bgCard2
                                    // clip 只裁矩形边界：圆角要另外用遮罩，否则四角会露出方角
                                    clip: true
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: bPicMask
                                    }

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        source: modelData.source
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        opacity: 0.92
                                    }

                                    // 名字条：从透明渐隐到深色，白字永远压得住（不再是一块灰白条）
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 34
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Theme.scrim }
                                        }
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        anchors.bottomMargin: 6
                                        text: modelData.name
                                        color: Theme.imageFg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                    }
                                }

                                // 圆角遮罩源：只做形状，不可见
                                Rectangle {
                                    id: bPicMask
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    visible: false
                                    layer.enabled: true
                                }

                                // 边框层（最上层，圆角完整）
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    color: "transparent"
                                    border.width: selected ? 2 : 1
                                    border.color: selected ? Theme.accent : Theme.line2
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!pane.b) return
                                        pane.b.applyBgPreset(modelData.id)
                                        if (pane.toast) pane.toast.show(qsTr("已使用「%1」").arg(modelData.name), 1800)
                                    }
                                }
                            }
                        }

                        // 用户导入的图（每张都有自己的取景，切回来还是上次调的样子）
                        Repeater {
                            model: pane.userPresets

                            delegate: Item {
                                id: uTile
                                width: 176
                                height: 104
                                readonly property bool selected: modelData.active === true

                                // 同上：图片容器不画边框，边框单独一层压在最上面
                                Rectangle {
                                    id: uPicFrame
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    color: Theme.bgCard2
                                    // clip 只裁矩形边界：圆角要另外用遮罩，否则四角会露出方角
                                    clip: true
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: uPicMask
                                    }

                                    // 缩略图用这张图**自己的**取景，所见即启动页上会看到的
                                    SBgImage {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        source: modelData.source
                                        zoom: modelData.zoom
                                        cropX: modelData.cropX
                                        cropY: modelData.cropY
                                    }

                                    // 名字条：透明 → 深色渐隐，白字永远压得住
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 34
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Theme.scrim }
                                        }
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        anchors.bottomMargin: 6
                                        text: modelData.name
                                        color: Theme.imageFg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                    }

                                }

                                // 圆角遮罩源：只做形状，不可见
                                Rectangle {
                                    id: uPicMask
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    visible: false
                                    layer.enabled: true
                                }

                                // 边框层（最上层，压住图片的直角，圆角完整）
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.rMd
                                    color: "transparent"
                                    border.width: selected ? 2 : 1
                                    border.color: selected ? Theme.accent : Theme.line2
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!pane.b) return
                                        pane.b.applyBgPreset(modelData.id)
                                        if (pane.toast) pane.toast.show(qsTr("已使用「%1」").arg(modelData.name), 1800)
                                    }
                                }

                                // 删除（只删数据目录里的副本，不动用户原图）
                                Item {
                                    width: 26
                                    height: 26
                                    anchors.right: parent.right
                                    anchors.rightMargin: 3
                                    anchors.top: parent.top
                                    anchors.topMargin: 3
                                    z: 2
                                    // 常驻显示：这个按钮先后因为「悬停判定写在按钮自己身上」和
                                    // 「悬停判定写在整块 tile 上」两次拿不到 hover 而消失。
                                    // 删除是低频且明确的动作，宁可一直露着，也不要看不见/点不中。
                                    visible: true
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 11
                                        color: Theme.scrim
                                        opacity: 0.7
                                    }
                                    SIcon {
                                        anchors.centerIn: parent
                                        name: "x"
                                        size: 12
                                        color: Theme.imageFg
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!pane.b) return
                                            pane.b.removeBgImage(modelData.id)
                                            if (pane.toast) pane.toast.show(qsTr("已移除「%1」").arg(modelData.name), 1800)
                                        }
                                    }
                                }
                            }
                        }

                        // 「选择本地图片」：导入后进图库，随时可切回来
                        Item {
                            width: 176
                            height: 104

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.rMd
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.line2
                                clip: true

                                Column {
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
                                        text: qsTr("选择本地图片")
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
                                    // 每次选择都会**追加**到图库（同内容自动去重），不覆盖已导入的
                                    if (pane.b.chooseBgImage()) {
                                        if (pane.toast) pane.toast.show(qsTr("已加入图库并启用"), 2000)
                                    }
                                }
                            }
                        }
                    }
                }

                SetStack {
                    width: parent.width
                    divider: false
                    bare: pane.solo
                    label: qsTr("取景")
                    desc: qsTr("在预览框内拖动调整位置；按住 Ctrl 滚轮或拖动下方滑块缩放。预览框与启动页同比例，框里看到的就是启动页实际显示的范围。")

                    SBgImage {
                        id: preview
                        // 宽度取「上限高度 × 比例」与可用宽度的较小者，高度反算 —— 保证与启动页同比例
                        width: Math.min(parent.width, Math.round(pane.previewMaxH * pane.stageAspect))
                        height: Math.max(160, Math.round(width / pane.stageAspect))
                        // customBgUrl = 当前使用的那张图的显示 URL（内置 → qrc，导入 → file:///）
                        source: (pane.b && pane.b.customBgUrl) ? pane.b.customBgUrl : ""
                        zoom: pane.viewZoom
                        cropX: pane.viewCx
                        cropY: pane.viewCy
                        interactive: true
                        onViewChanged: (z, cx, cy) => {
                            pane.viewZoom = z
                            pane.viewCx = cx
                            pane.viewCy = cy
                            pane.pushView()
                            previewHold.restart()   // 拖动/滚轮期间与之后 0.9s 保持"只剩预览"的模式
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 14
                        opacity: pane.solo ? 0 : 1
                        enabled: !pane.solo
                        Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }

                        SSlider {
                            id: zoomSlider
                            width: Math.max(180, preview.width - 300)
                            from: 100
                            to: 400
                            step: 5
                            value: Math.round(pane.viewZoom * 100)
                            onMoved: (v) => {
                                pane.viewZoom = v / 100.0
                                pane.pushView()
                                previewHold.restart()
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
                            text: qsTr("重置取景")
                            onClicked: {
                                if (!pane.b) return
                                pane.b.resetBgView()
                                pane.syncFromBackend()
                                if (pane.toast) pane.toast.show(qsTr("取景已重置"), 1600)
                            }
                        }

                        SButton {
                            kind: 1
                            radius: 2
                            height: 30
                            text: qsTr("恢复默认背景")
                            onClicked: {
                                if (!pane.b) return
                                pane.b.restoreDefaultBg()
                                pane.syncFromBackend()
                                if (pane.toast) pane.toast.show(qsTr("已恢复默认背景"), 1800)
                            }
                        }
                    }
                }
            }

            SetNote {
                width: parent.width
                kind: "info"
                icon: "image"
                opacity: pane.solo ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                text: qsTr("支持 PNG / JPG / WEBP / BMP。图片会被复制到启动器数据目录，删除或移动原文件不会影响显示。")
            }
        }
    }
}
