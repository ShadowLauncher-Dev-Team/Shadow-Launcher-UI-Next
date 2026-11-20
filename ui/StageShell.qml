// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 外壳：侧栏 + 内容区 + 启动浮层 + 版本页 + 账户页 + 全局窗口按钮
// 版本/账户都是"隶属启动页的全屏页"：打开时侧栏整体收起、页面 anchors.fill 全窗。
//
// 动效（2026-11-04）：
//   · 全屏页进出 = 侧栏宽度收到 0（durPage）+ 页面淡入并从右侧 24px 滑入；返回反向
//   · 位移放在容器的 transform 上，不动页面自身的 anchors，避免和组件内部布局打架
//   · 关闭时 visible 要等透明度真正降下去才置 false，否则会硬切
Item {
    id: root
    property Window hostWindow: null

    // ── 配色方案：后端是唯一真源，Theme.scheme 只是它的镜像 ──
    // 外观页写 b.colorScheme → 这里同步 Theme.scheme → 全局颜色 binding 立即重算。
    readonly property string colorScheme: (root.b && root.b.colorScheme) ? root.b.colorScheme : "dark"
    onColorSchemeChanged: Theme.scheme = root.colorScheme

    // ══ 全局拖入分发 ══════════════════════════════════════════════
    // 拖进启动器的东西可能是整合包 / Mod / 资源包 / 光影包 / 存档 / authlib 链接。
    // 只看扩展名会错（.zip 有四种可能），所以一律交给后端打开压缩包看结构，
    // 再决定落到哪。版本设置里的 Mod 管理页能接住，靠的就是这个全局入口。
    readonly property string dropVersionId: (root.b && root.b.selectedVersion) ? root.b.selectedVersion : ""
    readonly property var dropImporter: (root.b && root.b.modpackImporter) ? root.b.modpackImporter : null

    // ── 整合包开始导入 → 自动切到下载进度页 ──
    // 覆盖全部入口：全局拖入、版本页选文件、下载页安装。
    // 旧行为：拖入只弹一句「已导入 1 个文件」且不跳页（实际只是刚开始导），
    // 版本页导入后也只弹 toast。用户根本看不到进度。
    Connections {
        target: root.dropImporter
        function onBusyChanged() {
            if (!root.dropImporter || !root.dropImporter.busy) return
            // 必须把所有全屏页都关掉，尤其是版本页。
            // sideCollapsed = versionsOpen || accountOpen || sideNarrowed，
            // 版本页开着时侧栏是收起的 → 从版本页导入时
            // 只设 progressOpen 而不关版本页，就会出现「左侧菜单直接消失、
            // 进度页又被版本页盖住，用户无法退出」(*实测反馈*)。
            root.versionsOpen = false
            root.accountOpen = false
            root.resDetailOpen = false
            root.settingsOpen = false
            root.prefsOpen = false
            root.progressOpen = true
            root.downloadOpen = false
            root.multiplayerOpen = false
            sideBar.currentKey = "progress"
        }
    }
    // 版本设置页当前所在分区（mods / shaders / packs / saves / ...），由 settingsPage 同步
    property string settingsPane: ""
    // 拖入能否落到"当前上下文"：Mod 只在 Mod 管理页、光影只在光影页、资源包只在资源包页
    function dropContextAccepts(kind) {
        if (!root.settingsOpen) return false
        var k = root.settingsPane
        if (kind === "mod") return k === "mods"
        if (kind === "shaderpack") return k === "shaders"
        if (kind === "resourcepack") return k === "packs"
        if (kind === "world") return k === "saves"
        return false
    }
    // 页面名：用于"请先进入「X」页面"
    // ── 拖入提示只描述"当前页面真的能做什么" ──
    // 之前这里写死成「整合包 / Mod / 资源包 / 光影包 / 存档，或外置登录链接」，
    // 等于声称什么都能导 —— 而实际上 Mod 只能在 Mod 管理页、外置登录链接只能在账号页。
    // 提示必须跟着位置变，否则就是在骗用户往这儿拖。
    readonly property string dropHintTitle: {
        if (root.accountOpen) return qsTr("松开以填入外置登录地址")
        if (root.settingsOpen) {
            var k = root.settingsPane
            if (k === "mods") return qsTr("松开以导入 Mod")
            if (k === "shaders") return qsTr("松开以导入光影包")
            if (k === "packs") return qsTr("松开以导入资源包")
            if (k === "saves") return qsTr("松开以导入存档")
        }
        return qsTr("松开以导入整合包")
    }
    readonly property string dropHintBody: {
        if (root.accountOpen)
            return qsTr("支持 authlib-injector 链接，或含 API 地址的文本 / jar")
        if (root.settingsOpen) {
            var k = root.settingsPane
            if (k === "mods") return qsTr("接收 .jar 格式的 Mod；整合包（.zip / .mrpack）在这里也能导")
            if (k === "shaders") return qsTr("接收 .zip 格式的光影包")
            if (k === "packs") return qsTr("接收 .zip 格式的资源包")
            if (k === "saves") return qsTr("本页暂不支持拖动导入存档")
        }
        return qsTr("整合包（.zip / .mrpack）在任何页面都能导；Mod / 资源包 / 光影包 / 存档要先进对应页面")
    }
    // 拖动过程中同样按位置粗筛：在启动页拖 .jar 就该当场变禁止，而不是等松手才说"去 Mod 管理页"
    readonly property var dropAcceptExts: {
        if (root.accountOpen) return [".jar"]
        if (root.settingsOpen) {
            var k = root.settingsPane
            if (k === "mods") return [".jar", ".zip", ".mrpack"]
            if (k === "shaders") return [".zip", ".mrpack"]
            if (k === "packs") return [".zip", ".mrpack"]
            if (k === "saves") return [".zip"]
        }
        return [".zip", ".mrpack"]
    }
    readonly property string dropRejectBody: qsTr("当前位置不能导入这种文件。整合包可在任何页面拖入；其余内容请先进入对应页面")

    function dropContextName(kind) {
        if (kind === "mod") return qsTr("Mod 管理")
        if (kind === "shaderpack") return qsTr("光影管理")
        if (kind === "resourcepack") return qsTr("资源包")
        if (kind === "world") return qsTr("存档")
        return ""
    }
    // 内容名：用于"要导入 X"
    // 这两个必须分开 —— 之前页面名被当成内容名拼进了同一句，说成"要导入 Mod 管理"。
    function dropKindName(kind) {
        if (kind === "mod") return qsTr("Mod")
        if (kind === "shaderpack") return qsTr("光影包")
        if (kind === "resourcepack") return qsTr("资源包")
        if (kind === "world") return qsTr("存档")
        return qsTr("这个文件")
    }

    function localizeDropPath(u) {
        var s = String(u === undefined || u === null ? "" : u)
        if (s.indexOf("file:") === 0) {
            s = s.substring(5)
            if (s.indexOf("///") === 0) s = s.substring(2)
            else if (s.indexOf("//") === 0) s = "//" + s.substring(2)
            if (s.charAt(0) === "/" && s.charAt(2) === ":") s = s.substring(1)
            try { s = decodeURIComponent(s) } catch (e) { }
        }
        return s
    }

    // 从路径里取文件名，用于报错时说清"是哪个文件不行"
    function dropBaseName(u) {
        var s = String(u || "")
        var cut = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"))
        if (cut >= 0) s = s.substring(cut + 1)
        try { s = decodeURIComponent(s) } catch (e) { }
        return s
    }

    function handleGlobalDrop(urls) {
        if (!root.b || !urls) return
        var doneCount = 0
        var errors = []          // 全部收集起来再决定怎么说，别只留最后一个

        // 类型判定顺序很重要：先回答"这文件我认不认识"，再去谈"该放哪"。
        // 顺序反过来的话，没选实例时拖一张 .png 会得到"请先选择一个实例" —— 答非所问。
        for (var i = 0; i < urls.length; ++i) {
            var u = String(urls[i])
            var name = root.dropBaseName(u)
            var kind = String(root.b.classifyDroppedTarget(u))

            if (kind === "unknown" || kind === "datapack") {
                errors.push(qsTr("%1：认不出这是什么（支持 Mod / 资源包 / 光影包 / 整合包 / 存档）").arg(name))
                continue
            }

            if (kind === "authlib-link" || kind === "url") {
                var api = String(root.b.parseAuthlibInjectorLink(u))
                if (api.length === 0) api = u          // 普通 http 链接：当作 API 地址候选
                root.pendingAuthlibApi = ""
                root.pendingAuthlibApi = api
                root.accountOpen = true
                doneCount++
                continue
            }

            if (kind === "authlib") {
                root.accountOpen = true
                toastHost.show(qsTr("已识别 authlib-injector，请填写站点地址（如 littleskin.cn）"), 3600)
                continue
            }

            // 整合包是唯一"几乎到处都能导"的类型，不受页面门禁影响
            if (kind === "modpack") {
                if (root.dropImporter) {
                    root.dropImporter.startImport(root.localizeDropPath(u), "", false, "")
                    // 导入刚开始，必须把用户带到进度页。
                    // 旧实现只把 doneCount++，最后弹「已导入 N 个文件」
                    // —— 既不跳页，措辞还像已经导完（实际只是刚开始）。
                    toastHost.show(qsTr("开始导入整合包：%1").arg(name), 3000, "info")
                } else {
                    errors.push(qsTr("%1：整合包导入器未就绪").arg(name))
                }
                continue
            }

            if (kind === "world") {
                errors.push(qsTr("%1：存档导入暂未支持，请在存档页手动导入").arg(name))
                continue
            }

            // 以下都落到具体实例上，而且必须在对应页面
            if (root.dropVersionId.length === 0) {
                errors.push(qsTr("%1：请先在版本页选择一个实例").arg(name))
                continue
            }

            if (!root.dropContextAccepts(kind)) {
                errors.push(qsTr("%1：要导入%2，请先进入「%3」页面")
                              .arg(name).arg(root.dropKindName(kind)).arg(root.dropContextName(kind)))
                continue
            }

            var path = root.localizeDropPath(u)
            var ok = false
            if (kind === "mod") ok = root.b.importMod(path, root.dropVersionId)
            else if (kind === "resourcepack") ok = root.b.importResourcePack(path, root.dropVersionId)
            else if (kind === "shaderpack") ok = root.b.importShaderPack(path, root.dropVersionId)

            if (ok) doneCount++
            else errors.push(qsTr("%1：导入失败，文件内容不是有效的%2").arg(name).arg(root.dropKindName(kind)))
        }

        // 汇总：成功就报成功（但失败也要说），全失败就报第一条 + 其余数量
        if (doneCount > 0 && errors.length === 0) {
            toastHost.show(qsTr("已导入 %1 个文件").arg(doneCount), 2600, "success")
        } else if (doneCount > 0) {
            toastHost.show(qsTr("已导入 %1 个，另有 %2 个未导入。%3")
                           .arg(doneCount).arg(errors.length).arg(errors[0]), 5000, "error")
        } else if (errors.length === 1) {
            toastHost.show(errors[0], 4200, "error")
        } else if (errors.length > 1) {
            toastHost.show(qsTr("%1（另有 %2 个问题）").arg(errors[0]).arg(errors.length - 1), 5000, "error")
        }
    }
    // 侧栏只有「完整模式」一种形态。
    // 曾经按 width < 900 切成图标轨道（Theme.sideWNarrow = 64）：菜单图标与文字锚点对不上，
    // 而且轨道态下侧栏点击几乎失效 —— 进了「下载进度」页就再也点不回去（影报过）。
    // 页面内部的窄屏适配（padding / 字号）另有各自的 narrow，与这里无关，那些保留。
    readonly property bool narrow: false
    readonly property int sideW: Theme.sideW
    property bool versionsOpen: false
    // 版本设置（从版本页的版本卡片进入；叠在版本页之上，返回时回到版本页）
    property bool settingsOpen: false
    // 全局设置（与「版本设置」是两件事：那个按版本，这个改全局默认值）
    property bool prefsOpen: false
    // 进设置前侧栏选中的是哪一项：退出时要还原回去，
    // 否则侧栏一直停在高亮的「设置」上（影报：从设置页出来，左侧仍显示设置页）。
    property string prefsPrevKey: "launch"
    property string settingsVersionId: ""
    property bool accountOpen: false
    // 全局拖入：识别到 authlib-injector 链接时暂存，账号页据此自动填地址。
    // 用属性中转而不是直接调 AccountPage，是因为拖入可能发生在账号页还没被创建的时候。
    property string pendingAuthlibApi: ""
    // 下载页与版本页/账户页同一套：侧栏宽度收到 0，页面淡入 + 右移 24
    property bool downloadOpen: false
    // 下载进度：独立页面（不再借用 DownloadPage 的 mode=2 视图）
    property bool progressOpen: false
    // 联机：与下载页同一套宿主（侧栏常驻、页面自绘标题），不是全屏页
    property bool multiplayerOpen: false
    // 帮助文档：官网的 VitePress 站点。启动器不内嵌，直接开系统浏览器 ——
    // 文档、截图、更新节奏跟官网是同一份，也省得打包体积翻倍。
    readonly property string helpDocsUrl: "https://shadowlauncher.cn/docs/"
    // 资源详情页（从资源库卡片打开）
    property bool resDetailOpen: false
    // 资源详情按"全屏独立页"处理：打开时侧栏收起、页面铺满整窗（与版本页/账户页同一套）
    //
    // 但侧栏收起会改变下面列表页的宽度 → 列数 3↔4、卡片尺寸全部重排。
    // 如果收起的同一帧就开始，用户会在详情页还半透明时看到身后整片卡片"跳一下"。
    // 所以详情页的收起延后到页面已经完全不透明之后再执行（那一刻重排在纯不透明页后面，看不见）。
    property bool sideNarrowed: false          // 侧栏是否已真正收起（与页面可见性解耦）
    // fullOpen：页面是否处于"全屏页"状态（拦住底下页面的交互）
    readonly property bool fullOpen: versionsOpen || accountOpen || resDetailOpen || settingsOpen || prefsOpen
    // sideCollapsed：侧栏是否应该收起。版本页/账户页立刻收；资源详情延后收（见 onResDetailOpenChanged）
    readonly property bool sideCollapsed: versionsOpen || accountOpen || sideNarrowed
    onResDetailOpenChanged: {
        if (resDetailOpen) {
            narrowDelay.restart()
        } else {
            narrowDelay.stop()
            sideNarrowed = false               // 复原立刻执行：此刻详情页仍不透明
        }
    }
    Timer {
        id: narrowDelay
        interval: Theme.durSlow
        onTriggered: root.sideNarrowed = root.resDetailOpen
    }
    readonly property var b: (typeof backend !== "undefined") ? backend : null

    // ── 模组/资源「文件下载」追踪 ──
    // 后端对 downloadModFile 只发信号（started/progress/finished/failed/cancelled），没有 model；
    // 详情页要就地显示进度、下载进度页也要能看到，所以统一在壳里收成一份表。
    property var fileDl: []
    // 已提示过的下载 id（后端 finished/failed 可能都发，避免重复 toast）
    property var _toasted: ({})
    function _dlIdx(id) {
        for (var i = 0; i < root.fileDl.length; ++i)
            if (root.fileDl[i].id === id) return i
        return -1
    }
    function _dlPatch(id, patch) {
        var arr = root.fileDl.slice()
        var i = root._dlIdx(id)
        var o = i >= 0 ? arr[i]
                       : ({ id: id, name: "", received: 0, total: 0, speed: 0, state: "run", path: "", error: "" })
        for (var k in patch) o[k] = patch[k]
        if (i >= 0) arr[i] = o; else arr.push(o)
        root.fileDl = arr
    }
    // 已结束的下载条目 4s 后从列表里移除：卡片消失，进度页不再挂一条"已完成"
    // --ui-drop-hint：强制显示拖入遮罩，用来验收"提示文案是否与实际可导内容一致"。
    // 拖动本身没法脚本模拟，但遮罩上的字可以截出来看。
    property bool dropHintForceShow: Qt.application.arguments.indexOf("--ui-drop-hint") >= 0
    // --ui-drop-test 用的延后执行（等 backend / Toast 就绪）
    Timer {
        id: dropTestTimer
        property var testPaths: []
        // 启动到窗口真正可见要好几秒；太早触发的话提示会在截图之前就超时消失
        interval: 10000
        repeat: false
        onTriggered: root.handleGlobalDrop(dropTestTimer.testPaths)
    }
    Timer {
        interval: 500
        repeat: true
        running: root.fileDl.length > 0
        onTriggered: {
            var now = Date.now(), keep = [], changed = false
            for (var i = 0; i < root.fileDl.length; ++i) {
                var d = root.fileDl[i]
                if (d.state !== "run" && d.hideAt > 0 && d.hideAt <= now) { changed = true; continue }
                keep.push(d)
            }
            if (changed) root.fileDl = keep
        }
    }
    Connections {
        target: root.b
        ignoreUnknownSignals: true

        // ── 后端统一反馈通道（2026-11-13 补接线）─────────────────
        // ShadowBackend::toastMessage 原来没有任何 QML 监听：更新模块的 16 条提示
        // （已是最新版本 / 检查更新失败 / 发现新版本正在后台下载 / 下载失败…）
        // 以及模组安装、版本后端的提示全部石沉大海 —— 用户点「检查更新」只看到
        // 按钮闪一下「检查中」，看不出结果。这里统一接到 ToastHost。
        function onColorSchemeChanged() { Theme.scheme = (root.b && root.b.colorScheme) ? root.b.colorScheme : "dark" }

        function onToastMessage(message) {
            if (!message || message.length === 0) return
            toastHost.show(message, 3000)
        }

        // 更新下载完成：常驻可点，点了重启并由 SLUpdater 安装
        function onUpdateReadyForRestart(version) {
            var v = (version && version.length > 0) ? version : qsTr("新版本")
            toastHost.showAction(qsTr("更新已就绪：%1，点击立即重启安装").arg(v), function() {
                if (root.b) root.b.quitForUpdate()
            }, "success")
        }

        function onModFileDownloadStarted(downloadId, fileName, fileSize, displayName) {
            root._dlPatch(downloadId, { name: displayName || fileName, total: fileSize, state: "run" })
        }
        function onModFileDownloadProgress(downloadId, received, total, speed) {
            root._dlPatch(downloadId, { received: received, total: total, speed: speed })
        }
        function onModFileDownloadFinished(downloadId, success, filePath, displayName) {
            root._dlPatch(downloadId, {
                name: displayName || "", state: success ? "done" : "fail", path: filePath || "",
                speed: 0, received: -1, hideAt: Date.now() + 4000
            })
            // 同一个下载 id 只提示一次：后端在失败路径上会先发 finished(false) 再发 failed，
            // 不去重就会出现两条"下载失败/完成"（用户报的重复弹窗）
            if (root._toasted[downloadId]) return
            var m2 = {}
            for (var k in root._toasted) m2[k] = root._toasted[k]
            m2[downloadId] = true
            root._toasted = m2
            if (success) toastHost.show(qsTr("%1 下载完成").arg(displayName || qsTr("文件")), 2600, "success")
            else toastHost.show(qsTr("%1 下载失败").arg(displayName || qsTr("文件")), 3200, "error")
        }
        function onModFileDownloadFailed(downloadId, errorDetail, displayName) {
            root._dlPatch(downloadId, { state: "fail", error: errorDetail || "", speed: 0, hideAt: Date.now() + 6000 })
            if (root._toasted[downloadId]) return
            var m3 = {}
            for (var k in root._toasted) m3[k] = root._toasted[k]
            m3[downloadId] = true
            root._toasted = m3
            toastHost.show(qsTr("%1 下载失败：%2").arg(displayName || qsTr("文件")).arg(errorDetail || qsTr("未知错误")), 3600, "error")
        }
        function onModFileDownloadCancelled(downloadId, displayName) {
            root._dlPatch(downloadId, { state: "fail", error: qsTr("已取消"), speed: 0, hideAt: Date.now() + 3000 })
        }
    }
    // 验收钩子：--update-check 延迟一点再点「检查更新」，等界面挂好、ToastHost 就绪
    Timer {
        id: schemeFlipTimer
        interval: 1500
        onTriggered: {
            if (!root.b) return
            var next = (root.b.colorScheme === "light") ? "dark" : "light"
            console.info("[ui] --scheme-flip ->", next)
            root.b.setColorScheme(next)
        }
    }

    Timer {
        id: updateCheckTimer
        interval: 1500
        onTriggered: {
            console.info("[ui] --update-check: 触发检查更新")
            if (root.b) root.b.checkForUpdate()
        }
    }

    // 顶部加载条：登录这类"不知道还要多久"的等待（后续可接更多长任务）
    // 登录这类不确定等待 + 资源库在途请求，统一走顶部 SLoadingBar
    readonly property bool loading: (b ? b.microsoftLoginBusy : false)
        // 同下面两条：只在下载页还开着的时候算它。
        // downloadPage 是常驻对象（不是按需卸载），里面的资源视图扫描不会因为退出而立刻结束，
        // 少了这个条件就会出现「进 Mod 页又马上退出，顶部光条还在一直转」。
        || (root.downloadOpen && downloadPage ? downloadPage.resourceBusy : false)
        // 只在详情页还开着的时候算它：关掉后残留的请求不该让顶部继续转
        || (root.resDetailOpen && resDetail ? resDetail.loadingVersions : false)
        // 版本设置里的扫盘 / 批量改名也点亮光条（几百个 jar 几秒没反馈会以为死了）
        || (root.settingsOpen && settingsPage.busy)
        || (root.prefsOpen && prefsPage.busy)
        // 皮肤上传 / 披风切换都要等服务器，1~3 秒没反馈会以为没点上
        || (root.accountOpen && accountPage ? accountPage.wardrobeBusy : false)

    // --ui-reenter 的驱动：进/退 每 1.2s 交替一次，用于连拍验证"第二次及以后进入是否还有过渡"。
    // 第一次 open 是初始状态（不播 transition），之后每次切换都会走 states/transitions。
    Timer {
        id: reenterTimer
        interval: 1200
        repeat: true
        onTriggered: {
            root.settingsOpen = !root.settingsOpen
            console.info("[ui] reenter toggle ->", root.settingsOpen)
        }
    }

    Component.onCompleted: {
        // 配色方案：后端是唯一真源，启动时先同步一次
        Theme.scheme = root.colorScheme
        if (Qt.application.arguments.indexOf("--ui-versions") >= 0) root.versionsOpen = true
        // 版本设置预览：--ui-settings [versionId]（截图/验收用；不给 id 就用当前选中版本）
        var si = Qt.application.arguments.indexOf("--ui-settings")
        if (si >= 0) {
            root.settingsVersionId = (si + 1 < Qt.application.arguments.length
                                      && Qt.application.arguments[si + 1].indexOf("--") !== 0)
                                     ? Qt.application.arguments[si + 1]
                                     : (b ? b.selectedVersion : "")
            root.settingsOpen = true
        }
        // --ui-reenter：进 → 退 → 再进，验证"第二次进入是否还有过渡"（截图/验收用）
        if (Qt.application.arguments.indexOf("--ui-reenter") >= 0) {
            root.settingsVersionId = b ? b.selectedVersion : ""
            root.settingsOpen = true
            reenterTimer.start()
        }
        // --ui-prefs [key]：全局设置页（截图/验收用；key 由 SettingsPage 自己解析 --ui-pane）
        if (Qt.application.arguments.indexOf("--ui-prefs") >= 0) {
            root.prefsOpen = true
            sideBar.currentKey = "settings"
        }
        if (Qt.application.arguments.indexOf("--ui-account") >= 0) root.accountOpen = true
        // --ui-drop-test <path>：把一条路径直接喂给全局拖入分发（验收用）。
        // 真正从资源管理器拖拽无法用脚本模拟，但"给了一个东西之后会不会给出正确反馈"
        // 这条链路可以这样验，包括拒绝时的提示文案。
        var dti = Qt.application.arguments.indexOf("--ui-drop-test")
        if (dti >= 0 && dti + 1 < Qt.application.arguments.length) {
            var paths = []
            for (var dk = dti + 1; dk < Qt.application.arguments.length; ++dk) {
                var av = Qt.application.arguments[dk]
                if (av.indexOf("--") === 0) break
                paths.push(av)
            }
            dropTestTimer.testPaths = paths
            dropTestTimer.start()
        }
        // --update-check：启动后自动点一次「检查更新」（验收用，与按钮同一路径）
        if (Qt.application.arguments.indexOf("--update-check") >= 0) updateCheckTimer.start()
        // --scheme-flip：1.5s 后切换一次配色（验收用：走与外观页卡片完全相同的
        //   b.setColorScheme 路径，验证切换即时生效、无需重启）
        if (Qt.application.arguments.indexOf("--scheme-flip") >= 0) schemeFlipTimer.start()
        if (Qt.application.arguments.indexOf("--ui-download") >= 0) {
            root.downloadOpen = true
            root.progressOpen = false
            sideBar.currentKey = "download"
            // --ui-dl-filter <N>：直接切到某个版本类型（0 正式 / 1 快照 / 2 远古 / 3 愚人节）。
            // 原生窗口的 tab 点击坐标随 DPI/窗口位置漂移，用参数切换才能稳定复现切换动画与数据一致性。
            var fi = Qt.application.arguments.indexOf("--ui-dl-filter")
            if (fi >= 0 && fi + 1 < Qt.application.arguments.length)
                downloadPage.filter = parseInt(Qt.application.arguments[fi + 1], 10) || 0
            // --ui-dl-tab <N>：直接切到某个资源 tab（1 Mod / 2 光影 / 3 资源包 / 4 整合包 / 5 数据包）
            var ti = Qt.application.arguments.indexOf("--ui-dl-tab")
            if (ti >= 0 && ti + 1 < Qt.application.arguments.length)
                downloadPage.tab = parseInt(Qt.application.arguments[ti + 1], 10) || 0
        }
        if (Qt.application.arguments.indexOf("--ui-progress") >= 0) {
            root.progressOpen = true
            root.downloadOpen = false
            sideBar.currentKey = "progress"
        }
        // --ui-multiplayer：联机页（截图验收用）。没有这个钩子只能靠模拟点击侧栏，
        // 自动化下点击偶尔被前台窗口截走，验收不稳定。
        if (Qt.application.arguments.indexOf("--ui-multiplayer") >= 0) {
            root.multiplayerOpen = true
            root.downloadOpen = false
            root.progressOpen = false
            sideBar.currentKey = "multiplayer"
        }
        // --ui-res-detail：直接打开资源详情页（截图验收用）。
        // 详情页要经过「下载页 → 选 tab → 等网络列表 → 点卡片」才能进来，
        // 自动化里任何一步慢了或点偏了就测不到，所以直接塞一份样本 item。
        if (Qt.application.arguments.indexOf("--ui-res-detail") >= 0) {
            // iris：必需前置 sodium，覆盖「模组 + 前置一起下载」这条路径（也是之前丢前置的那条）。
            var sample = {
                slug: "iris",
                title: "Iris Shaders",
                zh: "",
                desc: "A modern shaders mod for Minecraft intended to be compatible with existing OptiFine shader packs.",
                icon: "",
                source: "Modrinth",
                downloads: 120000000,
                dateModified: "2026-11-11",
                isModpack: false
            }
            resDetail.kind = "mod"
            resDetail.item = sample
            // --ui-batch-dl <dir>：自动批量下载到该目录（跳过原生选择文件夹对话框）
            var bi = Qt.application.arguments.indexOf("--ui-batch-dl")
            if (bi >= 0 && bi + 1 < Qt.application.arguments.length)
                resDetail.autoTargetDir = Qt.application.arguments[bi + 1]
            root.resDetailOpen = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    // 点空白释放文本焦点的实现已移到 C++ 窗口层（src/main_release.cpp 的 FocusClearFilter）：
    // 这一层在 QML 里做不可靠 —— 版本设置页每个 pane 都是 anchors.fill 的 Flickable，
    // 它会把 press 吃掉，挂在这里的 MouseArea / TapHandler 收不到，等于没装。

    // 顶部加载条（Material / Google 线性风格）：压在窗口最上沿
    SLoadingBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        z: 1000
        running: root.loading
    }

    // 侧栏：宽度动画收放，内容裁掉不溢出
    SideBar {
        id: sideBar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.sideCollapsed ? 0 : root.sideW
        narrow: root.narrow
        hostWindow: root.hostWindow
        // 点击侧栏"下载"进下载页；点其它主项离开（侧栏常驻，页面内不需要返回键）
        onNavActivated: (key) => {
            // key 是稳定标识（launch/download/multiplayer/settings/progress/help），
            // 不是显示文案 —— 文案翻译后这些判断不能跟着变。
            if (key === "download") {
                // 侧栏「下载」= 下载列表页：从配置态或独立进度页回来都先回到列表
                downloadPage.resetToList()
                root.prefsOpen = false
                root.downloadOpen = true
                root.progressOpen = false
                root.multiplayerOpen = false
            } else if (key === "progress") {
                // 侧栏「下载进度」：独立页面，与「下载」互不捆绑
                root.prefsOpen = false
                root.progressOpen = true
                root.downloadOpen = false
                root.multiplayerOpen = false
                sideBar.currentKey = "progress"
            } else if (key === "multiplayer") {
                // 联机页：与下载页同级，侧栏常驻
                root.prefsOpen = false
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = true
            } else if (key === "settings") {
                // 设置 = 全局默认值（独立全屏页）
                // 记住进来之前停在哪一项（点「设置」时 currentKey 已经被 SideBar 改掉了，
                // 所以趁还没改记录原值）
                root.prefsPrevKey = sideBar.previousKey
                console.info("[ui] 进入设置，记住上一项: " + root.prefsPrevKey)
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = false
                root.prefsOpen = true
            } else if (key === "launch") {
                root.downloadOpen = false
                root.progressOpen = false
                root.multiplayerOpen = false
                root.prefsOpen = false
            } else if (key === "help") {
                // 帮助文档 = 官网上的 VitePress 站点（shadowlauncher.cn/docs），
                // 不在启动器里另做一份：内容、截图、更新节奏跟官网保持同一份，
                // 也免得打包体积和「文档与官网不一致」的问题。
                // 侧栏这一项是子项（isMain=false），点它不会改高亮，页面也不需要切。
                console.info("[ui] 打开帮助文档: " + root.helpDocsUrl)
                Qt.openUrlExternally(root.helpDocsUrl)
            }
        }
        // 快起：前 40% 时间就收掉大部分宽度，与页面淡入同帧开始，视觉上是一次动作。
        // 复原（关闭全屏页）时 duration 归 0：那一刻全屏页还完全不透明，宽度跳变看不见；
        // 若也给 320ms，下面的列表要在整段动画里连续重排，最后半段露出来时就是一顿。
        Behavior on width {
            NumberAnimation {
                // 版本页/账户页照旧给动画；资源详情只在"延后收起"那一刻给动画（页面已不透明）；还原一律立刻
                duration: (root.sideNarrowed || root.versionsOpen || root.accountOpen) ? Theme.durPage : 0
                easing.type: Theme.easeEnter
            }
        }
    }

    // 窗口拖动已移到各页面 topBar 内部（见 DownloadPage / AccountPage 等的 topBar MouseArea →
    // backend.beginWindowMove()）。
    //
    // 这里原来有一条"拖动带"（2026-11-05）：anchors.left 从侧栏右缘铺到窗口右边、高度 Theme.topH，
    // 但它声明在页面之前 —— 后面的 stageHost / 各全屏页整个盖在它上面，不只是按钮。
    // 结果就是它一次也收不到 press，窗口从来拖不动（owner 2026-11-10 实测报"顶栏拖不动"）。
    // 另外它用 window.x += 手算位移，高 DPI 下会漂移、也拿不到贴边吸附。
    // 两处都已被页面内 topBar 的 backend.beginWindowMove() 取代，故删除。

    // 启动页：始终在原地（被全屏页盖住），只关掉交互
    // 启动页宿主：clip + 实底包一层。
    // 之前直接给 StagePage 加 translate：位移不改变 anchors，页面左移后**压到了侧栏右缘上面**
    // （侧栏先声明、启动页后声明 → 启动页在上），于是侧栏右边露出一条极光色的缝。
    // 现在位移只作用在宿主内部，宿主 clip 住，越界部分画不出去。
    Item {
        id: stageHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        // 外观页「只剩预览」时，下面这层启动页必须**原样归位**（不位移、不缩放），
        // 否则全屏页的 -22px 位移会在右边留下一条 22px 的纯色黑边（用户实测）。
        readonly property bool previewing: root.prefsOpen && prefsPage.livePreview
        Rectangle {
            anchors.fill: parent
            // 必须带 stageHost. 前缀：QML 子项**不会**自动继承父项的自定义属性作用域，
            // 裸写 previewing 会抛 ReferenceError 并且绑定整个失效（底色落回默认白）。
            color: stageHost.previewing ? "transparent" : Theme.bg
        }
        Item {
            anchors.fill: parent
            // 历史教训（都别再走回去）：
            //   · 位移(-22)/缩放(0.99) 会在页面四周留 1~22px 的缝，缝里露窗口外 → 「一圈白边」；
            //   · 整页 opacity 动画会变成一块只在切回时出现的「阴影」，切出时没有，很突兀。
            // 所以页面本体彻底不做动画，动感全部交给页内组件（StagePage.playEnter）。
            readonly property bool shifted: (root.downloadOpen || root.progressOpen
                                             || root.fullOpen || root.multiplayerOpen)
            // 页面本体**不做任何透明度/几何动画**：
            //   · 几何（位移/缩放）会在边缘留缝，缝里露的是窗口外 → 白边；
            //   · 整页透明度会变成一块突然出现又消失的「阴影」，切出时没有、切回时有，很突兀。
            // 回启动页的动感全部交给页内组件（StagePage.playEnter）。
            opacity: 1.0

            // 全屏页全部关掉的那一刻，让启动页里的组件重放入场
            onShiftedChanged: {
                if (!shifted) stagePage.playEnter()
            }
            StagePage {
                id: stagePage
                anchors.fill: parent
                enabled: !root.fullOpen && !root.downloadOpen && !root.progressOpen && !root.multiplayerOpen
                hostWindow: root.hostWindow
                narrow: root.narrow
                toast: toastHost
                onOpenVersions: root.versionsOpen = true
                onOpenAccount: root.accountOpen = true
                // 启动页「设置」= 当前选中版本的版本设置；没选版本就先去选
                onOpenSettings: (vid) => {
                    if (vid && vid.length > 0) {
                        root.settingsVersionId = vid
                        root.settingsOpen = true
                    } else {
                        root.versionsOpen = true
                    }
                }
            }
        }
    }

    // 侧栏右缘「长出去」的融合带（影：渐变要加在侧栏侧，不要压暗图片那一侧）
    // 做法是让侧栏的底色从它的右边界继续往图片方向渗 88px，
    // 而不是在页面里叠一层遮罩 —— 后者等于把图片的左边吃掉一截。
    // 只在启动页显示：其它页面是实底，渗过去会在左边缘留一道暗带。
    // 声明在页面容器之后，才盖在图片上；宽度 88px 时启动页内容（左边距 ~80px）已在渐隐末端，不受影响。
    Rectangle {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 88
        visible: !stageHost.shifted && !root.sideCollapsed
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.00; color: Theme.sidebar }
            GradientStop { position: 0.26; color: Qt.rgba(Theme.sidebar.r, Theme.sidebar.g, Theme.sidebar.b, 0.62) }
            GradientStop { position: 0.58; color: Qt.rgba(Theme.sidebar.r, Theme.sidebar.g, Theme.sidebar.b, 0.24) }
            GradientStop { position: 1.00; color: Qt.rgba(Theme.sidebar.r, Theme.sidebar.g, Theme.sidebar.b, 0.0) }
        }
    }

    // 启动浮层（页面内，不新开窗口）；启动中压住一切
    LaunchOverlay {
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    // ══ 全屏页宿主 ══
    // 过渡的做法（两次翻车后的定论）：
    //   · 宿主自身**从不做 opacity 动画**，一出现就是不透明实底 —— 半透明帧是"透出启动页"的唯一根因；
    //   · 动效只做在宿主内部的位移上（内容从右/下方 12~40px 归位），且宿主 clip 住，
    //     位移留下的缝露出的是宿主自己的底色，不是下层页面；
    //   · 关闭方向是硬切（目标页本来就是下层），进入方向才有过渡。

    // 版本管理（全窗覆盖）
    Item {
        id: versionsHost
        anchors.fill: parent
        visible: root.versionsOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 右侧 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            id: versionsSurface
            anchors.fill: parent
            // 独立于 state 管的 x/scale 的第二个位移通道：
            // 版本设置关闭、回到列表时用它做一次轻微归位（见 versionsSettleAnim）。
            // 用 transform 而不是再动 x，避免和 state 的 PropertyChanges 抢同一个属性。
            transform: Translate { id: versionsSettle; y: 0 }
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.versionsOpen
                PropertyChanges { target: versionsSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: versionsSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: versionsSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
        VersionPage {
            anchors.fill: parent
            toast: toastHost
            onClose: root.versionsOpen = false
            onOpenSettings: (vid) => {
                root.settingsVersionId = vid
                root.settingsOpen = true
            }
        }

        // ── 从版本列表进版本设置，退出时的过渡（2026-11-14）──
        // 关键：**关闭是瞬时的**，设置页立刻消失、不阻塞任何操作；
        // 过渡做在下层的版本列表上 —— 它自己轻放入场（与启动页
        // stagePage.playEnter() 完全同一思路）。
        // 旧做法是让设置页整体淡出 320ms 再消失，等于"关个页面还要等动画"，
        // 手感很差（影明确否掉）。
        ParallelAnimation {
            id: versionsSettleAnim
            NumberAnimation { target: versionsSettle; property: "y"; from: 10; to: 0; duration: Theme.durBase; easing.type: Theme.easeEnter }
            NumberAnimation { target: versionsSurface; property: "opacity"; from: 0.92; to: 1; duration: Theme.durBase; easing.type: Theme.easeEnter }
        }
        Connections {
            target: root
            function onSettingsOpenChanged() {
                // 只有"设置页叠在版本列表之上"这一条路径需要补过渡；
                // 从启动页进来的那条本来就正常（关闭会重放启动页入场）。
                if (!root.settingsOpen && root.versionsOpen) versionsSettleAnim.restart()
            }
        }
        }
    }

    // 版本设置（全窗覆盖；叠在版本页之上，返回回到版本页）
    Item {
        id: settingsHost
        anchors.fill: parent
        visible: root.settingsOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        Item {
            id: settingsSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.settingsOpen
                PropertyChanges { target: settingsSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: settingsSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: settingsSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
            VersionSettingsPage {
                id: settingsPage
                anchors.fill: parent
                versionId: root.settingsVersionId
                // 页面是常驻实例（只切 visible），分区页不会因此重建，
                // 所以要把「打开了」这个信号显式传进去触发刷新（2026-11-14）。
                opened: root.settingsOpen
                toast: toastHost
                onClose: root.settingsOpen = false
                // 全局拖入要按"用户当前在看哪个分区"决定文件落到哪，
                // 所以把当前分区同步回 StageShell。
                onCurrentKeyChanged: root.settingsPane = currentKey
            }
        }
    }

    // 全局设置（全窗覆盖；与版本设置页同一套入场）
    Item {
        id: prefsHost
        anchors.fill: parent
        visible: root.prefsOpen
        clip: true
        // 外观页「实时预览」：隐藏工作交给页面自己做（SettingsPage.chromeOpacity + 外观页 solo），
        // 这里保持不透明 —— 整页压透明度会让两层文字叠在一起，读不清也难看。
        // 但**这层宿主底色也必须一起让开**，否则设置页透明后露出来的是这层纯色（实测黑屏）。
        Rectangle {
            anchors.fill: parent
            color: (root.prefsOpen && prefsPage.livePreview) ? "transparent" : Theme.bg
            Behavior on color { ColorAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
        }
        Item {
            id: prefsSurface
            anchors.fill: parent
            // 收起态即出厂位置；打开时由 state 归位。
            // 不用「Behavior + duration: open ? durPage : 0」—— 时长与位移同帧求值，
            // 第二次打开会拿上一次的 0 直接瞬移。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.prefsOpen
                PropertyChanges { target: prefsSurface; x: 0; scale: 1 }
            }
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: prefsSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: prefsSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
            SettingsPage {
                id: prefsPage
                anchors.fill: parent
                toast: toastHost
                onClose: {
                    root.prefsOpen = false
                    // 还原侧栏选中项，否则退出后仍高亮「设置」
                    var back = root.prefsPrevKey
                    sideBar.currentKey = back
                    // 进设置时把所有页面都关掉了（设置是全屏页，声明顺序上联机/下载宿主在它前面，
                    // 不关就会被压在设置底下继续显示）。所以退出时必须**按还原的侧栏项把页面开回来** ——
                    // 之前只还原了侧栏高亮，于是「联机页进设置再退出」会变成
                    // 侧栏高亮联机、画面却是启动页（影报的正是这个）。
                    root.multiplayerOpen = (back === "multiplayer")
                    root.downloadOpen = (back === "download")
                    root.progressOpen = (back === "progress")
                    console.info("[ui] 退出设置，还原页面: " + back)
                }
            }
        }
    }

    // 账户（全窗覆盖）
    Item {
        id: accountHost
        anchors.fill: parent
        visible: root.accountOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 下方 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            id: accountSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            y: 40
            scale: 0.988
            states: State {
                name: "shown"
                when: root.accountOpen
                PropertyChanges { target: accountSurface; y: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: accountSurface; property: "y"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: accountSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
        AccountPage {
            id: accountPage
            anchors.fill: parent
            toast: toastHost
            externalApiToApply: root.pendingAuthlibApi
            onClose: root.accountOpen = false
        }
        }
    }

    // 下载页
    Item {
        id: downloadHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.downloadOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 右侧 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            id: downloadSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.downloadOpen
                PropertyChanges { target: downloadSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: downloadSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: downloadSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
        DownloadPage {
            id: downloadPage
            anchors.fill: parent
            toast: toastHost
            onClose: root.downloadOpen = false
            // 配置页点了「开始安装」：切到独立进度页，侧栏高亮跟随
            onOpenProgress: {
                root.progressOpen = true
                root.downloadOpen = false
                sideBar.currentKey = "progress"
            }
            onOpenResourceDetail: (kind, item) => {
                resDetail.kind = kind
                resDetail.item = item
                root.resDetailOpen = true
            }
        }
        }
    }

    // 联机页（与下载页同一套：侧栏常驻，页面自绘标题与内容）
    Item {
        id: multiplayerHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.multiplayerOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场只做位移 + 轻微缩放，宿主不透明且 clip 住 —— 不会透出下层启动页
        Item {
            id: multiplayerSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            x: 24
            scale: 0.988
            states: State {
                name: "shown"
                when: root.multiplayerOpen
                PropertyChanges { target: multiplayerSurface; x: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: multiplayerSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: multiplayerSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
        MultiplayerPage {
            anchors.fill: parent
            toast: toastHost
        }
        }
    }

    // 资源详情（全屏独立页，自带实底，拦截穿透）
    Item {
        id: resDetailHost
        anchors.fill: parent
        visible: root.resDetailOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 下方 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            id: resDetailSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            y: 12
            scale: 0.988
            states: State {
                name: "shown"
                when: root.resDetailOpen
                PropertyChanges { target: resDetailSurface; y: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: resDetailSurface; property: "y"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: resDetailSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
        ResourceDetailPage {
            id: resDetail
            anchors.fill: parent
            toast: toastHost
            fileDl: root.fileDl
            onDownloadsStarted: {
                // 下载已经在跑，直接把用户送到能看到它的地方
                root.resDetailOpen = false
                root.progressOpen = true
                sideBar.currentKey = "progress"
            }
            onBack: root.resDetailOpen = false
        }
        }
    }

    // 下载进度
    Item {
        id: progressHost
        anchors.left: sideBar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.progressOpen
        clip: true
        Rectangle { anchors.fill: parent; color: Theme.bg }
        // 入场：内容从 下方 挪回原位。
        // 底已经是不透明的，且 clip 住宿主 —— 空隙里露出的是自己的底色，永远透不出下层启动页。
        // 只做位移不做透明度：不会出现"先空一帧再显内容"。
        Item {
            id: progressSurface
            anchors.fill: parent
            // 收起态就是出厂位置；打开时由下面的 state 把它归位。
            // 不能用「Behavior + duration: open ? durPage : 0」——时长和位移在同一帧求值，
            // 第二次打开会拿到上一次关闭时算出的 0，位移直接瞬移（影报的"第二次进入是硬切"）。
            y: 12
            scale: 0.988
            states: State {
                name: "shown"
                when: root.progressOpen
                PropertyChanges { target: progressSurface; y: 0; scale: 1 }
            }
            // 只写 to: "shown" —— 进入才有过渡；离开没有 transition，保持既有的瞬时关闭
            transitions: Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: progressSurface; property: "y"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                    NumberAnimation { target: progressSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
                }
            }
        ProgressPage {
            id: progressPage
            anchors.fill: parent
            toast: toastHost
            fileDl: root.fileDl
        }
        }
    }

    // Toast：右下角通知栈。全窗挂一份，页面通过 toast 属性调用；
    // 不再往顶栏塞一行绿色文字（会挤动右侧按钮，且离开该页就看不到）。
    ToastHost {
        id: toastHost
        anchors.fill: parent
    }

    // 全局拖入：挂在整个窗口上，任何页面拖入都能接住。
    // 之前只在版本页 / 资源页 / 账号页各挂一个，结果在版本设置的 Mod 管理页拖文件
    // 什么都接不到（那里没有接收器），用户看到的就是一个"复制"光标。
    // 类型判定一律交给后端看压缩包结构，页面不再各自猜。
    SDropZone {
        anchors.fill: parent
        z: 800
        active: true
        // 这里只做**粗筛**：拖动过程中不可能去开压缩包（每移动一下解一个 zip 会卡死），
        // 所以按扩展名放过候选，真正的类型判定留给松手后的 classifyDroppedTarget。
        // 目的只有一个：拖 .png / .exe 这种明显不可能的东西进来时，当场就告诉用户不行，
        // 而不是挂着「松开以导入」的遮罩骗他松手。
        //
        // 粗筛范围和提示文案都由 StageShell 按当前页面算出（dropAcceptExts / dropHint*），
        // 不再写死一份"什么都能导"的清单 —— 那与 Mod 只能在本页导入的实际规则矛盾。
        accept: root.dropAcceptExts
        forceShow: root.dropHintForceShow
        hintTitle: root.dropHintTitle
        hintBody: root.dropHintBody
        rejectTitle: qsTr("这里不接受这种文件")
        rejectBody: root.dropRejectBody
        onDropped: (urls) => root.handleGlobalDrop(urls)
    }

    // 窗口按钮：所有页面共用（否则进全屏页就丢最小化/关闭）
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        spacing: 4
        z: 900
        SWindowButton {
            iconName: "minus"
            onClicked: if (root.hostWindow) root.hostWindow.showMinimized()
        }
        SWindowButton {
            iconName: "x"
            danger: true
            onClicked: if (root.hostWindow) root.hostWindow.close()
        }
    }

    // 协议门禁：未同意前盖住整个界面（连侧栏和窗口按钮一起）。
    // 必须**最后声明**：同 z 时后声明者在上；上面那排窗口按钮 z:900，本层 z:1000 仍压住它。
    AgreementGate {
        id: agreementGate
        anchors.fill: parent
        b: root.b
        hostWindow: root.hostWindow
    }
}
