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
    // 列表行规格：滑动指示条要靠它算步距（和版本页 listRowH/listRowGap 同一个思路）
    readonly property int acctRowH: 56
    readonly property int menuGap: 2
    readonly property int acctStride: acctRowH + menuGap
    readonly property int tabRowH: 62
    readonly property int tabStride: tabRowH + menuGap
    // 账号数据版本号：accounts 数组每次变化都会整体换新对象，
    // 行列表改用它来"原地重算"，避免 Repeater 把整列销毁重建（那就是切换账号时的闪烁）。
    property int accRev: 0

    Connections {
        target: page.b
        ignoreUnknownSignals: true
        function onAccountsChanged() { page.accRev++ }
        // 衣柜失败（尺寸不对 / 上传失败）必须让用户看到，否则点"应用"像没反应
        function onWardrobeError(msg) { page.flash(msg) }
        function onCapeChangeFinished(ok, msg) {
            page.flash(ok ? "披风已切换" : ("披风切换失败：" + msg))
        }
    }
    readonly property var yg: (b && b.yggdrasil) ? b.yggdrasil : null

    property int tab: 0                      // 0 正版 / 1 离线 / 2 外置
    property bool loginPanel: false          // true = 显示登录表单（切换账号时打开）
    property string offlineInput: ""
    property string apiRootInput: ""
    property string emailInput: ""
    property string passwordInput: ""
    property var toast: null          // StageShell 注入的 ToastHost：反馈统一走 Toast

    readonly property bool narrow: width < 900
    readonly property int leftW: narrow ? 240 : 300
    readonly property bool hasOnline: b ? b.isOnline : false
    readonly property bool hasExternal: (yg && yg.loggedIn) ? true : false
    readonly property bool hasOffline: (b && b.offlineUsername) ? b.offlineUsername.length > 0 : false
    readonly property bool hasAccount: hasOnline || hasOffline || hasExternal
    readonly property int accountCount: (b && b.accounts) ? b.accounts.length : 0
    readonly property bool busy: b ? b.microsoftLoginBusy : false
    readonly property string statusLine: (b && b.msStatus) ? b.msStatus : ""

    // ── 皮肤与披风（衣柜）──
    // 模型只有两种：Mojang 的 variant 就是 CLASSIC / SLIM，没有「自动」。
    // skinModelIndex = -1 表示"跟随官网值"；用户点过之后才用他自己的选择。
    property int skinModelIndex: -1
    readonly property int skinModelServer: (acct && String(acct.skinVariant || "").toUpperCase() === "SLIM") ? 1 : 0
    readonly property int skinModelShown: skinModelIndex >= 0 ? skinModelIndex : skinModelServer
    readonly property string skinFile: (b && b.selectedSkinPath) ? b.selectedSkinPath : ""
    readonly property bool wardrobeBusy: (b && b.wardrobeBusy) ? b.wardrobeBusy : false
    // 真实可用披风：来自 AccountBackend（Mojang profile 返回你已拥有的披风）。
    // 注意别再读 ShadowBackend.availableCapes —— 那是本地静态目录（全 Minecraft 披风图鉴），
    // 不是"你有哪几条"，也不能切换。
    readonly property var acct: (b && b.account) ? b.account : null
    readonly property var capes: (acct && acct.capes) ? acct.capes : []

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
        if (hasExternal && yg && yg.username) return yg.username
        if (b.offlineUsername) return b.offlineUsername
        return "未登录"
    }
    readonly property string typeText: {
        // 正在登录（换号）时不显示当前账号类型，避免顶栏写着"已登录"而正文在登录
        if (loginPanel) return ""
        if (b && b.isOnline) return "Microsoft 正版账户"
        if (hasExternal) return "外置账户"
        if (hasOffline) return "离线账户"
        return "未登录"
    }

    // ---- 右侧详情的"显示态" ----
    // 详情原来是直接绑后端实时值的：切换账号时新数据在同一次事件里替换旧数据，
    // 中间没有任何过渡（用户反馈"右侧信息载入无过渡"）。
    // 这里和版本页同一套：先淡出 → 完全透明时换快照 → 淡入 + 8px 上浮。
    property var acctView: null
    // 身份键：只有"换了账号"才播过渡动画。
    // 切到正版账号后后端还会陆续推 accountsChanged（恢复会话、补皮肤、令牌续期），
    // 那些事件不该让右侧重新"载入"一次。
    property string acctKey: ""
    function acctKeyNow() {
        if (!page.b) return ""
        var i = page.b.currentAccount
        var list = page.b.accounts
        var mode = "?"
        var nm = ""
        if (list && i >= 0 && i < list.length) {
            mode = String(list[i].mode)
            nm = String(list[i].name)
        }
        return i + "|" + mode + "|" + nm
    }
    function buildAcctView() {
        if (!page.b) return null
        var online = page.b.isOnline === true
        var u = online ? page.b.accountUuid : page.b.offlineUuid
        var skin = page.b.skinPath || ""
        return {
            name: page.displayName,
            typeText: page.typeText,
            online: online,
            head: page.headSource,
            rawHead: page.rawHeadSource,
            uuid: u ? u : "",
            skinText: skin.length > 0 ? "已同步" : "未设置"
        }
    }
    onLoginPanelChanged: if (!page.loginPanel) page.acctView = page.buildAcctView()

    // 反馈统一走 Toast（顶栏绿色文字会挤动右侧按钮，也留不住）
    function flash(msg) { if (page.toast) page.toast.show(msg) }
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

        // 空白处拖动窗口（无边框窗口没有系统标题栏，必须显式请求系统接管移动）。
        // 放在子项最前面：后面的按钮 / 搜索框都盖在它上面，控件照常响应，只有空白区能走到这里。
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: { if (backend) backend.beginWindowMove() }
        }

        SButton {
            id: backBtn
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 18 : 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: (page.hasAccount && page.loginPanel) ? "返回账户" : "返回"
            // 登录期间禁止离开本页：避免登录回调与页面切换互相踩
            dimmed: page.busy
            onClicked: {
                // 添加账号/换号态下，"返回"先退回账户详情。
                // 以前无论什么状态都直接 close()，进了添加账号就只剩"回主页"一条路，
                // 观感上就是"卡死在登录页"。
                if (page.hasAccount && page.loginPanel) { page.loginPanel = false; return }
                page.close()
            }
        }
        Text {
            id: pageTitle
            // 跟着按钮右边走，别用固定 leftMargin —— "返回账户"比"返回"宽，
            // 固定值会让它压到标题上（用户实测重叠）
            anchors.left: backBtn.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "账户"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            anchors.left: pageTitle.right
            anchors.leftMargin: 12
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
                text: page.hasAccount && !page.loginPanel ? "账户" : "登录方式"
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

                // 账号列表：一行一个已保存账号，当前账号高亮 + 左侧强调条。
                // 非当前账号没有真实皮肤（不缓存别人的头像），用名字首字母占位。
                Repeater {
                    // 模型是"行数"而不是 accounts 数组：数组换新时行不会被销毁重建，
                    // 内容变化由 accRev 触发重算。切换账号不再整列闪一下。
                    model: (page.b && page.b.accounts) ? page.b.accounts.length : 0
                    delegate: Item {
                        id: acctRow
                        visible: !page.loginPanel
                        width: menu.width
                        height: page.acctRowH
                        readonly property var acct: {
                            var rev = page.accRev   // 显式依赖：账号数据变了就重算
                            if (!page.b || !page.b.accounts) return null
                            return (index < page.b.accounts.length) ? page.b.accounts[index] : null
                        }
                        readonly property bool cur: !!acct && acct.current === true

                        // 底色只负责"当前账号"，悬停单独一层只动 opacity。
                        // 以前两者共用一个 color 绑定：切换时要从半透明白（#12ffffff）
                        // 插值到实心深色（#161c26），ARGB 通道直线插值会经过一段浅灰，
                        // 观感就是被切到的账号"大亮一下"。
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: acctRow.cur ? "#161c26" : "transparent"
                            border.width: acctRow.cur ? 1 : 0
                            border.color: "#232c3a"
                            Behavior on color {
                                ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: "#ffffff"
                            opacity: (acctHover.containsMouse && !acctRow.cur) ? 0.07 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                            }
                        }
                        SMinecraftHead {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            size: 34
                            // 每个账号在登录/切换时都存了头像快照；没有快照才退回首字母
                            source: (acctRow.acct && acctRow.acct.avatar && acctRow.acct.avatar.length > 0)
                                    ? acctRow.acct.avatar
                                    : (acctRow.cur ? page.headSource : "")
                            fallbackText: acctRow.acct ? acctRow.acct.name : ""
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
                                text: acctRow.acct ? acctRow.acct.name : ""
                                color: acctRow.cur ? "#ffffff" : "#cbd3de"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                readonly property bool relog: !!acctRow.acct && acctRow.acct.needsRelogin === true
                                text: relog ? "需重新登录" : (acctRow.acct ? acctRow.acct.typeText : "")
                                color: relog ? Theme.warn : (acctRow.cur ? Theme.ok : Theme.fg3)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                        MouseArea {
                            id: acctHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !page.busy
                            onClicked: {
                                var a = acctRow.acct
                                if (!page.b || !a) return
                                // 凭据已作废（登出过）：直接打开对应的登录表单重新验证，
                                // 而不是 switchAccount —— 那样只会静默失败
                                if (a.needsRelogin === true) {
                                    page.loginPanel = true
                                    page.tab = a.mode
                                    return
                                }
                                if (!a.current && page.b.switchAccount)
                                    page.b.switchAccount(a.index)
                            }
                        }
                    }
                }

                // 添加账号：入口放左侧列表里（右侧不再有"切换账号"——
                // 那个按钮点下去只是回到登录首屏，语义和"退出登录"撞车）
                Item {
                    id: addAccountRow
                    // 只有在"已有账号列表"时才需要这个入口；空列表时下面直接就是登录方式
                    visible: !page.loginPanel && page.accountCount > 0
                    width: menu.width
                    height: 38

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: addHover.containsMouse ? "#12ffffff" : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                        }
                    }
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        SIcon { name: "users"; size: 14; color: Theme.fg2 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "添加账号"
                            color: "#cbd3de"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        id: addHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { page.loginPanel = true; page.tab = 0 }
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
                        height: 62
                        readonly property bool sel: page.tab === index
                        visible: !page.hasAccount || page.loginPanel
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: parent.sel ? "#151a23" : "transparent"
                        }
                        Text {
                            x: 14
                            y: 12
                            height: 18
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.t
                            color: parent.sel ? "#ffffff" : "#cbd3de"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Text {
                            x: 14
                            y: 34
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

            // ---- 当前账号指示条（唯一一根）----
            // 和版本页同一套：换选中项时从旧行滑到新行。
            // 以前每行各长一根，切换时只是"这根消失、那根出现"，没有移动感。
            Item {
                id: acctSelLayer
                anchors.left: menu.left
                anchors.top: menu.top
                width: menu.width
                height: Math.max(0, page.accountCount * page.acctStride - page.menuGap)
                visible: !page.loginPanel && page.accountCount > 0
                         && page.b && page.b.currentAccount >= 0
                clip: true
                z: 3

                Rectangle {
                    property real animIdx: (page.b && page.b.currentAccount >= 0)
                                              ? page.b.currentAccount : 0
                    Behavior on animIdx {
                        NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter }
                    }
                    width: 2
                    height: 38
                    radius: 1
                    color: Theme.accent
                    y: animIdx * page.acctStride + (page.acctRowH - height) / 2
                }
            }

            // ---- 登录方式指示条（同一套做法）----
            Item {
                anchors.left: menu.left
                anchors.top: menu.top
                width: menu.width
                height: 3 * page.tabStride - page.menuGap
                visible: page.loginPanel || !page.hasAccount
                clip: true
                z: 3

                Rectangle {
                    property real animIdx: page.tab
                    Behavior on animIdx {
                        NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeEnter }
                    }
                    width: 2
                    height: 46
                    radius: 1
                    color: Theme.accent
                    y: animIdx * page.tabStride + (page.tabRowH - height) / 2
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

            // 账号数据一变（切换 / 登录完成 / 移除）：走一段过渡，而不是原地换字。
            // 触发点放在这里而不是页面根部，保证和动画同作用域
            Connections {
                target: page
                function onAccRevChanged() {
                    var key = page.acctKeyNow()
                    var sameAccount = (key === page.acctKey)
                    page.acctKey = key
                    // 首次铺数据 / 在登录面板里：直接铺，不演
                    if (page.acctView === null || !page.hasAccount || page.loginPanel) {
                        page.acctView = page.buildAcctView()
                        return
                    }
                    // 同一个账号的后台刷新（皮肤、令牌、uuid）：原地更新文字，不重播载入
                    if (sameAccount) {
                        page.acctView = page.buildAcctView()
                        return
                    }
                    detailSwap.restart()
                }
            }

            // 换账号：淡出（120ms）→ 在完全透明时换快照 → 淡入 + 8px 上浮（180ms）
            SequentialAnimation {
                id: detailSwap
                NumberAnimation {
                    target: detailCol; property: "opacity"; to: 0
                    duration: Theme.durFast; easing.type: Theme.easeExit
                }
                ScriptAction { script: page.acctView = page.buildAcctView() }
                ParallelAnimation {
                    NumberAnimation {
                        target: detailCol; property: "opacity"; from: 0; to: 1
                        duration: Theme.durBase; easing.type: Theme.easeEnter
                    }
                    NumberAnimation {
                        target: detailRise; property: "y"; from: 8; to: 0
                        duration: Theme.durBase; easing.type: Theme.easeEnter
                    }
                }
            }
            // 首次出现详情（进页面 / 关掉登录面板回来）
            ParallelAnimation {
                id: detailIn
                NumberAnimation {
                    target: detailCol; property: "opacity"; from: 0; to: 1
                    duration: Theme.durBase; easing.type: Theme.easeEnter
                }
                NumberAnimation {
                    target: detailRise; property: "y"; from: 8; to: 0
                    duration: Theme.durBase; easing.type: Theme.easeEnter
                }
            }

            // ---- 已登录且不在切换态：账户详情 ----
            // 详情区可能比窗口高（皮肤/披风两组卡片 + 底部操作）：必须可滚，
            // 否则"移除此账号"这类排在最后的东西会被裁到窗外点不到。
            Flickable {
                id: detailFlick
                anchors.fill: parent
                visible: page.hasAccount && !page.loginPanel
                contentWidth: width
                contentHeight: detailCol.implicitHeight + detailCol.y + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds

            Column {
                id: detailCol
                opacity: 0
                transform: Translate { id: detailRise; y: 0 }
                onVisibleChanged: if (visible) {
                    page.acctView = page.buildAcctView()
                    page.acctKey = page.acctKeyNow()
                    detailIn.restart()
                }
                // 首次进入：先把快照铺上，再淡入。没有这一步的话 acctView 一直是 null，
                // 第一次切换会走"无快照直接赋值"分支 —— 又变成没有过渡。
                Component.onCompleted: {
                    page.acctView = page.buildAcctView()
                    page.acctKey = page.acctKeyNow()
                    detailIn.restart()
                }
                x: page.narrow ? 22 : 32
                y: 28
                width: detailFlick.width - 2 * x
                spacing: 18

                Row {
                    spacing: 16
                    SMinecraftHead {
                        size: 56
                        // 头像不跟着 acctView 快照走：快照在"切账号那一刻"生成，
                        // 而正版皮肤是登录成功后异步下载/裁剪的 → 固化就会一直显示旧头像
                        rawSource: page.rawHeadSource
                        source: page.headSource
                        fallbackText: page.acctView ? page.acctView.name : ""
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: page.acctView ? page.acctView.name : ""
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.Bold
                        }
                        // 类型徽章：比一行裸文本更有「身份感」，也给头部补一点颜色
                        Rectangle {
                            visible: page.acctView ? page.acctView.typeText.length > 0 : false
                            height: 20
                            width: badgeText.implicitWidth + 18
                            radius: 10
                            color: "#1f3b82f6"
                            border.width: 1
                            border.color: "#3a5b9e"
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: page.acctView ? page.acctView.typeText : ""
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
                        Text { anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter; text: page.acctView ? page.acctView.typeText : ""; color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13 }
                    }
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "UUID"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        // UUID 完整显示（以前截成 8…4，等于看不全），右侧给一键复制
                        Text {
                            id: uuidValue
                            // 取"显示态"的 UUID：切换账号时它只在动画的透明帧里更新
                            readonly property string value: page.acctView ? page.acctView.uuid : ""
                            anchors.left: parent.left
                            anchors.leftMargin: 104
                            anchors.right: copyUuid.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: value.length > 0 ? value : "—"
                            color: "#d8dde5"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        SButton {
                            id: copyUuid
                            kind: 1
                            radius: 2
                            height: 26
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "复制"
                            visible: uuidValue.value.length > 0
                            onClicked: {
                                if (!page.b) return
                                page.b.copyToClipboard(uuidValue.value)
                                page.flash("已复制 UUID")
                            }
                        }
                    }
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "访问令牌"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter
                            text: (page.acctView && page.acctView.online) ? "已获取" : "不需要（离线）"
                            color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: (page.acctView && page.acctView.online) ? "后台自动续期" : ""
                            color: "#79828f"; font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                    }
                    Item {
                        width: parent.width; height: 40
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "皮肤"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter
                            text: page.acctView ? page.acctView.skinText : ""
                            color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                    }
                }

                // ---- 皮肤与披风 ----
                // 两层分组卡片：皮肤组（模型/文件/操作）自成一块，披风组自成一块。
                // 之前所有行和按钮平铺在一起，分不清哪个按钮属于哪一组。
                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        text: "皮肤与披风"
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    // ══ 皮肤 ══
                    Rectangle {
                        width: parent.width
                        height: skinInner.implicitHeight + 28
                        radius: 10
                        color: "#0b0e13"
                        border.width: 1
                        border.color: Theme.line

                        Column {
                            id: skinInner
                            x: 14
                            y: 14
                            width: parent.width - 28
                            spacing: 0

                            Text {
                                text: "皮肤"
                                color: "#98a1ae"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                bottomPadding: 6
                            }

                            Item {
                                width: parent.width; height: 40
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "模型"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                // Mojang 的 variant 只有 CLASSIC / SLIM 两种，没有「自动」这个第三种。
                                SSegmented {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 88
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 180
                                    itemHeight: 26
                                    items: ["经典", "纤细"]
                                    currentIndex: page.skinModelShown
                                    onActivated: (i) => page.skinModelIndex = i
                                }
                            }

                            Item {
                                width: parent.width; height: 40
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "皮肤文件"; color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 88
                                    anchors.right: pickBtn.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.skinFile.length > 0 ? page.skinFile : "未选择（64x64 或 64x32 PNG）"
                                    color: page.skinFile.length > 0 ? "#d8dde5" : "#5d6673"
                                    elide: Text.ElideMiddle
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                                SButton {
                                    id: pickBtn
                                    kind: 1
                                    radius: 2
                                    height: 26
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "选择"
                                    onClicked: { if (page.b) page.b.browseSkin() }
                                }
                            }

                            // 操作行收在皮肤组内部，不再和上面的字段平铺混排
                            Item {
                                width: parent.width
                                height: 52
                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    SButton {
                                        kind: 0
                                        radius: 2
                                        height: 32
                                        text: page.wardrobeBusy ? "上传中" : "应用皮肤"
                                        busy: page.wardrobeBusy
                                        enabled: page.skinFile.length > 0 && !page.wardrobeBusy
                                        onClicked: {
                                            if (!page.b) return
                                            page.b.saveWardrobeSettings(page.skinFile, "", page.skinModelShown === 1 ? 2 : 1)
                                            page.flash(page.hasOnline ? "正在上传皮肤" : "皮肤已保存到本地")
                                        }
                                    }
                                    SButton {
                                        kind: 1
                                        radius: 2
                                        height: 32
                                        text: "导出当前皮肤"
                                        onClicked: { if (page.b) page.b.saveSkinToFile() }
                                    }
                                }
                            }
                        }
                    }

                    // ══ 披风 ══
                    Rectangle {
                        width: parent.width
                        height: capeInner.implicitHeight + 28
                        radius: 10
                        color: "#0b0e13"
                        border.width: 1
                        border.color: Theme.line

                        Column {
                            id: capeInner
                            x: 14
                            y: 14
                            width: parent.width - 28
                            spacing: 8

                            Text {
                                text: "披风"
                                color: "#98a1ae"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                width: parent.width
                                text: page.capes.length > 0
                                      ? "点一下即刻切换；蓝框是当前使用中的披风。"
                                      : "这个账号没有可用披风（披风需在 Minecraft 活动中获得）。"
                                color: "#5d6673"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }

                            Flickable {
                                width: parent.width
                                height: page.capes.length > 0 ? 66 : 0
                                visible: page.capes.length > 0
                                contentWidth: capeRow.implicitWidth
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.HorizontalFlick

                                Row {
                                    id: capeRow
                                    spacing: 8
                                    Repeater {
                                        model: page.capes
                                        delegate: Rectangle {
                                            id: capeTile
                                            readonly property bool inUse: modelData && modelData.active === true
                                            width: 46
                                            height: 62
                                            radius: 6
                                            color: capeTile.inUse ? "#1f3b82f6"
                                                   : (capeHover.hovered ? "#161a22" : "#0e1116")
                                            border.width: 1
                                            border.color: capeTile.inUse ? "#3b82f6"
                                                        : (capeHover.hovered ? "#2a3341" : "#14171d")

                                            Image {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: 4
                                                width: 25
                                                height: 40
                                                // 披风纹理 64x32：正面（不穿鞘翅时看到的背面）就是左上 10x16。
                                                // 右半 32..46 是鞘翅用；整张缩下去会把它一起带进来，必须裁。
                                                // smooth:false = 最近邻放大，像素保持锐利（和头像同一个原则）。
                                                sourceClipRect: Qt.rect(0, 0, 10, 16)
                                                source: {
                                                    if (!modelData || !modelData.localPath) return ""
                                                    var p = modelData.localPath
                                                    return (p.indexOf("file:") === 0 || p.indexOf("qrc:") === 0)
                                                           ? p : ("file:///" + p.replace(/\\/g, "/"))
                                                }
                                                fillMode: Image.Stretch
                                                smooth: false
                                                asynchronous: true
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                anchors.bottomMargin: 4
                                                width: parent.width - 6
                                                text: capeTile.inUse ? "使用中"
                                                      : ((modelData && modelData.alias) ? modelData.alias : "")
                                                color: capeTile.inUse ? "#cfe0ff" : "#6b7686"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 8
                                                elide: Text.ElideRight
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            HoverHandler { id: capeHover }
                                            TapHandler {
                                                onTapped: {
                                                    if (!page.acct || capeTile.inUse) return
                                                    page.acct.selectCape(modelData.alias)
                                                }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        width: 46
                                        height: 62
                                        radius: 6
                                        visible: {
                                            for (var i = 0; i < page.capes.length; ++i)
                                                if (page.capes[i] && page.capes[i].active === true) return true
                                            return false
                                        }
                                        color: offHover.hovered ? "#161a22" : "#0e1116"
                                        border.width: 1
                                        border.color: offHover.hovered ? "#2a3341" : "#14171d"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "卸下"
                                            color: "#98a1ae"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                        HoverHandler { id: offHover }
                                        TapHandler {
                                            onTapped: { if (page.acct) page.acct.selectCape("") }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    spacing: 10
                    // 只保留"移除此账号"：退出登录与它语义重叠，用户明确要求合并
                    SButton {
                        kind: 1
                        radius: 2
                        height: 34
                        iconName: "x"
                        text: "移除此账号"
                        danger: true
                        visible: page.b && page.b.accounts && page.b.accounts.length > 0 && page.b.currentAccount >= 0
                        onClicked: {
                            if (!page.b) return
                            var i = page.b.currentAccount
                            if (i < 0) return
                            page.b.removeAccount(i)
                            page.flash("已移除该账号")
                        }
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
                    // 登录进度卡：以前是 42px 空盒子塞一行被截断的后端文案，
                    // 长文案（如"授权个人信息: ..."）只剩半句，看着像没做完的表单。
                    // 现在拆成「标题 + 明细（最多 3 行换行）」+ 呼吸点，高度随内容。
                    Rectangle {
                        id: statusCard
                        width: parent.width
                        height: statusCol.implicitHeight + 22
                        // busy 之外还要看 statusLine：开始登录的一瞬间 busy 可能还没翻过来，
                        // 但后端已经推了"打开浏览器"这类步骤文案
                        visible: page.busy || page.statusLine.length > 0
                        radius: 8
                        color: "#0f3b82f6"   // QML 不认 CSS 的 rgba()，用 ARGB 十六进制
                        border.width: 1
                        border.color: "#263140"

                        Rectangle {
                            id: statusDot
                            x: 14
                            y: statusCol.y + 5
                            width: 8; height: 8; radius: 4
                            color: Theme.accent
                            // 呼吸点：登录中才动（marquee 是循环周期，不是过渡时长）
                            SequentialAnimation on opacity {
                                running: page.busy
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 0.35; duration: Theme.marquee }
                                NumberAnimation { from: 0.35; to: 1.0; duration: Theme.marquee }
                            }
                        }
                        Column {
                            id: statusCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 32
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                width: parent.width
                                text: page.busy ? "正在登录 Microsoft 账号" : "登录状态"
                                color: "#dbe6f5"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                visible: page.statusLine.length > 0
                                text: page.statusLine
                                color: "#93a9c6"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
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
