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
                    // 消费点：VersionDownloader 选镜像（jar / libraries / assets）。
                    // 模组与整合包不跟随此项（契约 DOWNLOAD_CONTRACT §11），别写成「影响全部下载」。
                    desc: qsTr("影响 MC 本体与资源文件；加载器与模组下载另有独立策略")
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
                    // 名字跟契约对齐（原先叫「资源列表源」容易被读成模组平台源）。
                    // 消费点只有 MC 版本清单域：version_manifest / 版本 JSON / 资源索引
                    // （VersionBackend::setListDownloadSource、version_downloader.cpp:682）。
                    // Mod / 光影 / 资源包的搜索走 Modrinth/CurseForge，不受此项影响。
                    label: qsTr("版本列表源")
                    desc: qsTr("MC 版本清单、版本 JSON 与资源索引的来源；模组搜索不跟随此项")
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
                    // 上界 = 引擎契约上限 24（version_downloader.cpp:192，DOWNLOAD_CONTRACT §7）。
                    // 原先滑块画到 256、desc 写「192 最快」，而后端读注册表夹到 512、引擎又夹到 24，
                    // 于是「滑到最大」「显示 512」和「实际 24」三个数字互不相同（审计 SET-01）。
                    // 现在三处同一个常量：SettingsBackend::kMaxDownloadConcurrency。
                    desc: qsTr("上限 24（下载引擎的硬上限）；第三方镜像并发过高会被限流")
                    SSlider {
                        width: 260
                        from: 1
                        to: 24
                        step: 1
                        value: pane.s ? pane.s.maxDownloadThreads : 24
                        // maxDownloadThreads 是 Q_PROPERTY 的 WRITE 访问器，只能赋值；
                    // 当方法调用会抛 TypeError，滑块动了但右侧数字不变。
                    onMoved: (v) => { if (pane.s) pane.s.maxDownloadThreads = v }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46
                        horizontalAlignment: Text.AlignRight
                        text: (pane.s ? pane.s.maxDownloadThreads : 24)
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
