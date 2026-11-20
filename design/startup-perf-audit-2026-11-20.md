# 启动性能清点（2026-11-20）

> 目的：把「启动器一开机就加载了一堆当下不需要的东西」这件事量化，并逐条给出处理建议。
> 数据来源：`build/Release/logs/shadow_launcher_2026-11-20_22-16-20.log` 的 `[后端启动 +Nms]` 标记、
> 以及用 Qt6Core 单独编译的 benchmark（`_bench_json` / `_benchnorm`）实测。

## 一、实测时间线（v1.0.4，本机）

| 时刻 | 事件 | 距启动 |
|---|---|---|
| 20.677 | 日志就绪 / AppBackend | +0 |
| 20.703 | Account / Yggdrasil / Settings / Check / Version / Launch 全部构造完成 | +26ms |
| 20.704 → 21.281 | **ResourceBackend 构造**（ModManager + 解析两个 JSON） | **577ms** |
| 21.282 | JavaBackend 构造 → 立刻 HTTP GET 清华镜像 | +605ms |
| 21.412 | 8 个后端全部就绪（Constructor done） | +735ms |
| 21.415 → 22.840 | **QML 加载 + 全部页面实例化** | **1425ms** |
| 22.842 | 事件循环启动 / ScreenshotServer 监听 9999 | +2165ms |
| 22.843 | 版本列表刷新（缓存命中 923 个版本，解析 11ms） | |
| 22.901 | **首帧渲染完成** | **2224ms** |
| 22.793 → 24.174 | 系统 Java 扫描：5 个 JDK（异步，spawn 5+ 子进程） | 1.4s |
| 20.680 → 23.088 | Mojang 档案 + 皮肤/披风拉取（异步网络，2 个披风写盘） | 2.4s |

## 二、清点清单

| # | 启动时干了什么 | 证据 | 实测成本 | 建议 |
|---|---|---|---|---|
| A | `normTitle()` 每次调用都构造 `QRegularExpression` | `resource_backend.cpp:30` | **407ms**（28k 次调用，bench 实测） | **立即修**：改 static 常量（27ms）或手写过滤（3ms） |
| B | 解析 `mcmod_map.json`（1.8MB / 28k 条）+ `mod_zh.json`（688KB / 8k 条） | `resource_backend.cpp:262-263` | 纯解析+建索引仅 ~50ms（bench），大头是 A | 修完 A 后可接受；进一步可延后到首次搜索/详情页 |
| C | `JavaBackend` 构造即 `refreshVersions()` → GET 清华 Adoptium 列表 | `java_backend.cpp:24` | 网络 665ms（异步） | **延后**到打开 Java 页/设置时 |
| D | `scanSystemJavas()` 启动即扫描系统 Java | `shadow_backend.cpp:262` | 1.4s + 5 个子进程 | **延后**到 Java 页可见或启动游戏前 |
| E | 每个主页面都常驻实例化（Stage/Version/VersionSettings/Settings/Account/Download/Multiplayer/ResourceDetail） | `StageShell.qml:670/762/822/872/925/969/1021/1059` | 含在 1425ms QML 里（未拆到页级） | **先量再改**：不改成「首次点击才建」，改成「首帧后空闲时建」（见第五节） |
| F | `VersionPage` 不可见也调 `mcFolder.refreshFolders()` | `VersionPage.qml:386-395` | 扫盘（未单独计时） | **延后**到 `onVisibleChanged` |
| G | ScreenshotServer 常开，监听 127.0.0.1:9999 | `main_release.cpp:768,900-902` | 忽略不计，但**release 也开** | **清理**：仅在 dev/带参数时启动 |
| H | Mojang 档案 + 皮肤 + 2 个披风 | `account_backend`（+24ms 构造，异步拉取） | 网络 400ms + 2 次写盘 | **保留**（侧栏头像要用），可先读缓存、拉取延后 |
| I | 版本列表刷新：923 个版本（缓存命中） | `version_backend` | 11ms | 保留 |
| J | UpdateManager 静默检查 | `shadow_backend.cpp` | 已节流 6h，本次跳过 | 保留 |
| K | IconCache ×3（mkpath）+ 司南缓存目录 | `shadow_backend.cpp:275-277` | ~128ms 窗口（含联机设备） | 保留 |
| L | 联机设备昵称/房码 | `[Net] 设备昵称=` | 忽略 | 保留 |
| M | AgreementGate / Toast / LaunchOverlay | QML | 忽略 | 保留 |
| N | i18n 语言选择（QSettings） | `[autoLang]` | 忽略 | 保留 |

## 三、优先级

**P0（一行改动，收益 400ms）**：A —— `normTitle` 的正则改 static。
**P1（收益 1.4s 首屏 + 别让后台抢资源）**：E（页面创建时机，方案见第五节，**先加页级计时再动**）+ C/D（Java 相关延后）。
**P2（安全，非性能）**：G —— release 关掉 ScreenshotServer。
**P3（细节）**：F。

## 四、不建议动的

- 版本列表与账号信息：首屏就要用（版本号、头像），延后反而让首屏闪。
- UpdateManager 检查：已有 6h 节流。
- 三个 IconCache：只是 mkpath，删了会在首次取图标时卡一下。

## 五、关于「页面常驻」（2026-11-20 补充判断）

影提出一个正确的反驳：**常驻实例化对页面切换有利** —— 页面已在内存里，切换零组件创建成本，
不会出现「第一次点下载页先卡半秒再出内容」。所以「改成惰性」不是无脑优化。重新梳理：

**三种时机，成本不同**

| 方案 | 首帧 | 首次打开页面 | 结论 |
|---|---|---|---|
| 现在：全常驻 | 慢（1425ms 全付） | 快（0ms） | 每次启动都付，只有部分页面被用到 |
| 全惰性（点击才建） | 快 | **慢（可能几百 ms 白屏/骨架）** | 影担心的就是这个，**不采用** |
| **首帧后空闲创建** | 快 | 快（用户点开时通常已建好） | **推荐** |

**为什么「首帧后空闲创建」两头都占**：首帧之后才轮到页面创建，它不再阻塞窗口出现；
而用户从看到窗口到点「下载 / 设置」一般要 500ms 以上，这段时间足够把页面建完。
等于把 1425ms 的启动成本挪进「反正也在等」的空档。

**两条支持它的证据**

1. `StageShell.qml` 里已有空值保护：`downloadPage ? downloadPage.resourceBusy : false`、
   `accountPage ? ... : false`、`resDetail ? ... : false`（第 417/419/424 行）——
   说明代码本来就允许某些页面「当时还没被创建」，改造风险比看起来小。
2. 常驻不等于零成本：`VersionPage.Component.onCompleted` 会调 `mcFolder.refreshFolders()` 扫盘
   （第 386-395 行），即使页面不可见。所以现状是既付内存也付扫盘。

**动手前提**：目前只知道 QML 整体 1425ms，**不知道每页各占多少**。
先给每个页面加一行 `console.info("[启动] 页面 X 就绪 +Nms")`（复用后端 `[后端启动 +Nms]` 的风格），
跑一次拿到页级数字，再决定「哪些页留在首帧内、哪些挪到空闲」。没数字就动，属于猜。

**另外**：真正该先做的是 A（`normTitle`，400ms，1 行）与 G（ScreenshotServer，安全项），
这两个不涉及任何时序改造，零回归风险。页面时机改造放在页级数据之后。

## 六、已落地（2026-11-20 第一批）

| 项 | 改动 | 实测 |
|---|---|---|
| A | normTitle 的 QRegularExpression 改 static const | ResourceBackend 构造 577ms 降到 100ms |
| G | ScreenshotServer 默认不启动（需 --ui-screenshots 或 SHADOW_SS_PORT） | 9999 端口确认无监听 |

**首帧对比（同机、同构建、热启动）**：

| 指标 | 改前 | 改后 |
|---|---|---|
| 首帧渲染完成 | 2224ms | **1812ms** |
| total startup（到事件循环） | 2197ms | **1781ms** |
| ResourceBackend 构造 | 577ms | **100ms** |

冷启动第一次跑出 2626ms（磁盘缓存未热），第二次回到 1781ms。看这个指标要固定冷/热条件，
否则 800ms 的抖动会被误读成回归。

剩余未做：C/D（Java 相关延后）、E（页面创建时机，需先加页级计时）、F（VersionPage 扫盘时机）。

## 七、第二批（C / D / F）与 E 的结论

| 项 | 改动 | 实测 |
|---|---|---|
| C | JavaBackend 构造不再请求 Adoptium；新增 ensureVersionsLoaded()（幂等、失败可重试），Java 页可见时才拉 | 启动时 Adoptium 请求 1 → 0 |
| D | JavaPage 构造不再无条件扫系统 Java，只有页面本就可见才扫，否则等 onVisibleChanged | 启动时 java -version 探测 5 → 0 |
| F | VersionPage 构造不再 refreshFolders()（onPageShown 里本来就有同一句） | 启动少一次盘扫描 |

**验证方式**：`--ui-java-step 2` 打开 Java 页，日志按需出现「刷新Java版本列表」与 Adoptium 各级 GET；
正常启动的日志里 `Adoptium|检测到 Java|前置检测` 命中数 = 0。功能没有变化。

**E 的结论：不做页面惰性化**。先按计划加了页级计时，结果打翻了原来的假设：

- 8 个页面的 `Component.onCompleted` 在 **同一毫秒**（+868~871ms）全部触发 —— QML 把子组件的完成回调推迟到外层组件创建结束，所以页级 onCompleted 不能用来归因；
- 改用「临时移除一页 + A/B」实测：去掉 AccountPage（98KB，最大的一页），QML 加载 1780ms → 1704/1734ms，即 **一个页面只占 ~70ms**；
- 也就是说 QML 那 1.4~1.8s 的大头不在页面实例化，而在引擎/外壳/启动浮层/首次 polish。

结论：E 的前提不成立，不值得为它改 Loader（会引入页面状态、visible 时机、--ui-pane 钩子一串回归风险）。
页级计时探针已撤（它给出的是「最外层创建结束时刻」，留着会误导后来人）。

**度量教训**：这台机器上 QML 加载时间在 1.4s~2.9s 之间漂移（同一份代码、连跑 5 次），
绝对值不能拿来做结论；只有「同一时段内的 A/B」和「事件计数（请求数/进程数）」是可信的。
