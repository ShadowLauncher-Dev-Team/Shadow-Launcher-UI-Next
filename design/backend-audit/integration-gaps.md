# C++ 后端接入清点报告（新 UI vs 后端 API）

> 生成时间：2026-11-10 · 方法：脚本提取所有 `Q_PROPERTY`/`Q_INVOKABLE` 名称，在新 UI（`ui/**/*.qml`）全文做词边界匹配，零命中即为「未接入」。
> 结论口径：**未接入 ≠ 该删**。下面逐项给判定。

## 总览

| 后端类 | API 总数 | 新 UI 零引用 | 说明 |
|---|---|---|---|
| ShadowBackend | 121 属性 + 247 方法 | **41 + 124** | 主门面，问题最集中 |
| SettingsBackend | 97 | 24 | 全局/版本设置 |
| VersionBackend | 55 | 34 | 安装卡片体系大量未用 |
| ResourceBackend | 43 | 25 | 旧搜索接口已被 *Ex 取代 |
| JavaBackend | 39 | 18 | 安装器细节字段 |
| LaunchBackend | 37 | 16 | 内部检查函数 |
| AccountBackend | 32 | 13 | 皮肤/衣橱缺失 |
| YggdrasilBackend | 32 | 23 | 外置登录细节 |
| **UiNextPresenter（UiNext 单例）** | **49** | **32（实际 49/49 全未用）** | **整个桥接层零引用** |
| MinecraftFolderBackend | 30 | 22 | 文件夹管理大部分未接 |
| MultiplayerManager | 25 | 9 | 联机细节 |
| ModpackImporter | 18 | 13 | 导入流程细节 |
| AppearanceController（Appearance 单例） | 12 | 10 | 外观页未做 |
| UserDataBackend | 9 | 7 | 数据导入未接 |
| ModpackExporter | 12 | 2 | 基本齐全 |

---

# A. 必须重新接入（真实功能缺失，用户可感知）

| # | 缺失能力 | 后端 API | 现状与证据 | 判定 |
|---|---|---|---|---|
| A1 | **首次启动协议/内测门禁** | `agreementAccepted` `markAgreed` `betaAgreementHtml` `privacyAgreementHtml` `termsAgreementHtml` `betaGateEnabled` `betaStatus` `submitBetaKey` | 旧 UI `MainWindow.qml:1433` 有 `active: !backend.agreementAccepted` 强制弹 `AgreementOverlay`；**新 UI 完全没有**。用户装完直接进主界面，从未同意协议 | **必须接**（合规缺口）。要么补协议页，要么**明确决定放弃协议门禁并从后端移除** |
| A2 | **皮肤与披风编辑** | `browseSkin` `uploadSkin` `saveWardrobeSettings` `saveSkinToFile` `selectCape` `skinVariant` `capes` `capePath` `selectedSkinPath` `wardrobeBusy` `updateOfflineSkin` | 账户页只显示头像（`SAcctChip` 读 `skinPath`/`offlineSkinPath`），**没有任何编辑/上传/换披风入口**。后端整套衣柜逻辑空转 | **建议接**（账号页核心体验）。若决定不做，则这 11 个 API 连后端一起删 |
| A3 | **版本级进程优先级** | `versionProcessPriority` `versionProcessPriorityMode` `setVersionProcessPriority` `setVersionProcessPriorityMode` | 后端今天刚补齐（commit ff24ae4），`VsLaunchPane` 还没有这一行 | **必须接**（后端做了没 UI = 假功能），加一行即可 |
| A4 | **光影文件夹入口** | `openShaderPacksFolder` | 版本工具页有 Mod/资源包/存档/截图文件夹，**独缺光影** | **建议接**（一行按钮） |
| A5 | **版本配置文件夹** | `openConfigFolder` | 同上，`VsToolsPane` 无此入口 | **建议接** |
| A6 | **崩溃手动分析** | `analyzeCrashNow` `cleanupCrashArtifacts` | `LaunchOverlay` 只被动显示 `lastCrash`/`crashAnalyzing`，没有「立即分析」按钮；崩溃残留也没清理入口 | 接 `analyzeCrashNow`；`cleanupCrashArtifacts` 可随分析一起调用 |
| A7 | **手动检查文件变更** | `checkFileChanges` | 与 `verifyVersion` 功能重叠，需确认是否已被替代 | **待核**（若重复则删） |

---

# B. 应删除（死代码 / 已被取代 / 产品决策已废弃）

## B1. UiNextPresenter 整个桥接层（49 项全部未用）

**证据**：`ui/` 里搜 `UiNext|uiNext` **零命中**。它被 `main_release.cpp:663` 注册为 QML 单例并 `initialize(backend)`，但新 UI 从头到尾没引用过。

**判定：整层删除**（包括 `ui_next_presenter.{h,cpp}`、`appearance_controller` 的定位需一并重议、main_release 里的初始化与 `--ui-next-*` 参数处理）。

唯一例外：`appearance_controller` 被 `main_release` 用来处理 `--ui-next-mode/density` 截图参数，且外观页未来要用 —— **暂留，等外观页定**。

## B2. 已被产品决策废弃

| API | 理由 |
|---|---|
| `logout`（AccountBackend） | `AccountPage.qml:775` 注释明确：用户要求「退出登录」与「移除此账号」合并，只保留后者 |

## B3. 被新接口取代（旧版仍留着）

| 旧 API | 新 API | 位置 |
|---|---|---|
| `searchMods` `getPopularMods` `getShaderList` `getModCategories` `cfCategories` | `searchModsEx` `searchShadersEx` `searchResourcepacks` `searchModpacksEx` `searchDatapacksEx` | ResourceBackend |
| `downloadMod` `downloadShader` `downloadResourcepack` `downloadModpack` | `downloadModFile` + 详情页流程 | ResourceBackend |
| `fetchCfDependencies` `resolveCfDependencies` `resolveModZh` `resolveProjectLinks` | `fetchVersionDependencies` `resolveIconUrl` | ResourceBackend |
| `cacheIconAsync` `cachedIconPath` `cacheIconBatchAsync` `cacheShaderIconBatchAsync` `cacheRpIconBatchAsync` `resolveShaderIconUrl` `resolveRpIconUrl` | `resolveIconUrl` `cacheIconBatchAsync`（统一后） | ShadowBackend/ResourceBackend |
| `prefetchModsEx` `prefetchShadersEx` `prefetchResourcepacks` `prefetchModpacks` `prefetchDatapacks` | 搜索即预取，无需显式预热 | ResourceBackend |
| `listMods` `listResourcePacks` `listSaves`（同步版） | `listModsAsync` `listResourcePacksAsync` `listSavesAsync` | ShadowBackend |
| `updateTaskCard` `addTaskCard` `addResourceCard` `updateResourceCard` `completeResourceCard` `failResourceCard` `removeTaskCard` `removeResourceCard` `dismissAllCompleted` `cardData` `generation` | `installCardsModel`（ProgressPage 用的） | VersionBackend |
| `resourceDownloadProgress` `resourceDownloadTotal` `resourceDownloadSpeed` `resourceDownloadFile` `activeDownloads` `downloadQueue` | 进度页改用 `installCardsModel` | ShadowBackend |

## B4. 调试/自检专用（生产不需要）

`downloadSelfcheck` `downloadSourceSummary` `downloadProbe` `downloadProbeCancel` `downloadProbeCancelLeak` `downloadProbeMulti` `cacheForgeInstallerSha1` `diagAutoLangComboIdx` `logUiMsg` `readUiFlag` `writeUiFlag` `consumeJustUpdatedFlag` `readLanguageFile` `switchLanguage`

**判定**：要么建一个隐藏诊断页承接，要么删除。**倾向删除**（当前无人调用，属于历史调试残留）。注意 `setLanguageIndex` 已覆盖语言切换，`switchLanguage/readLanguageFile` 是旧实现。

## B5. 内部函数误标 Q_INVOKABLE

`resolvedGcMode` `resolvedAutoJoinServer` `resolvedFullscreen` `resolvedWindowTitle` `resolvedPreLaunchCommand` `resolvedPostExitCommand` `resolvedJvmArgs` `resolvedGameArgs` `resolvedHighPerfGpu`

**判定**：去掉 `Q_INVOKABLE`，降为普通成员函数（它们只在 C++ 内部合并全局/版本值时调用）。

## B6. QML 直接赋值属性的冗余 setter

`setJvmArgs` `setGameArgs` `setHighPerfGpu` `setMaxDownloadThreads`（QML 用 `.maxDownloadThreads = x` 或专用调用）

**判定**：删除方法，保留 Q_PROPERTY 的 WRITE。

## B7. 版本安装器内部字段（QML 读不到也不需要）

VersionBackend 的 `activeCount` `activeInstallId` `installedIds` `installPhase` `installVersionId` `installing` `installProgressOf` `installSpeedOf` `isModLoaderInstalling` `cleanupOrphanTempDirsIfIdle` `ensureSelectedVersionValid` `setGameDir` `cancelQueuedDownload` `setPendingUserDataImport` `cancelPendingUserDataImport`

**判定**：`setGameDir`/`ensureSelectedVersionValid`/`cleanupOrphanTempDirsIfIdle` 是内部调用（去掉 Q_INVOKABLE）；其余随 B3 一并清理。

---

# C. 待接入（外观页占位，暂不判定）

`sidebarOpacity` `contentOpacity` `backgroundBlur` `cropX` `cropY` + `setSidebarOpacity` `setContentOpacity` `setBackgroundBlur` `setCropX` `setCropY` `updateCrop` `pickBackgroundImage` `setCustomBgPath` `setTheme`

**理由**：外观页目前是占位页（后端三套未合并：`Theme.qml` 硬编码 / `Appearance` 单例 / `SettingsBackend.customBg`）。**等外观页动工时统一处理**，现在删了会白做。

---

# D. 需要影决策

1. **协议门禁（A1）**：恢复（做协议页）还是放弃（连后端一起删）？
2. **皮肤/披风编辑（A2）**：做还是不做？
3. **UiNextPresenter（B1）**：确认整层删除？（49 项零引用）
4. **调试钩子（B4）**：删掉还是保留一个隐藏诊断页？

---

# 附：完整未接入清单（供核对）

## ShadowBackend 未接入属性（41）

activeDownloads, activeVersionNames, agreementAccepted, availableCapes, backgroundBlur, betaAgreementHtml, betaGateEnabled, betaStatus, contentOpacity, cropX, cropY, currentVersionSummary, dataDir, devMode, downloadQueue, installing, installPhase, installVersionId, isolationEnabled, isScanningVersions, javaInstalled, launchPipeline, launchUsername, launchVersion, loginType, markAgreed, modManager, modpackImporter, privacyAgreementHtml, repairRunning, resourceDownloadFile, resourceDownloadProgress, resourceDownloadSpeed, resourceDownloadTotal, selectedSkinPath, sidebarOpacity, systemMemoryInfo, termsAgreementHtml, updateState, versionIds, wardrobeBusy

## ShadowBackend 未接入方法（124）

analyzeCrashNow, autoSelectJava, availableCapes, browseSkin, cachedIconPath, cacheForgeInstallerSha1, cacheIconAsync, cacheIconBatchAsync, cacheRpIconBatchAsync, cacheShaderIconBatchAsync, cancelModFileDownload, cancelModLoaderQueries, cancelPendingUserDataImport, cancelQueuedDownload, cfCategories, checkAll, checkFileChanges, cleanCorruptVersion, cleanupCrashArtifacts, consumeJustUpdatedFlag, deleteMod, demoLaunchFailure, demoLaunchRepairs, detectJava, diagAutoLangComboIdx, dismissCard, downloadMod, downloadModpack, downloadProbe, downloadProbeCancel, downloadProbeCancelLeak, downloadProbeMulti, downloadResourcepack, downloadSelfcheck, downloadShader, downloadSourceSummary, fetchCfDependencies, getAutoMemory, getModCategories, getPopularMods, getShaderList, installOptifineJar, isModdedVersion, isOfflineRestricted, killMinecraft, listResourcePacks, loginType, logout, logUiMsg, migrateVersion, migrateVersionToIsolated, modpackBusy, openConfigFolder, openJavaFileDialog, openPath, openShaderPacksFolder, openVerifyReport, pauseModFileDownload, pickBackgroundImage, pickJava, prefetchDatapacks, prefetchModpacks, prefetchModsEx, prefetchResourcepacks, prefetchShadersEx, quitForUpdate, readLanguageFile, readUiFlag, refreshInstalledList, removeOfflineUsername, resolveCfDependencies, resolvedAutoJoinServer, resolvedFullscreen, resolvedGameArgs, resolvedGcMode, resolvedHighPerfGpu, resolvedJvmArgs, resolvedPostExitCommand, resolvedPreLaunchCommand, resolvedWindowTitle, resolveModZh, resolveProjectLinks, resolveRpIconUrl, resolveShaderIconUrl, resumeModFileDownload, retryModFileDownload, saveSkinToFile, saveWardrobeSettings, searchMods, setAutoJoinServer, setAutoLangModeFromCombo, setBackgroundBlur, setContentOpacity, setCropX, setCropY, setCustomBgPath, setEmbeddedLoginEnabled, setFullscreenEnabled, setGameArgs, setHighPerfGpu, setIsolationEnabled, setJvmArgs, setPendingUserDataImport, setPostExitCommand, setPreLaunchCommand, setSidebarOpacity, setTheme, setVersionProcessPriority, setVersionProcessPriorityMode, setWindowTitleOverride, stopDemo, submitBetaKey, switchLanguage, updateCrop, updateOfflineSkin, uploadSkin, versionFullscreenMode, versionHighPerfGpuMode, versionPostExitMode, versionPreLaunchMode, versionProcessPriority, versionProcessPriorityMode, versionWindowTitleMode, writeUiFlag
