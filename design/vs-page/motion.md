# 版本设置页 · 动效设计（v1）

> 目标：让版本设置页动效与启动器已有动效语言一致——尤其是左栏菜单继承主菜单的"胶囊滑动"。
> 原则：克制、分层、不打架。每个动画都要有理由（反馈 / 空间关系 / 焦点转移）。

## 一、现有动效语言（继承基准）

来源：`ui/Theme.qml`（唯一真源）+ `ui/SideBar.qml`（主菜单）+ `ui/StageShell.qml`（整页切换）。

| 语义 | 常量 | 值 | 用在哪 |
|---|---|---|---|
| 状态反馈 | `durFast` | 120ms | hover、颜色、图标显隐 |
| 局部动作 | `durBase` | 180ms | 展开收起、提示、进度生长、分区切换 |
| 面板/列表 | `durSlow` | 260ms | 面板进出、列表逐条入场、菜单胶囊滑动 |
| 整页切换 | `durPage` | 320ms | 启动页 ↔ 版本页 / 账户页 / 版本设置 |
| 按压缩放 | `durPress` | 90ms | 按钮按下 |
| 缓动（进） | `easeEnter` | OutQuint | 快起慢收，有重量感 |
| 缓动（出） | `easeExit` | InCubic | 加速离场，利落 |
| 缓动（标准） | `easeStandard` | OutCubic | 通用 |
| 逐条入场 | `staggerStep` / `staggerMax` | 28ms / 12 行 | 列表入场错开 |

**主菜单的做法（必须继承）**：选中态是**单一滑块对象**，切页时从旧位置**滑到**新位置（`Behavior on y`，durSlow + easeEnter），左侧 2px 强调条跟着滑块走。
不是"旧竖条缩回去 + 新竖条长出来"——那是两段互不相关的动作，读不出方向。

## 二、分层（防打架）

三个层级的动效时长必须拉开，避免同时播放时糊成一团：

```
壳整页切换      durPage  320ms   （进入版本设置：右滑 24px + 淡入 + scale 0.988→1）
  └ 左栏胶囊    durSlow  260ms   （点菜单：胶囊 y 滑动）
      └ 分区内容 durBase 180ms   （新页淡入 + 上移 6px，只入场）
```

首次进入：壳在播 320ms，**分区内容不播入场**（只在 `sourceComponent` 变化时播），避免二次淡入。

## 三、逐页设计

### 3.1 左栏（全局）
| 位置 | 动效 | 参数 |
|---|---|---|
| 选中胶囊 | 单块 y 滑动（从旧位置滑到新位置） | `Behavior on y`，durSlow，easeEnter |
| 强调条 | 跟着胶囊走（不单独动） | 无独立动画 |
| 行 hover | 背景透明度 0↔1 | durFast，easeStandard |
| 行文字颜色 | 选中/未选中切换 | durFast，easeStandard |

去掉的东西：选中行自己的 2px 竖条 + 选中背景（与胶囊重复，会打架）。

### 3.2 分区切换（内容区）
- 新页 `opacity` 0→1 + translateY 6→0，durBase，easeEnter，只入场。
- 不做交叉淡出：旧页同帧替换，底色一致不会闪。

### 3.3 各分区（由子代理按分组实现）

**列表类（Mod 管理 / 资源包 / 存档）**
- 行 hover：背景色过渡 durFast
- 列表 add：淡入 + 上移 4px，durSlow，前 8 行按 staggerStep 错开
- 列表 remove：淡出 + 高度收 0，durBase，easeExit
- 空态/加载态文案：淡入 durBase
- 不做：搜索过滤动画（会闪）、displaced 动画（长列表卡）

**表单类（内存 / 启动配置 / 导出整合包）**
- 内存占用条：`Behavior on width`，durBase（只在拖滑条时变，非高频）
- 展开区：`Behavior on height`，durBase，easeEnter
- 导出页目录树展开/收起：高度 durSlow + 内部列表 opacity durBase
- 复选框：按压缩放 1→1.08→1，durFast，easePop
- **导出进度条：禁止 Behavior on width**（高频 progressChanged 会重置动画，永远追不上）

**信息类（快捷入口 / 概览 / 工具与维护）**
- 瓦片 hover：背景 + 图标颜色 durFast（不做位移，9 个一起抖会乱）
- 瓦片按下：scale 0.98，durPress + easePop
- 首次入场：逐条淡入 + 上移 6px，staggerStep / staggerMax / durSlow
- 工具页状态卡高度：durBase（避免布局跳）
- **校验进度条：禁止 Behavior on width**

## 四、不做什么（明确排除）

| 不做 | 理由 |
|---|---|
| 数字滚动动画（如内存 2048 MB 变化） | 太花，且会在连续调值时抖动 |
| 列表 hover 位移/缩放 | 鼠标划过整片列表时像在跳 |
| 分区切换交叉淡出 | 需要双 Loader 常驻，内存翻倍；同帧替换已足够 |
| 进度条宽度补间 | 高频信号会不断重置，进度条永远追不上（已踩过） |
| 普通行入场逐个延迟到整页 | 425 个模组时总时长失控；只对首屏前 12 行错开 |


---

## 五、实现实况（v1 已落地，2026-11-09）

### 证据
- `pill_0.png` / `pill_3.png`：点「存档」瞬间与 120ms 后的对照。胶囊从「Mod 管理」整块滑到「存档」，左侧蓝条跟随，「Mod 管理」不再高亮；同时内容区从暗变亮（分区入场淡入）。六帧连拍哈希前 3 帧不同、后 3 帧相同 → 动画真实播放并在 ~160ms 内完成。
- `motion_nav.png`：修复后的左栏（胶囊正确渲染在选中项上）。

### 与初版设计的偏差（子代理实测后发现，已按实测改）
1. **ListView 的 add/remove ViewTransition 在整表替换的 model 下永不触发**（model reset 只走 populate，add/remove 只在增量 insert/remove 时触发）。因此列表入场改成 delegate 自己播「入场预算」，只在首次载入和点刷新时给预算；搜索过滤、启停、删除后的静默重扫一律不给。
2. **删除行的淡出+收高没做**。要做得把 model 换成 keyed ListModel + 手写 diff，属于数据层改动，超出本次范围。
3. **VsToolsPane 原本在进度条上挂着 `Behavior on width`** —— 正是"高频信号重置动画、进度条永远追不上"的坑，本次已删除，宽度回归纯绑定。

### 已知限制（验收时请留意）
| 现象 | 原因 | 处理 |
|---|---|---|
| 启动配置的 JVM/游戏参数卡**收起时最后一帧跳 16px** | Column 对 `visible:false` 的子项立即去掉 spacing，spacing 无法动画 | 未修。修需把卡片包进宿主 Item 并改整列间距策略，风险大于收益 |
| 工具页「开始校验↔取消」交叉淡入期间按钮宽度固定为两者较宽值 | 两块 SButton 叠放，宽度不参与动画（否则会看到两条不同宽度的描边） | 有意为之，左侧文字区少约 26px |
| 列表删除没有收高动画 | 见上（ViewTransition 不触发） | 未做，删除反馈靠确认弹窗 + toast |
| 手感（是否流畅、有无顿挫） | 静态截图无法判定 | **需人工实测** |


---

## 六、修复：第二次进入是全屏页硬切（影报）

### 现象
第一次进版本设置页有滑入，之后再进就是**硬切**。

### 根因
`StageShell.qml` 里每个全屏页都是这个写法：

```qml
x: root.settingsOpen ? 0 : 24
Behavior on x { NumberAnimation { duration: root.settingsOpen ? Theme.durPage : 0 } }
```

**时长和位移在同一帧求值，顺序不可靠**：关闭时 `duration` 先算成 0；下次打开时如果 `x` 先于 `duration` 求值，就沿用了 0 → 位移瞬移。首次能对上只是碰巧。

全项目共 **8 处**同款写法（版本管理/版本设置/账户/下载/联机/资源详情/下载进度），也就是**所有全屏页第二次打开都会硬切**，不只版本设置。

### 修法
改成 `states` + `transitions`，时长是字面量，不参与条件求值；只写 `to: "shown"`，所以只有进入有过渡，离开仍瞬时（保持既有的"返回要快"）：

```qml
x: 24
scale: 0.988
states: State { name: "shown"; when: root.settingsOpen
                PropertyChanges { target: settingsSurface; x: 0; scale: 1 } }
transitions: Transition {
    to: "shown"
    ParallelAnimation {
        NumberAnimation { target: settingsSurface; property: "x"; duration: Theme.durPage; easing.type: Theme.easeEnter }
        NumberAnimation { target: settingsSurface; property: "scale"; duration: Theme.durPage; easing.type: Theme.easeEnter }
    }
}
```

### 验证
新增 `--ui-reenter`（测试用，与 `--ui-pane`/`--ui-settings` 同类）：进/退每 1.2s 交替。连拍 45 帧后统计帧间变化：

```
.XXXX...XXXX.XXXX...XXXX.XXXX.X.XXXX.XXXX...
最长连续变化帧 = 4
```

硬切只会变化 1 帧；连续 4 帧变化 = 过渡真实播放。


---

## 七、分段控件（SSegmented）选中态改成滑动（影报）

### 现象
「配置模式：跟随全局设置 / 独立配置」这类分段控件，切换时只有`颜色渐变`，选中块**原地灭、原地亮**，看不到左右移动。

### 根因
`ui/controls/SSegmented.qml` 是**每个分项自己画**选中底色：

```qml
color: index === root.currentIndex ? "#132340" : "transparent"
Behavior on color { ColorAnimation { ... } }
```

两块颜色各自渐变，中间没有任何东西在移动。

### 修法
在 Row 之下放**一个整块滑块**，位置由 `currentIndex` 算（分项等宽，可以直接算），`Behavior on x`（durSlow + easeEnter）+ `Behavior on width`（items 数量变化时不硬跳）；分项不再自己画底色，只保留文字颜色过渡（durFast）。

### 影响面
`SSegmented` 是共享控件，所以**下载页、导出整合包页等所有用到分段选择的地方**一起获得滑动效果。

### 验证
`seg_launch.png`：静止态滑块正确压在「跟随全局设置」上。
连续帧验证被环境挡住：合成点击在这台机器上抢不到前台（`SetForegroundWindow` 被系统拒绝），置顶后截屏能拿到窗口，但注入的鼠标事件没能点中控件。**该项动效需人工点一下确认。**


---

## 八、两个交互 bug（影报）

### 8.1 滚动卡手 / 滚到底再上滚卡死

**根因**：`ui/controls/STextArea.qml` 用 `ScrollView` 包 `TextArea`，而 **ScrollView 无条件消费滚轮**——哪怕内容根本没溢出，它也会把滚轮事件吃掉。

启动配置页有 4 个 STextArea（JVM 参数 / 游戏参数 / 前置命令 / 后置命令），其中前两个在「独立配置」模式下就在视野里。鼠标划过输入框时滚轮失效 → 时滚时不滚；滚到底后光标正好停在输入框上 → **完全滚不动，看起来卡死**。

**修法**：ScrollView → `Flickable`，并显式 `interactive: contentHeight > height`：
- 内容没溢出 → 不参与交互，滚轮直接穿透给页面
- 内容真溢出 → 内部正常滚动

（`ScrollView` 全项目只有这一处用到，改完即彻底。）

### 8.2 输入框点了别处不失焦

**根因**：没有全局规则。`SField` 里有个 `blur()`，注释写着"外部点击时主动收起焦点"，但**要靠每个页面自己调**——漏一处就一直保持聚焦态（蓝边不消失）。

**修法**：`StageShell` 根加一个最底层 MouseArea（`z: -1`），`onPressed` 时把 `hostWindow.activeFocusItem.focus` 置 false。上层控件消费掉的点击到不了这里，只有真正的空白点击才触发。

**教训**：这类"点到别处应该恢复默认"的行为必须放在壳层统一做，靠各页面自觉调用必漏。


### 8.3 焦点修复第一次失败（我改错了，第二次才修对）

**第一次做法（错）**：`StageShell` 根放一个全窗 `MouseArea(z:-1)`，`onPressed` 里把 `hostWindow.activeFocusItem.focus` 置 false。

两个问题：
1. **点空白仍不失焦** —— `focus = false` 对 FocusScope 链不作数，输入框照样显蓝。
2. **新引入退化** —— 点另一个输入框要点好几次、还得把鼠标移出去再移进来。

原因是我把 `STextArea` 改成了 `Flickable { interactive: false }`（为了不吃滚轮），它**不再消费 press**，press 直接穿透到全窗 MouseArea → 先被清焦点、输入框才拿到 click → 焦点流被打乱。**两个修复互相踩。**

**第二次做法（对）**：
```qml
Item {
    id: focusSink
    anchors.fill: parent
    z: -1
    TapHandler { onTapped: focusSink.forceActiveFocus() }
}
```
- 用 `TapHandler` 而不是 `MouseArea`：TapHandler 不抢 press，输入框该谁聚焦还是谁聚焦
- 不给 `activeFocusItem.focus = false`，而是把焦点交给一个独立接收器，走 Qt 自己的焦点转移

**教训**：修交互问题时，两个"都在讲焦点/事件"的改动会互相踩，必须一起想清楚 press 的传播链。


### 8.4 焦点第三轮：真凶是 TextEdit 没有 height（我引入的）

前两轮都在改"怎么清焦点"，但**真正的 bug 在输入框本身**：

我把 `STextArea` 从 `ScrollView` 改成 `Flickable` 时，里面的 `TextEdit` 只给了 `x/y/width`，**没给 `height`**。于是它只有内容高度（一两行 ≈ 14px），而外框有 `areaHeight`(92px) 那么高——

**只有文字那一行能点中、能拿焦点，点框的其他位置完全没反应。**

这就是影说的「点快了还是会出现刚才的情况」：点得准（正好落在文字行上）就正常，点偏就什么也没发生。日志里 `focusItem` 一直是 `QQuickRootItem` 而不是 `QQuickTextEdit`，是直接证据。

修：`height: Math.max(flick.height - 22, implicitHeight)`。

### 8.5 最终方案：焦点释放放到 C++ 窗口层

QML 层做不可靠，原因很具体：

| 做法 | 为什么不行 |
|---|---|
| 页面根层 `MouseArea(z:-1)`（下载页用的） | **下载页能用**是因为它没有全屏 Flickable；版本设置页每个 pane 都是 `anchors.fill` 的 Flickable，**它把 press 吃掉了**，下层监听收不到 |
| 逐处调 `SField.blur()`（下载页配合用的） | 漏一处就失效，全站要改几十处 |
| `TapHandler` + `focusSink` | 同样被 Flickable 吃掉；而且 tap 有手势判定延迟（点快会漏） |
| `activeFocusItem.focus = false` | 对 FocusScope 链无效 |

最终：`src/main_release.cpp` 里 `FocusClearFilter` 装在 `QQuickWindow` 上，拦 `MouseButtonPress`——当前焦点是 TextInput/TextEdit 且按下的点不在它矩形内，就 `contentItem()->forceActiveFocus()`。

优点：**不依赖任何 QML 事件传播链**，全站一次生效，按下即判断没有延迟。日志 `[focus] 点空白释放文本焦点` 可验证。
