// SPDX-License-Identifier: AGPL-3.0-or-later
// 主题令牌（唯一真源）。
//
// 2026-11-13：外观页动工，这里升级成"可切换配色方案"的调色板。
//   • scheme = "dark"（默认，黑）/ "light"（白）
//   • 所有颜色都由 scheme 派生（binding），切换后全局立即生效
//   • 组件里只准用 Theme.* 令牌，不准再写 #XXXXXX 字面色（构建期契约检查可另行加）
//
// 命名约定：
//   bg*            背景层（页面 < 卡片 < 输入框 < 悬停，由深到浅）
//   line*          边框（line 最浅 → line3 最重）
//   fg*            文字（fg 主 → fg4 最弱，占位符）
//   accent*        品牌蓝，两套方案共用一组。注意 accent 与 accentTop/accentBot 职责不同：
//                  accentTop/accentBot 是填充色（上面压 accentFg 白字），accent 主要是墨色
//                  （ui/ 下 87 处引用，绝大多数是图标/描边/文字/焦点环）。白字可读性只对
//                  前两者成立，详见 §品牌色。
//   accentFg       填充色（accentTop/accentBot）上的文字，永远白，两方案通用
//   imageFg        图片上的文字（两方案都偏白，配合 imageScrim*）
//   imageScrim*    图片遮罩（两种方案都用固定暗遮罩，保证 imageFg 永远可读）
pragma Singleton
import QtQuick

QtObject {
    // ── 配色方案 ─────────────────────────────────────────────
    // 由 StageShell 从后端（QSettings appearance/scheme）同步过来；
    // 直接写这里也能临时切换（截图/调试）。
    property string scheme: "dark"
    readonly property bool dark: scheme !== "light"

    // ── 背景层 ───────────────────────────────────────────────
    readonly property color bg:       dark ? "#08090d" : "#eef1f6"
    readonly property color sidebar:  dark ? "#0a0b0f" : "#e6ebf3"
    readonly property color bgCard2:  dark ? "#0b0d12" : "#f7f9fc"
    readonly property color bgCard:   dark ? "#0d1016" : "#ffffff"
    readonly property color bgInput:  dark ? "#0f131a" : "#ffffff"
    readonly property color bgHover:  dark ? "#151a23" : "#e9eef6"
    readonly property color bgRaised: dark ? "#12151c" : "#ffffff"

    // ── 边框 ─────────────────────────────────────────────────
    readonly property color line:  dark ? "#14171d" : "#e3e8f0"
    readonly property color line2: dark ? "#262b35" : "#cfd7e3"
    readonly property color line3: dark ? "#333a47" : "#b7c1d1"

    // ── 文字 ─────────────────────────────────────────────────
    readonly property color fg:  dark ? "#e8ebf2" : "#101827"
    readonly property color fg2: dark ? "#98a1ae" : "#3d4859"
    // fg3/fg4 也必须 ≥4.5:1（占位符同样是"正文/小字"，WCAG 不给占位符豁免）。
    // 2026-11-27 D3：原值深色 3.42 / 2.03、浅色 4.31 / 2.70 全部不达标，见下表调整后的实测值。
    readonly property color fg3: dark ? "#868f9d" : "#58606f"
    readonly property color fg4: dark ? "#7c8592" : "#606979"

    // ── 品牌色 ───────────────────────────────────────────────
    // 2026-11-27（D3 对比度修复）。原注释写"两种方案都用同一组蓝，保证按钮文字始终白字可读"
    // 与事实相反：白字压 accentTop(#4b8cf7) 只有 3.28:1、压 accent(#3b82f6) 3.68:1，都没到 4.5。
    // 现在的分工（三者在两套方案下取值相同）：
    //   accentTop/accentBot  填充色。白字压在上面必须 ≥4.5:1，且 SButton 悬停会再叠 5% 白
    //                        （#0dffffff），叠加后仍要 ≥4.5 → 取 4.73 / 6.05；两者保持"上亮下暗"。
    //   accent               墨色为主（ui/ 下 87 处引用，多为图标/描边/文字）。压在 #0d1016 上
    //                        是 5.18:1；若为迁就白字压到 4.5 以下，这 87 处反而破 4.5（只剩 3.25）。
    //                        职责冲突，故 accent 保持亮蓝不动，凡是"白字压 accent"的用法要换成填充色令牌。
    readonly property color accent:    "#3b82f6"
    readonly property color accentTop: "#2563eb"
    readonly property color accentBot: "#1d4ed8"
    readonly property color accentFg:  "#ffffff"
    readonly property color accentSoft: dark ? "#132340" : "#dce8ff"
    readonly property color accentText: dark ? "#a9c8ff" : "#1d4ed8"

    // ── 状态色 ───────────────────────────────────────────────
    readonly property color ok:        dark ? "#4ade80" : "#15803d"
    readonly property color warn:      dark ? "#f59e0b" : "#b45309"
    readonly property color danger:    "#ef4444"
    readonly property color dangerBot: "#dc2626"
    // warn 是**墨色**（文字/描边/图标），不能直接当填充色 —— 整条铺 #f59e0b 就是一坨大黄块。
    // 需要「警示底色」时用 warnSoft（与 dangerSoft 同一套做法：深色方案给低明度底）。
    readonly property color warnSoft:   dark ? "#2e2410" : "#fdf3e0"
    readonly property color dangerSoft: dark ? "#3a1f23" : "#fde8e8"
    readonly property color dangerText: dark ? "#ff9a94" : "#b91c1c"

    // ── 图片上的文字与遮罩 ───────────────────────────────────
    // 启动页/账户页属于"照片页"：无论黑白方案，图片上都用偏白的 onImage 文字 +
    // 暗遮罩。原因：用户可换任意亮图，暗遮罩+白字是唯一在任意图上都成立的组合；
    // 若浅色方案改成亮遮罩，遇到白色系图片会直接看不见字（违反"文字不可见"红线）。
    readonly property color imageFg: "#f2f5fa"
    readonly property color imageScrim0: "#0005080e"
    readonly property color imageScrim1: "#2805080e"
    readonly property color imageScrim2: "#8c05080e"
    readonly property color imageScrim3: "#f005080e"
    readonly property color imageScrimSide0: "#b805080e"
    readonly property color imageScrimSide1: "#2e05080e"
    readonly property color imageScrim: "#05080e"
    // 通用遮罩（弹层背景 / 图片压暗条）。遮罩的语义是「压暗后面」，
    // 所以两套方案都用深色；浅色方案下用亮色遮罩反而会把内容洗白。
    readonly property color scrim: "#05080e"
    // 照片页（启动页 / 账户页）专用固定暗色：这两页背景是图片，任何配色方案下都保持
    // 暗色文字体系，避免"浅色方案里深色文字压在暗图上"（文字不可见红线）。
    readonly property color pBg: "#08090d"
    readonly property color pLine: "#1c212b"
    readonly property color imageFgDim: "#a9b4c6"
    readonly property color imageFgFaint: "#78828f"

    // ── 尺寸 ─────────────────────────────────────────────────
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

    // ── 背景壁纸：唯一真源 ─────────────────────────────────
    // 之前启动页/账户页/版本页各写一遍 URL 规则，结果账户页读的是 customBgPath，
    // 内置预设背景时 path 为空 → 掉回默认极光图，和启动页不是同一张（用户实测截图）。
    // 现在所有页面只能走 bgUrl(b)：想换背景只改这里。
    readonly property string bgFallbackUrl: "qrc:/ui/stage-aurora.jpg"
    function bgUrl(b) {
        return (b && b.customBgUrl && b.customBgUrl.length > 0) ? b.customBgUrl : bgFallbackUrl
    }

    // ── 动效 ────────────────────────────────────────────────
    // 唯一真源。禁止在别处写裸 duration 数字，统一从这里取。
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

    // ── 动效系统（2026-11-06 补全）──
    // 按压缩放用 durPress：比 durFast 更短，按下即到位，松开靠 pop 回弹
    readonly property int durPress: 90
    // 一次性高光扫过（最新版卡 sheen / 骨架屏）
    readonly property int durSheen: 900
    // 回弹缓动：过冲 ~8% 再收回，用于"按下-松开""选中弹一下"这类需要活泼感的瞬间。
    // 注意：不是弹簧物理动画（会发散到 ±Infinity，契约禁止），是固定过冲的贝塞尔。
    readonly property int easePop: Easing.OutBack
    // 逐条入场的行数上限：超过之后统一在第 N 行同时出现，避免长列表拖沓
    readonly property int staggerMax: 12

    // ── 键盘焦点环（2026-11-27 D5 键盘可用性）──
    // 焦点必须是**独立一层描边**，不能复用控件自身的 border：
    // ghost 按钮 / 滑块 / 开关本来就带描边，复用的话焦点态与常态分不出来。
    // 颜色在深色下取 accent 的亮一档（压 bg #08090d ≈8.5:1）、
    // 浅色下用 accentTop 本色（压浅底 ≈4.6:1），都远超 WCAG 非文本 3:1。
    readonly property int focusRingWidth: 2
    readonly property int focusRingGap: 2          // 环与控件之间的空隙
    readonly property color focusRing: dark ? "#7aa7ff" : "#2563eb"
}
