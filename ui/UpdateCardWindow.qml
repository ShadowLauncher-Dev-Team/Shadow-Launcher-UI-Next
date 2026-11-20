// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Effects
import ShadowLauncher.Next

// 更新卡片预览窗口（2026-11-20）
//
// 为什么是独立窗口：真实的更新卡片由 SLUpdater 在桌面浮出（无边框、置顶），
// 不属于启动器窗口内部。要做"看到的和真实长相一致"的验收，预览也必须是
// 同样的形态：透明背景 + 置顶 + 可拖动，而不是塞在启动器页面里（会被别的窗口挡住）。
//
// 用法：ShadowLauncher.exe --ui-update-card
// 进度是假的（六档循环），不会触发任何更新、不会读写任何文件。
Window {
    id: win
    width: 360
    height: 96
    // 只有带 --ui-update-card 才显示。
    // 不能用 visible: win.mode 绑定：实测该绑定在 Component.onCompleted 前不生效（打印 visible=false），
    // 窗口被创建成隐藏且再也不会显示。改成 onCompleted 里显式赋值。
    property bool mode: false
    visible: false
    color: "transparent"
    // 不能用 Qt.Tool：工具窗口会跟着启动器主窗口一起被隐藏（主窗口最小化后卡片就没了，
    // 实测截图里卡片消失）。用独立顶层窗口 + 置顶，并且不抢焦点。
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    title: qsTr("更新卡片预览")

    property int step: 0
    property real progress: 0
    property bool indeterminate: true
    property string cardTitle: qsTr("正在安装更新")
    property string cardSub: qsTr("更新完成后将自动重启应用")
    property string phaseText: qsTr("正在等待旧版本退出…")

    readonly property var steps: [
        { "p": -1,  "title": qsTr("正在安装更新"), "sub": qsTr("更新完成后将自动重启应用"), "phase": qsTr("正在等待旧版本退出…") },
        { "p": 8,   "title": qsTr("正在安装更新"), "sub": qsTr("更新完成后将自动重启应用"), "phase": qsTr("正在更新文件…") },
        { "p": 25,  "title": qsTr("正在安装更新"), "sub": qsTr("更新完成后将自动重启应用"), "phase": qsTr("正在更新文件…") },
        { "p": 62,  "title": qsTr("正在安装更新"), "sub": qsTr("更新完成后将自动重启应用"), "phase": qsTr("正在更新文件…") },
        { "p": 87,  "title": qsTr("正在安装更新"), "sub": qsTr("更新完成后将自动重启应用"), "phase": qsTr("正在更新文件…") },
        { "p": 100, "title": qsTr("正在启动新版本"), "sub": qsTr("即将自动回到启动器"),       "phase": qsTr("更新完成，正在启动…") }
    ]

    function applyStep(i) {
        var s = win.steps[i]
        win.step = i
        win.indeterminate = (s.p < 0)
        win.progress = (s.p < 0) ? 0 : s.p / 100.0
        win.cardTitle = s.title
        win.cardSub = s.sub
        win.phaseText = s.phase
    }

    Component.onCompleted: {
        console.info("[卡片预览] mode=" + win.mode)
        if (!win.mode) return
        win.visible = true
        // 屏幕居中
        var scr = win.screen
        if (scr) {
            win.x = Math.round(scr.virtualX + (scr.width - win.width) / 2)
            win.y = Math.round(scr.virtualY + (scr.height - win.height) / 2)
        }
        win.applyStep(0)
        stepTimer.restart()
        console.info("[卡片预览] 窗口已创建 rect=" + win.x + "," + win.y + " " + win.width + "x" + win.height + " visible=" + win.visible)
        win.requestActivate()
    }

    Timer {
        id: stepTimer
        interval: 1800
        repeat: true
        running: false
        onTriggered: win.applyStep((win.step + 1) % win.steps.length)
    }

    // 整张卡可拖动（与真实卡片一致：没有标题栏也能挪）
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: win.startSystemMove()
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 14
        color: Theme.bgRaised
        border.width: 1
        border.color: Theme.line2

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 0.55
            shadowVerticalOffset: 10
            shadowOpacity: 0.55
        }
    }

    // 启动器图标（圆角裁切）
    Rectangle {
        x: 16
        y: 16
        width: 30
        height: 30
        radius: 8
        color: Theme.bg
        border.width: 1
        border.color: Theme.line2
        clip: true

        Image {
            anchors.fill: parent
            source: "qrc:/ui/app-icon.png"
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
        }
    }

    Text {
        x: 59
        y: 11
        width: 285
        text: win.cardTitle
        color: Theme.fg
        font.pixelSize: 14
        font.bold: true
        elide: Text.ElideRight
    }

    Text {
        x: 59
        y: 32
        width: 285
        text: win.cardSub
        color: Theme.fg2
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    Rectangle {
        id: track
        x: 16
        y: 58
        width: 328
        height: 3
        radius: 1.5
        color: Theme.line2
        clip: true

        Rectangle {
            height: parent.height
            radius: parent.radius
            width: win.indeterminate ? 0 : Math.max(0, track.width * win.progress)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.accentBot }
                GradientStop { position: 1.0; color: Theme.accentTop }
            }
            Behavior on width {
                NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
            }
        }

        Rectangle {
            id: marqueeBar
            visible: win.indeterminate
            height: parent.height
            radius: parent.radius
            width: track.width * 0.35
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.accentBot }
                GradientStop { position: 1.0; color: Theme.accentTop }
            }
            x: -width
            NumberAnimation on x {
                running: win.indeterminate
                loops: Animation.Infinite
                from: -marqueeBar.width
                to: track.width
                duration: Theme.marquee
            }
        }
    }

    Text {
        x: 16
        y: 69
        width: 250
        text: win.phaseText
        color: Theme.fg3
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    Text {
        x: 16
        y: 69
        width: 328
        horizontalAlignment: Text.AlignRight
        text: win.indeterminate ? qsTr("…")
                                : (win.progress >= 1 ? qsTr("完成")
                                                     : Math.round(win.progress * 100) + "%")
        color: Theme.fg2
        font.pixelSize: 11
    }
}
