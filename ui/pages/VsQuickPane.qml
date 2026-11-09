// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 快捷入口（定稿方案 C：轻量列表，无卡片框）
//
// 只放"点了就发生"的动作；版本的加载器/占用等信息属于「概览」，不在这里重复。
import QtQuick
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property var toast: null
    property var pendingExport: null

    readonly property var b: (typeof backend !== "undefined") ? backend : null

    // force=true：这是用户主动点的，连点第二次也必须给反馈（ToastHost 默认 5 秒同文去重）
    function openDir(fn, okText, failText) {
        if (!pane.b) return
        var ok = pane.b[fn](pane.versionId)
        if (pane.toast) pane.toast.show(ok ? okText : (failText || "打开失败"), -1, ok ? "info" : "error", true)
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
                        onClicked: pane.openDir(modelData.fn, "已打开" + modelData.label, modelData.fail)
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
                    { label: "崩溃日志",     icon: "alert-octagon", fn: "openCrashLog", tip: "打开", fail: "这个版本还没有崩溃日志" }
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
                        onClicked: pane.openDir(modelData.fn, "已打开" + modelData.label, modelData.fail)
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
                                var scriptText = pane.b.exportLaunchScript(
                                            pane.versionId, s.javaPath, s.maxMemoryMB,
                                            s.versionJvmArgs(pane.versionId),
                                            s.versionGameArgs(pane.versionId),
                                            s.versionHighPerfGpu(pane.versionId))
                                if (!scriptText || scriptText.length === 0) {
                                    if (pane.toast)
                                        pane.toast.show("导出失败：请检查 Java 是否就绪", -1, "error", true)
                                    return
                                }
                                pane.pendingExport = scriptText
                            }
                        }
                    }
                }
            }
        }
    }
    FileDialog {
        id: exportDialog
        title: "导出启动脚本"
        fileMode: FileDialog.SaveFile
        nameFilters: ["批处理脚本 (*.bat)"]
        defaultSuffix: "bat"
        onAccepted: {
            var text = pane.pendingExport
            if (!pane.b || !text) return
            var target = String(selectedFile).replace(/^file:\/\//, "")
            var ok = pane.b.saveTextFile(target, text)
            pane.pendingExport = null
            if (pane.toast)
                pane.toast.show(ok ? "已导出到 " + target : "保存失败，请换一个位置再试", -1, ok ? "info" : "error", true)
        }
        onRejected: pane.pendingExport = null
    }
}
