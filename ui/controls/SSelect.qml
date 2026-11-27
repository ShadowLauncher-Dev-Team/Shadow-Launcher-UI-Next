// SPDX-License-Identifier: AGPL-3.0-or-later
// 下拉选择：34 高胶囊 + 弹出列表（弹出层用项目自己的底/线，不引系统样式）
import QtQuick
import QtQuick.Controls.Basic
import ShadowLauncher.Next

Item {
    id: root
    property var items: []
    property int currentIndex: 0
    property string fallback: ""
    signal activated(int index)

    implicitHeight: 34
    implicitWidth: 220

    // ── 键盘（统一契约四件套）──
    // 本控件是 Item + QtQuick.Controls 的 Popup 手绘，**不是 ComboBox**：
    // ComboBox 那套键盘行为（方向键/Enter/Esc 收起）一点都不存在，全部自己实现。
    // "不可用"判据是 Item 自带的 enabled（本控件没有 dimmed/busy 这类内部灰态）。
    activeFocusOnTab: root.enabled

    // 弹层内的"高亮游标"：与已提交的 currentIndex 分开。
    // ↑/↓ 只移动高亮，Enter 才提交 —— 否则按 Esc 走开时值已经被改掉了。
    property int _cursor: 0
    readonly property int highlightIndex: pop.opened ? root._cursor : root.currentIndex

    // 鼠标点触发器与键盘 Space/Enter 的**同一个入口**
    function openList() {
        root._cursor = Math.max(0, Math.min(Math.max(0, root.items.length - 1), root.currentIndex))
        pop.open()
    }
    // 弹层里 ↑/↓ 的移动入口（只动高亮，不动值）
    function moveCursor(delta) {
        if (root.items.length === 0) return
        var i = Math.max(0, Math.min(root.items.length - 1, root._cursor + delta))
        if (i === root._cursor) return
        root._cursor = i
        if (list) list.positionViewAtIndex(i, ListView.Contain)
    }
    // 提交：鼠标点某一项 与 键盘 Enter 都走这里（改值 + 发 activated + 收起）
    function selectIndex(i) {
        root.currentIndex = i
        root.activated(i)
        pop.close()
    }

    // 键盘打开：与鼠标点触发器同一个入口（root.openList()）
    Keys.onPressed: function(e) {
        if (pop.opened) return      // 打开后按键都在弹层里处理
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            e.accepted = true
            if (e.isAutoRepeat || !root.enabled) return
            root.openList()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Theme.bgCard2
        border.width: 1
        border.color: pop.opened ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.right: chev.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: (root.currentIndex >= 0 && root.currentIndex < root.items.length)
                  ? root.items[root.currentIndex] : root.fallback
            color: (root.currentIndex >= 0) ? Theme.fg : Theme.fg3
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
        SIcon {
            id: chev
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            size: 13
            color: Theme.line3
        }
        MouseArea {
            id: triggerArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            property bool wasOpen: false
            onPressed: {
                // 点一下也拿焦点：键盘与鼠标共用同一套焦点状态
                root.forceActiveFocus()
                wasOpen = pop.visible
            }
            onClicked: {
                if (wasOpen) pop.close()
                else root.openList()
            }
        }
    }

    Popup {
        id: pop
        y: root.height + 4
        width: root.width
        padding: 4
        // 保留 outside-press（点空白处收起）；触发器用 onPressed 记下点击前的状态来 toggle，
        // 否则 press 阶段已关、click 又 open，表现就是"点第二次还是展开"
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        // 打开后把焦点交给列表：Popup 的 CloseOnEscape 只在 Escape 事件进到 popup item 时才生效，
        // 弹层里若没人拿焦点，Esc 会被窗口里的焦点项（触发器/别的控件）吃掉 —— 看起来就是"Esc 没反应"。
        // 这同时也是"下拉开着时 Tab 不带走焦点"的前提：焦点本来就该在弹层内部。
        onOpened: {
            list.forceActiveFocus()
            if (list && list.count > 0 && root._cursor >= 0) list.positionViewAtIndex(root._cursor, ListView.Contain)
        }
        // 关闭后焦点还给触发器，否则焦点停在已经消失的弹层里，Tab 从此断链
        onClosed: root.forceActiveFocus()
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durFast; easing.type: Theme.easeEnter }
            NumberAnimation { property: "y"; from: root.height + 1; to: root.height + 4; duration: Theme.durFast; easing.type: Theme.easeEnter }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durFast; easing.type: Theme.easeExit }
        }
        background: Rectangle {
            radius: Theme.rSm
            color: Theme.bgCard2
            border.width: 1
            border.color: Theme.line2
        }
        contentItem: ListView {
            id: list
            implicitHeight: Math.min(240, contentHeight)
            model: root.items
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // 弹层内的键盘：↑/↓ 动高亮、Enter/Space 提交、Esc 收起、Tab 就地吞掉。
            // Keys.priority 默认 BeforeItem：这里 accept 之后，ListView 自带的上下键翻选不会再执行一遍。
            Keys.onPressed: function(e) {
                if (e.key === Qt.Key_Down) {
                    e.accepted = true
                    root.moveCursor(1)
                } else if (e.key === Qt.Key_Up) {
                    e.accepted = true
                    root.moveCursor(-1)
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                    e.accepted = true
                    // 按住不放会连发，一次按下只提交一次
                    if (e.isAutoRepeat) return
                    root.selectIndex(root._cursor)
                } else if (e.key === Qt.Key_Escape) {
                    // closePolicy 已含 CloseOnEscape，这里显式再收一次：
                    // popup 是在 keyRelease 才处理 Escape，中间若有控件吃掉 press 就会漏
                    e.accepted = true
                    pop.close()
                } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                    // 下拉开着时按 Tab 不许把焦点带走：否则弹层还在、键盘却失联
                    e.accepted = true
                }
            }

            delegate: Item {
                width: pop.width - 8
                height: 32
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Theme.bgCard2
                    opacity: (hov.hovered || index === root.highlightIndex) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: index === root.highlightIndex ? Theme.accentText : Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                HoverHandler { id: hov }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // 鼠标点某一项与键盘 Enter 走同一个入口（root.selectIndex）
                    onClicked: root.selectIndex(index)
                }
            }
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
        visible: root.activeFocus
        z: 999
        antialiasing: true
    }
}
