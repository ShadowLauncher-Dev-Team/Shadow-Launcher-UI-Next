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
    // 建议值必须按**这个版本的模组数**算：原来用的是全局 mem.recommended（只看总内存），
    // 425 模组的整合包和一个空实例显示同一个建议值，用户无从判断。
    readonly property int autoMB: (pane.b && pane.versionId.length > 0)
                                   ? pane.b.recommendMemoryForVersion(pane.versionId)
                                   : (pane.mem.recommended ? pane.mem.recommended : 2048)
    // ── 「跟随全局」显示的必须是**启动时真正会用的值** ──
    // 全局开着自动分配时，启动走的是 getAutoMemoryForVersion（按模组数），
    // 根本不会用 maxMemoryMB。但界面一直显示后者 ——
    // 用户看到「跟随全局 2048 MB」且被提醒「低于建议」，以为自动配置也这么低。
    readonly property bool globalAutoOn: pane.s ? pane.s.autoMemoryEnabled : false
    readonly property int globalEffectiveMB: pane.globalAutoOn ? pane.autoMB : pane.globalMB
    readonly property int effectiveMB: pane.mode === 2 ? pane.manualMB : pane.globalEffectiveMB
    // 只有「自己手动压低」才提醒：自动与跟随-自动 本来就是建议值，不该报警。
    readonly property bool underAllocated: pane.mode === 2 && pane.autoMB > 0
                                           && pane.manualMB > 0 && pane.manualMB < pane.autoMB * 0.8

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

        // 点内容空白处清焦点。必须挂在 Flickable 自己身上：
        // 页面根层收不到（这个 Flickable 铺满内容区、会吃掉 press），挂在子项上又会挡拖拽。
        // tap 与 drag 不冲突：只有按下抬起位置基本不变的点击才触发。
        TapHandler {
            onTapped: pane.forceActiveFocus()
        }

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
                    text: qsTr("分配方式")
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 1.1
                }
                OptCard {
                    width: parent.width
                    title: qsTr("跟随全局设置")
                    desc: qsTr("使用启动器全局内存设置")
                    val: pane.globalAutoOn
                         ? qsTr("%1 MB·按模组自动").arg(pane.globalEffectiveMB)
                         : qsTr("%1 MB").arg(pane.globalMB)
                    active: pane.mode === 0
                    onClicked: pane.setMode(0)
                }
                OptCard {
                    width: parent.width
                    title: qsTr("自动配置")
                    desc: qsTr("按该版本的模组数与物理内存估算，每次启动重算")
                    val: qsTr("建议 %1 MB").arg(pane.autoMB)
                    active: pane.mode === 1
                    onClicked: pane.setMode(1)
                }
                OptCard {
                    width: parent.width
                    title: qsTr("自定义")
                    desc: qsTr("固定分配给这个版本")
                    val: pane.manualMB + " MB"
                    active: pane.mode === 2
                    onClicked: pane.setMode(2)
                }
            }

            // ── 内存不足提示 ──
            // 用户知道自己有多少模组，却不知道该分多少内存；
            // 只给一个滑块等于让他猜。这里把结论直接写出来。
            Rectangle {
                width: col.width
                height: warn.implicitHeight + 20
                radius: 8
                color: Theme.bgCard2
                border.color: Theme.line2
                border.width: 1
                visible: pane.underAllocated
                Text {
                    id: warn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    wrapMode: Text.WordWrap
                    text: qsTr("当前 %1 MB 低于该版本建议的 %2 MB。模组较多时内存不足，会在加载世界时卡住或直接崩溃。")
                            .arg(pane.effectiveMB).arg(pane.autoMB)
                    color: Theme.dangerText
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    lineHeight: 1.5
                }
            }

            // ── 分配内存 ──
            SCard {
                width: col.width
                title: qsTr("分配内存")
                // 非自定义模式整卡压暗：切换分配方式时跟着 OptCard 一起过渡，不要硬跳
                opacity: pane.mode === 2 ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

                Item {
                    width: parent.width
                    height: 26
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("范围 %1 – %2 MB").arg(pane.sliderMin).arg(pane.sliderMax)
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.manualMB + " MB"
                        color: Theme.fg
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
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.sliderMax + " MB"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
            }

            // ── 系统内存 ──
            SCard {
                width: col.width
                title: qsTr("系统内存")
                Item {
                    width: parent.width
                    height: 54
                    Text {
                        id: pctText
                        anchors.left: parent.left
                        anchors.baseline: parent.verticalCenter
                        text: pane.sysPercent
                        color: Theme.fg
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
                        text: qsTr("已用 %1 MB · 共 %2 MB").arg(pane.sysTotal - pane.sysAvail).arg(pane.sysTotal)
                        color: Theme.fg3
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
                        color: Theme.bgCard
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 5
                        width: parent.width * Math.min(1, (pane.sysTotal - pane.sysAvail) / Math.max(1, pane.sysTotal))
                        color: Theme.line3
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 5
                        width: parent.width * Math.min(1, pane.manualMB / Math.max(1, pane.sysTotal))
                        color: Theme.accent
                        // 这段只有拖滑条时才会变（低频），才敢用 Behavior on width。
                        // 左边那条「其他占用」只在 reload 时变，跟着一起动反而像卡了，不做。
                        Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
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
                                text: qsTr("本版本 %1 MB").arg(pane.manualMB)
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                        Row {
                            spacing: 6
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: Theme.line3
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: qsTr("其他占用")
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("可用 %1 MB").arg(pane.sysAvail)
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
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
            color: opt.active ? Theme.accentSoft : Theme.bgCard2
            border.width: 1
            border.color: opt.active ? Theme.accent : Theme.line2
            Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
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
            border.color: opt.active ? Theme.accent : Theme.line2
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
            color: opt.active ? Theme.fg : Theme.fg2
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
        Text {
            anchors.left: dot.right
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 33
            text: opt.desc
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: opt.val
            color: opt.active ? Theme.accentText : Theme.fg3
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
