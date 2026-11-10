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
                title: "下载源"

                SetRow {
                    width: parent.width
                    label: "游戏文件下载源"
                    desc: "影响 MC 本体与资源文件；加载器另有独立策略"
                    SSegmented {
                        itemHeight: 28
                        items: ["镜像优先", "官方优先", "自动切换"]
                        currentIndex: pane.s ? pane.s.fileDownloadSource : 1
                        onActivated: (i) => { if (pane.s) pane.s.fileDownloadSource = i }
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: "资源列表源"
                    desc: "Mod / 光影 / 资源包等的索引与详情"
                    SSegmented {
                        itemHeight: 28
                        items: ["镜像优先", "官方优先", "自动切换"]
                        currentIndex: pane.s ? pane.s.listDownloadSource : 1
                        onActivated: (i) => { if (pane.s) pane.s.listDownloadSource = i }
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: "速度与并发"

                SetRow {
                    width: parent.width
                    label: "最大并发连接"
                    desc: "太高会被下载站限流，16 是稳妥值"
                    SSlider {
                        width: 260
                        from: 1
                        to: 24
                        step: 1
                        value: pane.s ? pane.s.maxDownloadThreads : 16
                        onMoved: (v) => { if (pane.s) pane.s.setMaxDownloadThreads(v) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46
                        horizontalAlignment: Text.AlignRight
                        text: (pane.s ? pane.s.maxDownloadThreads : 16)
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                SetRow {
                    width: parent.width
                    label: "限速"
                    desc: "关掉表示不限速，占满带宽"
                    SSwitch {
                        checked: pane.s ? pane.s.downloadSpeedLimitMB > 0 : false
                        onToggled: (c) => {
                            if (!pane.s) return
                            // 打开时给一个默认上限，关掉写 -1（-1 才是不限速；0 会被夹成 0.1）
                            pane.s.downloadSpeedLimitMB = c ? 5.0 : -1.0
                        }
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: "速度上限"
                    desc: "1.0 – 20.0 MB/s"
                    SSlider {
                        width: 260
                        from: 1
                        to: 20
                        step: 1
                        enabled: pane.s ? pane.s.downloadSpeedLimitMB > 0 : false
                        value: pane.s && pane.s.downloadSpeedLimitMB > 0
                               ? Math.round(pane.s.downloadSpeedLimitMB) : 5
                        onMoved: (v) => { if (pane.s && pane.s.downloadSpeedLimitMB > 0) pane.s.downloadSpeedLimitMB = v }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 62
                        horizontalAlignment: Text.AlignRight
                        text: (pane.s && pane.s.downloadSpeedLimitMB > 0
                               ? pane.s.downloadSpeedLimitMB.toFixed(1) + " MB/s" : "不限速")
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
