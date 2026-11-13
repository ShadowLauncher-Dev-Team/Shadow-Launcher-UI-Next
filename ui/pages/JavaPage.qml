// SPDX-License-Identifier: AGPL-3.0-or-later
// 下载页 · Java Tab（2026-11-07 第一版：结构先落地，动效后续加）
//
// 交互：按旧 UI 的五步级联思路，做成"逐级抵近"——
//   ①版本 → ②JRE/JDK → ③架构 → ④系统 → ⑤分发形式（ZIP/ MSI）
// 已选步骤在下方卡片栈里收成一行（带「修改」），当前步骤展开；架构/系统按本机自动预选，可改。
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import ShadowLauncher.Next

Item {
    id: page

    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var java: b ? b.javaBackend : null

    // ── 选择状态 ──
    property int step: 0                 // 0..4，5 == 完成（显示文件卡）
    property string selVersion: ""
    property string selType: ""
    property string selArch: ""
    property string selOS: ""

    // ── 本机已装（系统扫描 + java_cache） ──
    property var detected: []
    property var cached: []
    property bool scanning: false
    property bool scanToastPending: false

    // ── 下载/安装状态 ──
    property string installingMajor: ""
    property string installStatus: ""
    // MSI：保存到用户选的目录
    property string pendingMsiUrl: ""
    property string pendingMsiName: ""
    property real pendingMsiSize: 0
    property bool msiBusy: false
    property int msiPct: 0
    property real msiSpeed: 0
    property string msiSavedPath: ""
    property string transLabel: ""    // 传输条标题快照（重选后 selVersion 会被清空，不能现拼）

    // ── 动效状态（与资源库/下载页同一套语言） ──
    property real reveal: 1        // 当前步骤内容的入场进度（0..1）
    property real enter: 0         // 整页进场进度（0..1）
    property int stepTick: 0       // 步进节拍

    // 传输条用：只要有任务在跑就算忙（重选会清空 selVersion，不能再比对它）
    readonly property bool zipBusy: installingMajor.length > 0
    readonly property bool zipInstalling: zipBusy && (selVersion.length === 0 || installingMajor === selVersion)
    readonly property bool anyBusy: installingMajor.length > 0 || msiBusy

    readonly property var stepNames: [qsTr("Java 版本"), "JRE / JDK", qsTr("CPU 架构"), qsTr("操作系统"), qsTr("分发形式")]
    readonly property var stepHints: [
        qsTr("选启动器/游戏需要的主版本。拿不准就选 17——覆盖目前绝大多数整合包与 Forge。"),
        qsTr("JDK 含 JRE 与编译工具；JRE 只有运行环境。启动器一键安装用 JDK（JRE 缺少 jdk.crypto.ec，部分加载器会崩）。"),
        qsTr("绝大多数机器是 x64。32 位系统选 x32；注意 Java 21 及以上没有 32 位版本。"),
        qsTr("选择你的操作系统。"),
        qsTr("便携版（ZIP）解压后由启动器托管，不写注册表；安装版（MSI）装进系统并写入 PATH / JAVA_HOME。")
    ]

    // ── 生命周期 ──
    function refreshLocal() {
        if (!java) return
        if (scanning) return
        scanning = true
        // 扫描是异步的（内部并发探测每个 java.exe），完成时 emit systemJavaScanFinished
        detected = java.scanSystemJavas()
        cached = java.javaCacheRuntimes()
    }

    // 扫描完成：结束 scanning 态；用户手动点过就回一句 toast
    function finishScan() {
        detected = java.detectedSystemJavas()
        cached = java.javaCacheRuntimes()
        scanning = false
        if (scanToastPending) {
            scanToastPending = false
            if (toast) toast.show(qsTr("已重新扫描：%1 个运行时").arg(localChips().length))
        }
    }

    function resetChoices() {
        step = 0
        selVersion = ""
        selType = ""
        selArch = ""
        selOS = ""
        if (java) { java.selectedVersion = ""; java.selectedType = ""; java.selectedArch = ""; java.selectedOS = "" }
    }

    // 架构 / 系统自动预选（后端给了 cpuArch，系统已知是 Windows）
    function autoPickArchOs() {
        if (!java) return
        if (selArch.length === 0 && java.javaArchs.length > 0) {
            var want = java.cpuArch
            if (want === "aarch64") want = "x64"
            selArch = java.javaArchs.indexOf(want) >= 0 ? want : java.javaArchs[0]
            java.selectedArch = selArch
        }
        if (selOS.length === 0 && java.javaOSes.length > 0) {
            selOS = java.javaOSes.indexOf("windows") >= 0 ? "windows" : java.javaOSes[0]
            java.selectedOS = selOS
        }
    }

    function pickVersion(v) {
        selVersion = v
        selType = ""; selArch = ""; selOS = ""
        step = 1
        java.selectedVersion = v
    }

    function pickType(t) {
        selType = t
        selArch = ""; selOS = ""
        step = 2
        java.selectedType = t
        autoPickArchOs()
    }

    function pickArch(a) {
        selArch = a
        selOS = ""
        step = 3
        java.selectedArch = a
    }

    function pickOs(o) {
        selOS = o
        step = 4
        java.selectedOS = o
    }

    function jumpTo(i) {
        // 回到某一步：这一步之后的选择全部作废（含这一步本身），rail 文案随之回到初始
        if (i <= 0) { resetChoices(); return }
        if (i <= 1) { selType = ""; if (java) java.selectedType = "" }
        if (i <= 2) { selArch = ""; if (java) java.selectedArch = "" }
        if (i <= 3) { selOS = ""; if (java) java.selectedOS = "" }
        step = i
    }

    function majorOfVersion(v) { return parseInt(v) || 0 }

    // ── 传输条（ZIP 安装 / MSI 保存共用一条，永不随换步消失）──
    function transferName() {
        if (anyBusy && transLabel.length > 0) return transLabel
        if (zipBusy) return qsTr("Java %1 · 便携版（ZIP）").arg(selVersion)
        if (msiBusy) return pendingMsiName.length > 0 ? pendingMsiName : qsTr("MSI 安装包")
        return ""
    }
    function transferPct() {
        if (zipBusy) return java ? java.javaDownloadPercent : 0
        return msiBusy ? msiPct : 0
    }
    function transferSpeed() {
        if (zipBusy) return java ? java.javaDownloadSpeedMBps : 0
        return msiBusy ? msiSpeed : 0
    }
    function transferCancel() {
        if (zipBusy) {
            if (java) java.cancelJavaInstall()
            installingMajor = ""
            installStatus = ""
            transLabel = ""
            return
        }
        if (msiBusy) {
            if (java) java.cancelDownload()
            msiBusy = false
            transLabel = ""
        }
    }

    function startZipInstall(fileName) {
        if (!java || anyBusy) return
        var major = majorOfVersion(selVersion)
        if (major <= 0) return
        installingMajor = selVersion
        transLabel = qsTr("Java %1 · %2 · %3 · 便携版（ZIP）").arg(selVersion).arg(selType.length > 0 ? String(selType).toUpperCase() : "JDK").arg(selArch)
        installStatus = qsTr("正在下载 Java %1…").arg(selVersion)
        java.installJavaRuntime(major, selType.length > 0 ? selType : "jdk", selArch)
    }

    function askMsiSave(url, name, size) {
        if (anyBusy) return
        pendingMsiUrl = url
        pendingMsiName = name
        pendingMsiSize = size
        msiPct = 0
        msiSpeed = 0
        msiSavedPath = ""
        msiDialog.currentFile = "file:///" + (java && java.installDir ? java.installDir() : "") + "/" + name
        msiDialog.open()
    }

    Component.onCompleted: refreshLocal()

    // 进入 Java 页：整页淡入 + 8px 上浮，内容不抢在边框之前出现
    onVisibleChanged: {
        if (visible) { enter = 0; pageIn.restart() }
    }

    NumberAnimation {
        id: pageIn
        target: page
        property: "enter"
        from: 0
        to: 1
        duration: Theme.durPage
        easing.type: Theme.easeEnter
    }

    // 换步：内容轻轻浮现（从 0.6 起淡入，不从 0 起 —— 从 0 会有 1 帧全透明，观感是"闪一下"）
    onStepChanged: {
        stepTick++
        if (step === 0) { reveal = 1; return }
        cardIn.restart()
    }

    NumberAnimation {
        id: cardIn
        target: page
        property: "reveal"
        from: 0.6
        to: 1
        duration: Theme.durBase
        easing.type: Theme.easeEnter
    }

    Connections {
        target: page.java
        enabled: page.java !== null
        function onJavaInstallStateChanged() {
            if (!page.java) return
            page.installingMajor = page.java.installingMajor
            page.installStatus = page.java.installStatusText
            if (page.installingMajor.length === 0) { page.transLabel = ""; page.refreshLocal() }
        }
        function onJavaCacheListChanged() { page.refreshLocal() }
        function onSystemJavaScanFinished() { page.finishScan() }
        function onJavaArchsChanged() { page.autoPickArchOs() }
        function onJavaOSesChanged() { page.autoPickArchOs() }
        function onDownloadProgress(pct, dl, total, speed) {
            if (!page.msiBusy) return
            page.msiPct = pct
            page.msiSpeed = speed
        }
        function onDownloadFinished(ok, path) {
            if (!page.msiBusy) return
            page.msiBusy = false
            page.msiPct = 100
            if (ok) {
                page.msiSavedPath = path
                if (page.toast) page.toast.show(qsTr("已保存到 %1").arg(path))
            } else {
                if (page.toast) page.toast.show(qsTr("下载失败"))
            }
        }
    }

    FileDialog {
        id: msiDialog
        title: qsTr("选择 MSI 保存位置")
        fileMode: FileDialog.SaveFile
        nameFilters: ["Windows 安装包 (*.msi)", "所有文件 (*)"]
        onAccepted: {
            var p = page.urlToPath(selectedFile)
            page.msiBusy = true
            page.msiPct = 0
            page.transLabel = page.pendingMsiName
            if (page.java) page.java.downloadJavaFileToPath(page.pendingMsiUrl, p, page.pendingMsiSize)
        }
    }

    function urlToPath(u) {
        var s = String(u)
        if (s.indexOf("file:///") === 0) s = s.substring(8)
        return s
    }

    // ══════════ 布局 ══════════
    // 内容可滚动：第 5 步文件多时不会顶到下方「本机已检测到」卡片
    Flickable {
        id: scrollArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: localCard.top
        anchors.bottomMargin: 14
        clip: true
        contentWidth: width
        contentHeight: topCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

    Column {
        id: topCol
        width: scrollArea.width
        spacing: 0
        opacity: page.enter
        transform: Translate { y: (1 - page.enter) * 8 }

        // ── 步骤条 ──
        Item {
            id: rail
            width: parent.width
            height: 52

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Repeater {
                    model: 5
                    delegate: Item {
                        readonly property bool last: index === 4
                        width: rail.width / 5
                        height: 40

                        Row {
                            id: nodeRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            z: 1
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                color: page.step > index ? Theme.accent
                                     : page.step === index ? Theme.bgCard2 : "transparent"
                                border.width: 1
                                border.color: page.step > index ? Theme.accent
                                            : page.step === index ? Theme.accent : Theme.bgHover
                                // 状态切换走颜色过渡，不再硬切
                                Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                                Behavior on border.color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                                Text {
                                    anchors.centerIn: parent
                                    text: (index + 1)
                                    color: page.step > index ? Theme.accentFg
                                         : page.step === index ? Theme.accent : Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                                }
                            }
                            Text {
                                id: nodeLabel
                                anchors.verticalCenter: parent.verticalCenter
                                // 固定宽度：文案随选择变长变短（"Java 版本" → "25"）时，连线起点不动
                                width: 68
                                elide: Text.ElideRight
                                text: page.stepValue(index)
                                color: page.step >= index ? Theme.fg : Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: page.step === index ? Font.DemiBold : Font.Normal
                                Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                            }
                        }

                        // 连接到下一个节点：已走过/当前段 = 蓝色细线，未到 = 深灰细线（不放光效）
                        Item {
                            id: wire
                            visible: !parent.last
                            anchors.verticalCenter: parent.verticalCenter
                            // 连线几何全部用常量：圆点 18 + 间距 8 + 标签 68 + 左右各 12 → 每段线长度、位置完全一致
                            x: 18 + 8 + 68 + 12
                            width: Math.max(18, parent.width - (18 + 8 + 68 + 12) - 12)
                            height: 16

                            readonly property bool done: page.step > index
                            readonly property bool active: page.step === index

                            // 底色线：变蓝/变亮都走过渡（换步时这一段像被"填"上）
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 1
                                color: (wire.done || wire.active) ? Theme.accent : Theme.bgInput
                                opacity: wire.done ? 0.55 : (wire.active ? 0.9 : 1)
                                Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                                Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                            }

                        }
                    }
                }
            }
        }



        // ── 传输中常驻条：换步、重选都不受影响，进度不会丢（这里也能取消）──
        Rectangle {
            id: transferStrip
            width: parent.width
            height: page.anyBusy ? 46 : 0
            visible: height > 1
            radius: Theme.rMd
            color: Theme.bgCard2
            border.width: 1
            border.color: Theme.accentSoft
            clip: true
            opacity: page.anyBusy ? 1 : 0
            Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
            Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: stripRight.left
                anchors.rightMargin: 12
                text: page.transferName()
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }

            Row {
                id: stripRight
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(page.transferPct()) + "% · " + page.transferSpeed().toFixed(1) + " MB/s"
                    color: Theme.accentText
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                Rectangle {
                    id: cancelBtn
                    property bool hovered: false
                    property bool pressed: false
                    height: 22
                    width: cancelText.implicitWidth + 16
                    radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: hovered ? Theme.bgCard : "transparent"
                    border.width: 1
                    border.color: hovered ? Theme.bgHover : Theme.line2
                    scale: pressed ? 0.96 : 1
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Behavior on scale { NumberAnimation { duration: Theme.durPress; easing.type: Theme.easePop } }
                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: qsTr("取消")
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: cancelBtn.hovered = true
                        onExited: cancelBtn.hovered = false
                        onPressedChanged: cancelBtn.pressed = pressed
                        onClicked: page.transferCancel()
                    }
                }
            }

            Rectangle {
                id: transferBar
                readonly property real inset: Theme.rMd
                x: inset
                anchors.bottom: parent.bottom
                height: 2
                radius: 1
                width: (parent.width - inset * 2) * page.transferPct() / 100
                color: Theme.accent
                clip: true

                Rectangle {
                    id: transferSheen
                    width: 90
                    height: 2
                    x: -width
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00ffffff" }
                        GradientStop { position: 0.5; color: "#ccffffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                    SequentialAnimation {
                        running: transferBar.visible
                        loops: Animation.Infinite
                        NumberAnimation { target: transferSheen; property: "x"; from: -90; to: transferBar.width; duration: Theme.durSheen; easing.type: Theme.easeStandard }
                    }
                }
            }
        }

        Item { width: 1; height: page.anyBusy ? 10 : 0 }

        // ── 步骤卡栈：选完的卡收起（不删除），下一张展开 ──
        // 每张卡是独立实例，不共用同一个 Rectangle 换内容 —— 从结构上消除"同卡切内容"的闪
        Column {
            id: stepStack
            width: parent.width
            spacing: 10

            Repeater {
                model: 5
                delegate: Rectangle {
                    id: stepBox
                    readonly property int stepIndex: index   // 卡片所属步骤（pill 里有自己的 index，必须区分）
                    readonly property bool done: page.step > index
                    readonly property bool active: page.step === index
                    readonly property bool ghost: page.step < index
                    readonly property real contentH: boxCol.implicitHeight
                    property real boxH: 132

                    width: parent.width
                    height: done ? 56 : (active ? (index === 4 ? 64 : boxH) : 60)
                    radius: Theme.rMd
                    color: ghost ? Theme.bgCard2 : Theme.bgCard2
                    border.width: 1
                    border.color: active ? Theme.accentSoft : (done ? Theme.line2 : Theme.bgInput)
                    clip: true
                    Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    // 只在"展开"时记录内容高度；退化的临时值（<60）忽略，避免先塌后撑
                    onContentHChanged: if (contentH > 60 && stepIndex < 4) boxH = contentH + 40

                    // ① 已选完：收起成一行（标题 · 已选值 · 修改）
                    Row {
                        visible: stepBox.done
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "STEP " + (stepBox.stepIndex + 1)
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.stepNames[stepBox.stepIndex]
                            color: Theme.fg2
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.stepValue(stepBox.stepIndex)
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 1 }
                        Rectangle {
                            id: editBtn
                            property bool hovered: false
                            property bool pressed: false
                            height: 22
                            width: editText.implicitWidth + 16
                            radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: hovered ? Theme.bgCard : "transparent"
                            border.width: 1
                            border.color: hovered ? Theme.line2 : "transparent"
                            scale: pressed ? 0.96 : 1
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                            Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                            Behavior on scale { NumberAnimation { duration: Theme.durPress; easing.type: Theme.easePop } }
                            Text {
                                id: editText
                                anchors.centerIn: parent
                                text: qsTr("修改")
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            SRipple { id: editRipple; maxRadius: 56 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: editBtn.hovered = true
                                onExited: editBtn.hovered = false
                                onPressedChanged: editBtn.pressed = pressed
                                onClicked: function (mouse) {
                                    editRipple.burst(mouse.x, mouse.y)
                                    page.jumpTo(stepBox.stepIndex)
                                }
                            }
                        }
                    }

                    // ② 还没走到：占位
                    Row {
                        visible: stepBox.ghost
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "STEP " + (stepBox.stepIndex + 1)
                            color: Theme.line2
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.stepNames[stepBox.stepIndex]
                            color: Theme.line3
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("选完上一步后展开")
                            color: Theme.line2
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    // ③ 当前步（1~4）：展开内容
                    Column {
                        id: boxCol
                        visible: stepBox.active && stepBox.stepIndex < 4
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 18
                        spacing: 12

                        Row {
                            width: parent.width
                            spacing: 9
                            Text {
                                text: "STEP " + (stepBox.stepIndex + 1)
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                            }
                            Text {
                                text: page.stepNames[index]
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: page.optionsForStep(stepBox.stepIndex)
                                delegate: Rectangle {
                                    id: pill
                                    property bool hovered: false
                                    property bool pressed: false
                                    height: 34
                                    width: pillRow.width + 32
                                    radius: Theme.rSm
                                    color: page.isPicked(stepBox.stepIndex, modelData) ? Theme.accentSoft
                                         : hovered ? Theme.bgCard : Theme.bgCard2
                                    border.width: 1
                                    border.color: page.isPicked(stepBox.stepIndex, modelData) ? Theme.accent
                                                : hovered ? Theme.line2 : Theme.line2
                                    scale: pressed ? 0.97 : 1
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                    Behavior on scale { NumberAnimation { duration: Theme.durPress; easing.type: Theme.easePop } }
                                    // 主字与小字按基线对齐：Row 的垂直居中会让 10px 的小字视觉上下沉
                                    Item {
                                        id: pillRow
                                        anchors.centerIn: parent
                                        height: pillMain.height
                                        width: pillMain.width + (pillSub.visible ? pillSub.width + 7 : 0)
                                        Text {
                                            id: pillMain
                                            x: 0; y: 0
                                            text: page.optionLabel(stepBox.stepIndex, modelData)
                                            color: page.isPicked(stepBox.stepIndex, modelData) ? Theme.accentFg : Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                        }
                                        Text {
                                            id: pillSub
                                            visible: page.optionSub(stepBox.stepIndex, modelData).length > 0
                                            x: pillMain.width + 7
                                            anchors.baseline: pillMain.baseline
                                            text: page.optionSub(stepBox.stepIndex, modelData)
                                            color: page.isPicked(stepBox.stepIndex, modelData) ? Theme.accentText : Theme.fg3
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                    }
                                    SRipple {
                                        id: pillRipple
                                        anchors.fill: parent
                                        color: "#ffffff"
                                        maxRadius: 90
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: pill.hovered = true
                                        onExited: pill.hovered = false
                                        onPressedChanged: pill.pressed = pressed
                                        onClicked: function (mouse) {
                                            pillRipple.burst(mouse.x, mouse.y)
                                            page.choose(stepBox.stepIndex, modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: page.stepHints[Math.min(stepBox.stepIndex, 4)]
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            lineHeight: 1.5
                        }
                    }

                    // ④ 第 5 步：已选摘要 + 重新选择
                    Row {
                        visible: stepBox.active && stepBox.stepIndex === 4
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("已选")
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Java " + page.selVersion + " · " + page.selType.toUpperCase()
                                  + " · " + page.selArch + " · " + page.optionLabel(3, page.selOS)
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 1 }
                        Rectangle {
                            id: reselectBtn
                            property bool hovered: false
                            property bool pressed: false
                            height: 22
                            width: reselectText.implicitWidth + 16
                            radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: hovered ? Theme.bgCard : "transparent"
                            border.width: 1
                            border.color: hovered ? Theme.line2 : "transparent"
                            scale: pressed ? 0.96 : 1
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                            Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                            Behavior on scale { NumberAnimation { duration: Theme.durPress; easing.type: Theme.easePop } }
                            Text {
                                id: reselectText
                                anchors.centerIn: parent
                                text: qsTr("重新选择")
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            SRipple { id: reselectRipple; maxRadius: 56 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: reselectBtn.hovered = true
                                onExited: reselectBtn.hovered = false
                                onPressedChanged: reselectBtn.pressed = pressed
                                onClicked: function (mouse) {
                                    reselectRipple.burst(mouse.x, mouse.y)
                                    page.resetChoices()
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 14 }

        // ── 候选文件（step 4） ──
        Column {
            width: parent.width
            spacing: 10
            visible: page.step === 4

            // 左标题 / 右来源：两端锚定，右边与卡片右缘对齐（原来用 width-400 的占位 Item，右边落在随机位置）
            Item {
                width: parent.width
                height: 16
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("选择分发形式 · %1 个文件").arg(page.javaFilesCount())
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("来源 mirrors.tuna.tsinghua.edu.cn")
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            Repeater {
                model: page.fileRows()
                delegate: Rectangle {
                    id: fileCard
                    property bool hovered: false
                    property bool pressed: false
                    width: parent.width
                    height: 88
                    radius: Theme.rMd
                    color: hovered ? Theme.bgCard2 : Theme.bgCard2
                    border.width: 1
                    border.color: (modelData.isZip && page.zipInstalling) || hovered ? Theme.accentSoft : Theme.bgHover
                    clip: true
                    scale: pressed ? 0.995 : 1
                    opacity: page.reveal
                    transform: Translate { y: (1 - page.reveal) * 6 }
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Behavior on scale { NumberAnimation { duration: Theme.durPress; easing.type: Theme.easePop } }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        onEntered: fileCard.hovered = true
                        onExited: fileCard.hovered = false
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: 14
                        Rectangle {
                            width: 38; height: 38; radius: 9
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.isZip ? Theme.accentSoft : Theme.bgCard2
                            border.width: 1
                            border.color: modelData.isZip ? Theme.accentSoft : Theme.bgHover
                            Text {
                                anchors.centerIn: parent
                                text: modelData.ext.toUpperCase()
                                color: modelData.isZip ? Theme.accentText : Theme.fg2
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                        Column {
                            // 图标与动作区之间铺满：不手算 38/14/190 这类魔法数（算错就会挤出卡外）
                            anchors.left: parent.left
                            anchors.leftMargin: 38 + 14
                            anchors.right: parent.right
                            anchors.rightMargin: 118 + 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Text {
                                width: parent.width
                                text: modelData.name
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                            }
                            Text {
                                width: parent.width
                                text: page.fileDesc(modelData) + " · " + modelData.sizeText
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        Item {
                            width: 118
                            height: 40
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right

                            // ZIP：安装中显示进度
                            Column {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.isZip && page.zipInstalling
                                spacing: 5
                                Text {
                                    anchors.right: parent.right
                                    text: page.java ? (page.java.javaDownloadPercent + "% · "
                                          + page.java.javaDownloadSpeedMBps.toFixed(1) + " MB/s") : ""
                                    color: Theme.accentText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: page.installStatus
                                    color: Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            // MSI：保存中显示进度
                            Column {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !modelData.isZip && page.msiBusy
                                spacing: 5
                                Text {
                                    anchors.right: parent.right
                                    text: page.msiPct + "% · " + page.msiSpeed.toFixed(1) + " MB/s"
                                    color: Theme.accentText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: qsTr("正在保存…")
                                    color: Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            // 默认按钮
                            SButton {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                kind: 1
                                width: 104
                                height: 34
                                visible: modelData.isZip ? !page.zipInstalling : !page.msiBusy
                                text: modelData.isZip ? (page.zipInstalled ? qsTr("重新安装") : qsTr("下载并安装"))
                                                      : qsTr("下载")
                                enabled: !page.anyBusy
                                onClicked: {
                                    if (modelData.isZip) page.startZipInstall(modelData.name)
                                    else page.askMsiSave(modelData.url, modelData.name, modelData.size)
                                }
                            }
                        }
                    }

                    // 卡内进度条：左右各内缩 = 卡片圆角半径，端点也圆化，不会在圆角处戳出直角
                    Rectangle {
                        id: bar
                        readonly property real inset: Theme.rMd
                        readonly property real pct: modelData.isZip ? (page.java ? page.java.javaDownloadPercent : 0) : page.msiPct
                        x: inset
                        anchors.bottom: parent.bottom
                        height: 2
                        radius: 1
                        width: (parent.width - inset * 2) * pct / 100
                        visible: modelData.isZip ? page.zipInstalling : page.msiBusy
                        color: Theme.accent
                        clip: true

                        // 流光只动它自己（之前 target 写成 parent，动的是整条进度条的 x，看起来就是"从左划入"反复抽搐）
                        Rectangle {
                            id: sheen
                            width: 90
                            height: 2
                            x: -width
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#00ffffff" }
                                GradientStop { position: 0.5; color: "#ccffffff" }
                                GradientStop { position: 1.0; color: "#00ffffff" }
                            }
                            SequentialAnimation {
                                running: bar.visible
                                loops: Animation.Infinite
                                NumberAnimation { target: sheen; property: "x"; from: -90; to: bar.width; duration: Theme.durSheen; easing.type: Theme.easeStandard }
                            }
                        }
                    }
                }
            }
        }

    }
    }

    // ── 本机已装（贴底常驻：上半部内容再多，页面也不会头重脚轻）──
    Rectangle {
        id: localCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: localCol.implicitHeight + 28
        opacity: page.enter
        transform: Translate { y: (1 - page.enter) * 8 }
            radius: Theme.rMd
            color: Theme.bgCard2
            border.width: 1
            border.color: Theme.line2

            Column {
                id: localCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: qsTr("本机已检测到")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: page.localSummary()
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 1; height: 1 }
                    Rectangle {
                        id: rescanBtn
                        property bool hovered: false
                        height: 22
                        width: rescanText.implicitWidth + 16
                        radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        color: page.scanning ? Theme.bgCard : (hovered ? Theme.bgCard : "transparent")
                        border.width: 1
                        border.color: page.scanning ? Theme.line2 : (hovered ? Theme.line2 : "transparent")
                        property bool pressed: false
                        scale: pressed ? 0.96 : 1
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                        Behavior on scale { NumberAnimation { duration: Theme.durPress; easing.type: Theme.easePop } }

                        Text {
                            id: rescanText
                            anchors.centerIn: parent
                            text: page.scanning ? qsTr("扫描中…") : qsTr("重新扫描")
                            color: page.scanning ? Theme.fg3 : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: page.scanning ? Qt.ArrowCursor : Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: rescanBtn.hovered = true
                            onExited: rescanBtn.hovered = false
                            onPressedChanged: if (!page.scanning) rescanBtn.pressed = pressed
                            onClicked: {
                                if (page.scanning) return
                                page.scanToastPending = true
                                page.refreshLocal()
                            }
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: page.localChips()
                        delegate: Rectangle {
                            id: localChip
                            property bool hovered: false
                            height: 24
                            width: localChipRow.implicitWidth + 20
                            radius: 6
                            color: hovered ? Theme.bgCard : Theme.bgCard2
                            border.width: 1
                            border.color: hovered ? Theme.line2 : Theme.line2
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                            Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: localChip.hovered = true
                                onExited: localChip.hovered = false
                            }
                            Row {
                                id: localChipRow
                                anchors.centerIn: parent
                                spacing: 7
                                Rectangle {
                                    width: 6; height: 6; radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.warn ? Theme.warn : Theme.ok
                                }
                                Text {
                                    text: modelData.label
                                    color: Theme.fg2
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }

    // ══════════ 数据辅助 ══════════
    function optionsForStep(s) {
        if (!java) return []
        if (s === 0) return java.javaVersions
        if (s === 1) return java.javaTypes
        if (s === 2) {
            // 镜像里有一堆服务器架构（ppc64/s390x/riscv64…），启动器用不到
            var keep = ["x64", "x32", "aarch64"]
            var out = []
            for (var i = 0; i < java.javaArchs.length; ++i)
                if (keep.indexOf(java.javaArchs[i]) >= 0) out.push(java.javaArchs[i])
            return out
        }
        if (s === 3) {
            // 启动器只支持 Windows
            return java.javaOSes.indexOf("windows") >= 0 ? ["windows"] : java.javaOSes
        }
        return []
    }

    function isPicked(s, v) {
        if (s === 0) return selVersion === v
        if (s === 1) return selType === v
        if (s === 2) return selArch === v
        if (s === 3) return selOS === v
        return false
    }

    function optionLabel(s, v) {
        if (s === 0) return String(v)
        if (s === 1) return String(v).toUpperCase()
        if (s === 2) return String(v)
        if (s === 3) {
            var m = { "windows": "Windows", "linux": "Linux", "mac": "macOS", "alpine-linux": "Alpine" }
            return m[String(v)] || String(v)
        }
        return String(v)
    }

    function optionSub(s, v) {
        if (s === 0) {
            if (String(v) === "8") return qsTr("旧版整合包")
            if (String(v) === "17") return qsTr("主流")
            if (String(v) === "21") return "1.20.5+"
            if (String(v) === "25") return qsTr("最新")
        }
        if (s === 2 && String(v) === java.cpuArch) return qsTr("已识别")
        return ""
    }

    function stepValue(i) {
        if (i === 0) return selVersion.length > 0 ? selVersion : stepNames[0]
        if (i === 1) return selType.length > 0 ? selType.toUpperCase() : stepNames[1]
        if (i === 2) return selArch.length > 0 ? selArch : stepNames[2]
        if (i === 3) return selOS.length > 0 ? optionLabel(3, selOS) : stepNames[3]
        return stepNames[4]
    }


    function choose(s, v) {
        if (s === 0) pickVersion(String(v))
        else if (s === 1) pickType(String(v))
        else if (s === 2) pickArch(String(v))
        else if (s === 3) pickOs(String(v))
    }

    readonly property bool zipInstalled: {
        for (var i = 0; i < cached.length; ++i)
            if (String(cached[i].major) === selVersion) return true
        return false
    }

    function javaFilesCount() { return java ? java.javaFiles.length : 0 }

    function fileRows() {
        if (!java) return []
        var out = []
        var sorted = java.javaFiles.slice().sort(function (a, b) {
            var rank = function (x) { return (x.ext || "") === "zip" ? 0 : ((x.ext || "") === "msi" ? 1 : 2) }
            return rank(a) - rank(b)
        })
        for (var i = 0; i < sorted.length; ++i) {
            var f = sorted[i]
            out.push({
                name: f.name || "",
                url: f.url || "",
                size: f.size || 0,
                sizeText: fmtSize(f.size || 0),
                ext: f.ext || "zip",
                isZip: (f.ext || "") === "zip"
            })
        }
        return out
    }

    function fileDesc(f) {
        if (f.ext === "zip") return qsTr("便携版（Portable）· 解压后由启动器托管，不写注册表")
        if (f.ext === "msi") return qsTr("安装版（Installer）· 写入系统目录与 PATH / JAVA_HOME，需管理员权限")
        return qsTr("归档包 · 解压后手动指定给启动器")
    }

    function fmtSize(n) {
        if (!n || n <= 0) return ""
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MiB"
        if (n >= 1024) return (n / 1024).toFixed(0) + " KiB"
        return n + " B"
    }

    function localChips() {
        var out = []
        for (var i = 0; i < detected.length; ++i) {
            var d = detected[i]
            out.push({ label: String(d.major) + " · " + String(d.version) + (d.isJdk ? " JDK" : " JRE"),
                       warn: false })
        }
        for (var k = 0; k < cached.length; ++k) {
            var c = cached[k]
            out.push({ label: qsTr("%1 · 启动器托管%2").arg(String(c.major)).arg(c.isJdk ? " JDK" : ""),
                       warn: !c.complete })
        }
        return out
    }

    function localSummary() {
        var n = detected.length + cached.length
        if (n === 0) return qsTr("未发现可用 Java —— 建议装一个")
        return qsTr("%1 个运行时 · 你可能并不需要下载").arg(n)
    }
}
