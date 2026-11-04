# shadcn/ui 风格在 Qt/QML 中实现的可行性评估

> 日期：2026-11-03  
> 结论对象：是否采用 shadcn/ui 作为 Shadow Launcher 新视觉体系  
> 说明：只做可行性与工程评估，本报告不修改 UI 代码

---

## 0. 结论

**可行，而且视觉层比完整 Fluent 2 更容易；但不能把 shadcn/ui 当作“现成 QML 组件库”直接移植。**

准确说法是：

> **采用 shadcn/ui 的设计语法，自建一小组 QML 原语和组合组件。**

综合评估：

| 维度 | 结论 |
|---|---|
| 视觉还原难度 | **低** |
| 基础控件实现难度 | **低到中** |
| 复杂交互组件难度 | **中到高** |
| 官方 QML 支持 | **不存在** |
| 社区 QML 移植 | 有，但规模很小，不足以作为依赖 |
| 推荐程度 | **可行，推荐在受控范围内实施** |
| 预计 BUG 风险 | **基础控件低；浮层与键盘交互中；完整组件集高** |

---

## 1. shadcn/ui 的官方构建形式

shadcn/ui 不是一个传统 npm 组件包，而是：

- 组件源码通过 CLI 复制进项目；
- 基于 React；
- 样式依赖 Tailwind CSS；
- 交互与无障碍依赖 Radix UI、Base UI、React Aria 等；
- 复杂组件继续依赖 `cmdk`、TanStack Table、Sonner、Recharts、Embla 等；
- 主题通过 CSS variables 与环境变量式语义 token 控制；
- 当前官方支持的框架包括 Next.js、Vite、TanStack Start、Laravel、React Router、Astro。

官方文档没有提供 Vue、Qt、QML 或非 Web 构建方式。

因此：

- **没有官方 QML 版本。**
- **没有官方 QML 主题导出。**
- **没有可以直接复制的 QML 构建流水线。**

---

## 2. shadcn/ui 的结构对 QML 的映射

shadcn/ui 的核心不是样式本身，而是四层结构：

```text
Design Tokens
  ↓
Primitives（Button / Input / Dialog 等）
  ↓
Composition（CardHeader + CardContent 等）
  ↓
Theme（light / dark / accent / radius）
```

这四层与 QML 并不冲突，反而可以对应为：

```text
Shadow Theme（C++ token snapshot）
  ↓
QML Primitives（Button / Input / Overlay 等）
  ↓
Compound Components（PanelHeader / DialogContent 等）
  ↓
Runtime Theme（light / dark / density / reducedMotion）
```

真正不能直接迁移的是 shadcn 背后的 Web 行为层。

---

## 3. QML 实现难度分级

### 3.1 低风险，容易还原

| shadcn 元素 | QML 实现 | 评价 |
|---|---|---|
| 颜色 token | C++ 语义 token / QML singleton | 很低 |
| 圆角、边框、间距 | Layout + 属性 | 很低 |
| Button / Input / Label | `QtQuick.Controls.Basic` 定制 | 低 |
| Switch / Checkbox / Radio | Control 模板定制 | 低 |
| Badge / Separator / Skeleton | 简单 QML | 低 |
| Tabs / Accordion | 状态 + Layout | 中低 |
| Progress / Spinner | QML 动画 | 低 |
| 基础 Toast | 单例通知宿主 | 低 |
| Lucide 图标 | 现有 SVG 资源 + 着色 | 低 |

这些元素可以高保真复刻 shadcn 的视觉气质：

- 中性黑蓝表面；
- 细描边而非重阴影；
- 明确焦点 ring；
- 语义化状态；
- 克制的 hover / active 变化；
- 统一间距和字阶。

### 3.2 中等风险，需要行为设计

| shadcn 元素 | QML 难点 | 风险 |
|---|---|---|
| Dialog / AlertDialog | 模态、焦点陷阱、Esc、遮罩、关闭顺序 | 中 |
| Popover / DropdownMenu | 锚点定位、页面边界翻转、键盘导航 | 中 |
| Select / Combobox | 模型、键盘、过滤、滚动、可编辑输入 | 中 |
| Tooltip | 延迟、定位、避免遮挡、减少动效 | 中低 |
| Sheet | 侧滑层级、焦点锁、与主窗口交互 | 中 |
| Toast queue | 堆叠、优先级、动作、关闭与任务状态 | 中 |
| Sidebar collapse | 窄屏、折叠态、快捷键、状态持久化 | 中 |

### 3.3 高风险，不建议第一轮移植

| shadcn 元素 | 原因 | 建议 |
|---|---|---|
| Data Table | TanStack 功能、排序、筛选、分页、列宽、选择 | 使用现有 QAbstractListModel / TableView 自建 |
| Command Palette | `cmdk` 的键盘、模糊匹配、组合行为 | 只实现启动器实际需要的搜索面板 |
| 复杂 Form | React Hook Form + Zod 校验链 | QML 表单 + C++ 校验 |
| Charts | Recharts / shadcn 图表 | 用项目自己的统计图 |
| AI 组件 | 强依赖 Web/SSE 服务 | 与当前启动器无关 |
| 响应式 Sidebar 全家桶 | 状态、移动端抽屉、快捷键、嵌套菜单 | 只实现桌面启动器所需状态 |

---

## 4. QML 实现的真实风险

### 风险 1：误把 shadcn 当成组件库

shadcn 的类名、`data-state`、CSS variables、Radix 行为都不可直接用于 QML。  
正确做法是：

- 复制语义 token；
- 复制视觉比例；
- 复制组件组合思想；
- 重新实现 QML 行为。

### 风险 2：Tailwind 思维导致零散布局

QML 没有 Tailwind。若继续在页面里手写 `Rectangle + Text + MouseArea`，结果不会是 shadcn，而是当前这种“无风格卡片”。

必须建立：

- `ShadowButton`
- `ShadowInput`
- `ShadowField`
- `ShadowDialog`
- `ShadowMenu`
- `ShadowTabs`
- `ShadowCard`（如确实需要）
- `ShadowTable`

页面禁止直接创建这些元素的底层矩形。

### 风险 3：浮层与焦点

shadcn 质量很大一部分来自 Dialog / Popover / DropdownMenu 的交互。QML `Popup` 可以做，但需要自行处理：

- 父级与剪裁；
- 窗口内定位；
- 遮罩；
- Esc；
- 焦点恢复；
- 嵌套浮层；
- 外部点击；
- 任务进行中关闭。

当前项目已有 `OverlayHost` 方向，应继续收敛为唯一宿主，而不是每页自造 `Popup`。

### 风险 4：颜色空间

shadcn 当前主题使用 CSS `oklch(...)`。QML 的颜色类型并不会像 CSS 那样直接消费现代颜色函数。

因此：

- token 在 C++ 中以 `QColor` 可接受的 sRGB/HEX 形式保存；
- 设计稿中的 OKLCH 必须先转换并做对比度校验；
- 不要直接把 `oklch(...)` 字符串塞进 QML。

### 风险 5：文字和滚动布局

Qt Quick 的 Text / Flickable / ScrollView 与浏览器排版不同。需要显式处理：

- `elide`；
- `wrapMode`；
- 最小宽度；
- `implicitHeight`；
- 不要在 `ScrollView` 中制造 `implicitWidth` / `implicitHeight` 绑定循环；
- 列表使用稳定模型和角色更新。

---

## 5. 官方推荐的 QML 构建形式

### 5.1 shadcn 官方

没有 QML 构建形式。  
官方推荐方式只覆盖 React Web 技术栈。  
不能把 shadcn 的 CLI 直接用于 Qt 项目。

### 5.2 Qt 官方推荐

对于自定义视觉体系，Qt 官方推荐：

1. **基于 `QtQuick.Controls.Basic`**
   - Basic 是平台无关、性能优先、最适合自定义样式的官方基础。
   - 当前项目已通过 `QT_QUICK_CONTROLS_STYLE=Basic` 强制使用。
2. **自定义样式模块**
   - 如果要做全局 Controls 风格，需提供 `qmldir`；
   - 控件以 `QtQuick.Templates` 为根；
   - 通过 QML module 发布，而不是在业务文件中逐项覆盖。
3. **使用 `qt_add_qml_module`**
   - 声明 URI、QML_FILES、资源前缀；
   - 自动生成 qmldir / qmltypes；
   - 支持 qmllint、qmlcachegen；
   - 这是本项目当前已经在采用的方式。
4. **使用 Qt Quick Layouts**
   - 自适应布局；
   - 避免固定坐标；
   - 避免在 Layout 子项上直接绑定 x/y。
5. **使用 QAbstractListModel**
   - 长列表与实时进度；
   - 角色级通知；
   - 避免 QVariantList 全量 rebuild。

---

## 6. 推荐实施形态

### 6.1 不整体采用社区 QML shadcn

社区有 `QtShadcn/qtshadcn` 等项目，仓库自身 MIT，但规模很小、非官方，不能作为稳定依赖。  
可以参考其 token / component 分层，不建议整体 vendor。

### 6.2 采用“应用内设计系统”

```text
qml-next/
  Theme.qml                      // 语义 token 单例
  controls/
    ShadowButton.qml
    ShadowInput.qml
    ShadowField.qml
    ShadowSwitch.qml
    ShadowSelect.qml
    ShadowDialog.qml
    ShadowMenu.qml
    ShadowTabs.qml
    ShadowTable.qml
  patterns/
    AccountCard.qml
    VersionPicker.qml
    LaunchStatus.qml
  pages/
    HomePage.qml
    DownloadPage.qml
    SettingsPage.qml
```

规则：

- 页面只能使用设计系统组件；
- 组件只使用语义 token；
- tokens 来自 C++ ThemeController；
- 所有浮层进入 OverlayHost；
- 所有远程/业务状态来自 C++ Presenter；
- QML 组件不直接写死颜色、时长、z-index。

### 6.3 建议首批组件

**第一批：**

- Button
- Input
- Field/Label
- Switch
- Checkbox
- Separator
- Badge
- Tabs
- ScrollArea
- Toast
- Dialog

**第二批：**

- Select
- DropdownMenu
- Tooltip
- Popover
- Sheet

**第三批：**

- Table
- Command 搜索
- 可折叠 Sidebar
- 复杂 Form

---

## 7. 最终判断

### 可行性

**高。** shadcn 的视觉语言比 Fluent 的材质、阴影和原生控件语义更简单，QML 完全能够还原。

### 容易程度

- 纯视觉：**容易**
- 基础控件：**容易到中等**
- 复杂交互：**中等**
- 完整 shadcn 组件全家桶：**困难且没有必要**

### BUG 概率

- 只做启动器所需组件：**低到中**
- 把所有 Web 行为照搬：**中到高**
- 继续在页面里自由拼 Rectangle/Text：**高**

### 推荐方案

**采用 shadcn/ui 风格，但只实现 Shadow Launcher 实际需要的子集；以 Qt 官方推荐方式构建自有 QML 设计系统。**

不采用：

- shadcn CLI；
- Radix/Tailwind 代码；
- 社区 qtshadcn 整体依赖；
- 全量 DataTable / Command / Sidebar 全家桶。

---

## 8. 参考来源

- [shadcn/ui 官方文档](https://ui.shadcn.com/docs)
- [shadcn/ui Theming](https://ui.shadcn.com/docs/theming)
- [shadcn/ui Installation](https://ui.shadcn.com/docs/installation)
- [shadcn/ui Components](https://ui.shadcn.com/docs/components)
- [shadcn/ui Dialog](https://ui.shadcn.com/docs/components/dialog)
- [shadcn/ui Sidebar](https://ui.shadcn.com/docs/components/sidebar)
- [shadcn/ui Command](https://ui.shadcn.com/docs/components/command)
- [Qt 自定义 Controls 样式](https://doc.qt.io/qt-6.8/qtquickcontrols-customize.html)
- [qt_add_qml_module](https://doc.qt.io/qt-6.8/qt-add-qml-module.html)
- [QML Best Practices](https://doc.qt.io/qt-6.8/qtquick-bestpractices.html)
- [Qt Quick Controls Styles](https://doc.qt.io/qt-6.8/qtquickcontrols-styles.html)
- [QtShadcn/qtshadcn（社区项目，非官方）](https://github.com/QtShadcn/qtshadcn)
