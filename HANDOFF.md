# 交接文档 — Shadow Launcher v2 UI 重写

> 更新时间：2026-11-04 17:40（上一版 16:57）
> 仓库：`D:\latest-code\shadow-v2`（git，main）
> 设计稿源：`D:\latest-code\cpp\design-2026-11-04\`（网页原型，不在本仓库 git 里；仓库内 `design/` 是迁移时的一份拷贝）

---

## 0. 一句话现状

**启动浮层全链路跑通**：总进度 + 节点清单按后端真实管线的节点数和顺序渲染，失败态常驻并给出具体原因，取消干净退回，800×550 装得下。**当前不需要修 bug，下一步是往下铺页面。**

---

## 1. 用户已拍板的设计决策（**不要再推翻**）

| 项 | 决定 |
|---|---|
| 启动进度位置 | **主界面中央浮层**（不是独立小窗口，不是页面内角落） |
| 浮层内容 | **两部分：总进度条（上）+ 启动进度节点清单（下，竖排，随进度推进）** |
| 节点数量 | **必须遵循后端实际**，不许写死；离线账户跳过"检查登录状态"→ 5 个节点，正版/外置 6 个 |
| 形状 | 面板 2px（视觉直角）；**内部一律直角，禁止嵌套圆角**；节点用 8×8 直角方点，不用圆点 |
| 取消 | 右下角，唯一出口；**不用红色**（取消不是危险动作）；不做右上角 × |
| 遮罩 | 启动中点击遮罩**不关闭** |
| 总进度 | 阶段级（已完成节点/可见节点），**不许编造字节百分比**；字节进度放节点子行 |
| 首屏判据 | 一个元素能留，唯一理由是**它能改变用户下一步动作**；说不出就删 |

三版布局比选已做过：选 **A 上下结构**（总进度条在上 + 节点清单在下）。B（左右分栏，进度表达两遍）和 C（时间轴，把总进度条换成竖线）已被否。

---

## 2. 构建与运行

```powershell
cd D:\latest-code\shadow-v2
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --parallel
```

| 用途 | 命令 |
|---|---|
| 旧 UI（兜底） | `build\Release\ShadowLauncher.exe` |
| **新 UI** | `build\Release\ShadowLauncher.exe --ui-next` |
| 尺寸预览 | `--ui-size 800x550` |
| **启动浮层演示（安全，不碰游戏）** | `launch-ui-demo.bat` 或 `pwsh tools/overlay-demo.ps1 -Mode online -Out shot.png` |
| 演示变体 | `-Mode fail`（失败态）、`-Mode online-fail`（6 节点失败）、`-Size 800x550` |
| 浮层读数（开发用） | 加 `--ui-overlay-debug`，屏幕左下角出现 DBG 行 |

⚠️ 编译前若 exe 被占用（LNK1104），先 `Get-Process ShadowLauncher | Stop-Process -Force`。

---

## 3. 已完成

### 3.1 新 UI（`ui/`，QML 模块 URI `ShadowLauncher.Next`）
- `Main.qml` — 无边框透明窗，1100×720，最小 800×550，支持 `--ui-size`
- `Theme.qml` — 设计令牌单例
- `StageShell.qml` — 侧栏 + 内容区 + **LaunchOverlay 挂载点**
- `SideBar.qml` — 导航（按 `currentLabel` 选中，窄窗收成 64px 图标条）
- `pages/StagePage.qml` — 启动页：极光全幅 + 版本标题 + 启动按钮
- `controls/` — `SIcon`(lucide SVG + MultiEffect 着色) / `SButton`(新增 `radius`/`danger` 覆盖) / `SWindowButton` / `SAcctChip`
- `LaunchOverlay.qml` — **启动浮层，已跑通**
- `assets/stage-aurora.jpg` — 内置背景（CMake 用 `BASE` 注册为 `qrc:/ui/stage-aurora.jpg`）

### 3.2 后端：启动流程接入 StepPipeline

| 文件 | 关键点 |
|---|---|
| `src/core/step_pipeline.h/.cpp` | `DetailRole`；`appendStep()` 里把节点 statusChanged/progressChanged/detailChanged/hiddenChanged 转成单行 `dataChanged` |
| `src/backend/launch_backend.h/.cpp` | `buildLaunchPipeline()`（顺序与 `runNextCheck()` 的 case 0..5 一一对应）/ `syncPipelineStep()` / `completePipeline()` / `failPipelineStep()`；**新增浮层属性**：`launchStepRows`(QVariantList) / `launchFailed` / `launchFailReason` / `launchFinishedOk`；**新增演示入口**：`demoLaunch(mode)` / `stopDemo()` |
| `src/backend/shadow_backend.h/.cpp` | 以上属性与 `demoLaunch`/`stopDemo` 全部转发，QML 只认 `backend` 一个入口 |

节点顺序（必须与 `runNextCheck()` 的 case 一一对应）：
```
case 0 检查登录状态 / 1 检查 Java 环境 / 2 检查版本文件 / 3 检查依赖文件 / 4 检查内存分配 / 5 启动游戏进程
```
离线账户（`!m_authIsOnline && !m_yggdrasilMode`）时 login 节点 `setSkipped()+setHidden(true)`，浮层只画可见节点 = 5 个。

节点内子状态通过 `connect(this, &LaunchBackend::launchCheckProgress, ...)` 写入当前节点 detail，**不需要改任何 emit 站点**。

### 3.3 工程护栏
- `tools/check-ui-contract.ps1` + CMake 目标 `UiContractCheck`（构建期硬失败）：禁止 appVersion 加前缀、禁止 emoji 图标、禁止 SpringAnimation、`font.pixelSize` 必须整数、警惕 `layer.enabled`+`MultiEffect`
- `tools/capture.ps1` — 抓窗口截图（`SetProcessDPIAware` + `PrintWindow(...,2)`）
- **`tools/overlay-demo.ps1`** — 浮层探针（**替代已删除的 overlay-probe.ps1 / launch-test.ps1**）：起 demo 态 → 用应用自带 ScreenshotServer 的 `GET /screenshot` 抓图 / `POST /eval` 执行 QML 表达式（例如 `backend.cancelLaunch()`）→ 杀进程。**全程不点"启动"，不可能误启动游戏。**

### 3.4 commit 记录
```
a9b9934 chore: 从 cpp/ 迁移 C++ 后端，UI 重写起点
14c5bbe feat(ui): 新 UI 垂直切片——启动页按 DESIGN_SPEC v2 落地
6325472 fix(ui): 版本号重复 v；新增构建期 UI 契约检查
ffa8f16 test(ui): 验收 Gate1 -- hover 变红 / 800x550 / 启动态三阶段
3718b53 revert(ui): 撤回按长度自适应标题字号
ee2682a feat(launch-overlay): 启动阶段管线接入后端 StepPipeline；新增中央启动浮层
（本次）fix(launch-overlay): 节点清单渲染、失败态、阶段级总进度、安全演示态
```

---

## 4. 曾经的最大阻塞：节点清单渲染为空（0 行）——已解决，结论记在这里

**现象**：浮层正常弹出，标题/步数/17% 都对，但节点清单一行都没有，面板里一段空白。

**排查掉了两件事（都别再走一遍）**：
1. **不要指望把 `StepModel`（QAbstractItemModel）通过 `Q_PROPERTY(QObject* model)` 喂给 QML 的 Repeater/ListView`model:`**。这条路径在本工程里从来没真正跑通过——版本下载卡片一直是用 `buildPipelineSteps()` 手工构建 `QVariantList` 的。浮层现在走同一套已验证的模式：后端出 `QVariantList launchStepRows`（`{key,name,detail,status,isLast}`，只含可见节点），QML 只吃这个数组。
2. **不要在 `Column` 里放 `Repeater` 来渲染节点**。Repeater 的委托是被塞进父 Column 的 `children` 里的；模型整体替换时重建的委托会改变子项顺序 → 底部元素跑到面板顶部（实测踩过）。现在节点列表是一个 `ListView`（`height` 由 QML 侧按行规则算好的 `rowsHeight()` 给定，不用 `contentHeight`，避免面板高度慢一拍）。

**顺带修掉的两个真问题**：
- 总进度原先用 `weightedProgress()`，把节点内字节百分比混进总进度（等于"编造百分比"，违反契约第 3 节）。现在 = 已完成可见节点 / 可见节点总数。
- 失败时 `abortCheck` 会把 `m_launching` 置 false，浮层本来会连错误原因一起藏掉。现在可见性判 `launching || launchFailed || launchFinishedOk`，失败态常驻；`failPipelineStep()` 同时把原因写进节点子行。

---

## 5. 踩过的坑（务必先看，能省几小时）

| 坑 | 现象 | 正解 |
|---|---|---|
| `font.pixelSize` 是 **int** | 写 13.5/12.5 报 `Invalid property assignment: int expected`，**整页不渲染** | 只用整数 |
| `qt6_add_resources` 不给 `BASE` | alias 会带上源相对路径（`qrc:/ui/ui/assets/x.jpg`），图加载失败 | `BASE "ui/assets"` |
| 透明窗口 + 图加载失败 | 直接透出桌面，看着像"没渲染" | 页面底层放不透明底色兜底 |
| `.ps1` 无 BOM | PowerShell 5.1 按 GBK 读，中文乱码 + `Unexpected token` | 存 UTF-8 **带 BOM** |
| 外部 `SetWindowPos` 调 Qt 无边框窗 | 高度变成 65535 | 让程序自己读 `--ui-size` 改尺寸 |
| PowerShell 抓 Qt 窗口 | 非 DPI 感知时拿到逻辑坐标；被遮挡只抓到别的窗口 | `SetProcessDPIAware()` + `PrintWindow(hwnd, hdc, 2)`，或直接用应用自带 ScreenshotServer |
| **鼠标模拟点 Qt 窗口** | 无人值守环境下 `SetForegroundWindow` 静默失败、`SendMessage(WM_LBUTTON*)` 到 Qt 不生效，点不动还以为按钮坏了 | 用 `POST /eval {"qml":"backend.cancelLaunch()"}` 走同一条信号链；真点留给人工 |
| **把 QAbstractItemModel 直接当 QML model** | Repeater/ListView 静默 0 行，无报错 | 后端出 `QVariantList`（本仓库已验证的唯一可靠做法） |
| **Column 里放 Repeater** | 模型替换后子项顺序漂移，底部元素跑到顶部 | 节点列表改用 ListView；高度自己算 |
| `SpringAnimation` | 数值发散到 ±Infinity，控件消失 | 已写进契约检查 |
| `layer.enabled` + 整窗 `MultiEffect` | 文字瞬间放大、控件消失 | 只在单个小图标上用 MultiEffect |
| QML 里加 `console.info` 调试 | 曾出现"以为加了其实没落盘"，白排查 | 改用**画在界面上**的诊断行（`--ui-overlay-debug`） |

### ⚠️ 历史操作事故（已消除隐患）
上一轮用脚本点"启动"但"取消"按钮坐标算错，**两次真的把 Minecraft 启动起来了**。根因是脚本靠猜坐标点真实按钮。
现在 `overlay-probe.ps1` / `launch-test.ps1` **已删除**，换成 `overlay-demo.ps1`：浮层状态由后端假状态机驱动（`--ui-demo-launch`），脚本只读图 + 调 QML 表达式，**没有任何"点启动"的路径**。

---

## 6. 验收记录（2026-11-04 17:1x–17:4x，全部用 demo 态抓图）

- [x] 节点清单渲染 — 6 节点（`--ui-demo-online`）/ 5 节点（离线）都正确
- [x] 取消干净退回 — `backend.cancelLaunch()` 后浮层消失、主按钮回蓝"启动游戏"、状态行清空
- [x] 失败态 — 红方点 + 红节点名 + 子行给具体原因（"启动失败：未找到 Java 21，可在版本设置中指定"）+ 底栏"查看日志/重试"，**失败后浮层常驻**
- [x] 离线 5 节点（login 隐藏，总进度按 5 分母算）
- [x] 800×550 浮层放得下（面板 600 宽，上下各留 ~58px）
- [x] 完成态 — 全部完成时显示 100% + "游戏已启动"，2.2s 后收起
- [ ] **真机启动一次**（会真的起 Minecraft，必须在用户在场时做）：确认 6 个节点的名称/顺序/子行与真实流程一致
- [ ] 失败态真实触发（例如把 Java 路径指到不存在的目录）后，"重试"能否拉起下一轮
- [ ] "查看日志"按钮打开的是启动器日志目录（`openLauncherLogsFolder()`）——演示态下点一次即可确认

---

### 3.5 上次游玩（已完成，2026-11-04 17:45）

- `ShadowBackend.lastPlayedLabel`（NOTIFY `lastPlayedChanged`）+ `recordLastPlayed()`。
- **写盘时机**：只有 `LaunchBackend::minecraftStarted`（游戏进程真的起来）才写，检查失败/取消都不写。
- **存哪**：`<dataDir>/last-played.json`，`{ "<versionId>": <epoch ms> }`。
- **为什么不读版本目录 mtime**：非隔离版本的 `logs/`、`options.txt` 是所有版本共用的，拿它当"上次玩这个版本"会撒谎。没有记录 → 返回空串，QML 整行不显示（宁可没有，不给假信息）。
- 文案：今天 HH:mm / 昨天 HH:mm / N 天前 / M 月 d 日 / yyyy-MM-dd。

### 3.6 版本管理页（2026-11-04 19:xx，第一版：主从详情）

- **入口**：启动页底部「版本」按钮 → `StagePage.openVersions()` → `StageShell.versionsOpen = true`。
- **侧栏收起**：`versionsOpen` 时 `SideBar.visible=false` 且 `width=0`，版本页 `anchors.fill` 覆盖整窗；顶部自带「返回」。启动浮层 z=200 仍然压住一切（启动中进不了这一页的交互）。
- **调试入口**：`--ui-versions` 直接进版本页（配合 `--ui-size 800x550` 看窄窗）。
- **数据源**：`backend.versionDetails`（后端异步扫 `versions/`，字段见 §3.6.1）；进入页面时主动调 `refreshVersionDetails()`，**后端不会自己扫**。
- **功能**：选版本（写 `selectedVersion`）/ 启动 / 打开目录 / 复制版本 / 刷新 / 搜索（id+MC+加载器+加载器版本）/ 按发布时间倒序 / 打开页面自动滚到选中项。
- **图标**：直接用旧 UI 的 MC 方块图标 `qrc:/qt/qml/ShadowLauncher/qml/icons/blocks/*.png`（按 loaderType/versionType 选：Fabric/Anvil/NeoForge/RedstoneBlock/Grass/CommandBlock/CobbleStone，整合包优先用 modpackIconPath）。
- **未做（下一轮）**：数据表型（第二版，用户要求在验证主从详情后加）、删除/重命名/校验修复、版本设置入口、动效。

#### 3.6.1 versionDetails 字段（后端已给）
`id / mcVersion / loaderType / loaderVersion / versionType / releaseTimeMs / sizeBytes / modCount / isModpack / modpackIconPath / modpackIcon / jsonPath / jarPath`

本次补的两个：
1. `mcVersion`（之前根本没写进 detail，QML 只能拆目录名）：优先 `inheritsFrom`，否则 JSON 的 `id` 必须匹配 `^\d+\.\d+(\.\d+)?$` 才采用，**认不出就留空**。
2. `lastPlayedLabelFor(versionId)`（Q_INVOKABLE）：逐版本「上次游玩」文案，复用 `last-played.json`。

#### 3.6.2 MC 版本怎么认出来的（多路取证，五级降级）
本机版本 `1` 的 JSON 被拍平过：**没有 `inheritsFrom`、没有 `net.fabricmc:intermediary`、assetIndex id 是数字 `32`**。最初只认 `inheritsFrom` + `id`，于是显示"未识别"。后来补成五级，**15 个版本全部认出来了**：

| 级 | 来源 | 说明 | 本机命中 |
|---|---|---|---|
| 1 | `inheritsFrom` | 加载器版本的标准写法，最可靠 | 0 |
| 2 | **`clientVersion`** | 版本 JSON 记录的基础客户端版本；拍平/改名后**仍常被保留** | 10 |
| 3 | JSON 的 `id` | 原版版本用，但必须匹配 `^\d+\.\d+(\.\d+)?$` | 4 |
| 4 | **jar 内 `version.json` 的 `id`** | 原版 jar 自带的版本描述（1.14+ 必有），用 `QZipReader` 只读这一个条目，不解压整个 jar | 0 |
| 5 | 目录名正则拆 `XX.X-loader-YY` | `26.2-fabric-0.19.5` 这类命名 | 1 |

- 全都不成立 → 空串，QML 显示「未识别」，**绝不拿目录名冒充**。
- 每行记 `mcVersionSource`（排查用）；实测 `Immersive Fight 4.2.4 → 1.20.1`、`RLCraft → 1.12.2`、`Zombie Invade 100 Days → 1.20.1` 都靠 `clientVersion` 认出来的——**整合包改名场景这才是主力**。
- `QZipReader` 来自 `<QtCore/private/qzipreader_p.h>`；项目早已链接 `Qt6::CorePrivate`（`userdata_backend.cpp` 就在用），不引入新依赖。

---

## 7. 遗留问题
- **版本名过短**：用户机器上版本名叫 `1`，58px 下像页码。已确认这是数据问题不是排版问题，**不要再用"按长度自适应字号"去掩盖**（已 revert）。
- **版本名 `1` 过短** 是数据问题，不是排版问题；接版本列表页后用户可自己改名。
- 浅色主题：用户已明确"交给后续开发"，当前只做深色。
- `lastPlayed` 只是"从本版启动器起"的记录；老用户的历史游玩时间不会凭空出现（这是刻意的：不猜）。

---

## 8. 下一步建议顺序

1. **动效系统**（用户 19:20 明确：动效暂缓，先做版本页；版本页验证通过后再补）——Theme 加 motion token + SAnimate 标准件 + 把 `CheckUiNextContract.cmake` 接进构建
2. **版本管理第二版：数据表型**（用户已选定 A+B 两种，先验证主从详情，再加数据表）
3. 版本管理的补齐：删除/重命名/校验修复、版本设置入口
4. 版本设置页（Java/内存/JVM 参数），对接已有 `ShadowBackend` 的 per-version 接口
5. 账户面板（`loginMode` 三态严格分离：正版/离线/外置）
6. 浅色主题
