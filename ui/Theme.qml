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

    // ── 动效 ────────────────────────────────────────────────
    // 唯一真源。禁止在别处写裸 duration 数字（构建期契约检查会拦）。
    // 语义分工：
    //   durFast  120  状态反馈：hover / 颜色 / 图标显隐 / 按压缩放
    //   durBase  180  局部动作：下拉展开、提示条出现、进度条生长
    //   durSlow  260  面板与列表：面板进出、列表逐条入场
    //   durPage  320  整页切换：启动页 ↔ 版本页 / 账户页
    readonly property int durFast: 120
    readonly property int durBase: 180
    readonly property int durSlow: 260
    readonly property int durPage: 320

    // ── 动效系统（2026-11-05）：时长/缓动只从这里取，页面里不再写裸数字 ──
    readonly property int durLoop: 1200          // 循环类动效一个来回
    readonly property int easeLoop: Easing.Linear // 循环用线性，避免首尾顿挫

    // 缓动：进入用 OutQuint（快起慢收，有重量感），离开用 InCubic（加速离场，利落）
    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeEnter: Easing.OutQuint
    readonly property int easeExit: Easing.InCubic

    // 列表逐条入场的步进（行数 × 步进 控制在 240ms 内）
    readonly property int staggerStep: 28

    // 循环型动效（不确定进度条、骨架屏）的周期，不属于过渡时长
    readonly property int marquee: 1150
}