// SPDX-License-Identifier: AGPL-3.0-or-later
// Java 与内存：当前 Java / 自动检测 / 已检测列表（可切换，不可删）/ 内存双滑块
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null
    // 扫描 / 自动检测期间点亮壳的顶部光条
    property bool busy: false

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var s: (pane.b ? pane.b.settings() : null)

    property var javaList: []

    function refreshJavaList() {
        if (!pane.s) { pane.javaList = []; return }
        pane.javaList = pane.s.availableJavaList()
    }
    function refreshMemory() {
        if (!pane.s) return
        pane.mem = pane.s.getMemoryStatus()
    }
    property var mem: ({})

    Component.onCompleted: { refreshJavaList(); refreshMemory() }

    Connections {
        target: pane.s
        ignoreUnknownSignals: true
        function onJavaPathChanged() { pane.refreshJavaList() }
        function onMemorySettingsChanged() { pane.refreshMemory() }
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
                    desc: pane.s && pane.s.javaPath.length > 0 ? pane.s.javaPath : "尚未选择"

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        width: javaTag.implicitWidth + 20
                        radius: 11
                        color: (pane.s && pane.s.javaReady) ? "#0c1a12" : "#1a1408"
                        border.width: 1
                        border.color: (pane.s && pane.s.javaReady) ? "#1e3a2a" : "#3d2f12"
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: (pane.s && pane.s.javaReady) ? Theme.ok : Theme.warn
                            }
                            Text {
                                id: javaTag
                                anchors.verticalCenter: parent.verticalCenter
                                text: pane.s && pane.s.javaReady
                                      ? ("Java " + pane.s.javaMajor)
                                      : "未就绪"
                                color: (pane.s && pane.s.javaReady) ? Theme.ok : Theme.warn
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
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
                    label: "自动检测"
                    desc: "扫描常见安装目录与 PATH，挑出最合适的版本"
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: "自动检测"
                        enabled: !pane.busy
                        onClicked: {
                            if (!pane.s) return
                            pane.busy = true
                            pane.s.autoSelectJava()
                            pane.busy = false
                            pane.refreshJavaList()
                        }
                    }
                    SButton {
                        kind: 1
                        radius: 2
                        height: 32
                        text: pane.busy ? "扫描中" : "重新扫描"
                        enabled: !pane.busy
                        onClicked: {
                            if (!pane.s) return
                            pane.busy = true
                            pane.s.scanJavaInstallations()
                        }
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: "已检测到的 Java"

                // 列表行：点整行切换当前 Java（不提供"移除"—— 用户不该在启动器里删掉系统里的 Java）
                Repeater {
                    model: pane.javaList

                    Item {
                        id: jrow
                        width: col.width
                        height: 52
                        readonly property bool cur: pane.s
                                                       && pane.s.javaPath.length > 0
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

                        HoverHandler { id: jHover }
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

                // 列表为空时的说明（首次启动还没扫描过）。
                // 必须显式 visible：高度为 0 的 Item 不裁剪子项，Text 会照画出来压住第一行。
                Item {
                    width: col.width
                    visible: pane.javaList.length === 0
                    height: visible ? 52 : 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: "还没有检测结果，点上面的「重新扫描」"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
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
                          : ""
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
