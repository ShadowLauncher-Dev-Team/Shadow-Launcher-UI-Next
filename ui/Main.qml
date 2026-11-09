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

    // 窗口尺寸：默认就是设计稿的 1100x720，不按屏幕缩。
    // 曾经为了"导出条不被裁到屏幕外"在这里做了 min(720, 屏高-40)，结果整台机器一进来窗口就矮了 69px，
    // 影直接发现了——这是拿全局默认尺寸去补一个局部问题，代价太大，撤掉。
    // 只有屏幕小到明显放不下（逻辑高 < 640 / 宽 < 1000）时才收口，避免小屏笔记本完全不可用。
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
            if (lh < 640) appWindow.height = Math.max(appWindow.minimumHeight, lh - 40)
            if (lw < 1000) appWindow.width = Math.max(appWindow.minimumWidth, lw - 40)
            console.info("[ui] window phys", pw, "x", ph, "dpr", dpr,
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