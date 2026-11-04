// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root
    property bool narrow: false
    property int current: 0
    property Window hostWindow: null

    implicitWidth: narrow ? Theme.sideWNarrow : Theme.sideW

    readonly property var mainItems: [
        { ic: "play",     label: "启动" },
        { ic: "download", label: "下载" },
        { ic: "globe",    label: "联机" },
        { ic: "bar-chart-3", label: "统计" },
        { ic: "settings", label: "设置" }
    ]
    readonly property var subItems: [
        { ic: "list",     label: "下载进度" },
        { ic: "book-open", label: "帮助文档" },
        { ic: "compass",  label: "实用网站" }
    ]

    Rectangle {
        anchors.fill: parent
        color: Theme.sidebar
        Rectangle {   // 右侧发丝线
            width: 1
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: Theme.line
        }
        // 拖拽窗口
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

        Repeater {
            model: root.mainItems
            delegate: navRow
        }

        Item { Layout.preferredHeight: 12 }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.line
            visible: !root.narrow
        }
        Item { Layout.preferredHeight: 12 }

        Repeater {
            model: root.subItems
            delegate: navRow
        }

        Item { Layout.fillHeight: true }

        Text {
            visible: !root.narrow
            text: "v" + (typeof backend !== "undefined" && backend ? backend.appVersion : "")
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
            readonly property bool sel: root.current === (index < root.mainItems.length ? index : -1)

            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm
                color: row.sel ? "#151a23" : (rowHover.containsMouse ? "#12151c" : "transparent")
                Behavior on color { ColorAnimation { duration: 110 } }
            }
            Rectangle {  // 选中左侧强调条
                visible: row.sel
                width: 2
                height: parent.height - 20
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: root.narrow ? -8 : -12
                color: Theme.accent
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
                    font.pixelSize: 13.5
                    font.weight: row.sel ? Font.DemiBold : Font.Normal
                }
                Item { Layout.fillWidth: true }
            }
            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (index < root.mainItems.length) root.current = index
            }
        }
    }
}