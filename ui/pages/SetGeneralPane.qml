// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null
    property bool busy: false

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var s: (pane.b ? pane.b.settings() : null)

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.height + 60
        // 内容没溢出时不吃滚轮（否则滚轮事件被这里吞掉，页面看起来"滚不动也没反应"）
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
                title: qsTr("语言")

                SetRow {
                    width: parent.width
                    label: qsTr("界面语言")
                    desc: qsTr("切换后需要重启启动器生效")
                    SSelect {
                        width: 168
                        // 语言名一律用**该语言自己的写法**，不随界面语言变化（这是通例）
                        // 繁体分港澳与台湾两套：用词不同（網絡/網路、帳戶/帳號、按/依…），
                        // 不能只给一个「繁體中文」再靠系统区域猜。
                        // English 暂时不列：en.ts 还没做，列出来选了也没效果。
                        items: [qsTr("简体中文"), qsTr("繁體中文（香港／澳門）"), qsTr("繁體中文（台灣）")]
                        currentIndex: pane.s ? pane.s.languageIndex : 0
                        onActivated: (i) => { if (pane.s) pane.s.setLanguageIndex(i) }
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: qsTr("游戏内语言")
                    desc: qsTr("启动游戏时把语言写进 options.txt")
                    SSegmented {
                        itemHeight: 28
                        items: [qsTr("不写入"), qsTr("系统语言"), qsTr("按地区")]
                        currentIndex: pane.s ? pane.s.autoLangMode : 1
                        onActivated: (i) => { if (pane.s) pane.s.setAutoLangMode(i) }
                    }
                }
            }

            SetNote {
                width: parent.width
                kind: pane.s && pane.s.languageChanged ? "warn" : "info"
                icon: pane.s && pane.s.languageChanged ? "alert-triangle" : "info"
                text: pane.s && pane.s.languageChanged
                      ? qsTr("界面语言已修改，重启启动器后生效。")
                      : qsTr("「系统语言」按 Windows 的语言设置；「按地区」按网络所在地判断，适合系统语言与实际习惯不一致时。")
            }
        }
    }
}
