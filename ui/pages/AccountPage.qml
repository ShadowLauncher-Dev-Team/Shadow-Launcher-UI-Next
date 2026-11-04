// SPDX-License-Identifier: AGPL-3.0-or-later
// 账户页（全屏）：登录 / 切换 / 退出 / 查看皮肤状态
// 三种登录方式严格分离（lastLoginMode：0 正版 / 1 离线 / 2 外置），互不复用输入。
// 头像规则：MC 头像是方形，不用圆形头像，也不给头像加边框或圆角（用户 2026-11-04 明确）。
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: page

    signal close()

    readonly property var b: (typeof backend !== "undefined") ? backend : null
    readonly property var yg: (b && b.yggdrasil) ? b.yggdrasil : null

    property int tab: 0                      // 0 正版 / 1 离线 / 2 外置
    property bool loginPanel: false          // true = 显示登录表单（切换账号时打开）
    property string offlineInput: ""
    property string apiRootInput: ""
    property string emailInput: ""
    property string passwordInput: ""
    property string hint: ""

    readonly property bool narrow: width < 900
    readonly property int leftW: narrow ? 240 : 300
    readonly property bool hasOnline: b ? b.isOnline : false
    readonly property bool hasOffline: (b && b.offlineUsername) ? b.offlineUsername.length > 0 : false
    readonly property bool hasAccount: hasOnline || hasOffline
    readonly property bool busy: b ? b.microsoftLoginBusy : false
    readonly property string statusLine: (b && b.msStatus) ? b.msStatus : ""

    // 原始皮肤优先（自己裁脸）；头部图兜底
    readonly property string rawHeadSource: (b && b.isOnline) ? (b.skinTexturePath || "") : ""
    readonly property string headSource: {
        if (!b) return ""
        if (b.isOnline) return b.skinPath || b.offlineSkinPath || ""
        return b.offlineSkinPath || ""
    }
    readonly property string displayName: {
        if (!b) return "未登录"
        if (b.isOnline && b.username) return b.username
        if (b.offlineUsername) return b.offlineUsername
        return "未登录"
    }
    readonly property string typeText: {
        // 正在登录（换号）时不显示当前账号类型，避免顶栏写着"已登录"而正文在登录
        if (loginPanel) return ""
        if (b && b.isOnline) return "Microsoft 正版账户"
        if (hasOffline) return "离线账户"
        return "未登录"
    }

    function flash(msg) { page.hint = msg; hintTimer.restart() }
    function startMicrosoft() { if (page.b) { page.b.lastLoginMode = 0; page.b.microsoftLogin() } }
    function cancelMicrosoft() { if (page.b) page.b.cancelMicrosoftLogin() }
    function doOffline() {
        if (!page.b) return
        var n = page.offlineInput.trim()
        if (n.length === 0) { page.flash("先填一个用户名"); return }
        page.b.lastLoginMode = 1
        page.b.offlineLogin(n)
        page.flash("已切换到离线账户 " + n)
    }
    function doExternal() {
        if (!page.yg) return
        if (page.apiRootInput.length === 0 || page.emailInput.length === 0 || page.passwordInput.length === 0) {
            page.flash("API 地址、账号、密码都要填")
            return
        }
        page.b.lastLoginMode = 2
        page.yg.login(page.apiRootInput.trim(), page.emailInput.trim(), page.passwordInput)
        page.flash("正在登录外置账户…")
    }

    Timer { id: hintTimer; interval: 2600; onTriggered: page.hint = "" }

    Component.onCompleted: {
        if (page.b) {
            page.tab = page.b.lastLoginMode
            if (page.offlineInput.length === 0) page.offlineInput = page.b.offlineUsername || ""
        }
        if (page.yg) {
            page.apiRootInput = page.yg.apiRoot || ""
            if (page.yg.apiRoot) page.yg.fetchMeta(page.yg.apiRoot)
        }
        if (Qt.application.arguments.indexOf("--ui-account-login") >= 0)
            page.loginPanel = true
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onMicrosoftLoginSuccess() { page.loginPanel = false; page.flash("登录成功") }
        function onMicrosoftLoginFailed(err) { page.flash("登录失败：" + err) }
    }

    // ---------- 底色 ----------
    // 用「同一张壁纸 + 深色压暗层」，而不是半透明透出下层：
    // 直接透下层会把启动页的大标题、按钮一起透出来，两层 UI 叠着更乱。
    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: (b && b.customBgPath && b.customBgPath.length > 0)
                ? ("file:///" + b.customBgPath)
                : "qrc:/ui/stage-aurora.jpg"
    }
    // 压暗：0xd9 ≈ 85%，壁纸隐约可见，正文对比度仍然够
    Rectangle { anchors.fill: parent; color: "#d908090d" }

    // ---------- 顶栏 ----------
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 56

        SButton {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 18 : 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: "返回"
            onClicked: page.close()
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 108 : 120
            anchors.verticalCenter: parent.verticalCenter
            text: "账户"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 162 : 174
            anchors.verticalCenter: parent.verticalCenter
            text: page.typeText
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: page.narrow ? 108 : 124
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // 提示条淡入淡出，不要硬切（文字内容变化时也顺滑）
                visible: opacity > 0.01
                opacity: page.hint.length > 0 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                }
                text: page.hint
                color: Theme.ok
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            SButton {
                kind: 1
                radius: 2
                height: 32
                iconName: "refresh-cw"
                text: "刷新状态"
                onClicked: {
                    if (!page.b) return
                    if (page.yg && page.yg.loggedIn) page.yg.validateSession()
                    page.flash("已刷新")
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        height: 1
        color: Theme.line
    }

    // ---------- 主体 ----------
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom

        // ===== 左列 =====
        Item {
            id: leftPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: page.leftW

            Rectangle {
                anchors.fill: parent
                color: "#c00a0c11"
            }

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 1
                color: Theme.line
            }

            Text {
                id: listTitle
                anchors.left: parent.left
                anchors.leftMargin: page.narrow ? 16 : 20
                anchors.top: parent.top
                anchors.topMargin: 16
                text: page.hasAccount && !page.loginPanel ? "当前账户" : "登录方式"
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Column {
                id: menu
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: listTitle.bottom
                anchors.topMargin: 10
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 2

                // 已登录且不在切换态：显示当前账号
                Rectangle {
                    visible: page.hasAccount && !page.loginPanel
                    width: menu.width
                    height: 56
                    radius: 8
                    color: "#161c26"
                    border.width: 1
                    border.color: "#232c3a"
                    // 左侧强调条：表明「当前正在使用」
                    Rectangle {
                        width: 2
                        height: parent.height - 18
                        radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        color: Theme.accent
                    }
                    SMinecraftHead {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        size: 34
                        rawSource: page.rawHeadSource
                        source: page.headSource
                        fallbackText: page.displayName
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 54
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            width: parent.width
                            text: page.displayName
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: page.hasOnline ? "正版 · 已登录" : "离线 · 仅本地"
                            color: page.hasOnline ? Theme.ok : Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                // 三个登录方式
                Repeater {
                    model: [
                        { t: "正版账户", s: "Microsoft 登录" },
                        { t: "离线账户", s: "只用用户名" },
                        { t: "外置登录", s: "皮肤站 / 第三方验证" }
                    ]
                    delegate: Item {
                        width: menu.width
                        height: 54
                        readonly property bool sel: page.tab === index
                        visible: !page.hasAccount || page.loginPanel
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: parent.sel ? "#151a23" : "transparent"
                        }
                        Rectangle {
                            visible: parent.sel
                            width: 2
                            height: parent.height - 16
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            color: Theme.accent
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.t
                            color: parent.sel ? "#ffffff" : "#cbd3de"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            text: modelData.s
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.tab = index
                        }
                    }
                }

                // 离线名历史
                Text {
                    width: menu.width
                    topPadding: 14
                    visible: page.tab === 1 && (!page.hasAccount || page.loginPanel) && page.b
                             && page.b.offlineUsernames.length > 0
                    text: "用过的名字"
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                Repeater {
                    model: (page.tab === 1 && page.b) ? page.b.offlineUsernames : []
                    delegate: Item {
                        width: menu.width
                        height: 30
                        visible: !page.hasAccount || page.loginPanel
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: "#9fb4cf"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { page.offlineInput = modelData }
                        }
                    }
                }
            }
        }

        // ===== 右侧 =====
        Item {
            id: rightPane
            anchors.left: leftPane.right
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            // ---- 已登录且不在切换态：账户详情 ----
            Column {
                visible: page.hasAccount && !page.loginPanel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: page.narrow ? 22 : 32
                anchors.rightMargin: page.narrow ? 22 : 32
                anchors.topMargin: 28
                spacing: 18

                Row {
                    spacing: 16
                    SMinecraftHead {
                        size: 56
                        rawSource: page.rawHeadSource
                        source: page.headSource
                        fallbackText: page.displayName
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: page.displayName
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.Bold
                        }
                        // 类型徽章：比一行裸文本更有「身份感」，也给头部补一点颜色
                        Rectangle {
                            visible: page.typeText.length > 0
                            height: 20
                            width: badgeText.implicitWidth + 18
                            radius: 10
                            color: "#1f3b82f6"
                            border.width: 1
                            border.color: "#3a5b9e"
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: page.typeText
                                color: "#a9c6f2"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "账号类型"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text { anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter; text: page.typeText; color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13 }
                    }
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "UUID"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (!page.b) return "—"
                                var u = page.hasOnline ? page.b.accountUuid : page.b.offlineUuid
                                if (!u || u.length === 0) return "—"
                                return u.length > 12 ? (u.substring(0, 8) + "…" + u.substring(u.length - 4)) : u
                            }
                            color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                    }
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "访问令牌"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter
                            text: page.hasOnline ? "已获取" : "不需要（离线）"
                            color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: page.hasOnline ? "后台自动续期" : ""
                            color: "#79828f"; font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                    }
                    Item {
                        width: parent.width; height: 40
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "皮肤"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter
                            text: (page.b && page.b.skinPath && page.b.skinPath.length > 0) ? "已同步" : "未设置"
                            color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                    }
                }

                Row {
                    spacing: 10
                    SButton {
                        kind: 1
                        radius: 2
                        height: 34
                        iconName: "user"
                        text: "切换账号"
                        onClicked: { page.loginPanel = true; page.tab = 0 }
                    }
                    SButton {
                        kind: 1
                        radius: 2
                        height: 34
                        iconName: "log-out"
                        text: "退出登录"
                        danger: true
                        onClicked: {
                            if (!page.b) return
                            if (page.yg && page.yg.loggedIn) page.yg.logout()
                            page.b.logout()
                            page.flash("已退出登录")
                        }
                    }
                }
            }

            // ---- 登录表单 ----
            Column {
                visible: !page.hasAccount || page.loginPanel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: page.narrow ? 22 : 32
                anchors.rightMargin: page.narrow ? 22 : 32
                anchors.topMargin: 28
                spacing: 16

                // 正版
                Column {
                    id: tabPanel0
                    visible: page.tab === 0
                    width: parent.width
                    spacing: 14
                    opacity: 0
                    transform: Translate { id: tabShift0; y: 8 }
                    onVisibleChanged: if (visible) tabIn0.restart()
                    ParallelAnimation {
                        id: tabIn0
                        NumberAnimation { target: tabPanel0; property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Theme.easeEnter }
                        NumberAnimation { target: tabShift0; property: "y"; from: 8; to: 0; duration: Theme.durBase; easing.type: Theme.easeEnter }
                    }
                    Text {
                        text: "用 Microsoft 账号登录"
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: "登录后可在正版服务器上玩，也会同步你的皮肤。"
                        color: "#9fb4cf"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    SButton {
                        kind: 0
                        height: 40
                        iconName: page.busy ? "x" : "globe"
                        text: page.busy ? "取消登录" : "开始登录"
                        busy: page.busy
                        onClicked: { if (page.busy) page.cancelMicrosoft(); else page.startMicrosoft() }
                    }
                    Item {
                        width: parent.width
                        height: 42
                        visible: page.busy || page.statusLine.length > 0
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: "#0f3b82f6"   // QML 不认 CSS 的 rgba()，用 ARGB 十六进制
                            border.width: 1
                            border.color: "#263140"
                        }
                        Rectangle {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: Theme.accent
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 32
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.statusLine.length > 0 ? page.statusLine : "正在打开浏览器…"
                            color: "#bcd0e8"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                // 离线
                Column {
                    id: tabPanel1
                    visible: page.tab === 1
                    width: parent.width
                    spacing: 12
                    opacity: 0
                    transform: Translate { id: tabShift1; y: 8 }
                    onVisibleChanged: if (visible) tabIn1.restart()
                    ParallelAnimation {
                        id: tabIn1
                        NumberAnimation { target: tabPanel1; property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Theme.easeEnter }
                        NumberAnimation { target: tabShift1; property: "y"; from: 8; to: 0; duration: Theme.durBase; easing.type: Theme.easeEnter }
                    }
                    Text {
                        text: "离线账户"
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: "只填一个用户名，不需要密码。"
                        color: "#9fb4cf"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        width: page.narrow ? 240 : 300
                        height: 40
                        radius: 8
                        color: "#11141b"
                        border.width: 1
                        border.color: page.offlineInput.length > 0 ? "#2a3646" : "#1c2029"
                        TextInput {
                            id: offlineField
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.offlineInput
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            selectionColor: Theme.accent
                            clip: true
                            onTextChanged: page.offlineInput = text
                            Text {
                                anchors.fill: parent
                                visible: offlineField.text.length === 0
                                text: "用户名"
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                    SButton {
                        kind: 0
                        height: 40
                        iconName: "play"
                        text: "使用这个用户名"
                        dimmed: page.offlineInput.trim().length === 0
                        onClicked: page.doOffline()
                    }
                }

                // 外置
                Column {
                    id: tabPanel2
                    visible: page.tab === 2
                    width: parent.width
                    spacing: 12
                    opacity: 0
                    transform: Translate { id: tabShift2; y: 8 }
                    onVisibleChanged: if (visible) tabIn2.restart()
                    ParallelAnimation {
                        id: tabIn2
                        NumberAnimation { target: tabPanel2; property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Theme.easeEnter }
                        NumberAnimation { target: tabShift2; property: "y"; from: 8; to: 0; duration: Theme.durBase; easing.type: Theme.easeEnter }
                    }
                    Text {
                        text: "外置登录"
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: "填皮肤站的 API 地址与账号（如 LittleSkin）。"
                        color: "#9fb4cf"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: [
                            { ph: "https://littleskin.cn/api/yggdrasil", key: 0 },
                            { ph: "邮箱", key: 1 },
                            { ph: "密码", key: 2 }
                        ]
                        delegate: Rectangle {
                            width: page.narrow ? 260 : 320
                            height: 40
                            radius: 8
                            color: "#11141b"
                            border.width: 1
                            border.color: "#1c2029"
                            TextInput {
                                id: f
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                selectionColor: Theme.accent
                                echoMode: modelData.key === 2 ? TextInput.Password : TextInput.Normal
                                text: modelData.key === 0 ? page.apiRootInput
                                      : (modelData.key === 1 ? page.emailInput : page.passwordInput)
                                onTextChanged: {
                                    if (modelData.key === 0) page.apiRootInput = text
                                    else if (modelData.key === 1) page.emailInput = text
                                    else page.passwordInput = text
                                }
                                Text {
                                    anchors.fill: parent
                                    visible: f.text.length === 0
                                    text: modelData.ph
                                    color: Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                    Text {
                        visible: page.yg !== null && page.yg.statusMessage.length > 0
                        width: parent.width
                        text: page.yg ? page.yg.statusMessage : ""
                        color: "#bcd0e8"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    SButton {
                        kind: 0
                        height: 40
                        iconName: "globe"
                        text: "登录"
                        onClicked: page.doExternal()
                    }
                }
            }
        }
    }
}
