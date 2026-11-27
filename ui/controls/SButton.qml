// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root

    // kind: 0 = primary(实心) 1 = ghost(描边)
    property int kind: 0
    property string text: ""
    property string iconName: ""
    property bool busy: false
    property bool dimmed: false
    property bool hovered: false
    // 圆角可覆盖：启动浮层面板是 radius 2 的直角语言，内部禁止嵌套大圆角
    property int radius: kind === 0 ? Theme.rMd : Theme.rSm
    // ghost 的危险变体（描边红/文字红）：只给"重试/结束进程"这类真实危险动作用
    property bool danger: false
    // 灰态但**仍可点**：用于"未登录，点了去登录"这类引导（dimmed 是不可点，别混用）
    property bool muted: false
    // ── 色调 ──
    // "auto"：跟随当前配色方案（默认，普通页面用）
    // "dark"：固定在深色底上（启动页 / 账户页是照片页，背景永远是暗图，
    //         浅色方案下若用 auto 会出现"白底白字"——实测整块按钮消失）
    property string tone: "auto"
    readonly property bool onDark: tone === "dark"
    readonly property color _softBorder: onDark ? "#333a47" : Theme.line2
    readonly property color _softFg: onDark ? "#e8ebf2" : Theme.fg
    readonly property color _softFg2: onDark ? "#98a1ae" : Theme.fg2
    readonly property color _softFill: onDark ? "#1b2129" : Theme.bgHover
    readonly property color _softFg3: onDark ? "#8d96a4" : Theme.fg3
    signal clicked()

    implicitHeight: kind === 0 ? 48 : 34
    implicitWidth: inner.implicitWidth + (kind === 0 ? 68 : 28)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: {
            if (root.kind === 0) {
                // 忙碌态是红底白字：白字压 danger(#ef4444) 只有 3.76:1，压 dangerBot(#dc2626) 是 4.83:1。
                // danger 本身按"墨色"用（图标/描边），深一档的 dangerBot 才是可承载白字的填充。
                if (root.busy) return Theme.dangerBot
                // 灰态按钮不能用"浅底 + 白字"：白色方案下就是白底白字（实测按钮整块消失）。
                // 灰态统一走"弱底 + 次要文字色"，两套方案都可读。
                if (root.dimmed || root.muted) return root._softFill
                return Theme.accentBot
            }
            return "transparent"
        }
        border.width: (root.kind === 0 && (root.muted || root.dimmed)) ? 1 : (root.kind === 0 ? 0 : 1)
        border.color: root.kind === 0 ? root._softBorder
                                     : (root.danger ? (root.onDark ? "#6d2a2a" : Theme.dangerSoft)
                                                    : root._softBorder)
        antialiasing: true

        // 主按钮渐亮（覆盖在纯色之上）
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.kind === 0 && !root.busy && !root.dimmed && !root.muted
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.accentTop }
                GradientStop { position: 1.0; color: Theme.accentBot }
            }
        }

        scale: press.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
    }

    RowLayout {
        id: inner
        anchors.centerIn: parent
        spacing: 9
        SIcon {
            visible: root.iconName !== ""
            name: root.iconName
            size: root.kind === 0 ? 18 : 14
            color: root.kind === 0
                   ? ((root.muted || root.dimmed) ? root._softFg3 : Theme.accentFg)
                   : (root.danger ? (root.onDark ? "#ff9a94" : Theme.dangerText) : root._softFg2)
        }
        Text {
            // 文字宽度上限 = 按钮宽度 - 左右内边距 - 图标与间距。
            // 不给上限时，调用方一旦把 width 设得比文案窄，文字会直接从按钮里伸出去
            // （协议门禁 132px 的「Accept and continue」压在隔壁按钮上就是这么来的）。
            // 上限而不是固定宽度：正常情况下它仍按内容撑开，只有真的放不下才省略。
            Layout.maximumWidth: Math.max(0, root.width - 12
                - ((root.iconName !== "") ? (root.kind === 0 ? 18 : 14) + 9 : 0))
            elide: Text.ElideRight
            text: root.text
            color: root.kind === 0
                   ? ((root.muted || root.dimmed) ? root._softFg3 : Theme.accentFg)
                   : (root.danger ? (root.onDark ? "#ff9a94" : Theme.dangerText) : root._softFg)
            font.family: Theme.fontFamily
            font.pixelSize: root.kind === 0 ? 15 : 13
            font.weight: root.kind === 0 ? Font.DemiBold : Font.Normal
            font.letterSpacing: root.kind === 0 ? 0.4 : 0
        }
    }

    // ghost 悬停底色：用透明度过渡，不再硬切（独立于 MouseArea，避免 z 序问题）
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.kind === 1 && !root.dimmed
        opacity: root.hovered ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
        }
        color: root.danger ? "#1aef4444" : "#16ffffff"
        border.width: 1
        border.color: root.danger ? Theme.danger : root._softBorder
    }

    // 主按钮 hover 提亮（#0dffffff = 5% 白覆盖）：只解释"鼠标在这里"，不改变主色。
    // 注意这层覆盖也会压在白字下面：Theme.accentTop 已按"叠加后仍 ≥4.5:1"取值（4.73:1）。
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.kind === 0 && !root.busy && !root.dimmed && !root.muted
        color: "#0dffffff"
        opacity: root.hovered ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
        }
    }

    MouseArea {
        id: press
        anchors.fill: parent
        // 必须同时看 root.enabled：以前只判断 dimmed，
        // 调用方写 enabled: false 时按钮看着灰、实际照样能点（点了触发空操作，用户以为坏了）。
        enabled: root.enabled && !root.dimmed
        cursorShape: (root.enabled && !root.dimmed) ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: true
        onContainsMouseChanged: root.hovered = containsMouse
        onClicked: root.clicked()
    }
}