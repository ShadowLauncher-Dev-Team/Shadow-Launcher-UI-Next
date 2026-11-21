// SPDX-License-Identifier: AGPL-3.0-or-later
// 关于：版本 / 许可 / 日志入口 / 鸣谢 / 内测人员
//
// 鸣谢内容原样搬自旧设置页 qml/SettingsPage.qml（541 行条目组件、675-736 行两张卡），
// 不是新写的文案。
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null

    // 项目地址单一来源：许可证与主页两个按钮都从这里取，别再各写一份
    readonly property string repoUrl: "https://github.com/ShadowLauncher-Dev-Team/Shadow-Launcher-UI-Next"

    // 鸣谢条目：name 有 url 时可点击；badge 非空时显示小徽标
    readonly property var credits: [
        { name: "PCL2", url: "https://github.com/Meloong-Git/PCL", badge: "",
          desc: qsTr("启动器的下载引擎与版本隔离设计参考了它的实现路径。") },
        { name: "HMCL", url: "https://github.com/HMCL-dev/HMCL", badge: "",
          desc: qsTr("启动参数构建、版本目录识别等实现路径参考了它。") },
        { name: "bangbang93", url: "https://afdian.com/a/bangbang93", badge: "",
          desc: qsTr("提供了镜像源和 Forge 安装工具。") },
        { name: "z0z0r4", url: "https://www.mcimirror.top/", badge: "",
          desc: qsTr("提供了 MCIM 镜像源，主要用于 Mod 等资源的下载，虽然不大稳定（也可能是我测试太多给我限速了），但好歹不用死守着有时非常逆天的官方源了。") },
        { name: "Lucide", url: "https://lucide.dev/", badge: "",
          desc: qsTr("提供了启动器目前所有可见的图标。") },
        { name: "MCBLOCK", url: "https://mcblock.top/", badge: "",
          desc: qsTr("为启动器的启动页提供了超多好看的壁纸！") },
        { name: "ChunMoMo", url: "", badge: qsTr("内测人员"),
          desc: qsTr("直接提供了一台能远程操控的电脑给开发者测试初代联机功能（而且是整整一个下午）。虽然初代联机功能已经废弃，但还是得感谢。") }
    ]

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

            // ── 版本 ──
            SetGroup {
                width: parent.width
                title: qsTr("版本")

                SetRow {
                    width: parent.width
                    minHeight: 72
                    label: "Shadow Launcher " + (pane.b ? pane.b.appVersion : "")
                    desc: qsTr("构建 2026-11-10 · Qt 6.8.3 · Windows x64")

                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: (pane.b && pane.b.updateChecking) ? qsTr("检查中") : qsTr("检查更新")
                        enabled: pane.b ? !pane.b.updateChecking : false
                        onClicked: { if (pane.b) pane.b.checkForUpdate() }
                    }
                }

                SetStack {
                    width: parent.width
                    divider: false
                    label: qsTr("版权与许可")
                    desc: qsTr("(C) 2025-2026 影 / Shadow / xiaole1173")

                    Row {
                        spacing: 8

                        SButton {
                            kind: 1
                            radius: 2
                            height: 30
                            text: qsTr("GNU AGPL v3 许可证")
                            onClicked: Qt.openUrlExternally(pane.repoUrl + "/blob/main/LICENSE")
                        }
                        SButton {
                            kind: 1
                            radius: 2
                            height: 30
                            text: qsTr("访问项目主页")
                            onClicked: Qt.openUrlExternally(pane.repoUrl)
                        }
                    }

                    Text {
                        width: parent.width
                        text: qsTr("非 Minecraft 官方产品。未经 Mojang 或 Microsoft 批准，也不与 Mojang 或 Microsoft 关联。")
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        lineHeight: 1.6
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ── 工具 ──
            SetGroup {
                width: parent.width
                title: qsTr("工具")

                SetRow {
                    width: parent.width
                    divider: false
                    label: qsTr("启动器日志")
                    desc: qsTr("遇到问题时，日志是排查的第一手资料")
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: qsTr("打开文件夹")
                        onClicked: { if (pane.b) pane.b.openLauncherLogsFolder() }
                    }
                }
            }

            // ── 鸣谢 ──
            SetGroup {
                width: parent.width
                title: qsTr("鸣谢")

                Item {
                    width: col.width
                    height: introText.implicitHeight + 28

                    Text {
                        id: introText
                        x: 18
                        y: 14
                        width: parent.width - 36
                        text: qsTr("启动器开发过程中参考了主流 MC 启动器的功能实现路径，在此十分感谢这些项目。若非如此，本启动器可能还在 debug 的水深火热中……（本项目为独立实现，与上述项目无隶属或授权关系。）")
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        lineHeight: 1.7
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.line
                    }
                }

                Repeater {
                    model: pane.credits

                    Item {
                        id: crow
                        width: col.width
                        height: ccol.implicitHeight + 26

                        Column {
                            id: ccol
                            x: 18
                            y: 13
                            width: parent.width - 36
                            spacing: 4

                            Row {
                                spacing: 8

                                Text {
                                    id: cname
                                    text: modelData.name
                                    color: cHover.hovered && modelData.url.length > 0 ? Theme.accent : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.underline: cHover.hovered && modelData.url.length > 0

                                    Behavior on color {
                                        ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                                    }
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.badge.length > 0
                                    height: 20
                                    width: badgeText.implicitWidth + 16
                                    radius: 6
                                    color: Theme.accentSoft

                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: modelData.badge
                                        color: Theme.accentText
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: modelData.desc
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                lineHeight: 1.65
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.line
                            visible: index < pane.credits.length - 1
                        }

                        HoverHandler { id: cHover }
                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.url.length > 0
                            cursorShape: modelData.url.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: Qt.openUrlExternally(modelData.url)
                        }
                    }
                }
            }

            // ── 内测人员 ──
            SetGroup {
                width: parent.width
                title: qsTr("内测人员的支持")

                SetStack {
                    width: parent.width
                    label: qsTr("挖 bug 的人")
                    desc: qsTr("这里非常荣幸地宣布：jh_hello、XChenyYa 二人以神奇的 bug 体制挖掘出了启动器的很多莫名其妙的 bug，包括但不限于下载、UI 显示、联机等多个方面。")
                }

                SetStack {
                    width: parent.width
                    label: qsTr("联机测试")
                    desc: qsTr("非常感谢 jh_hello、XChenyYa、渡、LUVlhr 等人对联机功能后续测试的全方位支持！")
                }

                SetStack {
                    width: parent.width
                    divider: false
                    label: qsTr("以及其他内测小伙伴")
                    desc: qsTr("以及其他参与内测的小伙伴们也十分感谢！")
                }
            }

            // ── 赞助支持 ──
            SetGroup {
                width: parent.width
                title: qsTr("赞助支持")

                SetStack {
                    width: parent.width
                    divider: false
                    label: qsTr("爱发电用户_Wa3G")
                    desc: qsTr("感谢 爱发电用户_Wa3G 为本启动器赞助了19元！")
                }
            }
        }
    }
}
