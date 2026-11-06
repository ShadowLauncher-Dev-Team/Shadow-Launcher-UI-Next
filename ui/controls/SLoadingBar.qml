// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 顶部不确定进度条（Material / Google 线性进度风格）
// 用途：知道"在做事"但不知道还剩多久 —— 登录、检查更新、扫描、资源库拉取这类。
// 用法：running: true 开始扫动；false 时淡出（不硬切）。
//
// 2026-11-06 修「硬消失」：
//   ① 之前 opacity 绑在 running 上用 Behavior 动画，绑定更新与动画竞争，实测结束瞬间直接归零；
//     改成显式 NumberAnimation，running 变化时手动 start/stop，时序完全可控。
//   ② 淡出用 durSlow(260) 而不是 durFast(120)：3px 的条在 120ms 内淡完，眼睛只会看到"没了"。
//   ③ 停下时扫动段**继续扫**（running || opacity > 0.02），否则它定在屏幕中间变成一块静止色块，
//      再配合淡出就像被人一把抹掉。
Item {
    id: root

    property bool running: false
    property color color: Theme.accent
    property int thickness: 3

    implicitHeight: thickness
    clip: true
    opacity: 0
    visible: opacity > 0.001

    onRunningChanged: {
        if (running) {
            fadeOut.stop()
            fadeIn.start()
        } else {
            fadeIn.stop()
            fadeOut.start()
        }
    }

    Component.onCompleted: opacity = running ? 1 : 0

    NumberAnimation {
        id: fadeIn
        target: root; property: "opacity"; to: 1
        duration: Theme.durFast; easing.type: Theme.easeStandard
    }
    NumberAnimation {
        id: fadeOut
        target: root; property: "opacity"; to: 0
        duration: Theme.durSlow; easing.type: Theme.easeStandard
    }

    // 极淡底轨：空档期不会看着像闪一下
    Rectangle {
        anchors.fill: parent
        radius: root.thickness / 2
        color: "#12ffffff"
    }

    // 扫动的高亮段：从左侧外部扫到右侧外部，循环
    Rectangle {
        id: bar
        width: root.width * 0.32
        height: root.thickness
        radius: root.thickness / 2
        color: root.color
        x: -width

        SequentialAnimation on x {
            // 淡出期间继续扫：停住 + 淡出会读成"硬消失"
            running: root.running || root.opacity > 0.02
            loops: Animation.Infinite
            NumberAnimation {
                from: -bar.width
                to: root.width
                duration: Theme.marquee
                easing.type: Easing.InOutQuad
            }
            PauseAnimation { duration: Theme.durFast }
        }
    }
}
