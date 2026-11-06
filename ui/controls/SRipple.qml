// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 点击涟漪：从按下的那一点扩散一圈再消失。
// 只在"点击会离开当前视图"的地方用（进详情、开始安装），不铺满全部控件 —— 过度会腻。
Item {
    id: root
    property color color: "#ffffff"
    property real maxRadius: 220
    clip: true

    Item {
        id: ripple
        visible: false
        anchors.fill: parent

        Rectangle {
            id: circle
            width: 0; height: 0
            radius: width / 2
            antialiasing: true
            x: root._cx - width / 2
            y: root._cy - height / 2
            color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.16)
        }

        ParallelAnimation {
            id: anim
            NumberAnimation { target: circle; property: "width";  from: 0; to: root.maxRadius * 2; duration: Theme.durSlow; easing.type: Theme.easeEnter }
            NumberAnimation { target: circle; property: "height"; from: 0; to: root.maxRadius * 2; duration: Theme.durSlow; easing.type: Theme.easeEnter }
            NumberAnimation { target: circle; property: "opacity"; from: 1; to: 0; duration: Theme.durSlow; easing.type: Theme.easeExit }
            onFinished: ripple.visible = false
        }
    }

    property real _cx: 0
    property real _cy: 0

    function burst(px, py) {
        root._cx = px
        root._cy = py
        circle.width = 0
        circle.height = 0
        circle.opacity = 1
        ripple.visible = true
        anim.restart()
    }
}
