// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 启动配置（定稿甲：单列块卡片）
//
// 一张卡 = 一个功能域：Java 环境 / JVM 参数 / 启动行为 / 游戏参数 / 命令。
// 全部字段都是 SettingsBackend 的版本级接口，不臆造：mode 0 一律表示"跟随全局"。
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var s: b ? b.settings() : null

    // ── 本地镜像（避免绑定里反复跨 C++ 调用）──
    property int jvmMode: 0
    property int gameMode: 0
    property string jvmArgs: ""
    property string gameArgs: ""
    property int javaMode: 0
    property int gcMode: 0
    property bool fullscreen: false
    property bool highPerfGpu: false
    property string autoJoin: ""
    property string winTitle: ""
    property string preCmd: ""
    property string postCmd: ""
    property string javaVer: ""
    property int javaMajor: 0

    readonly property bool independent: pane.jvmMode === 1 || pane.gameMode === 1

    readonly property string mcVer: {
        if (pane.b && pane.b.versionDetails) {
            var arr = pane.b.versionDetails
            for (var i = 0; i < arr.length; ++i)
                if (arr[i] && arr[i].id === pane.versionId && arr[i].mcVersion) return arr[i].mcVersion
        }
        var dash = pane.versionId.indexOf("-")
        return dash > 0 ? pane.versionId.substring(0, dash) : ""
    }
    // MC 版本 → 建议 Java 主版本（1.20.5+ 需要 21；1.18~1.20.4 用 17；1.17 用 16；更早用 8）
    readonly property int suggestedMajor: {
        var v = pane.mcVer.split(".")
        if (v.length < 2) return 17
        var maj = parseInt(v[1], 10)
        var min = v.length > 2 ? parseInt(v[2], 10) : 0
        if (isNaN(maj)) return 17
        if (maj >= 21) return 21
        if (maj === 20 && min >= 5) return 21
        if (maj >= 18) return 17
        if (maj === 17) return 16
        return 8
    }

    function load() {
        if (!pane.s) return
        var vid = pane.versionId
        pane.jvmMode = pane.s.versionJvmArgsMode(vid)
        pane.gameMode = pane.s.versionGameArgsMode(vid)
        pane.jvmArgs = pane.s.versionJvmArgs(vid)
        pane.gameArgs = pane.s.versionGameArgs(vid)
        pane.javaMode = pane.s.versionJavaMode(vid)
        pane.gcMode = pane.s.versionGcMode(vid)
        pane.fullscreen = pane.s.versionFullscreen(vid)
        pane.highPerfGpu = pane.s.versionHighPerfGpu(vid)
        pane.autoJoin = pane.s.versionAutoJoinServer(vid)
        pane.winTitle = pane.s.versionWindowTitle(vid)
        pane.preCmd = pane.s.versionPreLaunchCommand(vid)
        pane.postCmd = pane.s.versionPostExitCommand(vid)
        pane.javaVer = pane.s.javaVersion || ""
        pane.javaMajor = pane.s.javaMajor || 0
    }

    Component.onCompleted: pane.load()

    Connections {
        target: pane.b
        ignoreUnknownSignals: true
        function onVersionLaunchSettingsChanged(vid) { if (vid === pane.versionId) pane.load() }
    }

    function switchMode(idx) {
        if (!pane.s) return
        var m = idx === 1 ? 1 : 0
        pane.s.setVersionJvmArgsMode(pane.versionId, m)
        pane.s.setVersionGameArgsMode(pane.versionId, m)
        pane.jvmMode = m
        pane.gameMode = m
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 56
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 28
            y: 22
            width: Math.max(360, pane.width - 56)
            spacing: 16

            // ── 配置模式（整页只影响 JVM / 游戏参数两项）──
            SRow {
                width: col.width
                label: "配置模式"
                labelWidth: 96
                SSegmented {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 240
                    items: ["跟随全局设置", "独立配置"]
                    currentIndex: pane.independent ? 1 : 0
                    onActivated: (i) => pane.switchMode(i)
                }
            }

            // ── Java 环境 ──
            SCard {
                width: col.width
                title: "Java 环境"

                SRow {
                    width: parent.width
                    label: "选择"
                    SSelect {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 220
                        items: ["自动选择", "版本目录内 Java", "手动指定"]
                        currentIndex: pane.javaMode
                        onActivated: (i) => {
                            if (!pane.s) return
                            pane.s.setVersionJavaMode(pane.versionId, i)
                            pane.javaMode = i
                        }
                    }
                }
                SRow {
                    width: parent.width
                    label: "全局 Java"
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: (pane.javaVer.length > 0 ? pane.javaVer : "未检测到")
                              + (pane.javaMajor > 0 ? "（Java " + pane.javaMajor + "）" : "")
                        color: pane.javaVer.length > 0 ? "#cfd6e1" : Theme.warn
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
                SRow {
                    width: parent.width
                    label: "建议"
                    divider: false
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Java " + pane.suggestedMajor + "+"
                        color: "#cfd6e1"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 88
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pane.mcVer.length > 0
                        text: "游戏 " + pane.mcVer
                        color: "#3f4753"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            // ── JVM 参数 ──
            SCard {
                width: col.width
                title: "JVM 参数"
                opacity: pane.independent ? 1 : 0.45

                STextArea {
                    width: parent.width
                    areaHeight: 92
                    enabled: pane.independent
                    text: pane.jvmArgs
                    placeholder: pane.independent ? "留空则使用全局 JVM 参数" : "跟随全局设置时不生效"
                    onEdited: (t) => {
                        if (!pane.s || pane.jvmArgs === t) return
                        pane.s.setVersionJvmArgs(pane.versionId, t)
                        pane.jvmArgs = t
                    }
                }

                Row {
                    topPadding: 10
                    bottomPadding: 10
                    spacing: 8
                    SButton {
                        kind: 1
                        text: "G1GC 平衡"
                        enabled: pane.independent
                        onClicked: pane.applyPreset("-XX:+UseG1GC -XX:MaxGCPauseMillis=50")
                    }
                    SButton {
                        kind: 1
                        text: "ZGC 低延迟"
                        enabled: pane.independent
                        onClicked: pane.applyPreset("-XX:+UseZGC -XX:+ZGenerational")
                    }
                    SButton {
                        kind: 1
                        text: "清空"
                        enabled: pane.independent
                        onClicked: pane.applyPreset("")
                    }
                }
            }

            // ── 启动行为 ──
            SCard {
                width: col.width
                title: "启动行为"

                SRow {
                    width: parent.width
                    label: "GC 策略"
                    SSelect {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 220
                        items: ["跟随全局", "ZGC 优先", "仅 G1GC", "不指定"]
                        currentIndex: pane.gcMode
                        onActivated: (i) => {
                            if (!pane.s) return
                            pane.s.setVersionGcMode(pane.versionId, i)
                            pane.gcMode = i
                        }
                    }
                }
                SRow {
                    width: parent.width
                    label: "全屏启动"
                    SSwitch {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        checked: pane.fullscreen
                        onToggled: (v) => {
                            if (!pane.s) return
                            pane.s.setVersionFullscreenMode(pane.versionId, 1)
                            pane.s.setVersionFullscreen(pane.versionId, v)
                            pane.fullscreen = v
                        }
                    }
                }
                SRow {
                    width: parent.width
                    label: "高性能 GPU"
                    SSwitch {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        checked: pane.highPerfGpu
                        onToggled: (v) => {
                            if (!pane.s) return
                            pane.s.setVersionHighPerfGpuMode(pane.versionId, 1)
                            pane.s.setVersionHighPerfGpu(pane.versionId, v)
                            pane.highPerfGpu = v
                        }
                    }
                }
                SRow {
                    width: parent.width
                    label: "自动进服"
                    SInput {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(300, parent.width)
                        text: pane.autoJoin
                        placeholder: "留空则不自动进服"
                        onEdited: (t) => {
                            if (!pane.s || pane.autoJoin === t) return
                            pane.s.setVersionAutoJoinServer(pane.versionId, t)
                            pane.autoJoin = t
                        }
                    }
                }
                SRow {
                    width: parent.width
                    label: "窗口标题"
                    divider: false
                    SInput {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(300, parent.width)
                        text: pane.winTitle
                        placeholder: "留空则用游戏默认标题"
                        onEdited: (t) => {
                            if (!pane.s || pane.winTitle === t) return
                            pane.s.setVersionWindowTitleMode(pane.versionId, 1)
                            pane.s.setVersionWindowTitle(pane.versionId, t)
                            pane.winTitle = t
                        }
                    }
                }
            }

            // ── 游戏参数 ──
            SCard {
                width: col.width
                title: "游戏参数"
                opacity: pane.independent ? 1 : 0.45
                STextArea {
                    width: parent.width
                    areaHeight: 56
                    enabled: pane.independent
                    text: pane.gameArgs
                    placeholder: pane.independent ? "留空则使用全局游戏参数" : "跟随全局设置时不生效"
                    onEdited: (t) => {
                        if (!pane.s || pane.gameArgs === t) return
                        pane.s.setVersionGameArgs(pane.versionId, t)
                        pane.gameArgs = t
                    }
                }
            }

            // ── 命令 ──
            SCard {
                width: col.width
                title: "命令"
                SRow {
                    width: parent.width
                    label: "启动前"
                    STextArea {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        areaHeight: 56
                        text: pane.preCmd
                        placeholder: "留空则不执行"
                        onEdited: (t) => {
                            if (!pane.s || pane.preCmd === t) return
                            pane.s.setVersionPreLaunchMode(pane.versionId, 1)
                            pane.s.setVersionPreLaunchCommand(pane.versionId, t)
                            pane.preCmd = t
                        }
                    }
                }
                SRow {
                    width: parent.width
                    label: "退出后"
                    divider: false
                    STextArea {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        areaHeight: 56
                        text: pane.postCmd
                        placeholder: "留空则不执行"
                        onEdited: (t) => {
                            if (!pane.s || pane.postCmd === t) return
                            pane.s.setVersionPostExitMode(pane.versionId, 1)
                            pane.s.setVersionPostExitCommand(pane.versionId, t)
                            pane.postCmd = t
                        }
                    }
                }
            }
        }
    }

    function applyPreset(text) {
        if (!pane.s) return
        pane.s.setVersionJvmArgs(pane.versionId, text)
        pane.jvmArgs = text
        if (pane.toast) pane.toast.show(text.length > 0 ? "已套用预设" : "已清空 JVM 参数")
    }
}
