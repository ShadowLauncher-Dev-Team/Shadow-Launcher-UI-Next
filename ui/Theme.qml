// SPDX-License-Identifier: AGPL-3.0-or-later
pragma Singleton
import QtQuick

QtObject {
    // 颜色
    readonly property color bg:        "#08090d"
    readonly property color sidebar:   "#0a0b0f"
    readonly property color line:      "#14171d"
    readonly property color line2:     "#262b35"
    readonly property color fg:        "#e8ebf2"
    readonly property color fg2:       "#98a1ae"
    readonly property color fg3:       "#5d6673"
    readonly property color accent:    "#3b82f6"
    readonly property color accentTop: "#4b8cf7"
    readonly property color accentBot: "#2563eb"
    readonly property color ok:        "#4ade80"
    readonly property color warn:      "#f59e0b"
    readonly property color danger:    "#ef4444"
    readonly property color dangerBot: "#dc2626"
    readonly property color scrim:     "#05080e"

    // 尺寸
    readonly property int sideW:       208
    readonly property int sideWNarrow: 64
    readonly property int rSm:         8
    readonly property int rMd:         10
    readonly property int rWin:        12
    readonly property int topH:        52
    readonly property int padL:        64
    readonly property int padR:        104
    readonly property int padB:        58

    // 字体
    readonly property string fontFamily: "Microsoft YaHei UI"
}