// SPDX-License-Identifier: AGPL-3.0-or-later
// Java 与内存：当前 Java / 重新扫描 / 已检测列表（可切换，含"自动选择"）/ 内存双滑块
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null
    // 扫描期间点亮壳的顶部光条。由 javaScanFinished 复位 —— 扫描是异步的，
    // 点完立刻置 false 会让光条一闪而过、而实际还在扫（影报的"光条一直在动"）。
    property bool busy: false

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var s: (pane.b ? pane.b.settings() : null)

    property var javaList: []
    property var mem: ({})

    // 是否处于"自动选择"（没有手动指定 Java）
    readonly property bool autoMode: pane.s ? (pane.s.javaPath.length === 0) : true

    function refreshJavaList() {
        if (!pane.s) { pane.javaList = []; return }
        pane.javaList = pane.s.availableJavaList()
    }
    function refreshMemory() {
        if (!pane.s) return
        pane.mem = pane.s.getMemoryStatus()
    }

    Component.onCompleted: {
        refreshJavaList()
        refreshMemory()
        // 上次关闭时可能还在扫（不会发生，但首次进来列表可能为空且未扫过）
        pane.busy = pane.s ? pane.s.isJavaScanning() : false
    }

    Connections {
        target: pane.s
        ignoreUnknownSignals: true
        function onJavaPathChanged() { pane.refreshJavaList() }
        function onMemorySettingsChanged() { pane.refreshMemory() }
        // 扫描真正结束才复位：结果写进缓存后要重新读一次列表
        function onJavaScanFinished() {
            pane.busy = false
            pane.refreshJavaList()
            console.info("[ui] javaScanFinished: busy=false, 列表=" + pane.javaList.length)
        }
    }

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
                title: "Java 运行时"

                SetRow {
                    width: parent.width
                    minHeight: 62
                    label: "当前 Java"
                    desc: pane.autoMode
                          ? "自动选择：启动时按版本需要的 Java 主版本匹配"
                          : (pane.s ? pane.s.javaPath : "")

                    // 版本徽标：高度对齐右侧 32 高的按钮，圆角 6（与项目里其它 badge 一致）。
                    // 原来是 22 高 + 全圆角，夹在 32 高按钮旁边显得又小又扁。
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        width: javaTag.implicitWidth + 26
                        radius: 6
                        color: pane.autoMode ? "#141a24"
                                             : ((pane.s && pane.s.javaReady) ? "#0c1a12" : "#1a1408")
                        border.width: 1
                        border.color: pane.autoMode ? Theme.line2
                                                    : ((pane.s && pane.s.javaReady) ? "#1e3a2a" : "#3d2f12")
                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !pane.autoMode
                                color: (pane.s && pane.s.javaReady) ? Theme.ok : Theme.warn
                            }
                            Text {
                                id: javaTag
                                anchors.verticalCenter: parent.verticalCenter
                                text: pane.autoMode
                                      ? "自动"
                                      : ((pane.s && pane.s.javaReady)
                                         ? ("Java " + pane.s.javaMajor) : "未就绪")
                                color: pane.autoMode ? Theme.fg2
                                                     : ((pane.s && pane.s.javaReady) ? Theme.ok : Theme.warn)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                    }

                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: "浏览"
                        enabled: !pane.busy
                        onClicked: { if (pane.s) pane.s.browseJava() }
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: "重新扫描"
                    desc: pane.busy
                          ? "正在扫描常见安装目录与 PATH…"
                          : "扫描常见的 Java 安装位置；扫描不会自动改动你当前的选择"
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: pane.busy ? "扫描中" : "重新扫描"
                        enabled: !pane.busy
                        onClicked: {
                            if (!pane.s) return
                            if (pane.s.isJavaScanning()) return   // 已在扫描：不会再有 finished，别把 busy 卡住
                            pane.busy = true
                            console.info("[ui] 重新扫描：busy=true")
                            // 异步：真正的复位在 onJavaScanFinished
                            pane.s.scanJavaInstallations()
                        }
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: "Java 选择"

                // 「自动选择」置顶：手动指定过任何一个 Java 之后，
                // 原来没有任何入口能回到"让启动器自己挑"（影报的第 2 条）。
                Item {
                    id: autoRow
                    width: col.width
                    height: 52

                    Rectangle {
                        anchors.fill: parent
                        color: pane.autoMode ? "#101720" : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 22
                        radius: 6
                        color: pane.autoMode ? "#12203a" : "#141a24"
                        SIcon {
                            anchors.centerIn: parent
                            name: "zap"
                            size: 12
                            color: pane.autoMode ? "#a9c8ff" : Theme.fg3
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 62
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: "自动选择（推荐）— 按每个版本需要的 Java 主版本匹配"
                        elide: Text.ElideRight
                        color: pane.autoMode ? Theme.fg : Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.line
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !pane.busy && !pane.autoMode
                        onClicked: {
                            if (!pane.s) return
                            pane.s.useAutoJava()
                            pane.refreshJavaList()
                        }
                    }
                }

                Repeater {
                    model: pane.javaList

                    Item {
                        id: jrow
                        width: col.width
                        height: 52
                        readonly property bool cur: !pane.autoMode && pane.s
                                                       && pane.s.javaPath === modelData.path

                        Rectangle {
                            anchors.fill: parent
                            color: jrow.cur ? "#101720" : "transparent"
                            Behavior on color {
                                ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 22
                            radius: 6
                            color: jrow.cur ? "#12203a" : "#141a24"
                            Text {
                                anchors.centerIn: parent
                                text: modelData.major
                                color: jrow.cur ? "#a9c8ff" : Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 62
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.path
                            elide: Text.ElideMiddle
                            color: jrow.cur ? Theme.fg : Theme.fg2
                            font.family: "Consolas"
                            font.pixelSize: 12
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.line
                            visible: index < pane.javaList.length - 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: !pane.busy && !jrow.cur
                            onClicked: {
                                if (!pane.s) return
                                pane.s.selectJavaByIndex(index)
                                pane.refreshJavaList()
                            }
                        }
                    }
                }

                // 列表为空时的说明。必须显式 visible —— 高度为 0 的 Item 不裁剪子项，
                // 否则 Text 会照画出来压住第一行。
                Item {
                    width: col.width
                    visible: pane.javaList.length === 0
                    height: visible ? 52 : 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.busy ? "正在扫描…" : "还没有检测结果，点上面的「重新扫描」"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.line
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: "内存分配"

                SetRow {
                    width: parent.width
                    label: "自动分配"
                    desc: "按物理内存可用量推荐一个值，不用手动调"
                    SSwitch {
                        checked: pane.s ? pane.s.autoMemoryEnabled : true
                        onToggled: (c) => { if (pane.s) pane.s.setAutoMemoryEnabled(c) }
                    }
                }

                SetRow {
                    width: parent.width
                    label: "最小内存"
                    desc: "JVM 起始堆大小（-Xms）"
                    SSlider {
                        width: 240
                        enabled: pane.s ? !pane.s.autoMemoryEnabled : false
                        from: 256
                        to: pane.s ? Math.max(512, pane.s.maxMemoryMB) : 8192
                        step: 256
                        value: pane.s ? pane.s.minMemoryMB : 512
                        onMoved: (v) => { if (pane.s) pane.s.setMinMemory(v) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 76
                        horizontalAlignment: Text.AlignRight
                        text: (pane.s ? pane.s.minMemoryMB : 512) + " MB"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: "最大内存"
                    desc: pane.mem && pane.mem.total
                          ? ("物理内存 " + pane.mem.total + " MB · 可用 " + pane.mem.available
                             + " MB · 推荐 " + pane.mem.recommended + " MB")
                          : "JVM 最大堆大小（-Xmx）"
                    SSlider {
                        width: 240
                        enabled: pane.s ? !pane.s.autoMemoryEnabled : false
                        from: 512
                        to: 32768
                        step: 256
                        value: pane.s ? pane.s.maxMemoryMB : 2048
                        onMoved: (v) => { if (pane.s) pane.s.setMaxMemory(v) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 76
                        horizontalAlignment: Text.AlignRight
                        text: (pane.s ? pane.s.maxMemoryMB : 2048) + " MB"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }

            SetNote {
                width: parent.width
                kind: "info"
                icon: "info"
                text: "自动分配开启时下面的滑块不可调；关掉它才能手动指定上下限。"
            }
        }
    }
}
