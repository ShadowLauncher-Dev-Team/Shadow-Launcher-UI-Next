// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 顶部不确定进度条（Material / Google 线性进度风格）
// 用途：知道"在做事"但不知道还剩多久 —— 登录、检查更新、扫描这类。
// 有确定进度时不要用它，用真正的进度条。
// 用法：running: true 开始扫动；false 时淡出。
Item {
    id: root

    property bool running: false
    property color color: Theme.accent
    property int thickness: 3

    implicitHeight: thickness
    clip: true
    visible: opacity > 0.01
    opacity: running ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
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
        // 不要用 visible: running —— 一停就瞬间消失，只剩底轨淡出，看着像"硬切"。
        // 跟随容器 opacity 一起淡出（Behavior on opacity 已在根上定义）。
        visible: opacity > 0.01

        SequentialAnimation on x {
            running: root.running
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
