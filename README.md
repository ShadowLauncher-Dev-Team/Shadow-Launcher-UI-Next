# Shadow Launcher v2

启动器第二次重写。C++ 后端自 v1.0.4 原样迁移，**UI 全部重写**。
上一代 UI（`qml/`）保留在 `legacy/` 之外未迁移；被废弃的 `qml-next/`（Qcoder 第三轮产物）已移除。

## 目录

```
src/            C++ 后端（原样迁移，未改动）
ui/             ← 新一代 QML（本仓库唯一在开发的 UI）
  Main.qml          入口 Window（无边框 / 透明 / 最小 800×550）
  Theme.qml         设计令牌（单例）
  StageShell.qml    侧栏 + 内容区
  SideBar.qml       左侧导航
  pages/StagePage.qml   启动页
  controls/         SButton / SIcon / SWindowButton / SAcctChip
  assets/           内置背景图
qml/            上一代 UI（仍参与编译，作为兜底入口，勿改）
docs/ui/        设计规范与历次验收记录
design/         网页原型（proto.html）与截图，仅作草稿纸
cmake/ tests/ thirdparty/ lzma_sdk/ resources/ icons/ i18n/
```

## 构建

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --parallel
```

- 默认启动：`build\Release\ShadowLauncher.exe`（跑旧 UI）
- 新 UI：`build\Release\ShadowLauncher.exe --ui-next`
- 截图：`pwsh tools/capture.ps1 -Exe build\Release\ShadowLauncher.exe -Out shot.png -W 1375 -H 897`

## UI 硬规则（踩过的坑，别再踩）

1. **图标一律 SVG**（`qrc:/qt/qml/ShadowLauncher/qml/icons/lucide/*.svg`），**禁止 emoji / Unicode 符号当图标**。
2. **禁止 `SpringAnimation`**：已实测数值会发散到 `-Infinity`，导致控件消失。
3. **禁止整窗 `layer.enabled` + `MultiEffect`**：会触发纹理重分配，表现为文字瞬间放大、控件消失。单个小图标上色用 `MultiEffect` 可以。
4. **禁止把功能摊成等权卡片网格**：首屏是"一个决定 + 一个按钮"。
5. **首屏信息准入判据**：一个元素能留，唯一理由是它能改变用户下一步的动作；说不出改变哪个决定就删。
6. 常态不显示"就绪/准备就绪"；只有异常才说话。

设计规范见 `docs/ui/DESIGN_SPEC`（在 `design/DESIGN_SPEC.md`），验收 rubric 共 12 项 100 分，**打分只能由看图的一方打**。
