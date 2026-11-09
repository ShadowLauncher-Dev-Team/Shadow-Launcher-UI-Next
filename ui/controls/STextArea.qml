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
        color: "#0d1016"
        border.width: 1
        border.color: edit.activeFocus ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }

    Text {
        anchors.fill: parent
        anchors.margins: 11
        visible: root.text.length === 0
        text: root.placeholder
        color: "#3f4753"
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        TextArea {
            id: edit
            padding: 11
            text: root.text
            color: "#cfd6e1"
            selectionColor: "#2c4a7a"
            selectedTextColor: "#ffffff"
            wrapMode: TextEdit.WrapAnywhere
            font.family: "Consolas"
            font.pixelSize: 11
            background: null
            onTextChanged: {
                if (root.text !== text) {
                    root.text = text
                    root.edited(text)
                }
            }
        }
    }
}
