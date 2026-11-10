// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var s: (pane.b ? pane.b.settings() : null)

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.height + 60
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        TapHandler { onTapped: pane.forceActiveFocus() }

        Column {
            id: col
            x: 40
            y: 4
            width: Math.min(900, flick.width - 80)
            spacing: 26

            SetGroup {
                width: parent.width
                title: "启动器"

                SetRow {
                    width: parent.width
                    divider: false
                    label: "启动器内嵌登录"
                    desc: "在启动器窗口内完成微软登录，不弹系统浏览器"
                    SSwitch {
                        checked: pane.s ? pane.s.embeddedLoginEnabled : false
                        onToggled: (c) => { if (pane.s) pane.s.embeddedLoginEnabled = c }
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: "路径"

                SetRow {
                    width: parent.width
                    divider: false
                    label: "游戏目录"
                    desc: pane.s ? pane.s.gameDir : ""
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: "打开目录"
                        onClicked: { if (pane.s) pane.s.openGameDir() }
                    }
                }
            }
        }
    }
}
