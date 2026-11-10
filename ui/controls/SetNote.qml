// SPDX-License-Identifier: AGPL-3.0-or-later
// 提示条：三段语义色。用于「需要重启」「命令有风险」「两层结构」这类说明。
//
// 布局用纯 anchors，不用 Row：
// Row/Column 是 Positioner，它的子项里写 anchors 属于未定义行为（本项目早有过注释警告）。
// 原来 Icon 在 Row 内 anchors.top，把 Row 的高度算成了图标高度，
// 于是文字比"行"高、整块又按错误的行高居中 —— 视觉上文字贴顶（影两次报「文字偏上」）。
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property string kind: "info"     // info | warn | danger
    property string text: ""
    property string icon: ""

    readonly property color tone: root.kind === "warn" ? "#e6c07a"
                                : (root.kind === "danger" ? "#f0a3a3" : "#9db8d8")
    readonly property color bgColor: root.kind === "warn" ? "#171106"
                                    : (root.kind === "danger" ? "#180d10" : "#0b1220")
    readonly property color lineColor: root.kind === "warn" ? "#3d2f12"
                                      : (root.kind === "danger" ? "#4a2226" : "#1a2b45")

    readonly property int padH: 14
    readonly property int padV: 11
    readonly property int iconSize: 15
    readonly property int iconGap: 9
    readonly property bool hasIcon: root.icon.length > 0

    implicitHeight: txt.implicitHeight + padV * 2

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: root.bgColor
        border.width: 1
        border.color: root.lineColor
    }

    SIcon {
        id: ico
        name: root.icon
        size: root.iconSize
        color: root.tone
        visible: root.hasIcon
        anchors.left: parent.left
        anchors.leftMargin: root.padH
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        id: txt
        anchors.left: parent.left
        anchors.leftMargin: root.padH + (root.hasIcon ? root.iconSize + root.iconGap : 0)
        anchors.right: parent.right
        anchors.rightMargin: root.padH
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.tone
        font.family: Theme.fontFamily
        font.pixelSize: 12
        // 用 FixedHeight 而不是比例行高：
        // ProportionalHeight(1.6) 会把多出来的行高堆在文字下方，单行时文字整体偏上
        // （实测框高 61、文字墨迹 438..459，上留白 17 下留白 22）。
        // FixedHeight 让文字在每行内部垂直居中，上下留白对称。
        lineHeightMode: Text.FixedHeight
        lineHeight: 19
        wrapMode: Text.WordWrap
    }
}
