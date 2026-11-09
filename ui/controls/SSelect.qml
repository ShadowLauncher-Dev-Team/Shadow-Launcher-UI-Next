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
        color: "#0d1016"
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
            color: (root.currentIndex >= 0) ? "#cfd6e1" : Theme.fg3
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
            color: "#4d5666"
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pop.opened ? pop.close() : pop.open()
        }
    }

    Popup {
        id: pop
        y: root.height + 4
        width: root.width
        padding: 4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Theme.rSm
            color: "#0b0d12"
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
                    color: "#0f131a"
                    opacity: (hov.hovered || index === root.currentIndex) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: index === root.currentIndex ? "#a9c8ff" : Theme.fg2
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
