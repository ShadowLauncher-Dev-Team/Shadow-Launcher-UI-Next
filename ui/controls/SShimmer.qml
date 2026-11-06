// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 高光扫过层（骨架屏 / 最新版卡 / 加载态）。
// 为什么不自己跑动画：一屏骨架屏有十几块，各自 NumberAnimation 会让主线程成片重绘；
// 统一由页面给一个 0..1 的 phase，所有实例共用一个节拍（与下载进度页流光同一套做法）。
// 裁剪在自身范围内，绝不越出被装饰的容器（"不穿模"由 clip 保证，不靠算坐标）。
Item {
    id: root
    property real phase: 0          // 0..1，由外部推进
    property int bandWidth: 120     // 光带宽度
    property color tint: "#ffffff"
    property real strength: 0.06    // 峰值不透明度
    property bool active: true
    clip: true

    Rectangle {
        id: band
        width: root.bandWidth
        height: parent.height * 1.6
        y: -parent.height * 0.3
        rotation: 18
        visible: root.active && root.width > 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0) }
            GradientStop { position: 0.5;  color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.strength) }
            GradientStop { position: 1.0;  color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0) }
        }
        // 从左侧完全看不见的位置，走到右侧完全看不见的位置
        x: -root.bandWidth + root.phase * (root.width + root.bandWidth * 2)
    }
}
