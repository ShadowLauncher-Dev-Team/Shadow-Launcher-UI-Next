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

    // 选中滑块：整块在分项之间滑动（与主菜单 SideBar 的胶囊同一套语言）。
    // 原来每项各自画选中底色 —— 切换是"旧的灭、新的亮"两个互不相关的动作，读不出方向。
    // 分项等宽，所以位置可以直接算；width 也加过渡，避免 items 数量变化时硬跳。
    Rectangle {
        id: segPill
        readonly property real segW: Math.max(60,
            (row.width - (root.items.length - 1) * row.spacing) / Math.max(1, root.items.length))
        x: 2 + root.currentIndex * (segW + row.spacing)
        y: 2
        width: segW
        height: row.height
        radius: 6
        color: "#132340"
        Behavior on x {
            NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
        }
        Behavior on width {
            NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
        }
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
                // 选中底色由上面的 segPill 承担；这里不再自己变色，否则滑块滑动时旧项还在亮
                color: "transparent"
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: index === root.currentIndex ? "#a9c8ff" : Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                    }
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
