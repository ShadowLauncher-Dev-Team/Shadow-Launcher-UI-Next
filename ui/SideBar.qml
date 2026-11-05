// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root
    property bool narrow: false
    property string currentLabel: "启动"
    property Window hostWindow: null
    /// 主菜单点击（StageShell 据此切换内容区页面）
    signal navActivated(string label)

    implicitWidth: narrow ? Theme.sideWNarrow : Theme.sideW
    clip: true

    readonly property var mainItems: [
        { ic: "play",        label: "启动",     group: "main" },
        { ic: "download",    label: "下载",     group: "main" },
        { ic: "globe",       label: "联机",     group: "main" },
        { ic: "bar-chart-3", label: "统计",     group: "main" },
        { ic: "settings",    label: "设置",     group: "main" }
    ]
    readonly property var subItems: [
        { ic: "list",     label: "下载进度", group: "sub" },
        { ic: "book-open", label: "帮助文档", group: "sub" },
        { ic: "compass",  label: "实用网站", group: "sub" }
    ]

    Rectangle {
        anchors.fill: parent
        color: Theme.sidebar
        Rectangle {
            width: 1
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: Theme.line
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            property point pressPos
            onPressed: (m) => { pressPos = Qt.point(m.x, m.y) }
            onPositionChanged: (m) => {
                if (!pressed || !root.hostWindow) return
                root.hostWindow.x += m.x - pressPos.x
                root.hostWindow.y += m.y - pressPos.y
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: root.narrow ? 8 : 12
        anchors.rightMargin: root.narrow ? 8 : 12
        anchors.topMargin: 16
        anchors.bottomMargin: 12
        spacing: 1

        Text {
            visible: !root.narrow
            text: "SHADOW"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Bold
            font.letterSpacing: 2.2
            leftPadding: 10
            Layout.bottomMargin: 18
        }
        Item { visible: root.narrow; Layout.preferredHeight: 6 }

        Repeater { model: root.mainItems; delegate: navRow }

        Item { Layout.preferredHeight: 12 }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.line
            visible: !root.narrow
        }
        Item { Layout.preferredHeight: 12 }

        Repeater { model: root.subItems; delegate: navRow }

        Item { Layout.fillHeight: true }

        Text {
            visible: !root.narrow
            // appVersion 已是可直接显示的完整串（含 v 前缀，见 src/version.h），此处禁止再做任何拼接装饰
            text: ((typeof backend !== "undefined" && backend) ? backend.appVersion : "")
            color: "#4b535f"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            leftPadding: 10
        }
    }

    Component {
        id: navRow
        Item {
            id: row
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            readonly property bool isMain: modelData.group === "main"
            readonly property bool sel: row.isMain && root.currentLabel === modelData.label

            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm
                color: row.sel ? "#151a23" : (rowHover.containsMouse ? "#12151c" : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
            }
            // 选中指示条：高度从 0 长出来，退选时缩回去（不是硬切）
            Rectangle {
                width: 2
                height: row.sel ? parent.height - 20 : 0
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: root.narrow ? -8 : -12
                color: Theme.accent
                Behavior on height {
                    NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter }
                }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.narrow ? 0 : 10
                spacing: 10
                SIcon {
                    name: modelData.ic
                    size: 17
                    color: row.sel ? "#ffffff" : Theme.fg2
                    Layout.alignment: root.narrow ? Qt.AlignHCenter : Qt.AlignLeft
                }
                Text {
                    visible: !root.narrow
                    text: modelData.label
                    color: row.sel ? "#ffffff" : Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: row.sel ? Font.DemiBold : Font.Normal
                }
                Item { Layout.fillWidth: true }
            }
            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    // 主项才改高亮；子项也要发信号，否则「下载进度」这类子项完全点不动
                    if (row.isMain) root.currentLabel = modelData.label
                    root.navActivated(modelData.label)
                }
            }
        }
    }
}