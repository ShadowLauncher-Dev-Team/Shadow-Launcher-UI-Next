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

    // 默认尺寸不能超出可用屏幕：1100x720 在 125% 缩放下是 1375x900 物理像素，
    // 1080p 屏上窗口底部（导出条里的路径/开始导出）会被裁到屏幕外，点都点不到。
    Component.onCompleted: {
        // Window.screen 的 availableWidth/Height 在 Qt6 里可能是 undefined，用物理尺寸 / devicePixelRatio 换算，
        // 且所有数值都要校验——算出 NaN 会让窗口变成 0x0 直接不可见。
        var scr = appWindow.screen
        var dpr = (scr && scr.devicePixelRatio) ? scr.devicePixelRatio : 1
        var pw = (scr && scr.width) ? scr.width : 0
        var ph = (scr && scr.height) ? scr.height : 0
        if (pw > 0 && ph > 0 && dpr > 0) {
            var lw = Math.floor(pw / dpr)
            var lh = Math.floor(ph / dpr)
            // 留 40 逻辑像素给任务栏/标题区：1100x720 在 125% 缩放下是 1375x900 物理，1080p 屏底部会被裁
            appWindow.width = Math.min(1100, Math.max(800, lw - 40))
            appWindow.height = Math.min(720, Math.max(550, lh - 40))
            console.info("[ui] window fit phys", pw, "x", ph, "dpr", dpr,
                         "-> logical", lw, "x", lh, "-> win", appWindow.width, "x", appWindow.height)
        } else {
            console.info("[ui] window fit skipped, keep", appWindow.width, "x", appWindow.height)
        }

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