// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root
    property bool narrow: false
    /// 下载页模式：只留图标条（56px），文字/副项/版本号全部收起
    property bool compact: false
    property string currentLabel: "启动"
    property Window hostWindow: null
    /// 主菜单点击（StageShell 据此切到下载页）
    signal navActivated(string label)

    implicitWidth: compact ? 56 : (narrow ? Theme.sideWNarrow : Theme.sideW)
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

    // 折叠态：独立布局（用 RowLayout/ColumnLayout 时会混入副项与分隔块，行高不齐）
    Column {
        visible: root.compact
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        Image {
            source: "qrc:/ui/shadowlauncher.png"
            sourceSize.width: 26
            sourceSize.height: 26
            width: 26
            height: 26
            anchors.horizontalCenter: parent.horizontalCenter
            smooth: true
        }
        Item { width: 1; height: 4 }

        Repeater {
            model: root.mainItems
            delegate: Item {
                id: cRow
                width: 44
                height: 42
                readonly property bool sel: root.currentLabel === modelData.label

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rSm
                    color: cRow.sel ? "#151a23" : (cHover.containsMouse ? "#12151c" : "transparent")
                }
                SIcon {
                    anchors.centerIn: parent
                    name: modelData.ic
                    size: 18
                    color: cRow.sel ? "#ffffff" : Theme.fg2
                }
                MouseArea {
                    id: cHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.currentLabel = modelData.label
                        root.navActivated(modelData.label)
                    }
                }
            }
        }
    }

    ColumnLayout {
        visible: !root.compact
        anchors.fill: parent
        anchors.leftMargin: root.compact ? 6 : (root.narrow ? 8 : 12)
        anchors.rightMargin: root.compact ? 6 : (root.narrow ? 8 : 12)
        anchors.topMargin: root.compact ? 10 : 16
        anchors.bottomMargin: 12
        spacing: root.compact ? 2 : 1

        // 折叠态：显示软件图标（SHADOW 文字在 56px 里放不下）
        Image {
            visible: root.compact
            source: "qrc:/ui/shadowlauncher.png"
            sourceSize.width: 26
            sourceSize.height: 26
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            Layout.alignment: Qt.AlignHCenter
            smooth: true
        }
        Text {
            visible: !root.narrow && !root.compact
            text: "SHADOW"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Bold
            font.letterSpacing: 2.2
            leftPadding: 10
            Layout.bottomMargin: 18
        }
        Item { visible: root.narrow && !root.compact; Layout.preferredHeight: 6 }

        Repeater { model: root.mainItems; delegate: navRow }

        Item { visible: !root.compact; Layout.preferredHeight: 12 }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.line
            visible: !root.narrow && !root.compact
        }
        Item { visible: !root.compact; Layout.preferredHeight: 12 }

        // 折叠态不显示副项：Repeater 的 visible 不隐藏已生成的 delegate，必须换空模型
        Repeater { model: root.compact ? [] : root.subItems; delegate: navRow }

        Item { Layout.fillHeight: true }

        Text {
            visible: !root.narrow && !root.compact
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
            Layout.preferredHeight: root.compact ? 36 : 38
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
                visible: !root.compact
                width: 2
                height: row.sel ? parent.height - 20 : 0
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: root.compact ? -6 : (root.narrow ? -8 : -12)
                color: Theme.accent
                Behavior on height {
                    NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter }
                }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: (root.narrow || root.compact) ? 0 : 10
                spacing: 10
                SIcon {
                    name: modelData.ic
                    size: 17
                    color: row.sel ? "#ffffff" : Theme.fg2
                    Layout.fillWidth: root.compact
                    Layout.alignment: (root.narrow || root.compact) ? Qt.AlignHCenter : Qt.AlignLeft
                }
                Text {
                    visible: !root.narrow && !root.compact
                    text: modelData.label
                    color: row.sel ? "#ffffff" : Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: row.sel ? Font.DemiBold : Font.Normal
                }
                Item { visible: !root.compact; Layout.fillWidth: true }
            }
            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.isMain) {
                        root.currentLabel = modelData.label
                        root.navActivated(modelData.label)
                        console.info("[ui] nav ->", modelData.label)
                    }
                }
            }
        }
    }
}