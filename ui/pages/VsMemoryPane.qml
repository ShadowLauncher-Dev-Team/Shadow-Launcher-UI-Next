// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 内存设置（定稿甲：分配方式单选 + 分配滑块 + 系统内存条）
//
// 模式语义（backend resolvedMemoryMB）：0=跟随全局 1=自动 2=自定义
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var s: b ? b.settings() : null

    property int mode: 0
    property int manualMB: 2048
    property var mem: ({})

    readonly property int sysTotal: pane.mem.total ? pane.mem.total : 8192
    readonly property int sysAvail: pane.mem.available ? pane.mem.available : 4096
    readonly property int sysPercent: pane.mem.percent ? pane.mem.percent : 0
    readonly property int sliderMin: (pane.s && pane.s.minMemoryMB > 0) ? pane.s.minMemoryMB : 512
    readonly property int sliderMax: Math.max(pane.sliderMin + 1024, pane.sysTotal)
    readonly property int globalMB: (pane.s && pane.s.maxMemoryMB > 0) ? pane.s.maxMemoryMB : 2048
    readonly property int autoMB: pane.mem.recommended ? pane.mem.recommended : 2048

    function reload() {
        if (!pane.s || !pane.b) return
        pane.mode = pane.s.versionMemoryMode(pane.versionId)
        pane.manualMB = pane.s.versionMemoryManualMB(pane.versionId)
        pane.mem = pane.b.getMemoryStatus()
    }
    Component.onCompleted: pane.reload()

    function setMode(m) {
        if (!pane.s) return
        pane.s.setVersionMemoryMode(pane.versionId, m)
        pane.mode = m
        pane.reload()
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

            // ── 分配方式 ──
            Column {
                width: col.width
                spacing: 8
                Text {
                    text: "分配方式"
                    color: "#3f4753"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 1.1
                }
                OptCard {
                    width: parent.width
                    title: "跟随全局设置"
                    desc: "使用启动器全局内存设置"
                    val: pane.globalMB + " MB"
                    active: pane.mode === 0
                    onClicked: pane.setMode(0)
                }
                OptCard {
                    width: parent.width
                    title: "自动配置"
                    desc: "启动时按剩余内存动态分配"
                    val: "建议 " + pane.autoMB + " MB"
                    active: pane.mode === 1
                    onClicked: pane.setMode(1)
                }
                OptCard {
                    width: parent.width
                    title: "自定义"
                    desc: "固定分配给这个版本"
                    val: pane.manualMB + " MB"
                    active: pane.mode === 2
                    onClicked: pane.setMode(2)
                }
            }

            // ── 分配内存 ──
            SCard {
                width: col.width
                title: "分配内存"
                opacity: pane.mode === 2 ? 1 : 0.45

                Item {
                    width: parent.width
                    height: 26
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "范围 " + pane.sliderMin + " – " + pane.sliderMax + " MB"
                        color: "#3f4753"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.manualMB + " MB"
                        color: "#cfd6e1"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
                SSlider {
                    width: parent.width
                    enabled: pane.mode === 2
                    from: pane.sliderMin
                    to: pane.sliderMax
                    step: 256
                    value: pane.manualMB
                    onMoved: (v) => {
                        if (!pane.s) return
                        pane.manualMB = v
                        pane.s.setVersionMemoryManualMB(pane.versionId, v)
                        if (pane.mode !== 2) pane.setMode(2)
                    }
                }
                Item {
                    width: parent.width
                    height: 22
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.sliderMin + " MB"
                        color: "#3f4753"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.sliderMax + " MB"
                        color: "#3f4753"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            // ── 系统内存 ──
            SCard {
                width: col.width
                title: "系统内存"
                Item {
                    width: parent.width
                    height: 54
                    Text {
                        id: pctText
                        anchors.left: parent.left
                        anchors.baseline: parent.verticalCenter
                        text: pane.sysPercent
                        color: "#eef2f8"
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.left: pctText.right
                        anchors.baseline: pctText.baseline
                        text: "%"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.left: pctText.right
                        anchors.leftMargin: 34
                        anchors.baseline: pctText.baseline
                        text: "已用 " + (pane.sysTotal - pane.sysAvail) + " MB · 共 " + pane.sysTotal + " MB"
                        color: "#5d6673"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
                // 双色条：本版本分配 + 其他占用
                Item {
                    width: parent.width
                    height: 10
                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: "#151a22"
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 5
                        width: parent.width * Math.min(1, (pane.sysTotal - pane.sysAvail) / Math.max(1, pane.sysTotal))
                        color: "#3a4a63"
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 5
                        width: parent.width * Math.min(1, pane.manualMB / Math.max(1, pane.sysTotal))
                        color: Theme.accent
                    }
                }
                Item {
                    width: parent.width
                    height: 30
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18
                        Row {
                            spacing: 6
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: Theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "本版本 " + pane.manualMB + " MB"
                                color: "#5d6673"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                        Row {
                            spacing: 6
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: "#3a4a63"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "其他占用"
                                color: "#5d6673"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "可用 " + pane.sysAvail + " MB"
                        color: "#5d6673"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // 单选卡：左点 + 标题/说明 + 右侧当前值
    component OptCard: Item {
        id: opt
        property string title: ""
        property string desc: ""
        property string val: ""
        property bool active: false
        signal clicked()

        height: 62

        Rectangle {
            anchors.fill: parent
            radius: Theme.rMd
            color: opt.active ? "#111a2b" : "#0b0d12"
            border.width: 1
            border.color: opt.active ? "#2c4a7a" : Theme.line2
            Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
        }
        Rectangle {
            id: dot
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: "transparent"
            border.width: 1
            border.color: opt.active ? Theme.accent : "#3a4454"
            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: Theme.accent
                visible: opt.active
            }
        }
        Text {
            anchors.left: dot.right
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 13
            text: opt.title
            color: opt.active ? "#eef2f8" : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
        Text {
            anchors.left: dot.right
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 33
            text: opt.desc
            color: "#4b5462"
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: opt.val
            color: opt.active ? "#a9c8ff" : "#5d6673"
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: opt.clicked()
        }
    }
}
