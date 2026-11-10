// SPDX-License-Identifier: AGPL-3.0-or-later
// 启动（全局默认）：GC / 优先级 / 全屏 / 窗口标题 / 自动进服 / 启动前后命令
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
            spacing: 22

            // 两层结构的说明放在最上面：这一页最容易让人搞不清「改了为什么某个版本没变」
            SetNote {
                width: parent.width
                kind: "info"
                icon: "info"
                text: "这里改的是全局默认值。某个版本在「版本设置的启动配置」里选了独立配置时，以那个版本自己的值为准。"
            }

            SetGroup {
                width: parent.width
                title: "Java 虚拟机"

                SetRow {
                    width: parent.width
                    label: "垃圾回收器"
                    desc: "自动会按 Java 版本挑最合适的；不确定就留自动"
                    SSegmented {
                        itemHeight: 28
                        items: ["自动", "分代 ZGC", "仅 G1GC", "不指定"]
                        currentIndex: pane.s ? pane.s.gcMode : 0
                        onActivated: (i) => { if (pane.s) pane.s.setGcMode(i) }
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: "进程优先级"
                    desc: "调高会让游戏在抢 CPU 时优先，代价是其它程序变慢"
                    SSegmented {
                        itemHeight: 28
                        items: ["高", "正常", "低"]
                        currentIndex: pane.s ? pane.s.processPriority : 1
                        onActivated: (i) => { if (pane.s) pane.s.setProcessPriority(i) }
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: "游戏窗口"

                SetRow {
                    width: parent.width
                    label: "全屏启动"
                    SSwitch {
                        checked: pane.s ? pane.s.fullscreenEnabled : false
                        onToggled: (c) => { if (pane.s) pane.s.fullscreenEnabled = c }
                    }
                }

                SetRow {
                    width: parent.width
                    label: "窗口标题"
                    desc: "留空则用游戏自己写的标题"
                    SInput {
                        width: 300
                        placeholder: "留空则用游戏默认标题"
                        text: pane.s ? pane.s.windowTitleOverride : ""
                        onEdited: (v) => { if (pane.s) pane.s.windowTitleOverride = v }
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: "自动进服"
                    desc: "只接受 host 或 host:port，例如 mc.example.com:25565"
                    SInput {
                        id: joinInput
                        width: 300
                        placeholder: "留空则不自动进服"
                        text: pane.s ? pane.s.autoJoinServer : ""
                        onEdited: (v) => {
                            if (!pane.s) return
                            pane.s.autoJoinServer = v
                            // 后端会拒绝非法地址（含空格 / 引号 / --）。
                            // 被拒时把输入框拉回真实值，避免「看着改了其实没存」。
                            if (v !== pane.s.autoJoinServer) {
                                joinInput.text = pane.s.autoJoinServer
                                if (pane.toast) pane.toast.show("只接受 host 或 host:port 格式", 2600, "warning")
                            }
                        }
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: "启动前后命令"

                SetStack {
                    width: parent.width
                    label: "启动前命令"
                    desc: "在游戏进程启动前执行一次"

                    STextArea {
                        width: parent.width
                        areaHeight: 76
                        placeholder: "留空则不执行"
                        text: pane.s ? pane.s.preLaunchCommand : ""
                        onEdited: (v) => { if (pane.s) pane.s.preLaunchCommand = v }
                    }
                }

                SetStack {
                    width: parent.width
                    divider: false
                    label: "退出后命令"
                    desc: "游戏进程结束后执行一次"

                    STextArea {
                        width: parent.width
                        areaHeight: 76
                        placeholder: "留空则不执行"
                        text: pane.s ? pane.s.postExitCommand : ""
                        onEdited: (v) => { if (pane.s) pane.s.postExitCommand = v }
                    }
                }
            }

            SetNote {
                width: parent.width
                kind: "warn"
                icon: "alert-triangle"
                text: "这两条命令会经 cmd.exe 原样执行，只填你自己写的或完全信任的内容。"
            }
        }
    }
}
