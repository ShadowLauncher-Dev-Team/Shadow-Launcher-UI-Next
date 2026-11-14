# C++ 后端审计：未接入 UI 与多余过时代码

> 生成：2026-11-14 · 方法：脚本提取 14 个 backend 头文件的全部 `Q_INVOKABLE` / `Q_PROPERTY`（共 744 个成员），
> 与 `ui/**/*.qml` + `tests/**` 做词边界匹配，并扣除定义行本身；再用 grep 逐条人工核实调用点。
> 口径：**未接入 ≠ 该删**。A 类可删，B 类该接 UI，C 类必须保留。

## 总览

| 类别 | 数量 | 处置 |
|---|---|---|
| 确定死码（QML、C++、tests 三处皆零引用） | **32** | 可直接删 |
| 重复实现（新接口已取代，旧接口仍留） | **约 30** | 删旧留新 |
| 死文件（不参与编译） | **2** | 直接删 |
| QML 零引用但 C++ 内部在用 | 238 | 逐条判定 |
| 其中：应「接 UI」的功能缺口 | **约 12 组** | 需影决策 |

---

# A. 确定死码（可直接删除）

## A1. 只声明未实现 / 实现后无人调用

| 文件 | 成员 | 证据 |
|---|---|---|
| app_backend.h | `resolvePath` `setDevMode` `appName` | QML/C++/tests 全零 |
| minecraft_folder_backend.h | `applyAsGameDir` | **头文件有声明，.cpp 里根本没有实现体** |
| minecraft_folder_backend.h | `versionHasJson` `versionInfos` `versionJarPath` `applyAsGameDir` | 全零，已被 `result()` / `setActiveFolder()` 取代 |
| minecraft_folder_backend.h | `currentDir` `foreignActive` `layoutId` | 全零（`layoutName` 另有在用） |
| userdata_backend.h | `executeImport` `validateArchive` `setPendingImport` `cancelPendingImport` `pendingArchivePath` `pendingItems` | 全零，**且 ShadowBackend 门面未转发** |

`UserDataBackend` 的**导出**在用（`VsToolsPane.qml:440`），**导入**整套从未接入选。

## A2. 被取代后遗留的进度属性

| 文件 | 成员 | 被谁取代 |
|---|---|---|
| java_backend.h | `javaInstalling` `javaInstallStep` `javaInstallTotal` `javaInstallStatus` `javaDownloadBytes` `javaDownloadTotal` `javaDownloadPercent` `fetching` | UI 实际用 `installingMajor` + `installStatusText`（JavaPage.qml:239-240） |
| resource_backend.h | `dlFile` `dlProgress` `dlTotal` | 进度页改用 `installCardsModel` |
| shadow_backend.h | `resourceDownloadFile/Speed/Total/Progress` `activeDownloads` `downloadQueue` | 同上 |
| shadow_backend.h | `betaStatus` | 无任何 UI 消费 |
| shadow_backend.h | `currentVersionSummary` `launchUsername` `markAgreed` | 全零 |
| version_backend.h | `activeInstallId` | 全零 |

## A3. 死文件（不参与编译）

| 文件 | 行数 | 证据 |
|---|---|---|
| `src/core/cef_login_app.cpp/.h` | 9 | CEF 已整体移除，CMakeLists 无任何 cef 引用；`#include "include/cef_app.h"` 现在根本编不过 |
| `src/core/update_checker.cpp/.h` | 128 | 被 `src/core/update_manager.cpp` 完全取代，无人 include |

---

# B. 重复实现（删旧留新）

| 旧接口 | 新接口 | 证据 |
|---|---|---|
| `searchMods` `getPopularMods` `getShaderList` `getModCategories` `cfCategories` | `searchModsEx` / `searchShadersEx` / `searchModpacksEx` | QML 旧接口 0 引用、新接口 3 处。**源码注释自承**：`resource_backend.cpp:2472`「仅 searchMods（非 Ex，QML 已不使用）」 |
| `addResourceCard` `updateResourceCard` `completeResourceCard` `failResourceCard` `dismissAllCompleted` | `installCardsModel` | QML 旧接口 0 引用 |
| `prefetchModsEx` `prefetchShadersEx` `prefetchResourcepacks` `prefetchModpacks` `prefetchDatapacks` | 搜索即预取 | QML 零引用，C++ 仅门面转发空转 |

---

# C. 功能已实现但 UI 未接（需影决策）

| # | 功能 | 后端 API | 现状 | 建议 |
|---|---|---|---|---|
| C1 | **协议 / 内测门禁** | `agreementAccepted` `markAgreed` `betaAgreementHtml` `privacyAgreementHtml` `termsAgreementHtml` `betaGateEnabled` `betaStatus` `submitBetaKey` | QML 全部零引用。旧 UI 有 `AgreementOverlay` 强制弹出，**新 UI 完全没有**——用户装完直接进主界面，从未同意协议 | **合规缺口，必须决策**：补协议页，或明确放弃并连后端一起删 |
| C2 | **Java 安装进度显示** | `javaInstallStep` `javaInstallTotal` 等 | `JavaPage` 只显示一行状态文字，无进度条/步骤 | 接进度条，或删掉多余属性只管状态文字 |
| C3 | **崩溃手动分析** | `analyzeCrashNow` `cleanupCrashArtifacts` | `LaunchOverlay` 只被动显示，无「立即分析」入口 | 接按钮 |
| C4 | **用户数据导入** | `executeImport` `validateArchive` 等 | 导出已接，导入未接 | 接导入，或删导入整套 |
| C5 | **版本级进程优先级** | `versionProcessPriority` `setVersionProcessPriority` | 后端完整，`VsLaunchPane` 无此行 | 加一行 |
| C6 | **光影 / 配置文件夹** | `openShaderPacksFolder` `openConfigFolder` | `VsToolsPane` 有 Mod/资源包/存档/截图，独缺这两个 | 各加一行按钮 |
| C6b | **文件夹改名/移除** | `renameGameFolder` `removeGameFolder` | 用户**能添加文件夹但不能改名或移除**（`VersionPage.qml:187` 只调 `addGameFolder`）。后端实现完整（含固有文件夹保护、活动目录回退），属功能半成品 | **建议接 UI**：文件夹菜单加「重命名 / 移除」 |
| C7 | **外观页** | `sidebarOpacity` `contentOpacity` `backgroundBlur` `cropX/Y` `pickBackgroundImage` | 外观页仍是占位 | **等外观页动工再统一处理**，现在别删 |

---

# D. 必须保留（改了会出事）

以下 QML 零引用，但 C++ 内部真实调用，**只是不该暴露给 QML**，应去掉 `Q_INVOKABLE` 而非删除：

- `LaunchBackend::checkJavaArchitecture / checkVersionHasNodes / checkVersionLibraries / checkVersionMissingNatives` —— 启动管线内部调用
- `VersionBackend::setGameDir / ensureSelectedVersionValid / cleanupOrphanTempDirsIfIdle / cardDataAt / cardData` —— 内部驱动卡片模型
- `SettingsBackend::resolved*` 系列 —— 全局/版本值合并，纯内部
- `MinecraftFolderBackend::probe / result / versionGameDir / versionJsonPath` —— 被门面大量调用（ext=41 / 273 / 10 / 7）
- `installCardsModel` 相关（`AddResourceCard` 除外，见 B）—— ProgressPage 的实际数据源

# E. 调试钩子（生产不需要，但别现在删）

`demoLaunch` `stopDemo` `demoRepairs` `demoFailure` `demoPrecheckFail` —— 由 `--ui-demo-*` 驱动，
是**唯一能在不启动游戏的前提下核对浮层 UI 的手段**（`tools/overlay-demo.ps1` 依赖它）。
建议编译期用 `#ifndef NDEBUG` 包起来，而不是删除。
