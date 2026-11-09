// SPDX-License-Identifier: AGPL-3.0-or-later
// 滑块：轨道 6 高 + 16 圆点。值按 step 对齐，拖动/点击都能改
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property int from: 0
    property int to: 100
    property int step: 1
    property int value: 0
    property bool enabled: true
    signal moved(int value)

    implicitHeight: 34

    readonly property real ratio: (root.to > root.from)
        ? Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from))) : 0

    function valueAt(x) {
        var r = Math.max(0, Math.min(1, x / Math.max(1, track.width)))
        var raw = root.from + r * (root.to - root.from)
        var snapped = Math.round(raw / root.step) * root.step
        return Math.max(root.from, Math.min(root.to, snapped))
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: "#151a22"

        Rectangle {
            width: parent.width * root.ratio
            height: parent.height
            radius: 3
            color: root.enabled ? Theme.accent : "#2a3444"
        }
    }
    Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        y: (parent.height - 16) / 2
        x: Math.max(0, Math.min(track.width - 16, track.width * root.ratio - 8))
        color: root.enabled ? "#ffffff" : "#4b5462"
        border.width: 2
        border.color: root.enabled ? Theme.accent : "#2a3444"
        Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onPressed: (m) => root.setFromX(m.x)
        onPositionChanged: (m) => { if (pressed) root.setFromX(m.x) }
        function setFromX(x) {
            var v = root.valueAt(x)
            if (v === root.value) return
            root.value = v
            root.moved(v)
        }
    }
}
