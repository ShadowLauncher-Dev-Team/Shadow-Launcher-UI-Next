# 交接文档 — Shadow Launcher v2 UI 重写

> 更新时间：2026-11-04 21:45（上一版 21:10）
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

#### 3.6.3 用户验收后的改造（2026-11-04 20:xx）

用户验收提出 5 条 + 1 个新功能，已全部落地：

| # | 意见 | 处理 |
|---|---|---|
| 1 | 大标题应显示版本号 | 大标题 = **版本名**（`sel.id`），副标题 = `MC 版本 · 加载器`；此前反了（大标题是 MC 版本） |
| 2 | 删「复制版本」 | 已删（版本选择界面不做管理动作） |
| 3 | 右上「打开游戏目录」多余 | 已删 |
| 4 | 不支持直接启动，右下改「确定」 | **改成选择器语义**：点列表只改 `pendingId`，「确定」才 `setSelectedVersion` 并返回；「返回」= 取消（不提交） |
| 5 | 「按发布时间」无实际作用 | 文案已删（排序仍按发布时间倒序，只是不再显示） |
| + | 补「切换游戏文件夹」 | 顶栏文件夹 chip + 下拉面板（`backend.mcFolder`：`folders` / `setActiveFolder` / `revertToDefault` / `pickFolderDialog` / `addGameFolder`）；切换后自动重扫 `versionDetails` |

- 调试参数新增 `--ui-folder-menu`（直接展开文件夹面板，截图/验证用）。
- 注意：`--ui-versions` 进版本页仍保留；两者可叠加。

### 3.7 账户页（2026-11-04 21:xx，全屏）

用户拍板「全屏吧，专门留出管理账户的地方」，不再做抽屉。实现要点：

| 项 | 实现 |
|---|---|
| 形态 | 全屏页 `ui/pages/AccountPage.qml`，`StageShell` 里与 `VersionPage` 同级 `anchors.fill`，侧栏宽度收为 0 |
| 入口 | 启动页右上胶囊 `SAcctChip` → `onOpenAccount`；未登录时主按钮变「先登录」（`SButton.muted`，灰底但仍可点）也进这里 |
| 顶栏 | 左「返回」+ 标题「账户」+ 副标题（正版/离线/未登录；打开换号面板时留空，避免"已登录"与正文冲突）|
| 左列 | 已登录=当前账户卡（头像+名+类型/状态）；未登录 / 换号=登录方式三选一（正版 / 离线 / 外置）|
| 右栏 | 正版：Uuid 掩码、访问令牌状态、皮肤状态 + 「切换账号」「退出登录」；离线：用户名输入 + 历史名列表；外置：API 根地址/邮箱/密码 + 服务器名 + 档案选择 |
| 数据源 | 全部真实后端属性，**没有一条编造**：`username/isOnline/accountUuid/skinPath/offlineUsernames/lastLoginMode/microsoftLoginBusy/msStatus` + `yggdrasil.*`；登录态切换用 `b.lastLoginMode = n`（属性写，不是 `setLastLoginMode()`）|
| 防重复点 | `b.microsoftLoginBusy` 时按钮换「取消登录」，`msStatus` 原文显示在提示条里（不加工、不猜进度）|
| 调试参数 | `--ui-account` 直接进账户页；`--ui-account-login` 再叠一层：直接展开登录面板（截图未登录态用）|

#### 3.7.1 头像：方形、无框、用后端 128 头图 + 最近邻

- 用户原话：「MC头像是方形的，QML不要用圆形头像；而且，不需要任何框把头像框住。」→ `SMinecraftHead.qml` 全组件 **无 radius、无 border**。
- **数据源**：直接使用 `backend.skinPath` —— 它是后端 `renderHead3D()` 渲染好的 **128×128 完整头部图**（正面 + 侧面的多面渲染，头发/犄角/头饰都在里面）。
- **不要自己从 64×64 皮肤裁脸 (8,8,8,8)**：那只是脸的正面一格，外层（帽层 40,8、侧面等）会全部丢掉。用户 2026-11-04 的原话是「我的角都不见了」，就是踩了这个。`skinTexturePath` 仍保留在后端，仅作"拿不到头图"时的兜底。
- **清晰度三件套**（照抄旧 UI `qml/MinecraftHead2D.qml`）：`smooth: false` + `mipmap: false` + **不设 `sourceSize`**。
  - 之前写 `smooth: true` 会糊成一团；设 `sourceSize` 预缩放到小尺寸再显示等于二次采样，也会糊。这两条是"头像模糊"的两个真因。
- 排查这类问题的正确姿势：把皮肤按 UV 网格放大标注再判断（`(8,8)`=脸正面、`(40,8)`=帽层正面、`(0,8)/(16,8)`=左右侧面），不要拿缩略图猜哪块是脸。
- 验收：账户页 56px 与旧 UI 48px 截图放大并排比对，角/面部/配色逐像素一致才算过。

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

---

## 9. 2026-11-04 晚：逻辑修正 + Toast 系统

用户在实操 v2 后提了 5 个逻辑问题 + 2 个美观问题，本轮处理结果：

| 问题 | 根因 | 处理 |
|---|---|---|
| 切游戏文件夹后 chip 文字不变 | `MinecraftFolderBackend::setActiveFolder()` 只写注册表、**不重扫 folders**，而 `folders` 是异步探测出来的缓存（含 active 标记）→ QML 读到旧列表 | setActiveFolder / revertToDefault 末尾补 `refreshFolders()`；`switchFolder()` 同时改为看返回值，失败提示"不是有效的游戏目录"（以前不管成败都提示"已切换"） |
| 账户页有"切换账号" | 语义与"退出登录"撞车（点下去只是回登录首屏） | 右侧删掉；左侧列表加"添加账号"行（hasAccount 时显示，点开登录表单） |
| 登录方式三行文字几乎重叠 | 行高 54 + 标题垂直居中 + 副标题 bottomMargin 10 → 两行只差 1~2px | 行高 62；标题 `y:12 h:18` 垂直居中，副标题 `y:34` |
| 退出登录后主页头像/名字不变 | `logout()` 清了 `m_skinPath` 但只 emit `accountChanged`；而 `skinPath/skinTexturePath` 的 NOTIFY 是 `skinReady` → QML 绑定不重算 | logout 里补 emit `skinReady()` + `offlineSkinReady()` |
| 版本页右侧信息硬切 | `page.sel` 换值直接改文本 | rightPane 加 `infoSwap`：120ms 压暗到 0.25 → 180ms 淡回，同时 infoCol 6px 上浮 |
| 左侧选中条只有"变大变小" | 每行各有一根自己的指示条 | 换成**整页唯一一根** `listSelBar`：`animIdx`（real 行号）带 Behavior 滑行，`contentY` 变化时不加动画（滚动实时跟随） |
| "刷新"绿色文字挤动控件 | 反馈写在顶栏 Text 里 | 新增 `ui/ToastHost.qml`（右下角栈，info/warning/success 三色，`show()` / `showAction()`），StageShell 全窗挂一份，页面用 `toast` 属性调用；页面原有的 `hint` 属性与 hintTimer 全部删除 |

**Toast 使用约定**：
- 位置右下角，bottomMargin = 16 + 56（避开页面主操作按钮，如版本页「确定」）
- 默认 2600ms；`showAction(msg, cb)` 常驻可点；最多同时 4 条，超了丢最老的
- 时长/缓动一律走 Theme token（`durFast`/`durBase`/`durPage`），契约检查会拦裸数字

**已知缺口**：后端目前只有"一个当前账号"，没有多账号列表存储，所以"添加账号"实际是打开登录流程、登录后**替换**当前账号。真正的多账号（列表 + 切换）需要后端加持久化，待确认后再做。

**顺带修**：`icons/lucide/lock.svg` 没进 CMake 资源列表（`qml/icons` 有、`icons/` 没有），启动日志一直报 icon missing；已补文件 + 资源条目。


---

## 10. 2026-11-04 深夜：第二轮实测问题 + 多账号列表

### 第二轮 5 条问题（commit 5a5cbf0）
1. **换版本"向上抽搐"** —— 顺序错了：上一版在内容已经换成新内容之后才播"压暗→淡回"，
   看到的是新文字先亮一下再闪一下。改为 shownId：淡出 → 在完全透明时换内容 → 淡入 +6px 上浮。
   **规则：交叉淡入必须先隐藏再换内容。**
2. **主按钮顶部白条** —— SButton 里 1px 的 `#33ffffff` 毛边高光，深色底上就是一道白线，已删。
3. **正版登录状态不美观** —— 后端 msStatus 文案长（"授权个人信息: ..."），旧卡片 42px 固定高 + elide
   只剩半句。改成标题 + 最多 3 行明细 + 呼吸点，高度随内容，只在登录中显示。
4. **点"添加账号"后卡死** —— 顶栏"返回"无条件 close()。现在登录表单态下文案变"返回账户"，
   点击 `loginPanel=false`。
5. **切文件夹后左侧无选中** —— 后端重扫后 selectedVersion 可能为空/失效，pendingId 还是旧 id，
   右侧用 rows[0] 兜底、左侧没有条。新增 `syncPendingFromList()`，rows 变化时校验并跟随 rows[0]。

### 多账号列表（commit 0a3367e）
- **存储**：`<AppData>/shadow/accounts.json`，条目 {mode, name, uuid, refreshToken, apiRoot, accessToken, clientToken}，
  凭据字段用 TokenCrypto 加密（和微软会话同一套）。**同一时刻只有一个活动账号。**
- **切换**：先 `clearActiveIdentity()`，再按 mode 装载：
  0 正版 → 装 refreshToken + `refreshMicrosoftToken()` 续期（失败提示重新登录，账号保留）；
  1 离线 → `offlineLogin(name)`；2 外置 → `YggdrasilBackend::restoreSession()`（装会话 + 落盘 + validate + 取皮肤）。
  切回本地账号前先 `ygg->logout()`，避免两套身份同时在线。
- **写入时机**：正版/离线登录成功、外置登录成功（ShadowBackend 连 YggdrasilBackend::loginSuccess）、
  启动时补登记已登录但不在列表里的正版会话。
- **UI**：左列 = 账号列表（当前项高亮 + 蓝条；非当前项只显示名字首字母，不伪造皮肤），
  点即切换；右列"移除此账号"（退出登录只清身份，不移出列表）。
- **已知限制**：非当前账号没有缓存皮肤；正版账号若 refreshToken 失效需重新登录；
  外置切换会打一次 validate 接口，慢网下要等一会儿。

