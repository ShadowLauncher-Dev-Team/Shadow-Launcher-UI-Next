// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Window {
    id: appWindow
    visible: true
    flags: Qt.FramelessWindowHint | Qt.Window
    minimumWidth: 800
    minimumHeight: 550
    width: 1100
    height: 720
    title: "Shadow Launcher"
    color: "transparent"

    // --ui-size 800x550 预览指定尺寸（截图 / 验收用；受 minimumWidth/Height 约束）
    Component.onCompleted: {
        var args = Qt.application.arguments
        var i = args.indexOf("--ui-size")
        if (i < 0 || i + 1 >= args.length) return
        var parts = args[i + 1].toLowerCase().split("x")
        if (parts.length !== 2) return
        var w = parseInt(parts[0], 10)
        var h = parseInt(parts[1], 10)
        if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) return
        appWindow.width = Math.max(appWindow.minimumWidth, w)
        appWindow.height = Math.max(appWindow.minimumHeight, h)
        console.info("[ui] window size ->", appWindow.width, "x", appWindow.height)
    }

    StageShell {
        anchors.fill: parent
        hostWindow: appWindow
    }
}