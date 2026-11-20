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
| E | 每个主页面都常驻实例化（Stage/Version/VersionSettings/Settings/Account/Download/Multiplayer/ResourceDetail） | `StageShell.qml:670/762/822/872/925/969/1021/1059` | 含在 1425ms QML 里 | **延后**：非默认页改 Loader 惰性创建（`SettingsPage` 已是 Loader，可复用） |
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
**P1（收益 1.4s 首屏 + 别让后台抢资源）**：E（页面惰性）+ C/D（Java 相关延后）。
**P2（安全，非性能）**：G —— release 关掉 ScreenshotServer。
**P3（细节）**：F。

## 四、不建议动的

- 版本列表与账号信息：首屏就要用（版本号、头像），延后反而让首屏闪。
- UpdateManager 检查：已有 6h 节流。
- 三个 IconCache：只是 mkpath，删了会在首次取图标时卡一下。
