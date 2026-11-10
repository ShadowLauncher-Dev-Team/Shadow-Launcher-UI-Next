// SPDX-License-Identifier: AGPL-3.0-or-later
// 提示条：三段语义色。用于「需要重启」「命令有风险」「两层结构」这类说明。
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

    // 上下等量留白 + 行内居中。
    // 原来 Row 用固定 y:12、Text 的 lineHeight 1.6 会撑出额外行高（多出的空隙在文字下方），
    // 于是视觉上文字贴顶、框内下方空一块（影报的「文字偏上」）。
    implicitHeight: body.implicitHeight + 22

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: root.bgColor
        border.width: 1
        border.color: root.lineColor
    }

    Row {
        id: body
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 28
        spacing: 9

        SIcon {
            name: root.icon
            size: 15
            color: root.tone
            visible: root.icon.length > 0
            anchors.top: parent.top
            anchors.topMargin: 2
        }
        Text {
            width: parent.width - (root.icon.length > 0 ? 24 : 0)
            text: root.text
            color: root.tone
            font.family: Theme.fontFamily
            font.pixelSize: 12
            lineHeight: 1.6
            wrapMode: Text.WordWrap
        }
    }
}
