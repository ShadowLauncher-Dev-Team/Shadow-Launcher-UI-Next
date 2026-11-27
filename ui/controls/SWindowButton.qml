// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string iconName: "x"
    property bool danger: false          // 关闭按钮：hover 变红
    property Window hostWindow: null
    signal clicked()

    width: 32
    height: 32

    // ── 键盘（统一契约四件套）──
    // 本控件没有 dimmed/busy 这类内部灰态：唯一的"不可用"通道是 Qt 的 Item.enabled
    // （为 false 时父子一起收不到鼠标事件，鼠标入口失活 ⇒ Tab 也跳过）。
    activeFocusOnTab: root.enabled

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: {
            if (!root.danger) return hover.containsMouse ? "#1affffff" : "transparent"
            return hover.containsMouse ? Theme.danger : "transparent"
        }
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }

    SIcon {
        anchors.centerIn: parent
        name: root.iconName
        size: 15
        color: root.danger && hover.containsMouse ? Theme.accentFg : Theme.fg2
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // 鼠标按下也拿焦点：键盘与鼠标共用同一套焦点状态
        onPressed: root.forceActiveFocus()
        onClicked: root.clicked()
    }

    // 键盘激活：与鼠标**同一个入口**（root.clicked()）
    Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            e.accepted = true
            if (e.isAutoRepeat || !root.enabled) return
            root.clicked()
        }
    }

    // 焦点环：圆角跟随自身背景层（Theme.rSm），只锚定 + 负 margin，不占布局
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingGap
        radius: Theme.rSm + Theme.focusRingGap
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus
        z: 999
        antialiasing: true
    }
}