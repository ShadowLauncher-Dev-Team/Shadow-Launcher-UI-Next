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
                    // 实测依据（官方源 5173 文件 / 566MB）：192 并发 16.7s 是拐点，256 并发 16.4s、收益消失；
                    // 再往上只会拉长服务端排队。真正会限流的是第三方镜像（BMCLAPI/CF），不是官方源。
                    // 所以 desc 按实测口径写，不给「调高会出问题」的暗示。
                    desc: qsTr("越高越快，官方源实测 192 最快；第三方镜像并发过高可能被限流")
                    SSlider {
                        width: 260
                        from: 1
                        // 上界要盖住默认并发（核数×12，夹取 [32,192]），写小了滑块会贴右端、
                        // 右侧数字却显示真实值，看起来「拖不动也看不出」。
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
                            // 打开时给一个默认上限，关掉写 -1；设置层把 <=0 一律当作不限速。
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
