// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Window {
    id: appWindow
    visible: true
    flags: Qt.FramelessWindowHint | Qt.Window
    // 无边框窗口没有可拖拽的边界，用户本来就调不了尺寸，所以不设 minimumWidth/minimumHeight
    // （2026-11-25：旧代码留了个 800×550 的"最小尺寸"，只为小屏收口和 --ui-size 测试钩子服务，
    //  反而制造出一整类"窄屏破版"的假缺陷）。
    width: 1100
    height: 720
    title: "Shadow Launcher"
    // 窗口底色必须是**不透明的深色**，不能是 transparent：
    // 无边框 + DWM 圆角下，回退动画里内容会短暂留出 1~3px 的缝（位移/缩放各留一条），
    // 透明窗口在这些缝上露的是桌面/别的窗口 —— 用户看到的就是「一圈白边」。
    // 换成深色实底后，同样的缝露的是自己的底色，肉眼不可见；圆角仍由 DWM 裁，不受影响。
    color: "#08090d"

    // 首帧渲染完成由 C++ 置 true（main_release 的 frameSwapped）——
    // 启动动画必须等这一刻才开演，否则会在 QML 同步构建期间被"快进"掉。
    property bool firstFrame: false

    // 窗口尺寸：默认就是设计稿的 1100x720，不按屏幕缩。
    // 只有屏幕明显放不下（逻辑高 < 640 / 宽 < 1000）时才收口，避免小屏笔记本不可用；
    // 不要为了个别元素被裁就改全局默认尺寸。
    //
    // 注意：Qt 6 里 Screen.width / Screen.height 已经是**逻辑像素**（device-independent），
    // 绝对不能再除一次 devicePixelRatio——那会把屏幕缩两遍，1440p@150% 的机器会永远开小窗。
    Component.onCompleted: {
        var scr = appWindow.screen
        var dpr = (scr && scr.devicePixelRatio) ? scr.devicePixelRatio : 1
        var lw = (scr && scr.width) ? Math.floor(scr.width) : 0
        var lh = (scr && scr.height) ? Math.floor(scr.height) : 0
        // 所有数值都要校验——算出 NaN 会让窗口变成 0x0 直接不可见。
        if (lw > 0 && lh > 0) {
            if (lh < 640) appWindow.height = lh - 40
            if (lw < 1000) appWindow.width = lw - 40
            console.info("[ui] screen logical", lw, "x", lh, "(dpr", dpr + ")",
                         "-> win", appWindow.width, "x", appWindow.height)
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
        appWindow.width = w
        appWindow.height = h
        console.info("[ui] window size ->", appWindow.width, "x", appWindow.height)
    }

    StageShell {
        anchors.fill: parent
        hostWindow: appWindow
    }

    // 启动动画（方案 A）。盖在外壳上面，首帧上屏后自己演完、自己隐藏。
    // 关掉的条件（--no-intro / 系统减少动画 / 设置项）在 C++ 那边统一判定，这里只看 startupIntro。
    StartupIntro {
        anchors.fill: parent
        hostWindow: appWindow
        enabled: startupIntro
        firstFrame: appWindow.firstFrame
    }

    // 更新卡片预览（--ui-update-card）：独立置顶透明窗口，与真实安装卡片同形态。
    // 必须直接实例化同模块类型：用 Loader { source: "UpdateCardWindow.qml" } 会报
    // "No such file or directory"（qrc 模块内相对 URL 不按文件路径解析）。
    UpdateCardWindow {
        mode: Qt.application.arguments.indexOf("--ui-update-card") >= 0
    }
}