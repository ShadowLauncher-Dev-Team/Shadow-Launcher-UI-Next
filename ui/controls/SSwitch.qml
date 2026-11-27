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

    // 轨道胶囊圆角：焦点环沿用它 + focusRingGap，才能和轨道同心
    readonly property real radius: 10

    // ── 键盘（统一契约四件套）──
    // "不可用"判据是 Item 自带的 enabled：开关没有 dimmed/busy 这类内部灰态，
    // 也不会因为不可用自己变灰（轨道颜色只看 checked），所以只能以 enabled 为准。
    activeFocusOnTab: root.enabled

    // 鼠标与键盘共用的唯一入口
    function toggle() {
        root.checked = !root.checked
        root.toggled(root.checked)
    }

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
        // 点一下也拿焦点：键盘与鼠标共用同一套焦点状态
        onPressed: { Theme.keyboardNav = false; root.forceActiveFocus() }
        onClicked: root.toggle()
    }

    // 键盘激活：与鼠标**同一个入口**（root.toggle()），不另写逻辑
    Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            e.accepted = true
            // isAutoRepeat：按住不放等于鼠标连点，一次按下只切一次
            if (e.isAutoRepeat || !root.enabled) return
            root.toggle()
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
