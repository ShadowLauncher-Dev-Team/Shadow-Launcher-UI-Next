// SPDX-License-Identifier: AGPL-3.0-or-later
// 下拉选择：34 高胶囊 + 弹出列表（弹出层用项目自己的底/线，不引系统样式）
import QtQuick
import QtQuick.Controls.Basic
import ShadowLauncher.Next

Item {
    id: root
    property var items: []
    property int currentIndex: 0
    property string fallback: ""
    signal activated(int index)

    implicitHeight: 34
    implicitWidth: 220

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Theme.bgCard2
        border.width: 1
        border.color: pop.opened ? Theme.accent : Theme.line2
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.right: chev.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: (root.currentIndex >= 0 && root.currentIndex < root.items.length)
                  ? root.items[root.currentIndex] : root.fallback
            color: (root.currentIndex >= 0) ? Theme.fg : Theme.fg3
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
        SIcon {
            id: chev
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            size: 13
            color: Theme.line3
        }
        MouseArea {
            id: triggerArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            property bool wasOpen: false
            onPressed: wasOpen = pop.visible
            onClicked: {
                if (wasOpen) pop.close()
                else pop.open()
            }
        }
    }

    Popup {
        id: pop
        y: root.height + 4
        width: root.width
        padding: 4
        // 保留 outside-press（点空白处收起）；触发器用 onPressed 记下点击前的状态来 toggle，
        // 否则 press 阶段已关、click 又 open，表现就是"点第二次还是展开"
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durFast; easing.type: Theme.easeEnter }
            NumberAnimation { property: "y"; from: root.height + 1; to: root.height + 4; duration: Theme.durFast; easing.type: Theme.easeEnter }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durFast; easing.type: Theme.easeExit }
        }
        background: Rectangle {
            radius: Theme.rSm
            color: Theme.bgCard2
            border.width: 1
            border.color: Theme.line2
        }
        contentItem: ListView {
            implicitHeight: Math.min(240, contentHeight)
            model: root.items
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                width: pop.width - 8
                height: 32
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Theme.bgCard2
                    opacity: (hov.hovered || index === root.currentIndex) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: index === root.currentIndex ? Theme.accentText : Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                HoverHandler { id: hov }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.currentIndex = index
                        root.activated(index)
                        pop.close()
                    }
                }
            }
        }
    }
}
