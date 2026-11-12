// SPDX-License-Identifier: AGPL-3.0-or-later
// 开关：36×20 轨道 + 16 圆点。开=蓝轨浅蓝点，关=灰轨灰点
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
        color: root.checked ? Theme.accentSoft : Theme.bgInput
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }
    Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        y: 2
        x: root.checked ? 18 : 2
        color: root.checked ? Theme.accentText : Theme.fg3
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
