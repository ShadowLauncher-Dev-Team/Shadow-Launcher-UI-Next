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

    // ── 键盘（统一契约四件套）──
    // 本控件是纯 Item 手绘，**不是 QtQuick.Controls 的 Slider**：方向键/Home/End 没有任何
    // 自带行为（没有 stepSize、没有 Keys 处理），必须自己实现，也就没有"重复实现"的问题。
    // "不可用"判据是本控件自己的 enabled（SetJavaPane 就在用 enabled: pane.s ? !auto : false）。
    activeFocusOnTab: root.enabled

    // 步长：优先用调用方给的 step，(to-from)/100 只在 step<=0 时兜底。
    // value 是 int，兜底值取整并至少为 1，否则小范围区间（如 0..50）会算出 0 步长、按方向键没反应。
    readonly property int keyStep: root.step > 0 ? root.step
        : Math.max(1, Math.floor((root.to - root.from) / 100))

    // 鼠标与键盘共用的唯一写值入口：夹紧范围 + 只在真的变了时才发 moved
    function setValue(v) {
        var nv = Math.max(root.from, Math.min(root.to, v))
        if (nv === root.value) return
        root.value = nv
        root.moved(nv)
    }

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
        color: Theme.bgCard

        Rectangle {
            width: parent.width * root.ratio
            height: parent.height
            radius: 3
            color: root.enabled ? Theme.accent : Theme.bgHover
        }
    }
    Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        y: (parent.height - 16) / 2
        x: Math.max(0, Math.min(track.width - 16, track.width * root.ratio - 8))
        color: root.enabled ? Theme.fg : Theme.line3
        border.width: 2
        border.color: root.enabled ? Theme.accent : Theme.bgHover
        Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        // setFromX 定义在本 MouseArea 内，不是 root 的方法。
        // 原来写成 root.setFromX(...) → 每次按下都抛 TypeError，滑块既不能点也不能拖。
        onPressed: (m) => {
            // 拖/点也拿焦点：键盘与鼠标共用同一套焦点状态
            Theme.keyboardNav = false
            root.forceActiveFocus()
            drag.setFromX(m.x)
        }
        onPositionChanged: (m) => { if (pressed) drag.setFromX(m.x) }
        // 鼠标走这里，键盘方向键走 root.setValue —— 同一个夹紧+发信号入口
        function setFromX(x) {
            root.setValue(root.valueAt(x))
        }
    }

    // ←/→ 按步长调节，Home/End 跳两端。故意**不接管 Space/Enter**：
    // 那是按钮语义，滑块上按空格要么无反应要么跳值，两种都不是用户预期。
    // 不接管 ↑/↓：垂直键留给外层滚动容器（设置页是 Flickable），翻页时按上下键仍然滚页面。
    // 不挡 isAutoRepeat：按住方向键连续调节是滑块的标准行为（按钮才需要挡连点）。
    Keys.onPressed: function(e) {
        if (!root.enabled) return
        if (e.key === Qt.Key_Left) {
            e.accepted = true
            root.setValue(root.value - root.keyStep)
        } else if (e.key === Qt.Key_Right) {
            e.accepted = true
            root.setValue(root.value + root.keyStep)
        } else if (e.key === Qt.Key_Home) {
            e.accepted = true
            root.setValue(root.from)
        } else if (e.key === Qt.Key_End) {
            e.accepted = true
            root.setValue(root.to)
        }
    }

    // 焦点环：独立一层描边，只锚定 + 负 margin，不占布局
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingGap
        radius: (root.radius !== undefined ? root.radius : 8) + Theme.focusRingGap
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && Theme.keyboardNav
        z: 999
        antialiasing: true
    }
}
