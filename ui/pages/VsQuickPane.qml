// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置 · 快捷入口（定稿方案 C：轻量列表，无卡片框）
//
// 只放"点了就发生"的动作；版本的加载器/占用等信息属于「概览」，不在这里重复。
//
// 动效（克制）：
//   入场：整行淡入 + 上浮 6px，staggerStep 错峰、staggerMax 封顶，durSlow + easeEnter
//   hover：底色 + 图标/文字颜色，只改颜色不做位移，durFast + easeStandard
//   按下：整个瓦片 0.98 → 1，durPress + easePop，只做按下这一下
//   入场必须作用在行容器上 —— 行内矩形已经绑了 hover 的 opacity，同一元素再叠一层就是两次淡入
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
        if (pane.toast) pane.toast.show(ok ? okText : (failText || qsTr("打开失败")), -1, ok ? "info" : "error", true)
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

        // 点内容空白处清焦点。必须挂在 Flickable 自己身上：
        // 页面根层收不到（这个 Flickable 铺满内容区、会吃掉 press），挂在子项上又会挡拖拽。
        // tap 与 drag 不冲突：只有按下抬起位置基本不变的点击才触发。
        TapHandler {
            onTapped: pane.forceActiveFocus()
        }

        Column {
            id: col
            x: 28
            y: 22
            width: Math.max(360, pane.width - 56)
            spacing: 0

            // ── 文件夹 ──
            Text {
                text: qsTr("文件夹")
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1.1
                bottomPadding: 6
            }
            Repeater {
                model: [
                    { label: qsTr("版本文件夹"),   icon: "folder",     fn: "openVersionDir",       tip: qsTr("打开") },
                    { label: qsTr("存档文件夹"),   icon: "box",        fn: "openSavesFolder",      tip: qsTr("打开") },
                    { label: qsTr("截图文件夹"),   icon: "camera",     fn: "openScreenshotsFolder", tip: qsTr("打开") },
                    { label: qsTr("Mod 文件夹"),   icon: "puzzle",     fn: "openModsFolder",       tip: qsTr("打开") }
                ]
                delegate: QuickTile {
                    width: col.width
                    order: index
                    label: modelData.label
                    iconName: modelData.icon
                    tipText: modelData.tip
                    onActivated: pane.openDir(modelData.fn, qsTr("已打开 %1").arg(modelData.label), modelData.fail)
                }
            }

            Item { width: 1; height: 18 }

            // ── 日志 ──
            Text {
                text: qsTr("日志")
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1.1
                bottomPadding: 6
            }
            Repeater {
                model: [
                    { label: qsTr("logs 日志"),   icon: "folder",     fn: "openLogsFolder",  tip: qsTr("打开") },
                    { label: qsTr("最新启动日志"), icon: "file-text",  fn: "openLatestLog",   tip: qsTr("打开") },
                    { label: qsTr("崩溃日志"),     icon: "alert-octagon", fn: "openCrashLog", tip: qsTr("打开"), fail: qsTr("这个版本还没有崩溃日志") }
                ]
                delegate: QuickTile {
                    // 行号接着上一组往下排，整页是一条连续波浪，不按分组重新计时
                    width: col.width
                    order: 4 + index
                    label: modelData.label
                    iconName: modelData.icon
                    tipText: modelData.tip
                    onActivated: pane.openDir(modelData.fn, qsTr("已打开 %1").arg(modelData.label), modelData.fail)
                }
            }

            Item { width: 1; height: 18 }

            // ── 其他 ──
            Text {
                text: qsTr("其他")
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1.1
                bottomPadding: 6
            }
            Repeater {
                model: [
                    { label: qsTr("复制版本路径"), icon: "copy", tip: qsTr("复制") },
                    { label: qsTr("导出启动脚本"), icon: "terminal", tip: qsTr("导出") }
                ]
                delegate: QuickTile {
                    width: col.width
                    order: 7 + index
                    label: modelData.label
                    iconName: modelData.icon
                    tipText: modelData.tip
                    onActivated: {
                        if (index === 0) {
                            var p = pane.b ? pane.b.copyVersionPath(pane.versionId) : ""
                            if (pane.toast) pane.toast.show(p ? qsTr("已复制版本路径") : qsTr("复制失败：版本不存在"))
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
                                    pane.toast.show(qsTr("导出失败：请检查 Java 是否就绪"), -1, "error", true)
                                return
                            }
                            pane.pendingExport = scriptText
                        }
                    }
                }
            }
        }
    }
    FileDialog {
        id: exportDialog
        title: qsTr("导出启动脚本")
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
                pane.toast.show(ok ? qsTr("已导出到 %1").arg(target) : qsTr("保存失败，请换一个位置再试"), -1, ok ? "info" : "error", true)
        }
        onRejected: pane.pendingExport = null
    }

    // ── 快捷入口行 ───────────────────────────────────────────
    // 三个分组共 9 行是同一套皮：布局与改动前逐像素一致，只把 hover / 按下 / 入场收在一处，
    // 免得三份 delegate 各写一套动效，以后改一处漏两处。
    component QuickTile: Item {
        id: tile
        property string label: ""
        property string iconName: "folder"
        property string tipText: qsTr("打开")
        // 全页连续行号（文件夹 0-3 / 日志 4-6 / 其他 7-8），入场按它错峰
        property int order: 0
        signal activated()

        height: 44

        // 按下：只做这一下。0.98 用 easePop 回弹，durPress 按下即到位
        scale: pressArea.pressed ? 0.98 : 1
        Behavior on scale {
            NumberAnimation { duration: Theme.durPress; easing.type: Theme.easePop }
        }

        // 入场：整行淡入 + 上浮 6px。位移走 Translate 而不是 item.y ——
        // 行由 Column 定位，直接动 y 会被 positioner 覆盖；Translate 不参与布局。
        property bool shown: false
        opacity: tile.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
        }
        transform: Translate {
            y: tile.shown ? 0 : 6
            Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
        }
        Timer {
            interval: Math.min(tile.order, Theme.staggerMax) * Theme.staggerStep
            running: true
            onTriggered: tile.shown = true
        }

        // hover 底色：保留原来的 opacity 过渡，补上 easeStandard
        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Theme.bgCard2
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
            }
        }
        SIcon {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            name: tile.iconName
            size: 15
            color: hover.hovered ? Theme.fg2 : Theme.fg3
            Behavior on color {
                ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
            }
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 35
            anchors.verticalCenter: parent.verticalCenter
            text: tile.label
            color: hover.hovered ? Theme.fg : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 13
            Behavior on color {
                ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: tile.tipText
            color: hover.hovered ? Theme.fg2 : Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
            Behavior on color {
                ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
            }
        }
        HoverHandler { id: hover }
        MouseArea {
            id: pressArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }
}
