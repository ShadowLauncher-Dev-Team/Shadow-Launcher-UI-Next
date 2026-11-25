# Shadow Launcher 代码索引（CODE_INDEX）

> **用途**：找功能 → 先查本文件 → 再去读代码。本文件只描述**当前**代码结构与职责，不描述历史。
>
> **不写什么**：更新日志与变更记录（GitHub commit 里有）、报错排查过程（见记忆库）、构建与环境配置（见 `ENV_SETUP.md`）、开发禁忌与流程（见 `DEV_RULES.md`）。

## 维护规则

1. 新增 / 删除 / 改名代码文件时，**同一次提交内**更新本文件。
2. 只写「现在是什么」，不写「以前怎样」「哪天改的」「是谁修的」。
3. 路径相对仓库根；职责一行说清，≤40 字；关键入口最多列 3 个。
4. 目录重组、大范围重命名这类结构性变更，允许整篇重写；日常维护只做增量修改。

## 一、速查：按功能找文件

| 想找的功能 | 看这里 |
|---|---|
| 程序入口（唯一） | `src/main_release.cpp` |
| 版本号唯一源 | `src/version.h` 的 `SHADOW_DISPLAY_VERSION` |
| 配置占位（Azure client / Gitee / 更新地址） | `src/secrets.h` |
| QML 根窗口 | `ui/Main.qml`（窗口本体 + 声明 `StageShell` / 启动动画 / 更新卡片窗） |
| 应用外壳与页面路由 | `ui/StageShell.qml`（直接实例化各 Page，路由/转场都在这里；**窗口拖动不在它里面**，已下放到各 Page 的 topBar MouseArea） |
| 侧栏菜单 | `ui/SideBar.qml` |
| 主题令牌（颜色/字号/圆角） | `ui/Theme.qml` —— QML 侧唯一被引用的令牌源；注意 `src/ui_next/AppearanceController` 另有一套调色板数据，当前 QML 未引用，启用前需先决定单一真源 |
| Toast 通知 | `ui/ToastHost.qml` |
| 启动动画 | `ui/StartupIntro.qml` + `ui/StartupIntroHalo.qml` |
| 首次启动协议确认 | `ui/AgreementGate.qml` |
| 启动游戏时的全屏遮罩 | `ui/LaunchOverlay.qml` |
| 首屏 / 启动页（玩哪个、要不要启动） | `ui/pages/StagePage.qml` |
| 版本管理页 | `ui/pages/VersionPage.qml` |
| 版本设置（右栏 + 各子页） | `ui/pages/VersionSettingsPage.qml` + `Vs*Pane.qml` |
| 下载页 / 下载进度页 | `ui/pages/DownloadPage.qml`、`ui/pages/ProgressPage.qml` |
| 账号页（登录/皮肤/披风） | `ui/pages/AccountPage.qml` |
| Java 管理页 | `ui/pages/JavaPage.qml` |
| 资源页 / 资源详情页 | `ui/pages/ResourcePage.qml`、`ui/pages/ResourceDetailPage.qml` |
| 联机页 | `ui/pages/MultiplayerPage.qml` |
| 设置页 + 各分页 | `ui/pages/SettingsPage.qml` + `Set*Pane.qml` |
| QML 能访问的唯一后端对象（`backend`） | `src/backend/shadow_backend.{h,cpp}`（转发所有子后端信号/属性） |
| 版本列表/安装/删除/校验/修复/隔离 | `src/backend/version_backend.{h,cpp}` |
| 启动游戏（进程/参数/Token/日志） | `src/backend/launch_backend.{h,cpp}`、`src/core/launcher.{h,cpp}` |
| 游戏「对局域网开放」端口检测（日志文案 + 增量监视） | `src/utils/mc_lan_log.h`、`src/backend/launch_backend.cpp`（probeLanPortFromLogs / onLanLogWatchTick） |
| 账号（离线 / 微软正版 / 皮肤 / 披风） | `src/backend/account_backend.{h,cpp}`、`src/core/microsoft_auth.{h,cpp}` |
| 外置登录（Yggdrasil / authlib-injector） | `src/backend/yggdrasil_backend.{h,cpp}`、`src/core/yggdrasil_auth.{h,cpp}` |
| 内嵌微软登录窗口（WebView2） | `thirdparty/wv2login/src/AppWindow.{h,cpp}` |
| 设置持久化 | `src/backend/settings_backend.{h,cpp}` |
| Java 扫描 / 选择 / 自动安装 | `src/backend/java_backend.{h,cpp}`、`src/core/java_runtime_installer.{h,cpp}` |
| 启动前检查（Java/版本文件/内存） | `src/backend/check_backend.{h,cpp}` |
| 版本目录布局 / 隔离 / 导入 | `src/core/minecraft_layout.{h,cpp}`、`src/core/version_isolation.{h,cpp}`、`src/backend/minecraft_folder_backend.{h,cpp}` |
| 资源搜索（Mod/资源包/光影/整合包） | `src/backend/resource_backend.{h,cpp}` + `src/core/resource_fetch_engine.{h,cpp}`（司南）+ `src/core/cf_api.{h,cpp}`（CurseForge） |
| 下载引擎（通用批量） | `src/core/file_downloader.{h,cpp}`（夸父） |
| 下载引擎（assets 资源） | `src/core/asset_downloader.{h,cpp}`（山海经） |
| 版本安装管线（client+libs+assets） | `src/core/version_downloader.{h,cpp}`（盘古） |
| Mod 批量下载 | `src/core/modpack/mod_download_engine.{h,cpp}`（精卫） |
| 整合包解析 / 下载 / 安装 / 导出 | `src/core/modpack/`（女娲 = `modpack_downloader`） |
| Forge / NeoForge / OptiFine 安装 | `src/core/mod_loader_installer.{h,cpp}` |
| 本地 Mod / 资源包 / 存档管理 | `src/core/local_mod_manager.{h,cpp}`、`src/core/mod_manager.{h,cpp}` |
| 联机（陶瓦 Terracotta 兼容） | `src/multiplayer/multiplayer_manager.{h,cpp}` |
| EasyTier 进程 / 白名单 | `src/multiplayer/easytier_process.{h,cpp}` |
| 房码算法 | `src/multiplayer/room_code.{h,cpp}` |
| Scaffolding 协议 | `src/multiplayer/scaffolding_protocol.{h,cpp}` |
| 更新检查 / 下载 / 安装 | `src/core/update_manager.{h,cpp}`、`update/SLUpdater.cpp`（独立更新器进程） |
| 安装步骤管线（进度 UI 的模型） | `src/core/step_pipeline.{h,cpp}`、`src/core/step_node.{h,cpp}` |
| 引擎雅名体系（盘古/夸父/山海经…） | `src/core/engine_identity.h` |
| 下载会话（跨页复用） | `src/session/download_session.{h,cpp}` |
| 外观 / 壁纸控制器 | `src/ui_next/appearance_controller.{h,cpp}` |
| HTTP 客户端 / 重试 | `src/core/http_client.{h,cpp}` |
| 日志（运行日志 / 调试日志） | `src/core/logger.{h,cpp}`、`src/utils/logger.{h,cpp}`、`src/backend/debug_logger.{h,cpp}` |
| 临时文件追踪与清理 | `src/utils/temp_tracker.{h,cpp}`、`src/core/cleanup_guard.h` |
| 崩溃检测 / 异常退出恢复 | `src/core/crash_detector.{h,cpp}` |
| 图标 / 头像缓存 | `src/core/icon_cache.{h,cpp}`、`src/core/render_head_util.h` |
| 下载转圈（C++ 场景图 item） | `src/ui_next/dl_spinner_item.{h,cpp}` |
| 自测可执行目标 | `tests/`，CMake 里用 `SHADOW_BUILD_UI_NEXT_TESTS` 等开关控制 |## 二、目录速览

```
src/
  main_release.cpp        程序入口（唯一）
  version.h               版本号唯一源
  secrets.h               Azure client / Gitee / 更新地址 占位（真实值走 secrets_local.h，不入库）
  ui_splash.*             启动闪屏（QQuickView）
  backend/                QML 后端聚合层：一个类一个后端，由 shadow_backend 统一暴露给 QML
  core/                   核心引擎与协议实现（不依赖 UI）
  core/modpack/           整合包子域
  multiplayer/            联机（陶瓦 Terracotta 协议兼容）
  session/                跨页会话状态
  utils/                  通用工具：哈希、日志、临时文件、令牌加密（lzma/ 是第三方 LZMA SDK）
  ui_next/                QML 侧 C++ 扩展（QQuickItem、壁纸控制器）
ui/
  Main.qml                窗口根（装配 StageShell + 启动动画 + 更新卡片窗）
  StageShell.qml          外壳与页面路由
  Theme.qml               主题令牌唯一真源
  *.qml                   公共层：侧栏、Toast、启动动画、遮罩、协议门
  pages/                  主页面（Stage/Version/Download/...）与子页（Set* 设置、Vs* 版本设置）
  controls/               通用控件：S- 前缀为基础控件，Set- 前缀为设置项组件
update/                   独立更新器进程（SLUpdater）
thirdparty/wv2login/      内嵌微软登录窗口（WebView2）
tests/                    自测可执行目标（CMake 开关控制）
tools/                    一次性脚本（抓数据/出图/验证），不属于产品代码
```

### 不维护的目录

| 路径 | 原因 |
|---|---|
| `src/utils/lzma/` | 第三方 LZMA SDK，随上游版本，不按本项目风格改注释 |
| `src/multiplayer/encrypted_*` | 由 `tools/encrypt_addr.py` 生成，改注释无意义 |
| `build/`、`dist/` | 构建产物 |

## 三、C++ 后端（`src/backend/`，QML 通过 backend 单对象访问）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `src/backend/account_backend.cpp` | 多账号/正版/离线/外置的登录、令牌刷新、皮肤披风装载 | AccountBackend::microsoftLogin, AccountBackend::switchAccount, AccountBackend::downloadOnlineSkin |
| `src/backend/account_backend.h` | 账号后端接口：属性、信号与多账号持久化结构 | AccountBackend, CapeInfo, StoredAccount |
| `src/backend/app_backend.cpp` | 应用级数据目录/游戏目录初始化与主题切换 | AppBackend(),setTheme,setGameDir |
| `src/backend/app_backend.h` | 应用级属性（版本号/数据目录/主题/开发模式） | AppBackend, appVersion, AGREEMENT_VERSION |
| `src/backend/check_backend.cpp` | 启动前 P0 校验：Java、jar、json、内存 | checkAll,checkJava,checkMemory |
| `src/backend/check_backend.h` | CheckBackend 接口声明（P0 同步校验） | checkAll,checkJavaArch |
| `src/backend/debug_logger.cpp` | 调试日志面板文本/条目与网络速率格式化 | append,net,speed |
| `src/backend/debug_logger.h` | DebugLogger 声明（QML_ELEMENT 单例） |  |
| `src/backend/java_backend.cpp` | Adoptium 镜像目录列表 + Java 下载/安装转发 | ensureVersionsLoaded,installJavaRuntime,installJavaForLaunch |
| `src/backend/java_backend.h` | JavaBackend 声明与 QML 属性/信号契约 |  |
| `src/backend/launch_backend.cpp` | 启动状态机：预检/内存/崩溃分析，游戏日志 LAN 端口监视 | runNextCheck, onLanLogWatchTick, probeLanPortFromLogs |
| `src/backend/launch_backend.h` | 启动流程：阶段管线、Java 自动装、崩溃分析接口 | LaunchBackend::launch, launchStepRows, exportLaunchScript |
| `src/backend/minecraft_folder_backend.cpp` | 外部 .minecraft 探测与游戏文件夹注册表实现 | probe, setActiveFolder, refreshFolders |
| `src/backend/minecraft_folder_backend.h` | 外部 .minecraft 选择/识别与多文件夹注册表接口 | MinecraftFolderBackend, probeMinecraftFolder, folders |
| `src/backend/resource_backend.cpp` | 资源双源池搜索（Mod/光影/资源包/整合包/数据包） | searchModsEx,resourcePoolState,resolveProjectLinks |
| `src/backend/resource_backend.h` | ResourceBackend 声明与池子/游标状态字段 |  |
| `src/backend/settings_backend.cpp` | QSettings 设置持久化、Java 扫描与背景图库 | loadSettings,scanJavaInstallations,findJavaForVersion |
| `src/backend/settings_backend.h` | 全局设置：Java/内存/背景图库/下载源/启动细节 | SettingsBackend, bgPresets, findJavaForVersion |
| `src/backend/shadow_backend.cpp` | 总装后端：装配各子后端并统一转发信号给 QML | proceedLaunch,switchAccount,exportLaunchScript |
| `src/backend/shadow_backend.h` | 门面：向 QML 暴露全部子后端并转发槽与信号 | ShadowBackend, account(), launchBackend() |
| `src/backend/userdata_backend.cpp` | 用户数据 ZIP 导出/校验/导入（版本目录根散开） | doExport, parseArchiveItems, executeImport |
| `src/backend/userdata_backend.h` | 用户数据导入导出接口与条目风险模型 | UserDataBackend, ImportItemInfo, validateArchive |
| `src/backend/version_backend.cpp` | MC/加载器安装编排、步骤管线、校验与修复 | installModLoader, rebuildStepsByKeys, verifyVersion |
| `src/backend/version_backend.h` | 版本后端接口：安装卡片模型、合并安装上下文、校验器 | VersionBackend, InstallCardModel, MergedInstallContext |
| `src/backend/yggdrasil_backend.cpp` | 外置登录：ALI 解析、认证、会话恢复与校验 | resolveApiRoot,login,validateSession |
| `src/backend/yggdrasil_backend.h` | YggdrasilBackend 声明与信号契约 |  |
| `src/backend/yggdrasil_skin_fetcher.cpp` | 外置皮肤抓取、缓存与兜底头像渲染 | fetchSkin,cacheDir |
| `src/backend/yggdrasil_skin_fetcher.h` | 外置登录皮肤获取（sessionserver + 域名白名单） | YggdrasilSkinFetcher::fetchSkin, cacheDir, applyFallbackSkin |

## 四、核心引擎（`src/core/`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `src/core/asset_downloader.cpp` | 资源/库文件高并发下载引擎：分片、镜像与看门狗 | startDownload, appendTasks, fireNext |
| `src/core/asset_downloader.h` | assets 专项下载引擎（自适应并发/分片/缓存预检）声明 | AssetDownloader::startDownload, appendTasks, setMaxConcurrent |
| `src/core/cf_api.cpp` | CurseForge API 适配：分类、搜索、版本与依赖 | CfApi::search, fetchFilesAsVersions, fetchModDependencies |
| `src/core/cf_api.h` | CurseForge API 适配器接口（搜索/文件/依赖/分类） | CfApi::search, fetchFilesAsVersions, toUnified |
| `src/core/cf_key_crypto.h` | 内嵌 CF Key 解密（HKDF + AES-GCM） | decryptEmbeddedCfKey, gcmDecrypt |
| `src/core/cleanup_guard.h` | 清理守卫纯逻辑：存档检测与残留分片删除 | dirHasUserSaves, removeStaleIndexParts |
| `src/core/crash_detector.cpp` | 崩溃报告解析、规则诊断与日志导出 | analyzeCrash, scanLatestCrash, exportLogs |
| `src/core/crash_detector.h` | 崩溃报告扫描与规则分析的数据结构与接口 | CrashDetector::analyzeCrash, exportLogs, matchRules |
| `src/core/download_accept.h` | 兜底重试的数据可接受性判定纯函数 | acceptFallbackPayload |
| `src/core/engine_identity.h` | 下载引擎雅名注册表与日志前缀/身份卡 | engineIdentity, engineTag, engineBanner |
| `src/core/file_downloader.cpp` | 夸父：多线程分片通用文件下载引擎实现 | addFile, managerTick, runWorker |
| `src/core/file_downloader.h` | 单文件多线程下载引擎（夸父）接口 | FileDownloader::addFile, start, setModpackMode |
| `src/core/geoip_service.cpp` | IP 地区检测（ip-api.com，24h 缓存，失败重试） | detectRegion, onReplyFinished, scheduleRetry |
| `src/core/geoip_service.h` | GeoIpService 接口（地区属性与检测信号） | detectRegion, regionDetected |
| `src/core/http_client.cpp` | 通用 HTTP 客户端与分片下载（驿道） | HttpClient::get, download, verifyFile |
| `src/core/http_client.h` | 驿道：HTTP 传输底座与文件下载句柄声明 | download, downloadWithReply, get |
| `src/core/icon_cache.cpp` | 图标 URL 磁盘缓存与超额淘汰 | IconCache::resolveUrl, cacheBatchAsync |
| `src/core/icon_cache.h` | 图标缓存类接口 | IconCache::cachedPath, resolveUrl |
| `src/core/java_runtime_installer.cpp` | 便携 Java 检测/下载/解压/完整性校验安装链 | installRequiredJavas, installJavaAsync, findAllJava |
| `src/core/java_runtime_installer.h` | Java 运行时检测与一键安装 | installRequiredJavas, scanSystemJavas, installJavaAsync |
| `src/core/launcher.cpp` | 组装启动参数并拉起/管理游戏进程 | Launcher::start, buildArgs, exportLaunchScript |
| `src/core/launcher.h` | 游戏启动（参数组装/进程管理/LAN 检测/日志脱敏） | start, buildLaunchScript, recentOutput |
| `src/core/loader_events.h` | 安装器事件到步骤 key 的映射（单一来源） | forLoader |
| `src/core/loader_plan.h` | 加载器安装步骤计划：key、权重、显隐 | LoaderPlan::make |
| `src/core/local_mod_manager.cpp` | 本地 mod/资源包/光影包扫描与启停 | scanMods, setModEnabled, scanResourcePacks |
| `src/core/local_mod_manager.h` | 本地 Mod/资源包/光影包扫描与启停接口 | scanMods, scanShaderPacks, setAllModsEnabled |
| `src/core/logger.cpp` | 日志单例实现（按日期文件 + 控制台镜像） | init, info, writeLog |
| `src/core/logger.h` | Logger 静态接口声明 | Logger::info, warn, error, init |
| `src/core/mc_language.cpp` | 区域/语言映射并写入 options.txt | localeToMinecraftLang, writeOptionsTxt |
| `src/core/mc_language.h` | 语言映射与 options.txt 写入接口 | localeToMinecraftLang, regionToMinecraftLang, writeOptionsTxt |
| `src/core/microsoft_auth.cpp` | 微软 OAuth 登录链：本地回调/内嵌助手 | startLogin, startEmbeddedLogin, refreshMcChain |
| `src/core/microsoft_auth.h` | 微软登录类接口、信号与忙碌状态 | startLogin, refreshMcChain, isUserBusy |
| `src/core/minecraft_layout.cpp` | 游戏目录布局探测与版本游戏目录解析 | probeMinecraftFolder, detectLayout, resolveVersionGameDir |
| `src/core/minecraft_layout.h` | 外部 .minecraft 布局识别与版本游戏目录解析 | probeMinecraftFolder, resolveVersionGameDir, detectLayout |
| `src/core/mod_loader_installer.cpp` | Forge/NeoForge/Fabric/OptiFine 安装器实现 | installForge, forgeStep3_route, runBootstrapperProcess |
| `src/core/mod_loader_installer.h` | ModLoaderInstaller 接口与安装状态 | installForge, installFabric, installOptifine |
| `src/core/mod_manager.cpp` | Modrinth 搜索/版本/下载与依赖解析 | searchModrinth, downloadMod, fetchModVersions |
| `src/core/mod_manager.h` | Modrinth/CF 搜索、版本查询与文件下载接口 | searchModrinth, downloadModFile, fetchVersionDependencies |
| `src/core/modpack_importer.cpp` | 整合包导入门面：装配任务与转发状态 | startImport, cancelImport, retryFailedModDownloads |
| `src/core/modpack_importer.h` | 整合包导入门面接口与 QML 属性 | startImport, importFinished, modItems |
| `src/core/region_utils.h` | 本地区域判定（系统时区/区域码） | isChinaRegion |
| `src/core/render_head_util.h` | 从 MC 皮肤裁剪缩放 128×128 头像 | renderHeadFromSkin |
| `src/core/resource_fetch_engine.cpp` | 司南引擎：API JSON 拉取与图标下载缓存 | getJson, iconLocalPath, prefetchIcons |
| `src/core/resource_fetch_engine.h` | 司南引擎接口：并发/缓存/重试策略 | getJson, iconLocalPath, iconReady |
| `src/core/screenshot_server.cpp` | 开发用截屏与 QML eval 的 HTTP 服务实现 | start, handleRequest, evalQml |
| `src/core/screenshot_server.h` | ScreenshotServer 接口与端点说明 | start, setWindow |
| `src/core/source_policy.h` | 源策略到 URL 的唯一决策点（按请求类别路由） | routeFor, preferOfficial, mcManifestPrimary |
| `src/core/step_keys.h` | 下载步骤 key 与显示名单一来源 | StepKeys::displayName, keyForLegacyName |
| `src/core/step_node.cpp` | 步骤节点状态与进度单调性实现 | setStatus, setPercentage, setByteProgress |
| `src/core/step_node.h` | StepNode 基类（Q_PROPERTY 定向绑定） | setStatus, setPercentage, setDetail |
| `src/core/step_pipeline.cpp` | 步骤模型与管线：状态、进度、显式推进 | addStep, advance, weightedProgress |
| `src/core/step_pipeline.h` | 步骤模型/管线类接口 | StepPipeline::addStep, start, advance |
| `src/core/update_manager.cpp` | 应用更新检查/断点续传下载/SHA256 校验 | checkSilent, doCheck, resumeDownload |
| `src/core/update_manager.h` | 启动器自更新生命周期与断点续传状态 | checkSilent, checkUserInitiated, resumePausedDownload |
| `src/core/version_downloader.cpp` | 盘古：版本安装管线（JSON/库/资源/校验/换源） | downloadVersion, onAllFinishedV2, retryWithNextMirror |
| `src/core/version_downloader.h` | VersionDownloader 接口与异步校验 worker | downloadVersion, cancel, retryWithNextMirror |
| `src/core/version_isolation.cpp` | 版本隔离配置与游戏目录解析（外部目录只读） | getVersionGameDir, isVersionIsolated, migrateToIsolated |
| `src/core/version_isolation.h` | 版本隔离开关与外部目录布局覆盖 | getVersionGameDir, markForeignIsolated, setFolderLayout |
| `src/core/version_manager.cpp` | 获取/缓存 MC 版本清单并判定已安装 | fetchVersions, isInstalled, parseManifest |
| `src/core/version_manager.h` | 版本管理器接口：源策略与缓存 | fetchVersions, isInstalled, setPreferOfficial |
| `src/core/yggdrasil_auth.cpp` | Yggdrasil 外置登录协议请求与响应解析 | authenticate, refresh, parseMeta |
| `src/core/yggdrasil_auth.h` | Yggdrasil 协议结构与会话接口 | YggdrasilAuth::authenticate, refresh, validate |

## 五、整合包子域（`src/core/modpack/`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `src/core/modpack/mod_download_engine.cpp` | 模组小文件批量下载引擎实现（分片/看门狗/重试） | ModDownloadEngine::pump, launchRequest, watchTick |
| `src/core/modpack/mod_download_engine.h` | 模组下载引擎对外契约与状态结构声明 | ModDownloadEngine, Segment, Item |
| `src/core/modpack/modpack_common.cpp` | 加载器标识/版本名/相对路径净化工具实现 | parseLoaderId, sanitizeVersionName, sanitizeRelPath |
| `src/core/modpack/modpack_common.h` | 双平台整合包统一数据结构与工具声明 | ModpackMeta, ModpackRemoteFile, parseLoaderId |
| `src/core/modpack/modpack_downloader.cpp` | CF 地址解析 + 引擎下载编排与信号桥接 | start, processResolvedBatch, onEngineFileFinished |
| `src/core/modpack/modpack_downloader.h` | 整合包下载层对外接口与运行态声明 | ModpackDownloader, DlItem |
| `src/core/modpack/modpack_exporter.cpp` | 版本导出：规则收集/双哈希查询/打包实现 | exportVersion, exportContext, postJson |
| `src/core/modpack/modpack_exporter.h` | 导出选项定义与 QML 可调接口声明 | ExportOptionDef, exportVersion, exportContext |
| `src/core/modpack/modpack_install_task.cpp` | 导入任务调度：解析/解压/下载/装 MC/回滚 | start, onDownloadAllFinished, rollback |
| `src/core/modpack/modpack_install_task.h` | 导入任务状态机、信号与卡片接口声明 | ModpackInstallTask, Phase, modItems |
| `src/core/modpack/modpack_parser.cpp` | CurseForge/Modrinth 清单解析实现 | detectFormat, parseCurseForge, parseModrinth |
| `src/core/modpack/modpack_parser.h` | 整合包解析层接口声明 | ModpackParser |
| `src/core/modpack/zip_archive.cpp` | miniz ZIP 读写封装与解压/打包实现 | extractPrefixTo, addFile, addDirectoryRecursive |
| `src/core/modpack/zip_archive.h` | ZIP 读写封装接口声明 | ZipArchive |

## 六、联机（`src/multiplayer/`，陶瓦 Terracotta 兼容）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `src/multiplayer/connection_guard.cpp` | 连接/入房/封包速率限制与冷却实现 | allowConnect, allowJoinRoom, checkAndAdd |
| `src/multiplayer/connection_guard.h` | 限流阈值常量与守卫接口声明 | ConnectionGuard, kMaxConnPerMinute |
| `src/multiplayer/easytier_process.cpp` | easytier-core 子进程启动与 peer/NAT 轮询 | start, parsePeerList, setTcpWhitelist |
| `src/multiplayer/easytier_process.h` | EasyTier 进程管理与 NAT 类型声明 | EasyTierProcess, EasyTierNatType |
| `src/multiplayer/mc_scanner.cpp` | LAN 组播收包：通配绑定 + 逐网卡加组，解析 MC 端口 | start, processDatagram, refreshInterfaces |
| `src/multiplayer/mc_scanner.h` | MC 扫描器接口与结果结构声明 | McScanner, McScanResult |
| `src/multiplayer/multiplayer_manager.cpp` | 联机房间编排：发现/握手/心跳/端口转发/FakeServer | startHostServer, notifyMcLanPort, startFakeServer |
| `src/multiplayer/multiplayer_manager.h` | 联机状态机、信号与成员声明 | MultiplayerManager, ConnectionDifficulty |
| `src/multiplayer/port_request.cpp` | 本地端口探测与固定回退实现 | requestSpecific, requestFree |
| `src/multiplayer/port_request.h` | 端口探测接口声明 | PortRequest |
| `src/multiplayer/relay_crypto.cpp` | 加密 blob 分片拼装与 AES-GCM 解密 | getAssembledBlob, aesGcmDecrypt, relayEndpoint |
| `src/multiplayer/relay_crypto.h` | 解密与中继端点接口声明 | aesGcmDecrypt, relayEndpoint, relayPrefix |
| `src/multiplayer/room_code.cpp` | 房间码生成/解析与 base34 校验和 | generate, parse, codeMod7 |
| `src/multiplayer/room_code.h` | 房间码结构与接口声明 | RoomCode::Parts, generate, parse |
| `src/multiplayer/scaffolding_protocol.cpp` | Scaffolding 协议包编解码实现 | buildPacket, buildResponse, packProtocolList |
| `src/multiplayer/scaffolding_protocol.h` | 协议名/状态码常量与编解码接口声明 | buildPacket, buildResponse, kHeartbeatIntervalMs |

## 七、会话与工具（`src/session/`、`src/utils/`、`src/ui_next/`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `src/session/download_session.cpp` | 安装会话实现：进度信号、取消、卡片导出 | cancel, toCard |
| `src/session/download_session.h` | 单个安装会话状态：步骤管线、速度、加载器数据 | pipeline, toCard, setSpeed |
| `src/ui_next/appearance_controller.cpp` | 外观控制器：配色/密度/动效令牌构建 | rebuildTokens, colorTokens, motionTokens |
| `src/ui_next/appearance_controller.h` | 外观控制器单例：主题、模式、密度与令牌 | setThemeId, tokens, availableThemes |
| `src/ui_next/dl_spinner_item.cpp` | 下载卡片不确定环的场景图绘制实现 | updatePaintNode, spinnerState |
| `src/ui_next/dl_spinner_item.h` | 下载卡片不确定环 QQuickItem 声明 | setRunning, setColor |
| `src/utils/hash_utils.h` | SHA1 十六进制统一入口 | sha1Hex |
| `src/utils/logger.cpp` | 会话日志落盘、重复折叠与告警摘要实现 | initLogger, installFileLogger |
| `src/utils/logger.h` | 分模块日志分类与日志初始化接口 | initLogger, logApp |
| `src/utils/mc_lan_log.h` | 「对局域网开放」日志行判定（≤26.1 / ≥26.2 两种文案） | McLanLog::openPort, isCloseLine |
| `src/utils/secure_wipe.h` | 敏感字符串/字节的安全清零工具 | secureWipe |
| `src/utils/temp_tracker.cpp` | 临时目录追踪文件读写与残留清理 | record, cleanupOrphans |
| `src/utils/temp_tracker.h` | 下载临时目录追踪与孤儿清理接口 | record, cleanupOrphans |
| `src/utils/token_crypto.cpp` | DPAPI 密钥保护 + AES-256-GCM 令牌加解密 | encrypt, decrypt |
| `src/utils/token_crypto.h` | 令牌加密接口（BCrypt + DPAPI） | encrypt, decrypt |
| `src/utils/types.h` | 全局数据结构：版本/账户/下载/设置/卡片 | McVersion, DownloadTask, InstallCard |

## 八、程序入口与其他（`src/*.cpp`、`update/`、`thirdparty/wv2login/`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `src/main_release.cpp` | 程序入口：窗口 / QML 引擎 / 后端装配 / 命令行开关（含各 --ui-* 调试开关） | `main`, `FocusClearFilter`, `--ui-next-mode` |
| `src/secrets.h` | 发布构建的配置占位符（真实值由本地 secrets_local.h 覆盖，该文件不入库） | `SHADOW_AZURE_CLIENT_ID`, `SHADOW_UPDATE_API_URL` |
| `src/ui_splash.cpp` | 启动封面窗实现：加载期静态画面，与 StartupIntro 第 0 帧对齐以做到无缝交接 | `SplashWindow::paintEvent` |
| `src/ui_splash.h` | 启动封面窗声明（QWidget；只为盖住 QML 同步加载那 1~2 秒的黑屏） | `SplashWindow` |
| `src/version.h` | 版本号唯一源（改这里，别再改 CMake 宏，否则触发全量重编） | `SHADOW_DISPLAY_VERSION` |
| `thirdparty/wv2login/src/App.cpp` | WebView2 登录辅助进程入口 | wWinMain |
| `thirdparty/wv2login/src/AppWindow.cpp` | WebView2 登录窗口与授权码捕获 | Initialize, CreateWebView2, Finish |
| `thirdparty/wv2login/src/AppWindow.h` | WebView2 登录窗口类声明 | Initialize, Finish |
| `thirdparty/wv2login/src/stdafx.h` | wv2login 预编译头与依赖 |  |
| `update/SLUpdater.cpp` | 独立更新进程：替换文件并重启 | wWinMain, copyTreeOverwrite |

## 九、QML 公共层（`ui/*.qml`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `ui/AgreementGate.qml` | 首次启动协议门禁与退场动画 | accept, docTitles |
| `ui/LaunchOverlay.qml` | 启动浮层：总进度、节点清单、失败诊断 | active, rows, crash |
| `ui/Main.qml` | 主窗口：尺寸适配与外壳/启动动画挂载 | StageShell, StartupIntro, UpdateCardWindow |
| `ui/MinRoot.qml` | 诊断用最小根窗口 | Window |
| `ui/SideBar.qml` | 侧栏导航与选中滑块 | navActivated, mainItems |
| `ui/StageShell.qml` | 外壳路由、全屏页宿主与全局拖入 | handleGlobalDrop, ToastHost |
| `ui/StartupIntro.qml` | 启动动画：字标从封面落进侧栏 | start, boot |
| `ui/StartupIntroHalo.qml` | 启动字标光晕层 | px, strength |
| `ui/Theme.qml` | 主题令牌唯一真源 | accent, bgUrl, durPage |
| `ui/ToastHost.qml` | 右下角 Toast 通知栈 | show, showAction |
| `ui/UpdateCardWindow.qml` | 更新卡片预览窗口 | mode, steps |

## 十、QML 页面（`ui/pages/`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `ui/pages/AccountPage.qml` | 账户页：登录、切换与移除账号，正版皮肤/披风衣柜 | close(), flash(), 登录结果信号 |
| `ui/pages/DownloadPage.qml` | 下载页：MC 版本列表 + 安装配置，含资源库与 Java tab | openResourceDetail(), openProgress(), tab |
| `ui/pages/JavaPage.qml` | 下载页 Java tab：按版本/JRE/架构/系统/分发形式选装 JRE | pickVersion(), refreshLocal(), step |
| `ui/pages/MultiplayerPage.qml` | 联机页：创建/加入房间、设备身份与成员列表 | createRoom(), joinRoom(), roomCode |
| `ui/pages/ProgressPage.qml` | 下载进度页：总览条 + 带步骤的任务卡，播放完成通知 | recalc(), installCardsModel, dismissCard() |
| `ui/pages/ResourceDetailPage.qml` | 资源详情页：按版本+加载器选文件，批量下载含前置 | installAll(), buildJobs(), downloadsStarted() |
| `ui/pages/ResourcePage.qml` | 资源库列表：Mod/光影/资源包/整合包/数据包共用的货架页 | doSearch(), applyPool(), handleDropped() |
| `ui/pages/SetAboutPane.qml` | 设置·关于：版本、许可、日志入口、鸣谢与内测名单 | checkForUpdate(), repoUrl, credits |
| `ui/pages/SetAdvancedPane.qml` | 设置·高级：启动器内嵌登录开关 | embeddedLoginEnabled |
| `ui/pages/SetAppearancePane.qml` | 设置·外观：配色方案与启动页图片取景 | setColorScheme(), applyBgPreset(), chooseBgImage() |
| `ui/pages/SetDownloadPane.qml` | 设置·下载：下载源、最大并发、限速 | fileDownloadSource, maxDownloadThreads, downloadSpeedLimitMB |
| `ui/pages/SetGeneralPane.qml` | 设置·常规：界面语言与游戏内语言写入 | setLanguageIndex(), setAutoLangMode() |
| `ui/pages/SetJavaPane.qml` | 设置·Java 与内存：扫描选择 Java、内存双滑块 | scanJavaInstallations(), availableJavaList(), setMinMemory() |
| `ui/pages/SetLaunchPane.qml` | 设置·启动：GC、优先级、全屏、自动进服、前后命令 | gcMode, processPriority, autoJoinServer |
| `ui/pages/SettingsPage.qml` | 全局设置全屏页：顶栏 + 左栏七项 + 分区内容 | rows, paneFor(), --ui-pane |
| `ui/pages/StagePage.qml` | 启动页首屏：玩哪个版本、账号入口与启动/取消 | openVersions(), openAccount(), openSettings() |
| `ui/pages/VersionPage.qml` | 版本管理：左列版本列表 + 右侧详情，可开版本设置 | refreshLocal(), openSettings, importModpack |
| `ui/pages/VersionSettingsPage.qml` | 版本设置全屏页：按版本能力过滤左栏，装载分区页 | reloadPanes(), ensureKeyVisible(), goTo() |
| `ui/pages/VsExportPane.qml` | 版本设置·导出整合包：内容树勾选 + 输出路径/格式 | export(), listMods(), quickDirs() |
| `ui/pages/VsLaunchPane.qml` | 版本设置·启动配置：Java/GC/优先级/参数/命令的版本级覆盖 | switchMode(), load(), setVersionJvmArgs() |
| `ui/pages/VsMemoryPane.qml` | 版本设置·内存：跟随全局/自动/自定义三档 + 系统内存条 | setMode(), versionMemoryMode(), resolvedMemoryMB() |
| `ui/pages/VsModsPane.qml` | 版本设置·Mod 管理：搜索、启停、批量、导入、虚拟列表 | reload(), bulk(), setModEnabled() |
| `ui/pages/VsOverviewPane.qml` | 版本设置·概览：加载器/游戏版本/内容计数 kv 单列 | refreshCounts(), requestPane() |
| `ui/pages/VsPacksPane.qml` | 版本设置·资源包：搜索、导入、删除（二次确认） | reload(), importResourcePack(), deleteResourcePack() |
| `ui/pages/VsPlaceholderPane.qml` | 版本设置分区占位：尚未施工的分区只显示「待施工」 | title, versionId |
| `ui/pages/VsQuickPane.qml` | 版本设置·快捷入口：打开各目录/日志、复制路径、导出脚本 | openDir(), copyText(), exportLaunchScript() |
| `ui/pages/VsSavesPane.qml` | 版本设置·存档：搜索、大小显示、删除（二次确认） | reload(), deleteSave() |
| `ui/pages/VsShadersPane.qml` | 版本设置·光影：改名启停、导入、删除，解包态只列出 | reload(), setShaderPackEnabled(), importShaderPack() |
| `ui/pages/VsToolsPane.qml` | 版本设置·工具与维护：校验/修复、克隆、重命名、删除版本 | verifyVersion(), repairVersion(), requestClose() |

## 十一、QML 控件（`ui/controls/`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `ui/controls/ResourceTile.qml` | 资源库网格卡片 | fmtDl, hovered |
| `ui/controls/SAcctChip.qml` | 账户胶囊（头像/名字/状态） | skinSource, status |
| `ui/controls/SBgImage.qml` | 背景图取景、缩放与拖动交互 | source, zoom, cropX |
| `ui/controls/SButton.qml` | 按钮（主/描边/危险/灰态） | kind, danger |
| `ui/controls/SCard.qml` | 设置卡片容器 | title, cardPaddingTop |
| `ui/controls/SDropZone.qml` | 全局拖入接收与提示遮罩 | dropped, accept, forceShow |
| `ui/controls/SField.qml` | 浮动标签搜索框 | text, edited, blur |
| `ui/controls/SIcon.qml` | Lucide SVG 图标着色 | name, color |
| `ui/controls/SInput.qml` | 单行输入框 | text, edited |
| `ui/controls/SPlaceholder.qml` | 输入框占位文字（空态显示，输入法组字时隐藏） | target, label |
| `ui/controls/SLoadingBar.qml` | 顶部不确定进度条 | running |
| `ui/controls/SMinecraftHead.qml` | 方形 MC 头像（头图/皮肤兜底） | source, rawSource |
| `ui/controls/SRipple.qml` | 点击涟漪 | burst |
| `ui/controls/SRow.qml` | 横向设置行 | label, rowHeight |
| `ui/controls/SSegmented.qml` | 等宽分段控件 | items, currentIndex, activated |
| `ui/controls/SSelect.qml` | 下拉选择 | items, currentIndex, activated |
| `ui/controls/SShimmer.qml` | 高光扫过层 | phase, bandWidth |
| `ui/controls/SSlider.qml` | 滑块 | value, moved |
| `ui/controls/SStaggerItem.qml` | 列表逐条入场容器 | index, play |
| `ui/controls/SSwitch.qml` | 开关 | checked, toggled |
| `ui/controls/STextArea.qml` | 多行文本输入 | text, edited |
| `ui/controls/SWindowButton.qml` | 窗口最小化/关闭按钮 | iconName, danger |
| `ui/controls/SetGroup.qml` | 设置分组（标题+卡片） | title, bare |
| `ui/controls/SetNote.qml` | 三段语义提示条 | kind, text |
| `ui/controls/SetRow.qml` | 横向设置行（自适应高） | label, desc |
| `ui/controls/SetStack.qml` | 纵向设置块 | label, desc |

## 十二、测试（`tests/`）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `tests/cf_test_vectors.h` | CF 密钥互操作固定测试向量 | TEST_EXPECT |
| `tests/diag_image.cpp` | WebP 解码能力诊断工具 | main |
| `tests/java_dl_test.cpp` | Java JDK 下载测速（TUNA 镜像） | main |
| `tests/test_appearance_controller.cpp` | 外观控制器令牌与持久化测试 | main |
| `tests/test_asset_completion.cpp` | 同 SHA1 预检查完成回归测试 | main |
| `tests/test_asset_watchdog.cpp` | in-flight 挂起看门狗回归测试 | main |
| `tests/test_cf_api.cpp` | CF 分类/搜索/文件转换自测 | main |
| `tests/test_cf_crypto_interop.cpp` | CF 密钥 Python 向量互操作测试 | main |
| `tests/test_export.cpp` | 整合包导出结构与自识别测试 | main |
| `tests/test_fd.cpp` | 夸父单文件下载测试 | main |
| `tests/test_forge147.cpp` | Forge 1.4.7 旧版安装集成测试 | main |
| `tests/test_game_folder.cpp` | 游戏文件夹注册表后端测试 | main |
| `tests/test_isogd.cpp` | 版本游戏目录布局感知测试 | main |
| `tests/test_java_autoinstall.cpp` | Java 自动安装异步流程测试 | main |
| `tests/test_java_cancel.cpp` | Java 自动安装取消与清理测试 | main |
| `tests/test_java_rules.cpp` | MC 版本到 Java 需求规则快照 | main |
| `tests/test_java_scan.cpp` | 系统 Java 扫描（含 MC runtime）测试 | main |
| `tests/test_jingwei_retry.cpp` | 精卫补位重试回归测试 | testEngineRetry, testTaskLayerRetryVisibility |
| `tests/test_launch_detail.cpp` | 启动参数细节（GC/全屏/进服/JVM）测试 | main |
| `tests/test_minecraft_layout.cpp` | 外部 .minecraft 布局识别测试 | probeMinecraftFolder, resolveVersionGameDir |
| `tests/test_modpack.cpp` | 整合包模块离线与在线自测 | runOfflineTests, runOnlineTests |
| `tests/test_resource_fetch_engine.cpp` | 司南资源拉取缓存与图标测试 | main |
| `tests/test_slf4j_dedup.cpp` | NeoForge slf4j 绑定去重测试 | main |
| `tests/test_slf4j_real.cpp` | 真实 NeoForge JSON slf4j 去重验证 | main |
| `tests/test_toggle_script.cpp` | Mod 启停与启动脚本生成测试 | main |
| `tests/test_yidao.cpp` | 驿道分片下载集成测试 | main |
| `tests/test_yidao147.cpp` | 驿道下载 1.4.7 universal.zip 校验 | main |
| `tests/test_zip_helper.cpp` | miniz 测试 ZIP 构造辅助 | buildTestZip |
## 十三、常用开发/调试开关

开关全部由 `src/main_release.cpp` 或 QML 侧读 `Qt.application.arguments` 实现；下表只列实测用过、确认有效的。

| 开关 | 作用 |
|---|---|
| `--ui-prefs --ui-pane <名称>` | 直接打开设置页的某个分页（如 `appearance`），做内存/渲染测量用 |
| `--ui-size 1280x720` | 强制窗口尺寸 |
| `--verify-test <版本ID>` | 校验指定版本，结果写 `build/Release/verify_test_result.txt` 后自动退出 |
| `--repair-test <版本ID>` | 先校验、失败自动进修复，验证「校验→修复」闭环 |
| `--ui-screenshots` | 启动内置截图服务（仅绑 `127.0.0.1`，默认不开） |
| `--screenshot` | 截图模式：关掉外观设置的持久化，不污染用户配置 |
| `--no-intro` | 跳过启动动画 |
| `--ui-update-card` | 直接预览更新卡片窗（与真实安装卡片同形态） |
| `--ui-gate` | 直接进首次启动协议门 |
| `--update-check` | 启动即触发一次更新检查 |

离屏测量（无窗口、可量内存）需要把 Qt 的 `qoffscreen.dll` 放进部署目录的 `platforms/`，再设 `QT_QPA_PLATFORM=offscreen`；否则进程会静默退出、量到的是空壳。
