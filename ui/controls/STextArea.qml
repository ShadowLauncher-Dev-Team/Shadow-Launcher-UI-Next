// SPDX-License-Identifier: AGPL-3.0-or-later
// 多行文本：等宽字、可滚动、带占位文字（占位是空态，不是说明）
import QtQuick
import QtQuick.Controls.Basic
import ShadowLauncher.Next

Item {
    id: root
    property string text: ""
    property string placeholder: ""
    property int areaHeight: 92
    // 与 SInput/SField 对齐：暴露内部文本框，供页面聚焦、以及构建后键盘验收注入焦点用。
    property alias input: edit
    signal edited(string text)

    implicitHeight: areaHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Theme.bgCard2
        // 聚焦视觉：把已有蓝边加粗到 Theme.focusRingWidth（输入类不另叠焦点环，见 SInput 说明）。
        border.width: edit.activeFocus ? Theme.focusRingWidth : 1
        border.color: edit.activeFocus ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }

    SPlaceholder {
        anchors.fill: parent
        anchors.margins: 11
        target: edit
        label: root.placeholder
        color: Theme.line3
        wrapMode: Text.WordWrap
        font.pixelSize: 11
    }

    // 不用 ScrollView：它**无条件消费滚轮**——内容根本没溢出时也会把滚轮吃掉，
    // 鼠标划过输入框时外层页面就滚不动（影报的"滚到最下面再上滚会卡死在原地"就是这个：
    // 到底后光标正好停在 JVM/游戏参数框上）。
    // 现在用 Flickable 并显式只在内容真的溢出时才 interactive，未溢出时滚轮直接穿透给页面。
    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: edit.implicitHeight + 22
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
            id: edit
            x: 11
            y: 11
            width: flick.width - 22
            // 必须给 height：不给的话它只有内容高度（一两行约 14px），
            // 输入框看着有 areaHeight 那么高，实际只有文字那一行能点中、能拿焦点，
            // 点框的下半部分完全没反应（影报的"点快了还是不行"就是这个）。
            height: Math.max(flick.height - 22, implicitHeight)
            text: root.text
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentFg
            wrapMode: TextEdit.WrapAnywhere
            selectByMouse: true
            // Tab 必须是"离开本控件"：QtQuick 的 TextEdit 没有 tabChangesFocus（实测 6.8 属性不存在），
            // 默认会把 Tab 当制表符插进正文。所以在 Keys 过滤器里消费 Tab，再走 Qt 自己的焦点头链
            // （nextItemInFocusChain 与窗口 Tab 遍历用的是同一个内部函数，跨 FocusScope 也正确）。
            Keys.onTabPressed: function(event) {
                event.accepted = true
                var next = edit.nextItemInFocusChain(true)
                if (next && next !== edit) next.forceActiveFocus()
            }
            Keys.onBacktabPressed: function(event) {
                event.accepted = true
                var prev = edit.nextItemInFocusChain(false)
                if (prev && prev !== edit) prev.forceActiveFocus()
            }
            // 真实的"不可用"判据是 enabled（本控件没有 dimmed）。
            activeFocusOnTab: root.enabled
            // Esc 分层：有内容 -> 清空并消费；已为空 -> 不消费，冒泡给 StageShell.escapeTopmost()。
            Keys.onEscapePressed: function(event) {
                if (edit.text.length > 0) {
                    edit.text = ""
                    event.accepted = true
                } else {
                    event.accepted = false
                }
            }
            font.family: "Consolas"
            font.pixelSize: 11
            onTextChanged: {
                if (root.text !== text) {
                    root.text = text
                    root.edited(text)
                }
            }
        }
    }
}