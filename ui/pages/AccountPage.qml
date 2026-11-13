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

    Timer {
        id: refreshTimer
        interval: 4000
        onTriggered: page.refreshBusy = false
    }

    Timer {
        id: removeProbeTimer
        interval: 1800
        repeat: false
        onTriggered: {
            if (!page.b) return
            var cur = page.b.currentAccount
            if (cur >= 0) page.b.removeAccount(cur)
            console.info("[验收] 已移除当前账号 index=" + cur)
        }
    }

    Timer {
        id: externalProbeTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (!page.b) return
            var accx = page.b.accounts
            // 不要过滤 current：外置账号本来就可能是 current，
            // 之前加了 !current 条件导致钩子永远选不到它（静默失效）。
            for (var k = 0; k < accx.length; ++k) {
                if (accx[k] && accx[k].mode === 2) {
                    page.b.switchAccount(accx[k].index)
                    return
                }
            }
        }
    }

    // 披风/皮肤的结果信号由 AccountBackend 发出（不是 ShadowBackend），
    // 以前挂在 page.b 上 → 永远收不到，所以切换成功/失败都没有任何提示。
    // 外置登录（yggdrasil）的结果信号以前一条都没接 ——
    // 后端会正常 emit loginSuccess / loginFailed，但前端没人听，
    // 所以点「登录」之后界面永远没反应，看起来就是"用不了"。
    Connections {
        target: page.yg
        ignoreUnknownSignals: true
        function onLoginSuccess() {
            page.profilePickOpen = false
            page.loginPanel = false
            page.passwordInput = ""
            if (page.b) page.b.lastLoginMode = 2
            page.flash(qsTr("外置账号登录成功"))
        }
        function onLoginFailed(err) {
            page.profilePickOpen = false
            page.flash(qsTr("登录失败：%1").arg(err || qsTr("未知错误")))
        }
        function onShowProfileSelection() {
            page.profilePickOpen = true
            // 后端能按 uuid 拉皮肤并渲染成 128x128 头图（profileHeadUrls），
            // 不预先拉的话弹窗里只能显示首字母色块，用户分辨不出角色。
            if (page.yg) page.yg.preloadProfileSkins()
            page.flash(qsTr("这个账号有多个角色，请选择一个"))
        }
        function onMetaFailed(err) {
            // 元数据拉不到不影响登录，只在状态栏提示
            page.flash(qsTr("皮肤站元数据获取失败：%1").arg(err || ""))
        }
    }

    Connections {
        target: page.acct
        ignoreUnknownSignals: true
        function onCapeChangeFinished(ok, msg) {
            page.capeBusy = false
            if (ok) page.flash(qsTr("披风已切换"))
            else page.flash(qsTr("切换失败：%1").arg(msg || qsTr("未知错误")))
        }
        function onSkinReady() { page.refreshBusy = false }
        function onCapesReady() { page.refreshBusy = false }
        // 刷新的最终结果：成功/失败都要说清楚，
        // 只发一句「正在重新获取」然后没下文，等于告诉用户"卡住了"。
        function onRefreshFinished(ok, msg) {
            page.refreshBusy = false
            refreshTimer.stop()
            page.flash(ok ? qsTr("状态已刷新") : qsTr("刷新失败：%1").arg(msg || qsTr("未知错误")))
        }
        function onSkinUploadFinished(ok, msg) {
            // 不写"正在同步"之类内部说法：对用户来说上传成功就是换好了，
            // 头像重绘是后端自己的事，不该让他等一个看不见的"同步"。
            page.flash(ok ? qsTr("皮肤已更换") : qsTr("上传失败：%1").arg(msg || qsTr("未知错误")))
        }
    }

    Connections {
        target: page.b
        ignoreUnknownSignals: true
        function onAccountsChanged() { page.accRev++ }
        // 衣柜失败（尺寸不对 / 上传失败）必须让用户看到，否则点"应用"像没反应
        function onWardrobeError(msg) { page.flash(msg) }
    }
    readonly property var yg: (b && b.yggdrasil) ? b.yggdrasil : null
    // 当前"被选中"的那条账号（accounts 数组 + currentAccount 索引）。
    // 详情面板必须以它为准：外置账号身份属于 YggdrasilBackend，
    // 光看 backend.isOnline 会把正版身份套到外置条目上。
    readonly property var curAcct: {
        if (!b || !b.accounts) return null
        const idx = b.currentAccount
        if (idx < 0 || idx >= b.accounts.length) return null
        return b.accounts[idx]
    }
    readonly property int curMode: curAcct ? curAcct.mode : -1
    // 外置账号真正可用的判定：已登录 且 未被服务端标记失效。
    // 只信 yg.loggedIn 会出错——恢复会话时它立刻就 true，而校验还没回来。
    readonly property bool externalLive: !!yg && yg.loggedIn === true
        && !(curAcct && curAcct.needsRelogin === true)

    // 验收钩子用：待处理的拖入路径（等 backend 就绪后再喂）
    property string pendingDrop: ""
    // --ui-account-addr <host>：直接走一次 fillApiHost，等价于点上方快捷钮。
    // 用来验收"点完之后页面长什么样" —— 真实点击没法脚本模拟，但入口是同一函数。
    property string pendingAddr: ""
    // 全局拖入把 authlib-injector 链接里的地址送到这里（StageShell 注入）
    property string externalApiToApply: ""
    onExternalApiToApplyChanged: {
        if (externalApiToApply.length === 0) return
        tab = 2
        loginPanel = true
        apiRootInput = externalApiToApply
        if (page.yg) {
            page.yg.fetchMeta(externalApiToApply)
        }
    }
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
    // 「正在浏览账号」= 有账号且不在登录表单里。
    // 不能再用 hasAccount 判：hasAccount 只表示「真的登录着」，
    // 唯一账号失效后它是 false，界面会同时走「无账号」和「有账号列表」两套布局 —— 就是那次 UI 紊乱。
    readonly property bool browsingAccounts: accountCount > 0 && !loginPanel
    // 点了某个「需重新登录」的账号：右侧改显示重新登录卡片，而不是把他扔进登录页
    property int reloginIdx: -1
    readonly property var reloginAcct: {
        if (!b || !b.accounts || reloginIdx < 0 || reloginIdx >= b.accounts.length) return null
        return b.accounts[reloginIdx]
    }
    readonly property bool showRelogin: !!reloginAcct && reloginAcct.needsRelogin === true

    // 让右侧卡片跟着「当前账号是否失效」走：
    // 唯一账号失效时如果只默认 -1，右侧会是空白（详情要 hasAccount、表单要 browsingAccounts=false，两边都不成立）。
    function syncReloginCard() {
        if (page.loginPanel || !page.b || !page.b.accounts) return
        var accs = page.b.accounts
        var cur = page.b.currentAccount
        var acc = (cur >= 0 && cur < accs.length) ? accs[cur] : null
        if (acc && acc.needsRelogin === true) {
            page.reloginIdx = cur
        } else if (page.reloginIdx >= 0) {
            var sel = page.reloginAcct
            if (!sel || sel.needsRelogin !== true) page.reloginIdx = -1
        }
    }
    readonly property bool busy: b ? b.microsoftLoginBusy : false
    readonly property string statusLine: (b && b.msStatus) ? b.msStatus : ""

    // ── 皮肤与披风（衣柜）──
    // 模型只有两种：Mojang 的 variant 就是 CLASSIC / SLIM，没有「自动」。
    // skinModelIndex = -1 表示"跟随官网值"；用户点过之后才用他自己的选择。
    property int skinModelIndex: -1
    readonly property int skinModelServer: (acct && String(acct.skinVariant || "").toUpperCase() === "SLIM") ? 1 : 0
    readonly property int skinModelShown: skinModelIndex >= 0 ? skinModelIndex : skinModelServer

    // 切换披风必须等服务器回包（1~3 秒），期间不给反馈就会以为没点上。
    // 这两个 busy 都是"点了置 true、收到完成信号置 false"，绝不在点击后立刻复位。
    property bool capeBusy: false
    // 「刷新状态」没有单一完成信号（皮肤/披风各自异步回来），
    // 用一次短计时表示进行中：够覆盖网络往返，又不会一直转。
    property bool refreshBusy: false
    // 外置登录返回多个角色时置 true，让用户选一个再完成登录
    property bool profilePickOpen: false
    readonly property bool skinBusy: (b && b.wardrobeBusy) ? b.wardrobeBusy : false
    // 对外（StageShell）用来点亮顶部光条。注意不能叫 busy ——
    // 上面已有 busy（登录忙碌），重名会编译失败。
    // 皮肤/披风在拉取（含逐张下载）也算忙：顶部 SLoadingBar 统一显示这类不确定等待。
    readonly property bool wardrobeBusy: skinBusy || capeBusy || refreshBusy || capesLoading
    readonly property string skinFile: (b && b.selectedSkinPath) ? b.selectedSkinPath : ""
    // 真实可用披风：来自 AccountBackend（Mojang profile 返回你已拥有的披风）。
    // 注意别再读 ShadowBackend.availableCapes —— 那是本地静态目录（全 Minecraft 披风图鉴），
    // 不是"你有哪几条"，也不能切换。
    readonly property var acct: (b && b.account) ? b.account : null
    readonly property var capes: (acct && acct.capes) ? acct.capes : []
    // 披风正在拉取（后端 capesLoading 的代理，含逐张下载）。
    // 注意 b 是 ShadowBackend，直接读 b.capesLoading 会拿到 undefined（踩过），
    // 必须走 accountLoading 这个代理；光条与文案都只认这一个状态。
    // 切号时后端会立刻置 false，加载条不会跟到下一个账号身上。
    readonly property bool capesLoading: (b && b.accountLoading) ? b.accountLoading : false
    readonly property bool capeLoadingVisible: capesLoading && capes.length === 0
    // 披风是否已经问过服务器：没问过时不许说「此账号没有可用披风」
    readonly property bool capesAsked: (b && b.capesAsked) ? b.capesAsked : false

    // 原始皮肤优先（自己裁脸）；头部图兜底
    readonly property string rawHeadSource: (b && b.isOnline) ? (b.skinTexturePath || "") : ""
    readonly property string headSource: {
        if (!b) return ""
        // 外置账号的头像来自它自己的皮肤站，不能借用正版/离线的头像
        if (curMode === 2) {
            const sf = (yg && yg.skinFetcher) ? yg.skinFetcher : null
            return (sf && sf.skinPath) ? sf.skinPath : ""
        }
        if (curMode === 1) return b.offlineSkinPath || ""
        if (b.isOnline) return b.skinPath || b.offlineSkinPath || ""
        return b.offlineSkinPath || ""
    }
    readonly property string displayName: {
        if (!b) return qsTr("未登录")
        // 选中哪条就显示哪条的名字
        if (curAcct && curAcct.name) return curAcct.name
        if (b.isOnline && b.username) return b.username
        if (hasExternal && yg && yg.username) return yg.username
        if (b.offlineUsername) return b.offlineUsername
        return qsTr("未登录")
    }
    readonly property string typeText: {
        // 正在登录（换号）时不显示当前账号类型，避免顶栏写着"已登录"而正文在登录
        if (loginPanel) return ""
        // 以"选中的那条账号"为准，而不是 backend 当前是谁在线。
        // 否则选中外置账号时，会被 backend.isOnline（正版还在线）抢先判成正版。
        if (curMode === 0) return qsTr("Microsoft 正版账户")
        if (curMode === 2) return page.externalLive ? qsTr("外置账户") : qsTr("外置账户（需重新登录）")
        if (curMode === 1) return qsTr("离线账户")
        if (b && b.isOnline) return qsTr("Microsoft 正版账户")
        if (hasExternal) return qsTr("外置账户")
        if (hasOffline) return qsTr("离线账户")
        return qsTr("未登录")
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
        var m = page.curMode
        var u = ""
        var skinText = qsTr("未设置")
        if (m === 2) {
            // 外置：uuid 取 YggdrasilBackend，皮肤取它的皮肤站贴图
            u = (page.yg && page.yg.uuid) ? page.yg.uuid
              : (page.curAcct && page.curAcct.uuid ? page.curAcct.uuid : "")
            var sf = (page.yg && page.yg.skinFetcher) ? page.yg.skinFetcher : null
            if (page.externalLive) {
                skinText = (sf && sf.skinPath) ? qsTr("已同步（皮肤站）") : qsTr("未获取")
            } else {
                skinText = qsTr("需重新登录")
            }
        } else if (m === 1) {
            u = page.b.offlineUuid || ""
            skinText = (page.b.offlineSkinPath || "").length > 0 ? qsTr("已同步") : qsTr("未设置")
        } else {
            var online = page.b.isOnline === true
            u = online ? page.b.accountUuid : page.b.offlineUuid
            skinText = (page.b.skinPath || "").length > 0 ? qsTr("已同步") : qsTr("未设置")
        }
        return {
            name: page.displayName,
            typeText: page.typeText,
            online: m === 0 ? (page.b.isOnline === true) : (m === 2 ? page.externalLive : false),
            head: page.headSource,
            rawHead: page.rawHeadSource,
            uuid: u ? u : "",
            skinText: skinText,
            tokenText: (m === 0) ? ((page.b.isOnline === true) ? qsTr("已获取") : qsTr("不需要（离线）"))
                     : (m === 2) ? (page.externalLive ? qsTr("已获取（皮肤站）") : qsTr("已失效，需重新登录"))
                     : qsTr("不需要（离线）")
        }
    }
    onLoginPanelChanged: if (!page.loginPanel) page.acctView = page.buildAcctView()

    // 反馈统一走 Toast（顶栏绿色文字会挤动右侧按钮，也留不住）
    // force=true：绕过 ToastHost 的"近期相同消息"去重。
    // 连续两次切披风成功文案一模一样，不去重的话第二次会被静默吞掉，
    // 表现就是"只有第一次有提示，之后再切完全没反应"。
    function flash(msg) { if (page.toast) page.toast.show(msg, undefined, undefined, true) }
    function startMicrosoft() { if (page.b) { page.b.lastLoginMode = 0; page.b.microsoftLogin() } }
    function cancelMicrosoft() { if (page.b) page.b.cancelMicrosoftLogin() }
    function doOffline() {
        if (!page.b) return
        var n = page.offlineInput.trim()
        if (n.length === 0) { page.flash(qsTr("先填一个用户名")); return }
        page.b.lastLoginMode = 1
        page.b.offlineLogin(n)
        page.flash(qsTr("已切换到离线账户 %1").arg(n))
    }
    // 快捷填入：只写域名，真正地址由 ALI 解析（见后端 resolveApiRoot）
    function fillApiHost(host) {
        page.apiRootInput = host
        if (page.yg) page.yg.resolveApiRoot(host)
    }

    // 登录前先确保地址是完整的 API 根：
    // 用户可能只写了 littleskin.cn，直接拿去拼 /authserver/authenticate 会 404。
    property bool pendingLogin: false
    function doExternal() {
        if (!page.yg) return
        if (page.apiRootInput.length === 0 || page.emailInput.length === 0 || page.passwordInput.length === 0) {
            page.flash(qsTr("地址、账号、密码都要填"))
            return
        }
        // 已经是完整 API 根就不折腾；否则先解析一次
        var raw = page.apiRootInput.trim()
        if (raw.indexOf("/api/") < 0 && raw.indexOf("yggdrasil") < 0) {
            page.pendingLogin = true
            page.yg.resolveApiRoot(raw)
            return
        }
        page.loginNow()
        // 不能在认证成功之前写 lastLoginMode：
        // 一旦写了，下次启动会按"上次是外置"去恢复那条（可能已失效的）会话，
        // 失败后又被判过期 —— 用户看到的就是"一点就说过期"的死循环。
        // 改为在 onLoginSuccess 里再落 lastLoginMode。
        page.loginNow()
    }

    // 拖入处理：逐个尝试识别，命中一个就够（不要把多个文件都当 API 地址）
    function handleDroppedFiles(urls) {
        if (!page.yg || !urls || urls.length === 0) return
        for (var i = 0; i < urls.length; ++i) {
            // 先看是不是 authlib-injector 的拖拽链接：
            //   authlib-injector:yggdrasil-server:https%3A%2F%2Flittleskin.cn%2Fapi%2Fyggdrasil
            // 这个格式在皮肤站页面上可以直接拖进启动器，是最省事的一条路，
            // 但它不是文件，必须走字符串解析而不是文件读取。
            var fromLink = String(page.b.parseAuthlibInjectorLink(String(urls[i])))
            if (fromLink.length > 0) {
                page.apiRootInput = fromLink
                page.yg.resolveApiRoot(fromLink)
                page.flash(qsTr("已从链接识别出 API 地址"))
                return
            }
            var kind = String(page.yg.resolveApiFromFile(String(urls[i])))
            if (kind.length === 0) continue
            if (kind === "api") {
                page.flash(qsTr("已从文件识别出 API 地址"))
                return
            }
            if (kind === "authlib") {
                // 认出了 authlib-injector 但里面没有站点地址：
                // 启动器本来就会在启动外置账号时自动下载/使用它，所以这里只需要告诉用户下一步
                page.flash(qsTr("已识别 authlib-injector，请再填站点地址（如 littleskin.cn）"))
                return
            }
        }
        page.flash(qsTr("没能从这个文件里识别出外置登录信息"))
    }

    function loginNow() {
        if (!page.yg) return
        page.yg.login(page.apiRootInput.trim(), page.emailInput.trim(), page.passwordInput)
        page.flash(qsTr("正在登录外置账户…"))
    }

    Component.onCompleted: {
        if (page.b) {
            page.tab = page.b.lastLoginMode
            if (page.offlineInput.length === 0) page.offlineInput = page.b.offlineUsername || ""
        }
        // 这里曾经把上次用过的 apiRoot 回填进输入框并立刻 fetchMeta。
        // 但这是一个"还没登录"的表单：预填一个地址会让人以为已经配好了，
        // 而 store 里的地址只说明"上次试过"，不代表现在有效。
        // 重启后应当是干净的空白表单，地址由用户点快捷钮或粘贴后当场解析。
        if (Qt.application.arguments.indexOf("--ui-account-login") >= 0)
            page.loginPanel = true
        // accounts.json 是异步装载的，这里先试一次；真正生效靠 accRevChanged 里的 syncReloginCard()
        page.syncReloginCard()
        // --ui-account-drop <path>：把一条本地路径直接喂给拖入处理函数。
        // 只用于验收「文件 -> 提取 API 地址」这段链路（真正的 DropArea 事件
        // 无法用脚本可靠模拟，那部分由 SDropZone 的独立探针覆盖）。
        var di = Qt.application.arguments.indexOf("--ui-account-drop")
        if (di >= 0 && di + 1 < Qt.application.arguments.length) {
            page.tab = 2
            page.loginPanel = true
            // 不能在这里立刻喂：此时 page.yg 往往还没注入，handleDroppedFiles 会直接 return。
            // 交给一个短 Timer 等 backend 挂上。
            page.pendingDrop = Qt.application.arguments[di + 1]
        }
        // --ui-account-tab N：直接落在某个登录 tab（0 正版 / 1 离线 / 2 外置），截图验收用
        var ai = Qt.application.arguments.indexOf("--ui-account-addr")
        if (ai >= 0 && ai + 1 < Qt.application.arguments.length) {
            page.tab = 2
            page.loginPanel = true
            page.pendingAddr = Qt.application.arguments[ai + 1]
        }
        var ti = Qt.application.arguments.indexOf("--ui-account-tab")
        if (ti >= 0 && ti + 1 < Qt.application.arguments.length) {
            var tv = parseInt(Qt.application.arguments[ti + 1], 10)
            if (!isNaN(tv) && tv >= 0 && tv <= 2) {
                page.tab = tv
                page.loginPanel = true
            }
        }
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onMicrosoftLoginSuccess() { page.loginPanel = false; page.flash(qsTr("登录成功")) }
        function onMicrosoftLoginFailed(err) { page.flash(qsTr("登录失败：%1").arg(err)) }
    }

    // ALI（API 地址指示）解析结果
    // 钩子落地：backend 就绪后处理挂起的拖入路径
    Timer {
        interval: 700
        running: page.pendingDrop.length > 0 && page.yg !== null
        repeat: true
        onTriggered: {
            var p2 = page.pendingDrop
            page.pendingDrop = ""
            page.handleDroppedFiles([p2])
        }
    }

    Timer {
        interval: 700
        running: page.pendingAddr.length > 0 && page.yg !== null
        repeat: true
        onTriggered: {
            var h = page.pendingAddr
            page.pendingAddr = ""
            page.fillApiHost(h)
        }
    }

    Connections {
        target: page.yg
        enabled: page.yg !== null
        function onApiRootResolved(resolved) {
            page.apiRootInput = resolved
            // 拿到真实地址后顺手问一次 meta：站点名和注册链接都在里面，
            // 不查的话用户看到的只是一个地址，不知道这是哪个站、该去哪注册。
            if (page.yg) page.yg.fetchMeta(resolved)
            if (page.pendingLogin) {
                page.pendingLogin = false
                page.loginNow()
            }
        }
        function onApiRootResolveFailed(error) {
            page.pendingLogin = false
            page.flash(error)
        }
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
            tone: "dark"
            id: backBtn
            anchors.left: parent.left
            anchors.leftMargin: page.narrow ? 18 : 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: (page.hasAccount && page.loginPanel) ? qsTr("返回账户") : qsTr("返回")
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
            text: qsTr("账户")
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
            color: Theme.imageFgFaint
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: page.narrow ? 108 : 124
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            SButton {
                tone: "dark"
                kind: 1
                radius: 2
                height: 32
                iconName: "refresh-cw"
                text: page.refreshBusy ? qsTr("刷新中") : qsTr("刷新状态")
                busy: page.refreshBusy
                // 以前这里只对「外置登录」调 validateSession()，正版账号什么都不做，
                // 却照样提示"已刷新" —— 纯假按钮。
                // 现在按账号类型做对应的真实刷新（当前账号）：
                //   正版 -> 强制向 Mojang 重拉皮肤+披风（downloadOnlineSkin(true)）
                //   外置 -> 校验会话
                //   离线 -> 重算 UUID 头像
                onClicked: {
                    if (!page.b) return
                    page.refreshBusy = true
                    refreshTimer.restart()
                    // 不在这里 flash「正在...」——按钮已变「刷新中」、顶部光条已亮，
                    // 再加一条过程提示只会和结果提示撞在一起。结果统一由 onRefreshFinished 给。
                    if (page.hasOnline) {
                        if (page.acct) page.acct.refreshSkin()
                    } else if (page.yg && page.yg.loggedIn) {
                        page.yg.validateSession()
                        page.refreshBusy = false
                        refreshTimer.stop()
                        page.flash(qsTr("已校验外置登录会话"))
                    } else if (page.hasOffline) {
                        if (page.acct) page.acct.refreshSkin()
                    } else {
                        page.refreshBusy = false
                        refreshTimer.stop()
                        page.flash(qsTr("当前还没有账号"))
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        height: 1
        color: Theme.pLine
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
                color: Theme.pLine
            }

            Text {
                id: listTitle
                anchors.left: parent.left
                anchors.leftMargin: page.narrow ? 16 : 20
                anchors.top: parent.top
                anchors.topMargin: 16
                text: page.browsingAccounts ? qsTr("账户") : qsTr("登录方式")
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
                                text: relog ? qsTr("需重新登录") : (acctRow.acct ? acctRow.acct.typeText : "")
                                color: relog ? Theme.warn : (acctRow.cur ? Theme.ok : Theme.imageFgFaint)
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
                                // 凭据已作废：既不 switchAccount（只会静默失败），
                                // 也不直接跳登录页（会把左侧撑成「账号列表 + 登录方式」两套布局，
                                // 影报过的 UI 紊乱）。改为右侧显示该账号的重新登录卡片，
                                // 由卡片上的「重新登录 / 移除此账号」决定下一步。
                                if (a.needsRelogin === true) {
                                    page.loginPanel = false
                                    page.reloginIdx = a.index
                                    return
                                }
                                page.reloginIdx = -1
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
                        SIcon { name: "users"; size: 14; color: Theme.imageFgDim }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("添加账号")
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
                        { t: qsTr("正版账户"), s: qsTr("Microsoft 登录") },
                        { t: qsTr("离线账户"), s: qsTr("只用用户名") },
                        { t: qsTr("外置登录"), s: qsTr("皮肤站 / 第三方验证") }
                    ]
                    delegate: Item {
                        width: menu.width
                        height: 62
                        readonly property bool sel: page.tab === index
                        visible: !page.browsingAccounts
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
                            color: Theme.imageFgFaint
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
                    visible: page.tab === 1 && !page.browsingAccounts && page.b
                             && page.b.offlineUsernames.length > 0
                    text: qsTr("用过的名字")
                    color: Theme.imageFgFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                Repeater {
                    model: (page.tab === 1 && page.b) ? page.b.offlineUsernames : []
                    delegate: Item {
                        width: menu.width
                        height: 30
                        visible: !page.browsingAccounts
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
                visible: !page.browsingAccounts
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
                    page.syncReloginCard()
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
                visible: page.hasAccount && !page.loginPanel && !page.showRelogin
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
                    // 验收钩子：--acct-refresh 时自动走一次「刷新状态」（验证强制刷新路径，只读不改账号）
                    if (Qt.application.arguments.indexOf("--acct-refresh") >= 0 && page.acct) {
                        page.refreshBusy = true
                        refreshTimer.restart()
                        page.acct.refreshSkin()
                    }
                    // 验收钩子：--acct-external 时切到外置账号（验证会话恢复/校验链路）。
                    // 必须延时：Component.onCompleted 时 accounts.json 还没加载完，
                    // 立即读 page.b.accounts 会拿到空数组，钩子静默失效。
                    if (Qt.application.arguments.indexOf("--acct-external") >= 0) {
                        externalProbeTimer.start()
                    }
                    // 验收钩子：--acct-remove-current 删掉当前账号（验证「重启后不会复活」）
                    if (Qt.application.arguments.indexOf("--acct-remove-current") >= 0) {
                        removeProbeTimer.start()
                    }
                    // 验收钩子：--acct-online 时切到第一个正版账号（截图核对用）
                    if (Qt.application.arguments.indexOf("--acct-online") >= 0 && page.b) {
                        var acc = page.b.accounts
                        for (var i = 0; i < acc.length; ++i) {
                            if (acc[i] && acc[i].mode === 0 && !acc[i].current) {
                                page.b.switchAccount(acc[i].index)
                                break
                            }
                        }
                    }
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
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: qsTr("账号类型"); color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
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
                            tone: "dark"
                            id: copyUuid
                            kind: 1
                            radius: 2
                            height: 26
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("复制")
                            visible: uuidValue.value.length > 0
                            onClicked: {
                                if (!page.b) return
                                page.b.copyToClipboard(uuidValue.value)
                                page.flash(qsTr("已复制 UUID"))
                            }
                        }
                    }
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: qsTr("访问令牌"); color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter
                            text: page.acctView ? (page.acctView.tokenText || "") : ""
                            color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: (page.curMode === 0 && page.acctView && page.acctView.online) ? qsTr("后台自动续期") : ""
                            color: "#79828f"; font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                    }
                    Item {
                        width: parent.width; height: 40
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: qsTr("皮肤"); color: "#6d7684"; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 104; anchors.verticalCenter: parent.verticalCenter
                            text: page.acctView ? page.acctView.skinText : ""
                            color: "#d8dde5"; font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                    }
                }

                // ---- 皮肤与披风 ----
                // 样式与上方账号信息行统一：无卡片底、只用分隔线，避免一大块深色割裂版面。
                // 分组靠小标题 + 缩进，不靠色块。
                Column {
                    width: parent.width
                    // 只有正版账号能在这里换皮肤/披风：
                    // 上传走 Mojang API，外置账号属于皮肤站，接口完全不同且当前未实现，
                    // 摆出来只会是点了没用的假控件。
                    visible: page.curMode === 0 && page.hasOnline
                    spacing: 0

                    // 区块标题
                    Item {
                        width: parent.width
                        height: 34
                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: qsTr("皮肤")
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }

                    // 模型
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("模型")
                            color: "#6d7684"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        SSegmented {
                            anchors.left: parent.left
                            anchors.leftMargin: 104
                            anchors.verticalCenter: parent.verticalCenter
                            width: 180
                            itemHeight: 26
                            items: [qsTr("经典"), qsTr("纤细")]
                            currentIndex: page.skinModelShown
                            onActivated: (i) => page.skinModelIndex = i
                        }
                    }

                    // 皮肤文件
                    Item {
                        width: parent.width; height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("皮肤文件")
                            color: "#6d7684"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 104
                            anchors.right: pickBtn.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.skinFile.length > 0 ? page.skinFile : qsTr("未选择（64x64 或 64x32 PNG）")
                            color: page.skinFile.length > 0 ? "#d8dde5" : "#5d6673"
                            elide: Text.ElideMiddle
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        SButton {
                            tone: "dark"
                            id: pickBtn
                            kind: 1
                            radius: 2
                            height: 26
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("选择")
                            onClicked: { if (page.b) page.b.browseSkin() }
                        }
                    }

                    // 操作行
                    Item {
                        width: parent.width
                        height: 56
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#101319" }
                        Row {
                            id: actionRow
                            // 与上方字段值同一个 104 基准（"账号类型"等行的值都从 104 起）
                            x: 104
                            y: Math.round((parent.height - height) / 2)
                            spacing: 10
                            SButton {
                                tone: "dark"
                                kind: 0
                                radius: 2
                                height: 30
                                text: page.skinBusy ? qsTr("上传中") : qsTr("应用皮肤")
                                busy: page.skinBusy
                                // 没选文件时按钮必须真的点不动，并且视觉上要看得出来。
                                // SButton 的 dimmed 本身就带"不可点 + 变灰"语义，
                                // 光靠 enabled:false 只是逻辑禁用、看着还是蓝色实心按钮，等于没提示。
                                dimmed: page.skinFile.length === 0 || page.skinBusy
                                onClicked: {
                                    if (!page.b) return
                                    page.b.saveWardrobeSettings(page.skinFile, "", page.skinModelShown === 1 ? 2 : 1)
                                    page.flash(page.hasOnline ? qsTr("正在上传皮肤") : qsTr("皮肤已保存到本地"))
                                }
                            }
                            SButton {
                                tone: "dark"
                                kind: 1
                                radius: 2
                                height: 30
                                text: qsTr("导出当前皮肤")
                                onClicked: { if (page.b) page.b.saveSkinToFile() }
                            }
                        }
                    }

                    // 披风标题（与「皮肤」标题同样左对齐，不用 104 缩进）
                    Item {
                        width: parent.width
                        height: 42
                        Text {
                            id: capeTitle
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: qsTr("披风")
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            id: capeHint
                            anchors.left: capeTitle.right
                            anchors.leftMargin: 10
                            anchors.baseline: capeTitle.baseline
                            text: page.capeBusy ? qsTr("正在切换...")
                                  : (page.capes.length > 0
                                     ? qsTr("点击切换，蓝框为当前使用")
                                     : (page.capeLoadingVisible
                                        ? qsTr("正在获取…")
                                        : (page.capesAsked
                                           ? qsTr("此账号没有可用披风")
                                           : "")))
                            color: "#5d6673"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    // 披风列表
                    Flickable {
                        id: capeFlick
                        width: parent.width
                        // 给上下各留 2px：磁贴若是正好贴着 Flickable 的裁剪边界，
                        // 边框/圆角在高 DPI 或不同窗口尺寸下会被裁掉几个像素。
                        height: page.capes.length > 0 ? 82 : 0
                        visible: page.capes.length > 0
                        contentWidth: capeRow.implicitWidth
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick

                        Row {
                            id: capeRow
                            y: 2
                            spacing: 8
                            Repeater {
                                model: page.capes
                                delegate: Rectangle {
                                    id: capeTile
                                    readonly property bool inUse: modelData && modelData.active === true
                                    width: 46
                                    height: 74
                                    radius: 6
                                    color: capeTile.inUse ? "#1f3b82f6"
                                           : (capeHover.hovered ? "#161a22" : "transparent")
                                    border.width: 1
                                    border.color: capeTile.inUse ? "#3b82f6"
                                                : (capeHover.hovered ? "#2a3341" : "#1a1e26")

                                    Item {
                                        id: capeBox
                                        readonly property int tileW: 28
                                        readonly property int tileH: 45
                                        readonly property real zoom: capeBox.tileW / 10.0
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 5
                                        width: capeBox.tileW
                                        height: capeBox.tileH
                                        clip: true

                                        Image {
                                            width: 64 * capeBox.zoom
                                            height: 32 * capeBox.zoom
                                            x: -capeBox.zoom
                                            y: -capeBox.zoom
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
                                    }
                                    // 名字永远显示（以前选中后名字被「使用中」顶掉，等于看不到选的是哪条），
                                    // 用蓝框 + 右侧小圆点表示"使用中"，两者并存。
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 4
                                        width: parent.width - 6
                                        text: (modelData && modelData.alias) ? modelData.alias : ""
                                        color: capeTile.inUse ? "#cfe0ff" : "#6b7686"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    // 不加右上角圆点：蓝框本身已经表示"使用中"，
                                    // 圆点压在磁贴边框上会把上边缘盖出一个缺口。
                                    HoverHandler { id: capeHover }
                                    TapHandler {
                                        onTapped: {
                                            if (!page.acct || capeTile.inUse || page.capeBusy) return
                                            // 切换要走服务器，先把 busy 立起来（顶部光条 + 禁用重复点击），
                                            // 由 onCapeChangeFinished 复位。
                                            page.capeBusy = true
                                            page.acct.selectCape(modelData.alias)
                                        }
                                    }
                                }
                            }
                            // 「卸下」常驻：以前它的 visible 绑在"有 active 披风"上，
                            // 一卸下就失去 active → 框自己消失，看着像界面出错。
                            // 现在只按"有没有披风可选"决定，并区分已卸下状态。
                            Rectangle {
                                id: offTile
                                readonly property bool anyActive: {
                                    for (var i = 0; i < page.capes.length; ++i)
                                        if (page.capes[i] && page.capes[i].active === true) return true
                                    return false
                                }
                                width: 46
                                height: 74
                                radius: 6
                                color: offHover.hovered ? "#161a22" : "transparent"
                                border.width: 1
                                border.color: offTile.anyActive
                                              ? (offHover.hovered ? "#2a3341" : "#1a1e26")
                                              : Theme.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: offTile.anyActive ? qsTr("卸下") : qsTr("未穿戴")
                                    color: offTile.anyActive ? "#98a1ae" : "#cfe0ff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                                HoverHandler { id: offHover }
                                TapHandler {
                                    onTapped: {
                                        if (!page.acct || page.capeBusy) return
                                        // 已经卸下了就别再发请求
                                        if (!offTile.anyActive) return
                                        page.capeBusy = true
                                        page.acct.selectCape("")
                                    }
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 12 }
                }

                Row {
                    spacing: 10
                    // 只保留"移除此账号"：退出登录与它语义重叠，用户明确要求合并
                    SButton {
                        tone: "dark"
                        kind: 1
                        radius: 2
                        height: 34
                        iconName: "x"
                        text: qsTr("移除此账号")
                        danger: true
                        visible: page.b && page.b.accounts && page.b.accounts.length > 0 && page.b.currentAccount >= 0
                        onClicked: {
                            if (!page.b) return
                            var i = page.b.currentAccount
                            if (i < 0) return
                            page.b.removeAccount(i)
                            page.flash(qsTr("已移除该账号"))
                        }
                    }
                }
            }
            }

            // ---- 需重新登录：右侧就地把「重新登录 / 移除」摆出来 ----
            // 以前点这类账号会直接跳登录页，左侧于是同时渲染「账号列表」和「登录方式」，
            // 加上 hasAccount 为 false，整页布局就乱了。现在只切右侧内容。
            Column {
                id: reloginCard
                visible: page.showRelogin
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: page.narrow ? 22 : 32
                anchors.rightMargin: page.narrow ? 22 : 32
                anchors.topMargin: 28
                spacing: 14

                Text {
                    width: parent.width
                    text: page.reloginAcct ? page.reloginAcct.name : ""
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: qsTr("需重新登录")
                    color: Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    text: qsTr("这个账号的登录凭据已经失效\n（可能过期、或在别处登录过）。重新登录一次即可继续使用。")
                    color: Theme.imageFgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 20
                    wrapMode: Text.WordWrap
                }
                Item { width: 1; height: 4 }
                Row {
                    spacing: 10
                    SButton {
                        tone: "dark"
                        kind: 0
                        radius: 2
                        height: 34
                        text: qsTr("重新登录")
                        onClicked: {
                            var a = page.reloginAcct
                            if (!a) return
                            page.reloginIdx = -1
                            page.tab = a.mode
                            page.loginPanel = true
                        }
                    }
                    SButton {
                        tone: "dark"
                        kind: 1
                        radius: 2
                        height: 34
                        iconName: "x"
                        text: qsTr("移除此账号")
                        danger: true
                        onClicked: {
                            var a = page.reloginAcct
                            if (!page.b || !a) return
                            page.b.removeAccount(a.index)
                            page.reloginIdx = -1
                            page.flash(qsTr("已移除该账号"))
                        }
                    }
                }
            }

            // ---- 登录表单 ----
            Column {
                visible: !page.browsingAccounts
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
                        text: qsTr("用 Microsoft 账号登录")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: qsTr("登录后可在正版服务器上玩，也会同步你的皮肤。")
                        color: "#9fb4cf"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    SButton {
                        tone: "dark"
                        kind: 0
                        height: 40
                        iconName: page.busy ? "x" : "globe"
                        text: page.busy ? qsTr("取消登录") : qsTr("开始登录")
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
                                text: page.busy ? qsTr("正在登录 Microsoft 账号") : qsTr("登录状态")
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
                        text: qsTr("离线账户")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: qsTr("只填一个用户名，不需要密码。")
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
                            color: Theme.imageFg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            selectionColor: Theme.accent
                            clip: true
                            onTextChanged: page.offlineInput = text
                            Text {
                                anchors.fill: parent
                                visible: offlineField.text.length === 0
                                text: qsTr("用户名")
                                color: Theme.imageFgFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                    SButton {
                        tone: "dark"
                        kind: 0
                        height: 40
                        iconName: "play"
                        text: qsTr("使用这个用户名")
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
                        text: qsTr("外置登录")
                        color: Theme.imageFg
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: qsTr("填皮肤站的地址与账号。地址可只写域名，登录前会自动识别完整 API 地址。")
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    // 快捷填入：点站点名即可，不必知道完整 API 地址。
                    // 地址最终由 ALI（X-Authlib-Injector-API-Location）在登录前解析，
                    // 所以这里只填域名也能用 —— 与 LittleSkin 手册的说法一致。
                    Row {
                        spacing: 6
                        visible: page.tab === 2
                        Repeater {
                            model: [
                                { label: "LittleSkin", host: "littleskin.cn" }
                            ]
                            delegate: Rectangle {
                                width: quickLabel.width + 18
                                height: 26
                                radius: Theme.rSm
                                color: quickHover.hovered ? Theme.bgHover : Theme.bgInput
                                border.width: 1
                                border.color: quickHover.hovered ? Theme.line2 : Theme.line
                                Text {
                                    id: quickLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: Theme.fg2
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                                HoverHandler { id: quickHover }
                                TapHandler {
                                    onTapped: page.fillApiHost(modelData.host)
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("点一下自动填好，也可只输入域名")
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        // 注册入口就放在站点名旁边：知道是哪个站、想注册，两步是连着的。
                        // 之前它在下面另起一行，还配了一个和上面一模一样的站点胶囊，
                        // 看起来像界面把同一句话说两遍。registerUrl 来自 meta，没解析出来就不显示。
                        Text {
                            visible: page.yg !== null && page.yg.registerUrl.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("· 还没有账号？去注册")
                            color: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            TapHandler {
                                onTapped: {
                                    if (page.yg && page.yg.registerUrl.length > 0)
                                        Qt.openUrlExternally(page.yg.registerUrl)
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }

                    Repeater {
                        model: [
                            { ph: qsTr("皮肤站地址，如 littleskin.cn"), key: 0 },
                            { ph: qsTr("邮箱"), key: 1 },
                            { ph: qsTr("密码"), key: 2 }
                        ]
                        delegate: Rectangle {
                            width: page.narrow ? 260 : 320
                            height: 40
                            radius: 8
                            color: Theme.bgInput
                            border.width: 1
                            border.color: f.activeFocus ? Theme.line2 : Theme.line
                            TextInput {
                                id: f
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.imageFg
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
                                    color: Theme.imageFgFaint
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
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    SButton {
                        tone: "dark"
                        kind: 0
                        height: 40
                        iconName: "globe"
                        text: qsTr("登录")
                        onClicked: page.doExternal()
                    }

                    // 多角色选择：后端 emit showProfileSelection 后必须让用户选一个，
                    // 否则会话停在"已认证但未选角色"，等于登录没完成。
                    Column {
                        width: parent.width
                        visible: page.profilePickOpen
                        spacing: 8

                        Text {
                            text: qsTr("选择角色")
                            color: Theme.imageFg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: (page.yg && page.yg.profiles) ? page.yg.profiles : []
                            delegate: Rectangle {
                                width: parent.width
                                height: 52
                                radius: 8
                                color: profHover.hovered ? Theme.bgHover : Theme.bgInput
                                border.width: 1
                                border.color: profHover.hovered ? Theme.line2 : Theme.line

                                // 角色皮肤头像：profileHeadUrls 里是同索引的本地头图，
                                // 还没拉到就先显示首字母色块（SMinecraftHead 自带这个兜底）
                                SMinecraftHead {
                                    id: profHead
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 32
                                    fallbackText: (modelData && modelData.name) ? modelData.name : "?"
                                    source: {
                                        var urls = (page.yg && page.yg.profileHeadUrls) ? page.yg.profileHeadUrls : []
                                        return (index >= 0 && index < urls.length) ? urls[index] : ""
                                    }
                                }

                                Column {
                                    anchors.left: profHead.right
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: (modelData && modelData.name) ? modelData.name : ""
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                        text: (modelData && modelData.id) ? modelData.id : ""
                                        color: Theme.fg3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                }
                                HoverHandler { id: profHover }
                                TapHandler {
                                    onTapped: {
                                        if (!page.yg) return
                                        page.yg.selectProfile(index)
                                    }
                                }
                            }
                        }

                        SButton {
                            tone: "dark"
                            kind: 1
                            radius: 2
                            height: 30
                            text: qsTr("取消")
                            onClicked: {
                                if (page.yg) page.yg.cancelLogin()
                                page.profilePickOpen = false
                            }
                        }
                    }
                }
            }
        }
    }

    // 拖入由 StageShell 的全局投放区接管：
    // 它识别到 authlib-injector 链接 / 文本时会把地址送到 externalApiToApply，
    // 本页据此自动切到外置登录并填好。handleDroppedFiles 保留给验收钩子
    // （--ui-account-drop）直接调用。
}
