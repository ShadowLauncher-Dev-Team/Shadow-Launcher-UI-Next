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
    signal edited(string text)

    implicitHeight: areaHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Theme.bgCard2
        border.width: 1
        border.color: edit.activeFocus ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }

    Text {
        anchors.fill: parent
        anchors.margins: 11
        // 输入法组字期间 text 仍是空的，只看 text 会让占位压在候选文字上
        visible: root.text.length === 0 && !edit.inputMethodComposing
        text: root.placeholder
        color: Theme.line3
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
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
