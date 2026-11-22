// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 输入框占位文字：空态显示，有内容或正在输入法组字时隐藏。
//
// 为什么必须感知组字态：TextInput / TextEdit 在输入法 preedit 期间 text 仍是空字符串
// （候选字由输入法内联绘制，尚未提交），只判断 text 长度会让占位文字压在候选字上。
// 全站输入框统一用本组件，别在页面里再手写 placeholder Text。
Text {
    id: root

    // 目标输入控件（TextInput 或 TextEdit）
    required property var target
    property string label: ""

    text: root.label
    visible: !!root.target && root.target.text.length === 0 && !root.target.inputMethodComposing
    color: Theme.line3
    font.family: Theme.fontFamily
    font.pixelSize: 12
}