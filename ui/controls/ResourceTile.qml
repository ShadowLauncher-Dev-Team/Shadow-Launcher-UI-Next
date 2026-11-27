// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 资源库网格卡片（A 方案「货架式」）：竖向，40 图标 + 中英名 + 两行简介 + 下载量/日期/来源
Rectangle {
    id: tile

    property string title: ""
    property string zh: ""
    property string description: ""
    property string iconUrl: ""
    property string slug: ""
    property int downloads: 0
    property string source: "Modrinth"
    property string dateModified: ""
    signal clicked()

    property bool hovered: false

    // ── 键盘（统一契约四件套）──
    // 本卡片没有 dimmed/busy 这类内部灰态：唯一的"不可用"通道是 Qt 的 Item.enabled
    // （为 false 时父子一起收不到鼠标事件，鼠标入口本来就已经死了 ⇒ Tab 也该跳过）。
    activeFocusOnTab: tile.enabled

    // 下载量缩写：中文用「亿 / 万」，英文没有这两个量级 → SI 后缀（120M / 12K）。
    // 探针就是译文本身：中文里「%1 万」含「万」，英文里不含。
    function fmtDl(n) {
        if (qsTr("%1 万").indexOf("万") < 0) {
            if (n >= 1000000) return qsTr("%1M").arg((n / 1000000).toFixed(1))
            if (n >= 1000) return qsTr("%1K").arg((n / 1000).toFixed(0))
            return n.toString()
        }
        if (n >= 100000000) return qsTr("%1 亿").arg((n / 100000000).toFixed(1))
        if (n >= 10000) return qsTr("%1 万").arg((n / 10000).toFixed(0))
        return n.toString()
    }
    // 鼠标点击与键盘激活的**唯一入口**：按压复位 → 涟漪起手式 → clicked()。
    // 键盘没有坐标，从卡片中心起涟漪（与中心点击同一效果）。
    function activate(px, py) {
        tile.pressed = false
        ripple.burst(px, py)
        tile.clicked()
    }

    // 页面统一推进的高光相位（用于 hover 时扫一道光）
    property real shimmerPhase: 0
    property bool pressed: false
    implicitHeight: 150
    radius: Theme.rMd
    color: hovered ? Theme.bgCard2 : Theme.bgCard2
    border.width: 1
    border.color: hovered ? Theme.line2 : Theme.line
    // clip 去掉：唯一的裁剪需求（涟漪越界、高光越界）已由 SRipple / SShimmer 各自
    // 的 clip:true 承担，根 Item 的矩形 clip 只会把焦点环（负 margin 那 2px）切掉，
    // 让环退化成贴着边框的一条 1px 暗线（qml.exe 探针实测：环色 #7aa7ff 只剩 30 号像素、
    // 亮度掉到 rgb(71,95,142)）。去掉后静止渲染与原来只差：卡片自身底边那 1 设备像素
    // （原先被 clip 削掉，现在正常绘制），其余 46 个像素差值为 1/255（抗锯齿舍入，探针比对）。
    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

    // ── 悬停 / 按压 ──
    // 悬停：整卡上浮 2px + 边框提亮（不是只变色），视线先感到"这张卡是活的"
    // 按压：缩到 0.975 再弹回（easePop 过冲），松手的回弹比按下更明显
    transform: Translate {
        y: tile.hovered ? -2 : 0
        Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
    }
    scale: tile.pressed ? 0.975 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easePop } }

    // hover 时一道柔光从左扫到右（复用页面相位，卡片自己不持有动画）
    SShimmer {
        anchors.fill: parent
        phase: tile.shimmerPhase
        active: tile.hovered
        bandWidth: 90
        strength: 0.07
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tile.hovered = true
        onExited: tile.hovered = false
        // 鼠标按下也拿焦点：键盘与鼠标共用同一套焦点状态
        onPressed: {
            tile.pressed = true
            Theme.keyboardNav = false
            tile.forceActiveFocus()
        }
        onReleased: tile.pressed = false
        onCanceled: tile.pressed = false
        onClicked: tile.activate(hit.mouseX, hit.mouseY)
    }

    // 键盘激活：与鼠标**同一个入口**（tile.activate → clicked() → 进详情），不另写逻辑
    Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            e.accepted = true
            // isAutoRepeat：按住不放会连发，等于鼠标连点；鼠标一次点击只进一次详情。
            if (e.isAutoRepeat || !tile.enabled) return
            tile.activate(tile.width / 2, tile.height / 2)
        }
    }

    // 点击涟漪：扩散后再离开（过渡到详情页的"起手式"）
    SRipple {
        id: ripple
        anchors.fill: parent
        color: Theme.accentText
        maxRadius: 260
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Row {
            width: parent.width
            spacing: 10
            Rectangle {
                width: 40; height: 40
                radius: Theme.rSm
                color: tile.hovered ? Theme.bgCard : Theme.bgCard
                clip: true
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                Image {
                    anchors.fill: parent
                    source: tile.iconUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: tile.iconUrl.length > 0
                    // hover 时图标轻微推近（1.08），卡片"凑过来"的感觉
                    scale: tile.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
                }
            }
            Column {
                width: parent.width - 50
                spacing: 2
                Text {
                    width: parent.width
                    text: tile.zh.length > 0 ? tile.zh : tile.title
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    x: tile.hovered ? 2 : 0
                    Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter } }
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: tile.zh.length > 0 ? tile.title : ""
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            width: parent.width
            height: 30
            text: tile.description
            color: Theme.fg2
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // 底部三列：左=下载量，中=更新日期，右=来源（全称，不再缩写）。
        // 用锚点而不是 Row + 硬编码宽度：之前 Item{width: parent.width-150} 让三列各自偏移，
        // 卡片宽度一变就错位。
        Item {
            width: parent.width
            height: 13

            Text {
                id: dlText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: tile.fmtDl(tile.downloads)
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: tile.dateModified.length >= 10 ? tile.dateModified.substring(0, 10) : ""
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: tile.source === "CurseForge" ? "CurseForge" : "Modrinth"
                color: tile.source === "CurseForge" ? Theme.warn : Theme.ok
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
    }

    // 焦点环：独立一层描边，只锚定 + 负 margin，不参与布局（不改尺寸/位置）
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingGap
        radius: tile.radius + Theme.focusRingGap
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: tile.activeFocus && Theme.keyboardNav
        z: 999
        antialiasing: true
    }
}
