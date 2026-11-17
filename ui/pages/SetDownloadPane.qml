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
                title: qsTr("下载源")

                SetRow {
                    width: parent.width
                    label: qsTr("游戏文件下载源")
                    desc: qsTr("影响 MC 本体与资源文件；加载器另有独立策略")
                    SSegmented {
                        itemHeight: 28
                        items: [qsTr("镜像优先"), qsTr("官方优先"), qsTr("自动切换")]
                        currentIndex: pane.s ? pane.s.fileDownloadSource : 1
                        onActivated: (i) => { if (pane.s) pane.s.fileDownloadSource = i }
                    }
                }

                SetRow {
                    width: parent.width
                    divider: false
                    label: qsTr("资源列表源")
                    desc: qsTr("Mod / 光影 / 资源包等的索引与详情")
                    SSegmented {
                        itemHeight: 28
                        items: [qsTr("镜像优先"), qsTr("官方优先"), qsTr("自动切换")]
                        currentIndex: pane.s ? pane.s.listDownloadSource : 1
                        onActivated: (i) => { if (pane.s) pane.s.listDownloadSource = i }
                    }
                }
            }

            SetGroup {
                width: parent.width
                title: qsTr("速度与并发")

                SetRow {
                    width: parent.width
                    label: qsTr("最大并发连接")
                    // 2026-11-18：这句原本写「16 是稳妥值」，但实测 192 才是最快档
                    //（官方源 192 并发冷装 16.0s，64 并发 56.9s）。改成按实测口径描述，
                    // 不再给用户「调高会出问题」的暗示 —— 真正会限流的是第三方镜像，不是官方源。
                    desc: qsTr("越高越快，官方源实测 192 最快；第三方镜像并发过高可能被限流")
                    SSlider {
                        width: 260
                        from: 1
                        // 2026-11-18：上限原本写死 24，而核心层夹取到 256、默认给到 192。
                        // 结果滑块永远贴在右端、数字却显示 192，改不动也看不出。
                        to: 256
                        step: 1
                        value: pane.s ? pane.s.maxDownloadThreads : 192
                        // maxDownloadThreads 是 Q_PROPERTY 的 WRITE 访问器，只能赋值；
                    // 当方法调用会抛 TypeError，滑块动了但右侧数字不变。
                    onMoved: (v) => { if (pane.s) pane.s.maxDownloadThreads = v }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46
                        horizontalAlignment: Text.AlignRight
                        text: (pane.s ? pane.s.maxDownloadThreads : 192)
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                SetRow {
                    width: parent.width
                    label: qsTr("限速")
                    desc: qsTr("关掉表示不限速，占满带宽")
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
                    label: qsTr("速度上限")
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
                               ? pane.s.downloadSpeedLimitMB.toFixed(1) + " MB/s"
                               : qsTr("不限速"))
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
