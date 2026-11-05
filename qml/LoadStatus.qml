// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts

// LoadStatus — 统一加载/空状态指示器
// 用法：
//   LoadStatus {
//       loading: page.modSearching
//       emptyText: "输入关键词搜索 Mod"
//       count: modResultsModel.count
//   }

Rectangle {
    id: root

    implicitWidth: parent ? parent.width : 200
    implicitHeight: root.count > 0 ? 0 : 140
    height: root.count > 0 ? 0 : implicitHeight
    color: "transparent"
    visible: root.count === 0
    clip: true

    property bool loading: false
    property string emptyText: ""
    property int count: 0
    /// 失败态文案（非空时优先于 emptyText 显示，并配暖色感叹号）
    property string errorText: ""
    /// 行动按钮文案（空结果给"重置筛选"，失败给"重试"）
    property string actionText: ""
    signal actionClicked()

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 10
        visible: root.count === 0

        // ── 加载环形弧（仅 loading 时显示） ──
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 28; height: 28
            color: "transparent"
            visible: root.loading
            LoadingSpinner {
                anchors.centerIn: parent
                width: 24; height: 24
                running: true
            }
        }

        // ── 图标（失败态）──
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading && root.errorText.length > 0
            text: "!"
            color: "#e0a458"
            font.pixelSize: 20
            font.bold: true
        }

        // ── 文字 ──
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.loading ? "正在加载…" : (root.errorText.length > 0 ? root.errorText : root.emptyText)
            color: root.loading ? StyleTokens.accentHover
                 : (root.errorText.length > 0 ? "#e0a458" : StyleTokens.textMuted)
            font.pixelSize: StyleTokens.fontSizeSm
        }

        // ── 行动按钮（重置筛选 / 重试）──
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading && root.actionText.length > 0
            implicitWidth: actionLabel.implicitWidth + 28
            implicitHeight: 32
            radius: StyleTokens.radiusMd
            color: actionMouse.containsMouse ? StyleTokens.accentHover : StyleTokens.accentSubtle
            border.width: 1
            border.color: StyleTokens.accentHover
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                id: actionLabel
                anchors.centerIn: parent
                text: root.actionText
                color: StyleTokens.textPrimary
                font.pixelSize: StyleTokens.fontSizeSm
            }
            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.actionClicked()
            }
        }
    }
}
