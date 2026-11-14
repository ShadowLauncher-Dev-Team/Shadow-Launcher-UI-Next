// SPDX-License-Identifier: AGPL-3.0-or-later
// 协议门禁：首次启动（或协议版本变更）必须同意后才能进入启动器。
//
// 形态沿用启动器的语言，不另起一套：
//   · 底 = 同一张壁纸（SBgImage，与启动页共用取景公式）+ 压暗遮罩 —— 不是白屏/灰屏
//   · 顶栏 = 侧栏的 SHADOW 字标 + 外壳那对窗口按钮（最小化 / 关闭）
//   · 卡片 = bgCard 底 + 1px line2 描边 + rWin 圆角（与 SCard 一致）
//   · 按钮 = SButton（实心主按钮 / 描边次按钮），不做新样式
//
// 动效全部走 Theme 令牌，禁止裸数字：
//   · 入场 = reveal 0→1（durPage / easeEnter）：遮罩淡入、卡片 0.98→1 放大归位并上浮 16px
//   · 切协议 = 面板淡入 + 5px 上浮（durBase / easeEnter），滚动位置归零
//   · 勾选 = 方框填充 + 对勾 scale 弹入（durFast / easePop）
//   · 阅读提示 = 「向下滚动」↔「已读完」两条文案交叉淡入淡出
//   · 同意 = reveal 1→0（durBase / easeExit），动画收完才真正 dismiss
//
// 关键时序：markAgreed 会立刻让 agreementAccepted 变 true，visible 的绑定一并失效。
// 所以 visible = (needed || closing) && !dismissed —— 退场动画期间靠 closing 撑住，
// 否则「点同意 → 门禁瞬间消失」，动画一帧都看不到。
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: gate
    objectName: "agreementGate"
    property var b: null
    property Window hostWindow: null

    // 后端已同意 / 退场动画进行中 / 已彻底关闭：三者共同决定可见性
    readonly property bool forceShow: Qt.application.arguments.indexOf("--ui-gate") >= 0
    readonly property bool needed: gate.forceShow || (gate.b ? !gate.b.agreementAccepted : false)
    property bool closing: false
    property bool dismissed: false
    visible: (gate.needed || gate.closing) && !gate.dismissed
    z: 1000

    // 入场/退场共用的进度量：0 = 完全收起，1 = 完全就位
    property real reveal: 0
    // 协议面板切换时的淡入量（0→1）
    property real docFade: 1

    readonly property bool beta: gate.b ? gate.b.betaGateEnabled === true : false
    property int docIndex: 0
    property bool agree: false

    readonly property var docTitles: gate.beta
        ? [qsTr("用户协议"), qsTr("隐私政策"), qsTr("内测协议")]
        : [qsTr("用户协议"), qsTr("隐私政策")]

    function htmlFor(i) {
        if (!gate.b) return ""
        if (i === 0) return gate.b.termsAgreementHtml || ""
        if (i === 1) return gate.b.privacyAgreementHtml || ""
        if (i === 2) return gate.b.betaAgreementHtml || ""
        return ""
    }

    // 当前协议读到哪儿：1 = 已到底。面板高度还没算出来时按 0 处理，
    // 否则首帧会误判「已读完」，提示语一闪再跳回去。
    readonly property real readProgress: {
        if (!docFlick || docFlick.height <= 1 || docFlick.contentHeight <= 0) return 0
        return Math.max(0, Math.min(1,
            (docFlick.contentY + docFlick.height) / docFlick.contentHeight))
    }
    readonly property bool read: gate.readProgress >= 0.995

    function startEnter() {
        if (gate.closing || gate.dismissed) return
        gate.reveal = 0
        enterAnim.restart()
    }

    function accept() {
        if (gate.closing || !gate.agree) return
        gate.closing = true
        // 先写同意记录：写盘失败也照样放行（不能让用户卡在门禁上）
        if (gate.b) gate.b.markAgreed = true
        exitAnim.restart()
    }

    function quitApp() {
        if (gate.hostWindow) gate.hostWindow.close()
        else Qt.quit()
    }

    Component.onCompleted: if (gate.visible) gate.startEnter()
    onVisibleChanged: if (gate.visible) gate.startEnter()

    NumberAnimation {
        id: enterAnim
        target: gate; property: "reveal"
        from: 0; to: 1
        duration: Theme.durPage; easing.type: Theme.easeEnter
    }
    NumberAnimation {
        id: exitAnim
        target: gate; property: "reveal"
        from: 1; to: 0
        duration: Theme.durBase; easing.type: Theme.easeExit
        onStopped: if (gate.closing) gate.dismissed = true
    }
    NumberAnimation {
        id: docFadeAnim
        target: gate; property: "docFade"
        to: 1
        duration: Theme.durBase; easing.type: Theme.easeEnter
    }

    onDocIndexChanged: {
        if (docFlick) docFlick.contentY = 0
        gate.docFade = 0
        docFadeAnim.restart()
    }

    // ══ 背景：壁纸 + 压暗 ══
    Rectangle {
        anchors.fill: parent
        color: Theme.pBg
    }

    SBgImage {
        anchors.fill: parent
        source: (gate.b && gate.b.customBgUrl && gate.b.customBgUrl.length > 0)
                ? gate.b.customBgUrl
                : "qrc:/ui/stage-aurora.jpg"
        zoom: (gate.b && gate.b.bgZoom) ? gate.b.bgZoom : 1.0
        cropX: (gate.b && gate.b.cropX !== undefined) ? gate.b.cropX : 0.5
        cropY: (gate.b && gate.b.cropY !== undefined) ? gate.b.cropY : 0.5
        fallbackColor: Theme.pBg
    }

    // 压暗：比启动页更重，保证卡片是画面上唯一的焦点
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: 0.82 * gate.reveal
    }

    // 顶部再压一层，字标与窗口按钮所在区域压得住亮图
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.35
        gradient: Gradient {
            GradientStop { position: 0.00; color: Theme.imageScrimSide0 }
            GradientStop { position: 0.55; color: Theme.imageScrim1 }
            GradientStop { position: 1.00; color: "transparent" }
        }
    }

    // 吃掉所有落在门禁上的点击：门禁之后的东西一律不能被点到
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    }

    // ══ 顶栏：字标 + 窗口按钮 ══
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 56
        opacity: gate.reveal

        // 无边框窗口：空白处按下交给系统接管移动（与各页顶栏同一做法）
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: if (gate.b) gate.b.beginWindowMove()
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
                // 品牌名，不翻译（与侧栏一致）
                text: "SHADOW"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 2.2
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                width: 1; height: 12
                color: Theme.line3
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: (gate.b && gate.b.appVersion) ? gate.b.appVersion : ""
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 8
            spacing: 4
            SWindowButton {
                iconName: "minus"
                onClicked: if (gate.hostWindow) gate.hostWindow.showMinimized()
            }
            SWindowButton {
                iconName: "x"
                danger: true
                onClicked: gate.quitApp()
            }
        }
    }

    // ══ 协议卡片 ══
    Item {
        id: cardWrap
        anchors.centerIn: parent
        width: Math.min(660, Math.max(0, gate.width - 96))
        height: Math.min(498, Math.max(0, gate.height - 170))
        opacity: gate.reveal
        scale: 0.98 + 0.02 * gate.reveal
        transform: Translate { y: (1 - gate.reveal) * 16 }

        Rectangle {
            anchors.fill: parent
            radius: Theme.rWin
            color: Theme.bgCard
            border.width: 1
            border.color: Theme.line2
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 0

            // ── 头 ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.rMd
                    color: Theme.accentSoft
                    SIcon {
                        anchors.centerIn: parent
                        name: "shield-check"
                        size: 19
                        color: Theme.accentText
                    }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Text {
                        text: qsTr("欢迎使用 Shadow Launcher")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: qsTr("开始前，请阅读并同意以下协议")
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }

            // ── 协议切换 + 阅读提示 ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 20
                spacing: 12

                SSegmented {
                    id: seg
                    // 自然宽度 + 下限：拉满整行会让两个 tab 各 300px，看着像进度条
                    Layout.preferredWidth: Math.max(300, seg.implicitWidth)
                    Layout.preferredHeight: seg.implicitHeight
                    items: gate.docTitles
                    currentIndex: gate.docIndex
                    onActivated: (i) => gate.docIndex = i
                }

                Item {
                    Layout.preferredWidth: 84
                    Layout.preferredHeight: 18
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("向下滚动阅读")
                        color: Theme.fg4
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        opacity: gate.read ? 0 : gate.reveal
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("已读完")
                        color: Theme.accentText
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        opacity: gate.read ? gate.reveal : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                        }
                    }
                }
            }

            // ── 协议正文 ──
            Rectangle {
                id: docPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 14
                radius: Theme.rMd
                color: Theme.bgCard2
                border.width: 1
                border.color: Theme.line2
                clip: true

                // 阅读进度：底轨 + 高亮段，跟着滚动生长
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 2
                    color: Theme.line
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    height: 2
                    radius: 1
                    color: Theme.accent
                    width: docPanel.width * gate.readProgress
                    Behavior on width {
                        NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                    }
                }



                Flickable {
                    id: docFlick
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    clip: true
                    contentWidth: width
                    contentHeight: docText.implicitHeight + 34
                    boundsBehavior: Flickable.StopAtBounds
                    // 内容没溢出时不吃滚轮（与 STextArea 的结论一致）
                    interactive: contentHeight > height
                    opacity: gate.docFade
                    transform: Translate { y: (1 - gate.docFade) * 5 }

                    Text {
                        id: docText
                        x: 18
                        y: 16
                        width: docFlick.width - 36
                        text: gate.htmlFor(gate.docIndex) || qsTr("无法加载协议文件")
                        textFormat: Text.RichText
                        color: Theme.fg2
                        linkColor: Theme.accentText
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        lineHeight: 1.6
                        lineHeightMode: Text.ProportionalHeight
                        wrapMode: Text.WordWrap
                        onLinkActivated: (url) => Qt.openUrlExternally(url)
                    }
                }

                // 底部渐隐：面板底边会把文字硬切在半行上，加一层底色渐变读成「还有内容」。
                // 必须**画在 Flickable 之上**（声明在它后面）：反过来的话文字画在渐变上面，等于没遮；
                // 读到底后淡出，不再暗示下面还有东西
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 26
                    opacity: gate.read ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard }
                    }
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Theme.bgCard2 }
                    }
                }
            }

            // ── 勾选 + 按钮 ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 18
                spacing: 12

                Item {
                    id: agreeRow
                    // 占满剩余宽度：按钮用自然宽度，文案就吃掉剩下的空间（放不下时省略）
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22

                    readonly property bool hover: agreeHover.containsMouse

                    RowLayout {
                        id: agreeInner
                        anchors.fill: parent
                        spacing: 9

                        Item {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: gate.agree ? Theme.accent
                                                 : (agreeRow.hover ? Theme.bgHover : "transparent")
                                border.width: gate.agree ? 0 : 1
                                border.color: agreeRow.hover ? Theme.line3 : Theme.line2
                                Behavior on color {
                                    ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                                }
                                Behavior on border.color {
                                    ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                                }
                            }
                            SIcon {
                                anchors.centerIn: parent
                                name: "check"
                                size: 12
                                color: Theme.accentFg
                                opacity: gate.agree ? 1 : 0
                                scale: gate.agree ? 1.0 : 0.5
                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easePop }
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: qsTr("我已阅读并同意以上全部协议")
                            color: agreeRow.hover ? Theme.fg : Theme.fg2
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            Behavior on color {
                                ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                            }
                        }
                    }

                    MouseArea {
                        id: agreeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: gate.agree = !gate.agree
                    }
                }


                SButton {
                    Layout.preferredHeight: 38
                    text: qsTr("同意并继续")
                    dimmed: !gate.agree
                    onClicked: gate.accept()
                }
                SButton {
                    Layout.preferredHeight: 38
                    kind: 1
                    text: qsTr("退出")
                    onClicked: gate.quitApp()
                }
            }

            // ── 脚注 ──
            Text {
                Layout.topMargin: 12
                text: qsTr("不同意以上协议将无法使用本启动器")
                color: Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
