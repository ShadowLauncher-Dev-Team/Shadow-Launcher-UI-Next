// SPDX-License-Identifier: AGPL-3.0-or-later
// 下载页 · Java Tab（2026-11-07 第一版：结构先落地，动效后续加）
//
// 交互：按旧 UI 的五步级联思路，做成"逐级抵近"——
//   ①版本 → ②JRE/JDK → ③架构 → ④系统 → ⑤分发形式（ZIP/ MSI）
// 已选步骤收成上方 chips，当前步骤只展开一张卡；架构/系统按本机自动预选，可改。
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

    // ── 动效状态（与资源库/下载页同一套语言） ──
    property real reveal: 1        // 当前卡片入场进度（0..1）
    property int stepTick: 0       // 步进节拍，用来重启动画

    readonly property bool zipInstalling: installingMajor.length > 0 && installingMajor === selVersion
    readonly property bool anyBusy: installingMajor.length > 0 || msiBusy

    readonly property var stepNames: ["Java 版本", "JRE / JDK", "CPU 架构", "操作系统", "分发形式"]
    readonly property var stepHints: [
        "选启动器/游戏需要的主版本。拿不准就选 17——覆盖目前绝大多数整合包与 Forge。",
        "JDK 含 JRE 与编译工具；JRE 只有运行环境。启动器一键安装用 JDK（JRE 缺少 jdk.crypto.ec，部分加载器会崩）。",
        "绝大多数机器是 x64。32 位系统选 x32；注意 Java 21 及以上没有 32 位版本。",
        "选择你的操作系统。",
        "便携版（ZIP）解压后由启动器托管，不写注册表；安装版（MSI）装进系统并写入 PATH / JAVA_HOME。"
    ]

    // ── 生命周期 ──
    function refreshLocal() {
        if (!java) return
        scanning = true
        // 扫描是异步的（内部并发探测每个 java.exe），完成时 emit systemJavaScanFinished
        detected = java.scanSystemJavas()
        cached = java.javaCacheRuntimes()
        scanning = false
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

    function startZipInstall(fileName) {
        if (!java || anyBusy) return
        var major = majorOfVersion(selVersion)
        if (major <= 0) return
        installingMajor = selVersion
        installStatus = "正在下载 Java " + selVersion + "…"
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

    // 换步：卡片重新入场（淡入 + 8px 上浮 + 0.99 缩放归位）；回到第 1 步不播
    onStepChanged: {
        stepTick++
        if (step === 0) { reveal = 1; return }
        reveal = 0
        cardIn.restart()
    }

    NumberAnimation {
        id: cardIn
        target: page
        property: "reveal"
        from: 0
        to: 1
        duration: Theme.durBase
        easing.type: Theme.easePop
    }

    Connections {
        target: page.java
        enabled: page.java !== null
        function onJavaInstallStateChanged() {
            if (!page.java) return
            page.installingMajor = page.java.installingMajor
            page.installStatus = page.java.installStatusText
            if (page.installingMajor.length === 0) page.refreshLocal()
        }
        function onJavaCacheListChanged() { page.refreshLocal() }
        function onSystemJavaScanFinished() { page.refreshLocal() }
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
                if (page.toast) page.toast.show("已保存到 " + path)
            } else {
                if (page.toast) page.toast.show("下载失败")
            }
        }
    }

    FileDialog {
        id: msiDialog
        title: "选择 MSI 保存位置"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Windows 安装包 (*.msi)", "所有文件 (*)"]
        onAccepted: {
            var p = page.urlToPath(selectedFile)
            page.msiBusy = true
            page.msiPct = 0
            if (page.java) page.java.downloadJavaFileToPath(page.pendingMsiUrl, p, page.pendingMsiSize)
        }
    }

    function urlToPath(u) {
        var s = String(u)
        if (s.indexOf("file:///") === 0) s = s.substring(8)
        return s
    }

    // ══════════ 布局 ══════════
    Column {
        id: topCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

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
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                color: page.step > index ? Theme.accent
                                     : page.step === index ? "#0d1016" : "transparent"
                                border.width: 1
                                border.color: page.step > index ? Theme.accent
                                            : page.step === index ? Theme.accent : "#2b313c"
                                Text {
                                    anchors.centerIn: parent
                                    text: (index + 1)
                                    color: page.step > index ? "#ffffff"
                                         : page.step === index ? Theme.accent : Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                            Text {
                                id: nodeLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.stepValue(index)
                                color: page.step >= index ? Theme.fg : Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: page.step === index ? Font.DemiBold : Font.Normal
                            }
                        }

                        // 到下一个节点的连线（已走过 = accent 55%）
                        Rectangle {
                            id: wire
                            visible: !parent.last
                            anchors.verticalCenter: parent.verticalCenter
                            x: nodeRow.x + nodeRow.width + 10
                            width: parent.width - nodeRow.width - 22
                            height: 1
                            color: page.step > index ? Theme.accent : "#20252e"
                            opacity: page.step > index ? 0.55 : 1
                            clip: true

                            // 步进瞬间，刚走过去的那条线从左到右扫一道淡蓝光
                            Rectangle {
                                id: flow
                                visible: false
                                width: Math.min(64, wire.width)
                                height: 1
                                x: -width
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#00a8ccff" }
                                    GradientStop { position: 0.5; color: "#a8ccff" }
                                    GradientStop { position: 1.0; color: "#00a8ccff" }
                                }
                            }

                            NumberAnimation {
                                id: flowAnim
                                target: flow
                                property: "x"
                                from: -flow.width
                                to: wire.width
                                duration: Theme.durSlow
                                easing.type: Theme.easeStandard
                                onFinished: flow.visible = false
                            }

                            Connections {
                                target: page
                                function onStepChanged() {
                                    // index = 起点节点序号；刚走过的是 index === step - 1 那条
                                    if (index === page.step - 1) {
                                        flow.visible = true
                                        flowAnim.restart()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 已选 chips ──
        Item {
            width: parent.width
            height: 34
            Row {
            id: chips
            visible: page.step > 0
            width: parent.width
            height: 34
            spacing: 8

            Repeater {
                model: page.step
                delegate: Rectangle {
                    height: 24
                    width: chipRow.implicitWidth + 20
                    radius: 6
                    color: "#0d1016"
                    border.color: Theme.line2
                    border.width: 1
                    anchors.verticalCenter: parent.verticalCenter
                    NumberAnimation on scale {
                        from: 0.92; to: 1
                        duration: Theme.durBase
                        easing.type: Theme.easePop
                    }
                    transformOrigin: Item.Left
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            id: chipText
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.stepValueShort(index)
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        SIcon {
                            name: "x"; size: 11; color: Theme.fg3
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.jumpTo(index)
                    }
                }
            }
            Text {
                visible: page.step > 0
                text: "点 × 回到那一步重选"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
            }
        }

        Item { width: 1; height: 4 }

        // ── 当前步骤卡 ──
        Rectangle {
            id: stepCard
            visible: page.step < 4
            width: parent.width
            height: cardCol.implicitHeight + 40
            radius: Theme.rMd
            color: "#0b0d12"
            border.width: 1
            border.color: "#2a3a54"
            opacity: page.reveal
            transform: Translate { y: (1 - page.reveal) * 8 }
            scale: 1 - (1 - page.reveal) * 0.01

            Column {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 9
                    Text {
                        text: "STEP " + (page.step + 1)
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                    }
                    Text {
                        text: page.stepNames[Math.min(page.step, 4)]
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
                        model: page.optionsForStep(page.step)
                        delegate: Rectangle {
                            id: pill
                            property bool hovered: false
                            property bool pressed: false
                            height: 34
                            width: pillRow.width + 32
                            radius: Theme.rSm
                            color: page.isPicked(page.step, modelData) ? "#10203a"
                                 : hovered ? "#12161d" : "#0d1016"
                            border.width: 1
                            border.color: page.isPicked(page.step, modelData) ? Theme.accent
                                        : hovered ? "#39424f" : Theme.line2
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
                                    text: page.optionLabel(page.step, modelData)
                                    color: page.isPicked(page.step, modelData) ? "#ffffff" : "#c3cbd8"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }
                                Text {
                                    id: pillSub
                                    visible: page.optionSub(page.step, modelData).length > 0
                                    x: pillMain.width + 7
                                    anchors.baseline: pillMain.baseline
                                    text: page.optionSub(page.step, modelData)
                                    color: page.isPicked(page.step, modelData) ? "#8fb6f8" : Theme.fg3
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
                                id: pillPress
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: pill.hovered = true
                                onExited: pill.hovered = false
                                onPressedChanged: pill.pressed = pressed
                                onClicked: function (mouse) {
                                    pillRipple.burst(mouse.x, mouse.y)
                                    page.choose(page.step, modelData)
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: page.step < 4
                    width: parent.width
                    text: page.stepHints[Math.min(page.step, 4)]
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }
        }

        Item { width: 1; height: 14 }

        // ── 第 5 步的已选摘要（替代 STEP 5 的空卡） ──
        Rectangle {
            visible: page.step === 4
            width: parent.width
            height: 56
            radius: Theme.rMd
            color: "#0b0d12"
            border.width: 1
            border.color: Theme.line2
            opacity: page.reveal
            transform: Translate { y: (1 - page.reveal) * 8 }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "已选"
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
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "重新选择"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.resetChoices()
                    }
                }
            }
        }

        Item { width: 1; height: 14 }

        // ── 还没走到的步骤：占位卡（"抵近"的层次感，选中一步就往上顶一格） ──
        Column {
            width: parent.width
            spacing: 10
            visible: page.step < 4

            Repeater {
                model: 4 - page.step
                delegate: Rectangle {
                    width: parent.width
                    height: 60
                    radius: Theme.rMd
                    color: "#0a0c11"
                    border.width: 1
                    border.color: "#1b1f27"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "STEP " + (page.step + index + 2)
                            color: "#3a424f"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.stepNames[page.step + index + 1]
                            color: "#4a5361"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "选完上一步后展开"
                            color: "#333a45"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
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

            Row {
                width: parent.width
                Text {
                    text: "选择分发形式 · " + page.javaFilesCount() + " 个文件"
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
                Item { width: parent.width - 400; height: 1 }
                Text {
                    text: "来源 mirrors.tuna.tsinghua.edu.cn"
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
                    color: hovered ? "#0e1117" : "#0b0d12"
                    border.width: 1
                    border.color: (modelData.isZip && page.zipInstalling) || hovered ? "#2a3a54" : "#262b35"
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

                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14
                        Rectangle {
                            width: 38; height: 38; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.isZip ? "#0c1626" : "#12151a"
                            border.width: 1
                            border.color: modelData.isZip ? "#1e324f" : "#2b3038"
                            Text {
                                anchors.centerIn: parent
                                text: modelData.ext.toUpperCase()
                                color: modelData.isZip ? "#8fb6f8" : "#98a1ae"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                        Column {
                            width: parent.width - 38 - 14 - 190
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Text {
                                width: parent.width
                                text: modelData.name
                                color: "#ffffff"
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
                            width: 170
                            height: 40
                            anchors.verticalCenter: parent.verticalCenter

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
                                    color: "#8fb6f8"
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
                                    color: "#8fb6f8"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: "正在保存…"
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
                                text: modelData.isZip ? (page.zipInstalled ? "重新安装" : "下载并安装")
                                                      : "下载"
                                enabled: !page.anyBusy
                                onClicked: {
                                    if (modelData.isZip) page.startZipInstall(modelData.name)
                                    else page.askMsiSave(modelData.url, modelData.name, modelData.size)
                                }
                            }
                        }
                    }

                    // 卡内进度条（流光裁在已填充段内）
                    Rectangle {
                        id: bar
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 2
                        width: parent.width * (modelData.isZip ? (page.java ? page.java.javaDownloadPercent : 0)
                                                                : page.msiPct) / 100
                        visible: modelData.isZip ? page.zipInstalling : page.msiBusy
                        color: Theme.accent
                        clip: true

                        Rectangle {
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
                                NumberAnimation { target: parent; property: "x"; from: -90; to: bar.width; duration: Theme.durSheen; easing.type: Theme.easeStandard }
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
            radius: Theme.rMd
            color: "#0b0d12"
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
                        text: "本机已检测到"
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
                    Text {
                        text: page.scanning ? "扫描中…" : "重新扫描"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.refreshLocal()
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: page.localChips()
                        delegate: Rectangle {
                            height: 24
                            width: localChipRow.implicitWidth + 20
                            radius: 6
                            color: "#0d1016"
                            border.width: 1
                            border.color: Theme.line2
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
            if (String(v) === "8") return "旧版整合包"
            if (String(v) === "17") return "主流"
            if (String(v) === "21") return "1.20.5+"
            if (String(v) === "25") return "最新"
        }
        if (s === 2 && String(v) === java.cpuArch) return "已识别"
        return ""
    }

    function stepValue(i) {
        if (i === 0) return selVersion.length > 0 ? selVersion : stepNames[0]
        if (i === 1) return selType.length > 0 ? selType.toUpperCase() : stepNames[1]
        if (i === 2) return selArch.length > 0 ? selArch : stepNames[2]
        if (i === 3) return selOS.length > 0 ? optionLabel(3, selOS) : stepNames[3]
        return stepNames[4]
    }

    function stepValueShort(i) { return stepValue(i) }

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
        if (f.ext === "zip") return "便携版（Portable）· 解压后由启动器托管，不写注册表"
        if (f.ext === "msi") return "安装版（Installer）· 写入系统目录与 PATH / JAVA_HOME，需管理员权限"
        return "归档包 · 解压后手动指定给启动器"
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
            out.push({ label: String(c.major) + " · 启动器托管" + (c.isJdk ? " JDK" : ""),
                       warn: !c.complete })
        }
        return out
    }

    function localSummary() {
        var n = detected.length + cached.length
        if (n === 0) return "未发现可用 Java —— 建议装一个"
        return n + " 个运行时 · 你可能并不需要下载"
    }
}
