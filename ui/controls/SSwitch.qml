// SPDX-License-Identifier: AGPL-3.0-or-later
// 开关：36×20 轨道 + 16 圆点。开=蓝轨白点，关=灰轨浅灰点。
// 轨道不能太暗：旧的「开」用 accentSoft(#132340)、「关」用 bgInput(#0f131a)，
// 两者和面板底色几乎同色，屏幕上只剩一个悬空圆点，看不出这是一枚开关。
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 36
    implicitHeight: 20

    Rectangle {
        id: track
        anchors.fill: parent
        radius: 10
        color: root.checked ? Theme.accent : Theme.line2
        border.width: root.checked ? 0 : 1
        border.color: Theme.line3
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }
    Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        y: 2
        x: root.checked ? 18 : 2
        color: root.checked ? Theme.accentFg : Theme.fg2
        Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked
            root.toggled(root.checked)
        }
    }
}
