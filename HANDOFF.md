# 交接文档 — Shadow Launcher v2 UI 重写

> 生成时间：2026-11-04 16:57
> 仓库：`D:\latest-code\shadow-v2`（git，main）
> 设计稿源：`D:\latest-code\cpp\design-2026-11-04\`（网页原型，不在本仓库 git 里；仓库内 `design/` 是迁移时的一份拷贝）

---

## 0. 一句话现状

**设计已定稿，QML 骨架已跑通，后端启动阶段管线已接上；但启动浮层的"节点清单"渲染为空（0 行），这是当前唯一阻塞项。**

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
| 总进度 | 阶段级（已完成节点/总节点），**不许编造字节百分比**；字节进度放节点子行 |
| 首屏判据 | 一个元素能留，唯一理由是**它能改变用户下一步动作**；说不出就删 |

三版布局比选已做过：选 **A 上下结构**（总进度条在上 + 节点清单在下）。B（左右分栏，进度表达两遍）和 C（时间轴，把总进度条换成竖线）已被否。

---

## 2. 构建与运行

```powershell
cd D:\latest-code\shadow-v2
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --parallel
```

- 旧 UI（兜底）：`build\Release\ShadowLauncher.exe`
- **新 UI：`build\Release\ShadowLauncher.exe --ui-next`**
- 尺寸预览：`--ui-size 800x550`
- 启动态安全演示（假状态机，不碰游戏）：`--ui-demo-launch`
- 双击启动：仓库根 `launch-ui-next.bat`

⚠️ 编译前若 exe 被占用（LNK1104），先 `Get-Process ShadowLauncher | Stop-Process -Force`。

---

## 3. 已完成

### 3.1 新 UI（`ui/`，QML 模块 URI `ShadowLauncher.Next`）
- `Main.qml` — 无边框透明窗，1100×720，最小 800×550，支持 `--ui-size`
- `Theme.qml` — 设计令牌单例
- `StageShell.qml` — 侧栏 + 内容区 + **LaunchOverlay 挂载点**
- `SideBar.qml` — 导航（按 `currentLabel` 选中，窄窗收成 64px 图标条）
- `pages/StagePage.qml` — 启动页：极光全幅 + 版本标题 + 启动按钮，含 `--ui-demo-launch`
- `controls/` — `SIcon`(lucide SVG + MultiEffect 着色) / `SButton` / `SWindowButton`(danger hover 变红) / `SAcctChip`
- `LaunchOverlay.qml` — **启动浮层（本轮重点，有 bug）**
- `assets/stage-aurora.jpg` — 内置背景（CMake 用 `BASE` 注册为 `qrc:/ui/stage-aurora.jpg`）

已验证可用：侧栏/图标/中文字体/极光全幅/主按钮/账户 chip/窗口按钮 hover 变红/800×550 自适应/启动态三阶段。

### 3.2 后端：把启动流程接上 StepPipeline

复用了现成的 `StepPipeline`/`StepNode`/`StepModel`（下载会话已在用）。

| 文件 | 改动 |
|---|---|
| `src/core/step_pipeline.h` | enum 增加 `DetailRole` |
| `src/core/step_pipeline.cpp` | `data()` 加 DetailRole；`roleNames()` 加 `detail`；**`appendStep()` 里连接节点 statusChanged/progressChanged/detailChanged/hiddenChanged → 单行 dataChanged**（不做这步 QML 委托不会刷新） |
| `src/backend/launch_backend.h` | include step_pipeline.h；4 个 Q_PROPERTY（`launchPipeline`/`launchOverallProgress`/`launchStepCount`/`launchStepNumber`）+ signal `launchStepsChanged()` + 5 个私有方法 + `StepPipeline* m_pipeline` |
| `src/backend/launch_backend.cpp` | `launch()` 里 `m_checkStep=0` 后调 `buildLaunchPipeline()`；`runNextCheck()` switch 前调 `syncPipelineStep(m_checkStep)`；`abortCheck()` 调 `failPipelineStep(reason)`；`emit minecraftStarted()` 前调 `completePipeline()` |
| `src/backend/shadow_backend.h/.cpp` | 4 个 Q_PROPERTY 转发 + signal `launchPipelineChanged()` + 构造函数 connect + getter 实现 |

**节点顺序必须与 `runNextCheck()` 的 case 0..5 一一对应**：
```
case 0 检查登录状态 / 1 检查 Java 环境 / 2 检查版本文件 / 3 检查依赖文件 / 4 检查内存分配 / 5 启动游戏进程
```
离线账户（`!m_authIsOnline && !m_yggdrasilMode`）时 login 节点 `setSkipped()+setHidden(true)`，`weightedProgress()` 会跳过 hidden 不计权重。

节点内子状态通过 `connect(this, &LaunchBackend::launchCheckProgress, ...)` lambda 自动写入当前节点 detail，**不需要改任何 emit 站点**。

### 3.3 工程护栏
- `tools/check-ui-contract.ps1` + CMake 目标 `UiContractCheck`（构建期硬失败）：禁止给 appVersion 加前缀、禁止 emoji 图标、禁止 SpringAnimation、`font.pixelSize` 必须整数、警惕 `layer.enabled`+`MultiEffect`
- `tools/capture.ps1` — 抓窗口截图（`SetProcessDPIAware` + `PrintWindow(...,2)`）
- `tools/overlay-probe.ps1` — **安全的启动浮层探测**：点启动 → 1.5s 抓图 → 立刻杀进程 + 清理 2 分钟内启动的 java
- `tools/launch-test.ps1` — ⚠️ 旧版，取消按钮坐标是错的，会误启动游戏，**建议删除或修正坐标后再用**

### 3.4 commit 记录
```
a9b9934 chore: 从 cpp/ 迁移 C++ 后端，UI 重写起点
14c5bbe feat(ui): 新 UI 垂直切片——启动页按 DESIGN_SPEC v2 落地
6325472 fix(ui): 版本号重复 v；新增构建期 UI 契约检查
ffa8f16 test(ui): 验收 Gate1 -- hover 变红 / 800x550 / 启动态三阶段
3718b53 revert(ui): 撤回按长度自适应标题字号
```
**注意：后端管线改动与 LaunchOverlay.qml 目前还没提交（工作区脏），交接时已一并提交。**

---

## 4. 当前阻塞：节点清单渲染为空

### 现象
浮层正常弹出，标题"启动 1"、总进度 **17%**、"**第 2 / 6 步**"都正确 —— 说明后端管线已建成 6 个节点、ShadowBackend 的三个属性都工作。**但节点清单一行都没有**，面板里出现一段空白。

### 已排除
- QML 没有 error/warning 日志
- `launchPipeline` 原本是 `CONSTANT`（QML 早期读到 null 后永不刷新），**已改为 `NOTIFY launchStepsChanged`**，且 `buildLaunchPipeline()` 里在 clearSteps 后补了一次 `emit launchStepsChanged()`
- 后端 6 节点确实建成（步数 6、进度 17% 佐证）

### 尚未排除（按可能性排序）
1. **delegate 里的 role 访问方式**。当前写的是 `model.name` / `model.statusInt` / `model.detail` / `model.hidden`。
   Qt6 推荐用 **`required property`** 显式声明，role 名写错会立刻报错而不是静默 0 行：
   ```qml
   delegate: Item {
       required property string name
       required property int statusInt
       required property string detail
       required property bool hidden
       ...
   }
   ```
2. `Repeater { model: root.steps }` 中 `root.steps` 是 `var` 持有 `QObject*`（来自 `pipe.model`，StepPipeline 的 `Q_PROPERTY(QObject* model CONSTANT)`）。可能需要 `model: root.pipe ? root.pipe.model : null` 直接绑定，或用 `required property var`。
3. `StepModel` 的 roleNames 里 `name` 是否与 delegate 上下文冲突。

### 建议的定位方法（最快）
在 `LaunchOverlay.qml` 的节点区上方临时加一行诊断 Text，**值直接画在界面上**（不要只靠 console.info，本会话中曾在 QML 里加日志但没生效、白排查了几轮）：
```qml
Text {
    width: body.width; height: 18
    text: "DBG pipe=" + (root.pipe ? "1" : "0")
          + " steps=" + (root.steps ? "1" : "0")
          + " rows=" + rep.count
          + " total=" + root.stepTotal
    color: "#ff9a94"; font.pixelSize: 11
}
```
（`rep` 是给 Repeater 起的 id；Repeater 自带 `count` 属性。）
然后用 `tools/overlay-probe.ps1` 抓图看这行数字：
- rows=0 且 steps=0 → `pipe.model` 取值问题
- rows=0 且 steps=1 → Repeater/role 问题
- rows=6 但看不见 → 是 delegate 的 height/visible 绑定问题

---

## 5. 踩过的坑（务必先看，能省几小时）

| 坑 | 现象 | 正解 |
|---|---|---|
| `font.pixelSize` 是 **int** | 写 13.5/12.5 报 `Invalid property assignment: int expected`，**整页不渲染** | 只用整数 |
| `qt6_add_resources` 不给 `BASE` | alias 会带上源相对路径（`qrc:/ui/ui/assets/x.jpg`），图加载失败 | `BASE "ui/assets"` |
| 透明窗口 + 图加载失败 | 直接透出桌面，看着像"没渲染" | 页面底层放不透明底色兜底 |
| `.ps1` 无 BOM | PowerShell 5.1 按 GBK 读，中文乱码 + `Unexpected token` | 存 UTF-8 **带 BOM** |
| 外部 `SetWindowPos` 调 Qt 无边框窗 | 高度变成 65535 | 让程序自己读 `--ui-size` 改尺寸 |
| PowerShell 抓 Qt 窗口 | 非 DPI 感知时拿到逻辑坐标；被遮挡只抓到别的窗口 | `SetProcessDPIAware()` + `PrintWindow(hwnd, hdc, 2)` |
| `SpringAnimation` | 数值发散到 ±Infinity，控件消失 | 已写进契约检查 |
| `layer.enabled` + 整窗 `MultiEffect` | 文字瞬间放大、控件消失 | 只在单个小图标上用 MultiEffect |
| QML 里加 `console.info` 调试 | 本会话出现过"以为加了其实没落盘"，导致白排查 | 改用**画在界面上**的诊断行 |

### ⚠️ 一个操作事故
本会话测试时用脚本点"启动"但"取消"按钮坐标算错，**两次真的把 Minecraft 启动起来了**（已全部清理）。后续请只用 `tools/overlay-probe.ps1`（抓到图立刻杀进程），或人工点。

---

## 6. 未验证清单

- [ ] 节点清单渲染（当前阻塞）
- [ ] 取消是否干净退回（`cancelLaunch` 后浮层消失、主按钮回蓝"启动游戏"）
- [ ] 失败态（节点变红 + 具体原因 + 查看日志/重试按钮）——目前 `failPipelineStep` 只设了 status=Failed，**QML 侧还没做失败态的按钮分支**
- [ ] 离线账户 5 节点（login 隐藏）
- [ ] 800×550 下浮层是否放得下（面板宽 600 会顶到边，需要窄窗规则：宽度 `Math.min(600, width-96)` 已写，未实测）
- [ ] 完成后浮层收起行为（目前 `visible: launching`，进程起来后 launching=false 会直接消失，没有"完成态"停留）

---

## 7. 遗留问题

- **`lastPlayed` 字段缺失**：启动页想显示"上次游玩 · 昨天 21:40"，但 `ShadowBackend` 没有这个字段。用户倾向保留这行，需要后端补（读版本目录 mtime 即可）。
- **版本名过短**：用户机器上版本名叫 `1`，58px 下像页码。已确认这是数据问题不是排版问题，**不要再用"按长度自适应字号"去掩盖**（已 revert）。
- 浅色主题：用户已明确"交给后续开发"，当前只做深色。

---

## 8. 下一步建议顺序

1. 用第 4 节的诊断行定位节点不渲染的真因，修好 → 抓 `--ui-next` 真实启动截图
2. 补失败态 UI（红点/原因/两个按钮）
3. 验证取消干净退回
4. 800×550 浮层适配
5. 版本列表页（token 密度试金石）→ 版本设置 → 账户面板
