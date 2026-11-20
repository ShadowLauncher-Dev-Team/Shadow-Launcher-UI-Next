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

    Component.onCompleted: {
        refreshLocal()
        // 验收钩子（与 --ui-download / --ui-dl-tab 同一套做法）：直接走到第 N 步，
        // 用真实后端取数（21 → JDK → 本机架构 → windows），不伪造任何列表。
        var si = Qt.application.arguments.indexOf("--ui-java-step")
        if (si >= 0 && si + 1 < Qt.application.arguments.length) {
            var target = parseInt(Qt.application.arguments[si + 1], 10) || 1
            page.pickVersion("21")
            if (target >= 2) page.pickType("jdk")
            if (target >= 3) page.pickArch(page.selArch.length > 0 ? page.selArch : "x64")
            if (target >= 4) page.pickOs("windows")
            console.info("[JavaPage] --ui-java-step ->", target)
        }
        // 验收钩子：--ui-java-demo → 1.4s 一步自动循环，用来拍换步过渡的中间帧
        if (Qt.application.arguments.indexOf("--ui-java-demo") >= 0) {
            console.info("[JavaPage] --ui-java-demo 已启动")
            stepDemo.start()
        }
        // 量一次真实宽度：这一步的瓦片数是按容器宽度算的，宽度不对就会溢出（调试用，可保留）
        Qt.callLater(function() {
            console.info("[JavaPage] 尺寸 page=" + page.width + " scroll=" + scrollArea.width
                         + " card=" + stepCard.width + " cols=" + page.optCols)
        })
    }

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

    // 换步：新内容淡入 + 顺着方向滑进来。
    // 曲线用 OutCubic 而不是 OutQuint：OutQuint 在 46% 时长就跑到 95%（实测日志 0.97），
    // 肉眼只剩 50ms 的可感知变化，看起来就是"硬切"。OutCubic 能把变化摊到整段 260ms。
    property int stepDir: 1
    property int lastStep: 0
    onStepChanged: {
        stepDir = step >= lastStep ? 1 : -1
        lastStep = step
        stepTick++
        cardIn.restart()
        console.info("[Java页] 换步 ->", step, "方向", stepDir > 0 ? "前进" : "后退")
        probe.restart()
    }

    // 换步 120ms 后回报一次 reveal —— 停在 0.15~0.9 之间就说明是"渐进淡入"而不是"直接跳"
    Timer {
        id: probe
        interval: 120
        onTriggered: console.info("[Java页] 过渡中 reveal =", page.reveal.toFixed(2))
    }

    Timer {
        id: stepDemo
        interval: 1400
        repeat: true
        property int seq: 0
        onTriggered: {
            var path = [1, 2, 3, 2, 1]
            page.step = path[seq % path.length]
            seq++
        }
    }

    NumberAnimation {
        id: cardIn
        target: page
        property: "reveal"
        from: 0
        to: 1
        duration: Theme.durSlow
        easing.type: Theme.easeStandard
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

    // ══════════ 页面级中性配色（2026-11-20 设计稿「A-1 石墨中性」定稿）══════════
    // 为什么不在 Theme 里改：影要求只改 Java 下载页，其它页面保持现状。
    // 这里蓝色只出现三处 —— 主按钮、进度条、当前步骤的下划线；其余全部走中性灰，
    // 深蓝底 + 浅蓝小字在这套字号下会发灰发脏（上一版一屏 7 处蓝，等于没有强调）。
    readonly property color nFill:    "#141519"   // 卡面（比页面亮一档，才不像糊在一起）
    readonly property color nFill2:   "#191a1f"   // 卡内的块（比卡面再亮一点 = 凸起）
    readonly property color nPick:    "#1c2330"   // 选中：轻微偏蓝，让强调线读得出来
    readonly property color nHover:   "#202128"
    readonly property color nStroke:  "#232429"
    readonly property color nStroke2: "#2c2d34"
    readonly property color nStroke3: "#3d3f48"
    readonly property color nText:    "#f2f3f5"
    readonly property color nText2:   "#b9bdc6"
    readonly property color nText3:   "#8a8f99"
    readonly property color nText4:   "#62666e"

    // 已选组合：底部状态行用（空项不出现）
    function comboText() {
        var parts = []
        if (selVersion.length > 0) parts.push(selVersion)
        if (selType.length > 0) parts.push(String(selType).toUpperCase())
        if (selArch.length > 0) parts.push(selArch)
        if (selOS.length > 0) parts.push(optionLabel(3, selOS))
        return parts.length > 0 ? parts.join(" · ") : qsTr("还没选")
    }
    function nextHint() {
        if (selVersion.length === 0) return qsTr("先选一个主版本")
        if (selType.length === 0) return qsTr("选择 JDK 或 JRE")
        if (selArch.length === 0) return qsTr("选择 CPU 架构")
        if (selOS.length === 0) return qsTr("选择操作系统")
        return qsTr("选一个文件即可开始")
    }
    // 推荐档：只用来"轻轻提亮"，不再加角标（角标会和副标题的「推荐」重复）
    function isRecommended(s, v) {
        if (s === 0) return String(v) === "21"
        if (s === 1) return String(v) === "jdk"
        if (s === 2) return java && String(v) === String(java.cpuArch)
        if (s === 3) return String(v) === "windows"
        return false
    }

    readonly property int optCount: optionsForStep(step).length
    readonly property int optCols: Math.max(1, Math.min(4, optCount))

    // ══════════ 布局 ══════════
    Flickable {
        id: scrollArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: localCard.top
        anchors.bottomMargin: 14
        clip: true
        contentWidth: width
        // 只把 contentHeight 抬到视口高，避免"内容比视口短却还能拖动"。
        // 不做垂直居中：页头会跟着飘到屏幕中间（实测比留白更难看）。
        contentHeight: Math.max(topCol.implicitHeight, height)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: topCol
            width: scrollArea.width
            spacing: 16
            opacity: page.enter
            transform: Translate { y: (1 - page.enter) * 8 }

            // ── 步骤行：同时充当标题与页头（tab 已经写着 Java，不再重复一遍页面标题）──
            Item {
                id: railRow
                width: parent.width
                height: 42

                // 重新扫描放在步骤行右端：不额外占高度，也不必滚动到底部去找
                Rectangle {
                    id: rescanTop
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    property bool hovered: false
                    height: 28
                    width: rescanTopText.implicitWidth + 22
                    radius: 7
                    color: hovered ? page.nHover : "transparent"
                    border.width: 1
                    border.color: page.nStroke2
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Text {
                        id: rescanTopText
                        anchors.centerIn: parent
                        text: page.scanning ? qsTr("扫描中…") : qsTr("重新扫描本机")
                        color: page.scanning ? page.nText4 : page.nText2
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: page.scanning ? Qt.ArrowCursor : Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: rescanTop.hovered = true
                        onExited: rescanTop.hovered = false
                        onClicked: {
                            if (page.scanning) return
                            page.scanToastPending = true
                            page.refreshLocal()
                        }
                    }
                }

                Item {
                    id: rail
                    anchors.left: parent.left
                    anchors.right: rescanTop.left
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    height: 42

                    // 量一遍步骤名（按"当前步"的字重量，取最宽的一列）。
                    // 这样整行是【等宽列 + 等长连接线】：换步时列不会左右乱窜，
                    // 线也永远居两列之间、长度一致（上一版每条线起点跟着文字宽度跑，才长短不一）。
                    Row {
                        id: labelMeasure
                        visible: false
                        height: 0
                        Repeater {
                            model: 5
                            delegate: Text {
                                text: page.stepNames[index]
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    readonly property real circle: 18
                    readonly property real gapCW: 8
                    readonly property real pad: 12
                    readonly property real colW: {
                        var m = 0
                        for (var i = 0; i < 5; ++i) {
                            var it = labelMeasure.children[i]
                            if (it) m = Math.max(m, it.implicitWidth + circle + gapCW)
                        }
                        m += pad * 2
                        return Math.min(m > 0 ? m : 104, (width - 48) / 5)
                    }
                    readonly property real wireW: Math.max(12, (width - colW * 5) / 4)
                    readonly property real dashLen: Math.max(24, Math.min(72, wireW * 0.7))
                    readonly property real rowY: 8
                    // 圆点中心：rowY + circle/2；连线对齐到这里（上一版对着整块的高度，所以偏下）
                    readonly property real wireY: rowY + circle / 2 - 0.5
                    function colX(i) { return i * (colW + wireW) }
                    function labelW(i) {
                        var it = labelMeasure.children[i]
                        return it ? it.implicitWidth : 44
                    }
                    function contentW(i) { return circle + gapCW + labelW(i) }

                    // 连接线：固定长度 + 在两段文字之间居中。
                    // 列是等宽的，所以"列边界"并不等于"两段文字的中间"；
                    // 直接铺满列间隙会看起来贴住较长的那一侧。
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            readonly property real leftEdge: rail.colX(index) + rail.pad + rail.contentW(index)
                            readonly property real rightEdge: rail.colX(index + 1) + rail.pad
                            x: leftEdge + (rightEdge - leftEdge - width) / 2
                            y: rail.wireY
                            width: Math.min(rail.dashLen, Math.max(10, rightEdge - leftEdge - 24))
                            height: 1
                            color: page.step > index ? page.nStroke3 : page.nStroke2
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                        }
                    }

                    // 当前步下划线：一条会滑动的线（换步是"移过去 + 变宽"，不是关一个开一个）
                    Rectangle {
                        id: railBar
                        y: rail.rowY + rail.circle + 7
                        height: 2
                        radius: 1
                        color: Theme.accent
                        x: rail.colX(page.step) + rail.pad
                        width: rail.contentW(page.step)
                        Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                        Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
                    }

                    Repeater {
                        model: 5
                        delegate: Item {
                            readonly property bool done: page.step > index
                            readonly property bool active: page.step === index
                            x: rail.colX(index)
                            y: 0
                            width: rail.colW
                            height: 42

                            // 左对齐（不是居中）：走过的步骤名字会缩短成已选值，
                            // 居中会让序号圆点左右漂；左对齐则圆点永远是同一个位置。
                            Row {
                                x: rail.pad
                                y: rail.rowY
                                spacing: rail.gapCW
                                Rectangle {
                                    width: rail.circle; height: rail.circle; radius: rail.circle / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: active ? Theme.accent : "transparent"
                                    border.width: 1
                                    border.color: active ? Theme.accent : done ? page.nStroke3 : page.nStroke2
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: (index + 1)
                                        color: active ? "#ffffff" : done ? page.nText3 : page.nText4
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    // 走过的步骤显示已选值，当前步显示步骤名
                                    text: (page.step > index) ? page.stepValue(index) : page.stepNames[index]
                                    color: active ? page.nText : (page.step > index) ? page.nText3 : page.nText4
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: active ? Font.DemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: index <= page.step
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: page.jumpTo(index)
                            }
                        }
                    }
                }
            }

            // ── 传输中常驻条 ──
            Rectangle {
                width: parent.width
                height: page.anyBusy ? 46 : 0
                visible: height > 1
                radius: 10
                color: page.nFill2
                border.width: 1
                border.color: page.nStroke2
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
                    color: page.nText2
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
                        color: page.nText3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Rectangle {
                        id: cancelBtn
                        property bool hovered: false
                        height: 22
                        width: cancelText.implicitWidth + 16
                        radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        color: hovered ? page.nHover : "transparent"
                        border.width: 1
                        border.color: page.nStroke2
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                        Text {
                            id: cancelText
                            anchors.centerIn: parent
                            text: qsTr("取消")
                            color: page.nText2
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: cancelBtn.hovered = true
                            onExited: cancelBtn.hovered = false
                            onClicked: page.transferCancel()
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    height: 2
                    color: page.nStroke
                    Rectangle {
                        height: parent.height
                        width: parent.width * page.transferPct() / 100
                        color: Theme.accent
                    }
                }
            }

            // ── 当前步内容卡（1~4 步）──
            Rectangle {
                id: stepCard
                width: parent.width
                visible: page.step < 4
                // 高度随内容：卡片被撑满会在下半截留一大片空白，比"内容到顶、下方留呼吸区"难看。
                // +80 = 上下内边距 40 + 底部状态行 24 + 与内容之间的缝 16
                height: page.step < 4 ? (cardCol.implicitHeight + 80) : 0
                Behavior on height { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                radius: 12
                color: page.nFill
                border.width: 1
                border.color: page.nStroke2

                Column {
                    id: cardCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 16
                    opacity: page.reveal
                    transform: Translate { y: (1 - page.reveal) * 14 * page.stepDir }

                    Text {
                        width: parent.width
                        text: page.stepHints[Math.min(page.step, 4)]
                        color: page.nText2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        lineHeight: 1.55
                        wrapMode: Text.WordWrap
                    }

                    Flow {
                        width: parent.width
                        spacing: 11
                        Repeater {
                            model: page.optionsForStep(page.step)
                            delegate: Rectangle {
                                id: tile
                                readonly property bool picked: page.isPicked(page.step, modelData)
                                readonly property bool rec: page.isRecommended(page.step, modelData)
                                property bool hovered: false
                                readonly property real tileW: Math.max(120, (cardCol.width - (page.optCols - 1) * 11) / page.optCols)
                                width: tileW
                                height: 76
                                radius: 10
                                color: picked ? page.nPick
                                              : rec ? "#161d29"
                                              : (hovered ? page.nHover : page.nFill2)
                                border.width: 1
                                border.color: picked
                                              ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                                              : rec ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
                                              : hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                                              : page.nStroke2
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

                                Rectangle {
                                    visible: tile.picked
                                    width: 3
                                    radius: 2
                                    x: 0
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.topMargin: 14
                                    anchors.bottomMargin: 14
                                    color: Theme.accent
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Text {
                                        text: page.optionLabel(page.step, modelData)
                                        color: tile.picked ? page.nText : page.nText2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 19
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        width: parent.width
                                        text: page.optionSub(page.step, modelData)
                                        color: tile.rec ? Theme.accentText : page.nText3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onEntered: tile.hovered = true
                                    onExited: tile.hovered = false
                                    onClicked: page.choose(page.step, modelData)
                                }
                            }
                        }
                    }

                }

                // 状态行贴在卡面底部：卡片会被撑高，跟着瓦片走就会悬在半空
                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 20
                    anchors.topMargin: 0
                    height: 24
                    visible: page.step < 4

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: page.nStroke
                    }
                    Row {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        spacing: 10
                        Text {
                            visible: page.selVersion.length > 0
                            text: qsTr("已选")
                            color: page.nText4
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        Text {
                            visible: page.selVersion.length > 0
                            text: page.comboText()
                            color: page.nText
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: page.nextHint()
                            color: page.selVersion.length > 0 ? page.nText4 : page.nText3
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // ── 第 5 步：候选文件（同样是卡面，最小高度与 1~4 步一致）──
            Rectangle {
                id: filesCard
                width: parent.width
                visible: page.step === 4
                height: filesCol.implicitHeight + 40
                radius: 12
                color: page.nFill
                border.width: 1
                border.color: page.nStroke2

            Column {
                id: filesCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 11

                Text {
                    width: parent.width
                    text: qsTr("便携版由启动器托管、不写注册表；安装版会写进系统目录并配置 PATH / JAVA_HOME。")
                    color: page.nText2
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    lineHeight: 1.55
                    wrapMode: Text.WordWrap
                    opacity: page.reveal
                }

                Repeater {
                    model: page.fileRows()
                    delegate: Rectangle {
                        id: fileCard
                        property bool hovered: false
                        readonly property bool busyZip: modelData.isZip && page.zipInstalling
                        readonly property bool busyMsi: !modelData.isZip && page.msiBusy
                        width: parent.width
                        height: 74
                        radius: 10
                        color: (busyZip || busyMsi) ? page.nPick : (hovered ? page.nHover : page.nFill2)
                        border.width: 1
                        border.color: (busyZip || busyMsi) ? page.nStroke3 : page.nStroke2
                        clip: true
                        opacity: page.reveal
                        transform: Translate { y: (1 - page.reveal) * 10 * page.stepDir }
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }

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
                                width: 36; height: 36; radius: 8
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                color: "transparent"
                                border.width: 1
                                border.color: page.nStroke3
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.ext.toUpperCase()
                                    color: page.nText3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 50
                                anchors.right: parent.right
                                anchors.rightMargin: 160
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    color: page.nText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                }
                                Text {
                                    width: parent.width
                                    text: page.fileDesc(modelData) + " · " + modelData.sizeText
                                    color: page.nText3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            Item {
                                width: 150
                                height: 36
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right

                                Column {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    visible: fileCard.busyZip || fileCard.busyMsi
                                    Text {
                                        anchors.right: parent.right
                                        text: fileCard.busyZip
                                              ? (page.java ? (page.java.javaDownloadPercent + "% · " + page.java.javaDownloadSpeedMBps.toFixed(1) + " MB/s") : "")
                                              : (page.msiPct + "% · " + page.msiSpeed.toFixed(1) + " MB/s")
                                        color: page.nText2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        text: fileCard.busyZip ? page.installStatus : qsTr("正在保存…")
                                        color: page.nText3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                }

                                // 自己画：SButton 的 kind=0 是 48 高 / 15px 字，塞进 74 高的行里会顶满；
                                // 这里按设计稿要 34 高的紧凑主按钮。
                                Rectangle {
                                    id: actBtn
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    readonly property bool primary: modelData.isZip
                                    property bool hovered: false
                                    width: modelData.isZip ? 116 : 96
                                    height: 34
                                    radius: 8
                                    visible: !(fileCard.busyZip || fileCard.busyMsi)
                                    color: primary
                                           ? (hovered ? Theme.accentTop : Theme.accentBot)
                                           : (hovered ? page.nHover : "transparent")
                                    border.width: primary ? 0 : 1
                                    border.color: page.nStroke2
                                    opacity: page.anyBusy ? 0.45 : 1
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.isZip
                                              ? (page.zipInstalled ? qsTr("重新安装") : qsTr("下载并安装"))
                                              : qsTr("另存为…")
                                        color: actBtn.primary ? "#ffffff" : page.nText2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: actBtn.primary ? Font.DemiBold : Font.Normal
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !page.anyBusy
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        hoverEnabled: true
                                        onEntered: actBtn.hovered = true
                                        onExited: actBtn.hovered = false
                                        onClicked: {
                                            if (modelData.isZip) page.startZipInstall(modelData.name)
                                            else page.askMsiSave(modelData.url, modelData.name, modelData.size)
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            height: 2
                            readonly property real pct: modelData.isZip ? (page.java ? page.java.javaDownloadPercent : 0) : page.msiPct
                            width: (parent.width - 2) * pct / 100
                            visible: fileCard.busyZip || fileCard.busyMsi
                            color: Theme.accent
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: qsTr("%1 个文件 · 来源 mirrors.tuna.tsinghua.edu.cn").arg(page.javaFilesCount())
                    color: page.nText4
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
            }
        }
    }

    // ── 本机已装（贴底常驻）──
    Rectangle {
        id: localCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: localCol.implicitHeight + 28
        opacity: page.enter
        transform: Translate { y: (1 - page.enter) * 8 }
        radius: 12
        color: page.nFill2
        border.width: 1
        border.color: page.nStroke2

        Column {
            id: localCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            Row {
                width: parent.width
                spacing: 9
                Text {
                    text: qsTr("本机已检测到")
                    color: page.nText2
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: page.localSummary()
                    color: page.nText4
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 1; height: 1 }
                Rectangle {
                    id: rescanBtn2
                    property bool hovered: false
                    height: 22
                    width: rescanText2.implicitWidth + 16
                    radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: hovered ? page.nHover : "transparent"
                    border.width: 1
                    border.color: hovered ? page.nStroke3 : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
                    Text {
                        id: rescanText2
                        anchors.centerIn: parent
                        text: page.scanning ? qsTr("扫描中…") : qsTr("重新扫描")
                        color: page.scanning ? page.nText4 : page.nText2
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: page.scanning ? Qt.ArrowCursor : Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: rescanBtn2.hovered = true
                        onExited: rescanBtn2.hovered = false
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
                        height: 24
                        width: localChipRow.implicitWidth + 20
                        radius: 6
                        color: "transparent"
                        border.width: 1
                        border.color: page.nStroke2
                        Row {
                            id: localChipRow
                            anchors.centerIn: parent
                            spacing: 7
                            Rectangle {
                                width: 5; height: 5; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.warn ? Theme.warn : Theme.ok
                            }
                            Text {
                                text: modelData.label
                                color: page.nText2
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
        // 类型：JDK/JRE 光两个缩写不够，补一句差别（与 stepHints 同口径）
        if (s === 1) {
            if (String(v) === "jdk") return qsTr("含编译工具 · 推荐")
            if (String(v) === "jre") return qsTr("只有运行环境")
            return ""
        }
        if (s === 3) {
            if (String(v) === "windows") return qsTr("Windows 10 / 11")
            return ""
        }
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
