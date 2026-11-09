// SPDX-License-Identifier: AGPL-3.0-or-later
// 分段控件：等价宽按钮，选中态蓝底
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property var items: []
    property int currentIndex: 0
    property int itemHeight: 26
    signal activated(int index)

    implicitHeight: itemHeight + 4
    implicitWidth: row.implicitWidth + 4

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: "#0a0c11"
        border.width: 1
        border.color: Theme.line2
    }
    Row {
        id: row
        anchors.fill: parent
        anchors.margins: 2
        spacing: 2
        Repeater {
            model: root.items
            delegate: Rectangle {
                width: Math.max(60, (row.width - (root.items.length - 1) * 2) / Math.max(1, root.items.length))
                height: row.height
                radius: 6
                color: index === root.currentIndex ? "#132340" : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: index === root.currentIndex ? "#a9c8ff" : Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.currentIndex === index) return
                        root.currentIndex = index
                        root.activated(index)
                    }
                }
            }
        }
    }
}
