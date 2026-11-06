// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// Toast 通知栈（右下角，独立于页面布局）
// 为什么需要它：以前"刷新/已切换文件夹"这类反馈是往顶栏塞一段绿色文字，
// 一出现就把右侧按钮挤走（控件错位），而且只能出现在顶栏不能出现在别处。
//
// API 与旧 UI 的 ToastManager 对齐：
//   show(msg) / show(msg, duration) / show(msg, duration, style)
//   showAction(msg, onAction[, style])            // 常驻可点
// style: "info"（蓝）| "warning"（橙）| "success"（绿）
Item {
    id: root
    // 压在窗口按钮之上（toast 在右下角，二者不重叠，但保险）
    z: 2000

    property int defaultDuration: 2600
    property int maxToasts: 4
    property int edgeMargin: 16

    property var _handlers: ({})
    property int _nextId: 0

    signal toastClicked(string message)

    // 同一件事可能被两处同时播报（下载完成 / 安装完成），用"主题"去重：
    // 去掉结尾的完成/失败字样后，5 秒内同主题只弹第一条。
    property var _recent: ({})
    function _subjectOf(msg) {
        return String(msg).replace(/\s*(下载完成|安装完成|下载失败|安装失败)$/, "")
    }
    function _seenRecently(msg) {
        var key = root._subjectOf(msg)
        var now = Date.now()
        var prev = root._recent[key] || 0
        var m = {}
        for (var k in root._recent) if (now - root._recent[k] < 6000) m[k] = root._recent[k]
        m[key] = now
        root._recent = m
        return prev > 0 && (now - prev) < 5000
    }
    function show(message, duration, style) {
        if (root._seenRecently(message)) return
        root.add(message, duration, style, null)
    }

    function showAction(message, onAction, style) {
        root.add(message, 0, style, onAction)
    }

    function add(message, duration, style, onAction) {
        if (!message || message.length === 0) return
        var life = (duration === undefined || duration === null) ? root.defaultDuration : duration
        if (life < 0) life = root.defaultDuration
        var tid = root._nextId++
        // 太长会横向撑满，截断（详情去日志里看）
        var msg = message.length > 160 ? message.substring(0, 160) + "…" : message
        toastModel.insert(0, {
            tid: tid,
            msg: msg,
            life: life,
            style: style || "info",
            clickable: onAction !== null
        })
        if (onAction !== null) root._handlers[tid] = onAction
        // 超过上限丢最老的
        while (toastModel.count > root.maxToasts)
            toastModel.remove(toastModel.count - 1)
    }

    function removeToast(tid) {
        for (var i = 0; i < toastModel.count; ++i) {
            if (toastModel.get(i).tid === tid) { toastModel.remove(i); return }
        }
    }

    function _click(tid, msg) {
        var h = root._handlers[tid]
        if (h) { delete root._handlers[tid]; h() }
        root.toastClicked(msg)
        root.removeToast(tid)
    }

    ListModel { id: toastModel }

    Column {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.edgeMargin
        // 抬高 56px：页面右下角通常有主操作按钮（如版本页「确定」），toast 不能压在上面
        anchors.bottomMargin: root.edgeMargin + 56
        spacing: 8

        Repeater {
            model: toastModel

            delegate: Item {
                id: wrap
                width: pill.width
                height: 34

                readonly property bool isWarning: model.style === "warning"
                readonly property bool isSuccess: model.style === "success"
                readonly property color barColor: isWarning ? Theme.warn
                                                : (isSuccess ? Theme.ok : Theme.accent)

                opacity: 0
                // 入场：从右滑进 + 轻微过冲放大（"弹"出来），出栈仍走快速淡出
                scale: 0.94
                transform: Translate {
                    id: shift
                    x: 14
                }

                Component.onCompleted: enterAnim.start()

                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: Theme.durBase; easing.type: Theme.easeEnter }
                    NumberAnimation { target: shift; property: "x"; to: 0; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: wrap; property: "scale"; to: 1; duration: Theme.durPage; easing.type: Theme.easePop }
                }

                // 出栈：横向滑回 + 淡出，动画结束才真正从 model 删除（否则会硬切）
                function dismiss() { if (!closing) exitAnim.start() }
                property bool closing: false
                ParallelAnimation {
                    id: exitAnim
                    NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: Theme.durFast; easing.type: Theme.easeExit }
                    NumberAnimation { target: shift; property: "x"; to: 14; duration: Theme.durFast; easing.type: Theme.easeExit }
                    NumberAnimation { target: wrap; property: "scale"; to: 0.96; duration: Theme.durFast; easing.type: Theme.easeExit }
                    onStarted: wrap.closing = true
                    onFinished: root.removeToast(model.tid)
                }

                Timer {
                    interval: model.life
                    running: model.life > 0
                    repeat: false
                    onTriggered: wrap.dismiss()
                }

                Rectangle {
                    id: pill
                    height: 34
                    radius: Theme.rSm
                    width: Math.min(toastText.implicitWidth + 34, 420)
                    color: toastMouse.containsMouse && model.clickable ? "#1b222c" : "#141a23"
                    border.width: 1
                    border.color: "#242c38"

                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                    }

                    // 左侧样式条
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        radius: 1
                        color: wrap.barColor
                    }

                    Text {
                        id: toastText
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.msg
                        color: "#d8dde5"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    MouseArea {
                        id: toastMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: model.clickable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._click(model.tid, model.msg)
                    }
                }
            }
        }
    }
}
