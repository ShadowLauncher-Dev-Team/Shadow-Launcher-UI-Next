// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 快捷入口（定稿方案 C：轻量列表，无卡片框）
//
// 只放"点了就发生"的动作；版本的加载器/占用等信息属于「概览」，不在这里重复。
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null

    function openDir(fn, okText) {
        if (!pane.b) return
        var ok = pane.b[fn](pane.versionId)
        if (pane.toast && okText) pane.toast.show(ok ? okText : "打开失败：版本目录不存在")
    }
    function copyText(t, okText) {
        if (!pane.b) return
        pane.b.copyToClipboard(t)
        if (pane.toast) pane.toast.show(okText)
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
            spacing: 0

            // ── 文件夹 ──
            Text {
                text: "文件夹"
                color: "#3f4753"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1.1
                bottomPadding: 6
            }
            Repeater {
                model: [
                    { label: "版本文件夹",   icon: "folder",     fn: "openVersionDir",       tip: "打开" },
                    { label: "存档文件夹",   icon: "box",        fn: "openSavesFolder",      tip: "打开" },
                    { label: "截图文件夹",   icon: "camera",     fn: "openScreenshotsFolder", tip: "打开" },
                    { label: "Mod 文件夹",   icon: "puzzle",     fn: "openModsFolder",       tip: "打开" }
                ]
                delegate: Item {
                    width: col.width
                    height: 44
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: "#0f131a"
                        opacity: hov.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                    }
                    SIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: modelData.icon
                        size: 15
                        color: "#5d6673"
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 35
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.tip
                        color: "#3f4753"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    HoverHandler { id: hov }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.openDir(modelData.fn, "已打开" + modelData.label)
                    }
                }
            }

            Item { width: 1; height: 18 }

            // ── 日志 ──
            Text {
                text: "日志"
                color: "#3f4753"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1.1
                bottomPadding: 6
            }
            Repeater {
                model: [
                    { label: "logs 日志",   icon: "folder",     fn: "openLogsFolder",  tip: "打开" },
                    { label: "最新启动日志", icon: "file-text",  fn: "openLatestLog",   tip: "打开" },
                    { label: "崩溃日志",     icon: "alert-octagon", fn: "openCrashLog", tip: "打开" }
                ]
                delegate: Item {
                    width: col.width
                    height: 44
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: "#0f131a"
                        opacity: hov2.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                    }
                    SIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: modelData.icon
                        size: 15
                        color: "#5d6673"
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 35
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.tip
                        color: "#3f4753"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    HoverHandler { id: hov2 }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.openDir(modelData.fn, "已打开" + modelData.label)
                    }
                }
            }

            Item { width: 1; height: 18 }

            // ── 其他 ──
            Text {
                text: "其他"
                color: "#3f4753"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1.1
                bottomPadding: 6
            }
            Repeater {
                model: [
                    { label: "复制版本路径", icon: "copy", tip: "复制" },
                    { label: "导出启动脚本", icon: "terminal", tip: "导出" }
                ]
                delegate: Item {
                    width: col.width
                    height: 44
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: "#0f131a"
                        opacity: hov3.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                    }
                    SIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: modelData.icon
                        size: 15
                        color: "#5d6673"
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 35
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.tip
                        color: "#3f4753"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    HoverHandler { id: hov3 }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (index === 0) {
                                var p = pane.b ? pane.b.copyVersionPath(pane.versionId) : ""
                                if (pane.toast) pane.toast.show(p ? "已复制版本路径" : "复制失败：版本不存在")
                            } else {
                                if (!pane.b) return
                                var s = pane.b.settings()
                                var out = pane.b.exportLaunchScript(
                                            pane.versionId, s.javaPath, s.maxMemoryMB,
                                            s.versionJvmArgs(pane.versionId),
                                            s.versionGameArgs(pane.versionId),
                                            s.versionHighPerfGpu(pane.versionId))
                                if (pane.toast)
                                    pane.toast.show(out && out.length > 0 ? "已导出启动脚本" : "导出失败：请检查 Java 是否就绪")
                            }
                        }
                    }
                }
            }
        }
    }
}
