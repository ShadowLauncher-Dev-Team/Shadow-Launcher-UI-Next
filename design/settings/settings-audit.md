# 设置页调研与审计报告（2026-11-10）

> 目的：为「设置页」施工提供依据 —— 后端有什么可配、现在缺什么、哪些功能有缺陷。
> 结论先行：**全局设置页完全不存在**（侧栏点「设置」只是回到启动页）；后端 32 个设置项中 **26 个没有任何 UI 入口**；审计发现 **2 个高危 + 4 个中危 + 5 个低危** 缺陷。

---

## 一、现状

| 项 | 状态 |
|---|---|
| 全局设置页 | **不存在**。`StageShell.qml:227` 对「设置」的处理只是关掉其它全屏页，回到启动页 |
| 版本设置页 | 完整（`ui/pages/VersionSettingsPage.qml` + Vs*Pane 系列），版本级覆盖项都在 |
| 后端设置能力 | `SettingsBackend`：**32 个 Q_PROPERTY + 约 60 个 Q_INVOKABLE**，全部可用（QML 里 `b.settings()` 已验证能调） |
| 持久化 | 全部走 `QSettings(organizationName, applicationName)`（Windows 上是注册表 `HKCU\\Software\\<org>\\<app>`） |

---

## 二、后端能力全景（按功能域）

### 1. Java
`javaPath` / `javaVersion` / `javaMajor` / `javaReady`
`scanJavaInstallations()` / `autoSelectJava()` / `availableJavaList()` / `persistedJavaList()` / `selectJavaByIndex(i)` / `removeJavaFromList(i)` / `browseJava()` / `findJavaForVersion(major, maxMajor)`

### 2. 内存
`minMemoryMB` / `maxMemoryMB` / `autoMemoryEnabled` / `getMemoryStatus()`
版本级：`versionMemoryMode` / `versionMemoryManualMB`

### 3. 启动（全局默认）
`gcMode` / `processPriority` / `fullscreenEnabled` / `autoJoinServer` / `windowTitleOverride` / `preLaunchCommand` / `postExitCommand`

### 4. 下载
`fileDownloadSource` / `listDownloadSource` / `maxDownloadThreads`(1-24) / `downloadSpeedLimitMB`

### 5. 外观
`customBgPath` / `sidebarOpacity` / `contentOpacity` / `backgroundBlur`(0-1) / `cropX` / `cropY`

### 6. 其它 / 高级
`languageIndex` / `languageChanged` / `autoLangMode` / `windowWidth` / `windowHeight`
`isolationEnabled` / `migrateVersionToIsolated(id)` / `getVersionGameDir(id)` / `openGameDir()` / `openVersionDir(id)`
`embeddedLoginEnabled` / `modDepsTooltipEnabled`
`exportSettingsToFile(path)` / `importSettingsFromFile(path)` / `exportSettingsPreview()`

---

## 三、UI 覆盖缺口（26 / 32 无任何入口）

| 有 UI | 无任何 UI 入口 |
|---|---|
| javaPath、javaVersion、minMemoryMB、maxMemoryMB、customBgPath、gcMode（版本级） | **autoMemoryEnabled、isolationEnabled、embeddedLoginEnabled、languageIndex、languageChanged、sidebarOpacity、contentOpacity、backgroundBlur、cropX、cropY、fileDownloadSource、listDownloadSource、maxDownloadThreads、downloadSpeedLimitMB、autoLangMode、windowWidth、windowHeight、processPriority、fullscreenEnabled、autoJoinServer、windowTitleOverride、preLaunchCommand、postExitCommand、modDepsTooltipEnabled、exportSettingsToFile、importSettingsFromFile** |

> 注：`gcMode` / `preLaunchCommand` 等在**版本设置页**里有版本级入口，但**全局默认值**没有任何 UI 可改 —— 用户只能逐版本覆盖，没有"全局默认"这一层。

---

## 四、建议信息架构（6 页）

### 页 1 · 常规
- 语言选择（`languageIndex`）+ 跟随系统（`autoLangMode`，注意 `languageChanged` 是"需要重启"标志）
- 窗口尺寸（`windowWidth` / `windowHeight`）——建议做成「记住上次窗口尺寸」开关 + 数字输入
- **设置导入 / 导出**（必须带安全确认，见审计 F1）

### 页 2 · Java 与内存
- Java 路径：选择/扫描/自动检测 + 版本显示 + 就绪徽标
- 已装 Java 列表（可移除）
- 内存：min / max 双滑块（min ≤ max，且上限受物理内存约束）+ 自动分配开关
- `getMemoryStatus()` 显示物理内存总量与建议值

### 页 3 · 启动（全局默认）
- GC 模式（`gcMode` 枚举，需限定范围）
- 进程优先级（`processPriority` 枚举）
- 全屏（`fullscreenEnabled`）
- 自动进服（`autoJoinServer`，需格式校验）
- 窗口标题（`windowTitleOverride`）
- 启动前命令 / 退出后命令（`preLaunchCommand` / `postExitCommand`）—— **必须带醒目风险提示**（会经 cmd.exe 执行）

### 页 4 · 下载
- 文件下载源（`fileDownloadSource` 枚举）
- 资源列表源（`listDownloadSource` 枚举）
- 最大并发（1–24 滑块）
- 限速（`downloadSpeedLimitMB`，**0 = 不限速**，需修 F6）

### 页 5 · 外观
- 自定义背景（`customBgPath`，选图 + 预览 + 清除）
- 侧栏不透明度 / 内容不透明度（`sidebarOpacity` / `contentOpacity`，**需补 clamp**）
- 背景模糊（`backgroundBlur`）
- 裁剪偏移 X/Y（`cropX` / `cropY`）

### 页 6 · 高级
- 版本隔离（`isolationEnabled`）+ 单版本迁移（`migrateVersionToIsolated`）
- 内嵌登录（`embeddedLoginEnabled`）
- Mod 依赖提示（`modDepsTooltipEnabled`）
- 打开游戏目录（`openGameDir`）
- **危险区**：删除版本（`deleteVersion`，必须二次确认 + 显示目标路径，见审计 F2）

---

## 五、审计发现

### 🔴 F1（高危）导入设置可导致任意命令执行（RCE）

**证据链**：
1. `SettingsBackend::importSettingsFromFile`（settings_backend.cpp:831）把 ini 的所有键**直接写进 QSettings**；
2. 过滤只靠黑名单 `token / secret / password / key / beta`，**`launch/preLaunchCommand` 不含这些词 → 原样写入**；
3. 重启后 `loadSettings()` 读出 → `launch_backend` → `Launcher::runPreLaunchCommand()`（core/launcher.cpp:2011）；
4. 执行方式：
```cpp
p->setProgram("cmd.exe");
p->setNativeArguments("/c " + m_preLaunchCommand);   // 完整 shell 解析
```

**攻击场景**：分享一个"优化配置.ini"，用户导入 → 下次启动游戏执行任意命令。

**修复建议**（三选一，建议 1+2 同时）：
1. 导入改**白名单**（只接受已知设置键），而不是黑名单；
2. 命令类键（`preLaunchCommand` / `postExitCommand` 及其版本级）**默认不导入**，或在导入前弹窗逐条展示；
3. 导入后立即展示"将要应用哪些键"的预览（`exportSettingsPreview` 已有反向能力）。

### 🔴 F2（高危）`deleteVersion` 路径遍历 → 可递归删除任意目录

```cpp
void SettingsBackend::deleteVersion(const QString& versionId) {
    QString verDir = m_gameDir + "/versions/" + versionId;   // versionId 无任何校验
    if (QDir(verDir).exists()) forceRemoveDir(verDir);       // 递归删
    ...
}```

`versionId = ".."` → 删 `<gameDir>/versions/..` = **整个 gameDir**；
`versionId = "../../.."` → 删到 gameDir 的上级。

**修复**：
- 校验 `versionId` 为单个合法目录名（无 `/`、无 `\`、无 `..`、非空）；
- 用 `QDir::cleanPath` + 前缀校验，确保最终路径仍在 `<gameDir>/versions/` 之下；
- 删除前二次确认并显示绝对路径。

### 🟠 F3（中危）`loadSettings()` 不做边界校验，导入即可写入非法值

```cpp
m_minMemoryMB = s.value("memory/minMB", 512).toInt();    // 无 qBound
m_maxMemoryMB = s.value("memory/maxMB", 2048).toInt();  // 无 qBound
```

所有 setter 里的 clamp 在"导入 + 重启"路径上**全部被绕过**。恶意 ini 可写 `maxMB = 999999999` → 启动参数 `-Xmx999999999M` → JVM 直接起不来。

**实测（2026-11-10，注入注册表后重启）**：
```
注入:    memory.minMB = -5        memory.maxMB = 999999    launch.gcMode = 99
启动后:  memory.minMB = 4294967291  memory.maxMB = 999999    launch.gcMode = 99
```
- `maxMB` **没有被 clamp 到 32768**；
- `minMB = -5` 被按无符号读成 **4294967291**，于是 `min > max`，状态荒谬；
- `gcMode = 99` 原样保留。

**危害被"自动内存"掩盖**：`autoMemory = true` 时启动日志显示 `启动内存: 12123MB (auto=1)`，手动值不参与。所以实际触发条件是**关掉自动内存**（`autoMemoryEnabled` 目前没有 UI，只能靠导入或注册表改）—— 但设置页一旦加上"自动内存"开关，这条路就通了：关掉自动 + 非法值 = JVM 直接起不来。

**修复**：`loadSettings` 对所有数值项补与 setter 相同的 clamp，并保证 `min ≤ max`。

### 🟠 F4（中危）导出会 `clear()` 目标文件且无确认

```cpp
QSettings dst(path, QSettings::IniFormat);
dst.clear();   // 若用户选了一个已有 ini，内容被清空
```

**修复**：写前检查文件是否存在 → 提示"将覆盖"；或先写临时文件再原子替换。

### 🟠 F5（中危）`setDownloadSpeedLimitMB(0)` 变成 0.1 MB/s

```cpp
void setDownloadSpeedLimitMB(double v) { m_downloadSpeedLimitMB = (v < 0) ? -1.0 : qBound(0.1, v, 20.0); ... }```

语义是"负数 = 不限速"，但用户在 UI 里把滑块拖到 **0** 想表示"不限速"时，`0 < 0` 为假 → `qBound(0.1, 0, 20)` = **0.1**，等于限速到 100 KB/s（几乎断网）。

**实测**：注册表里"不限速"的真实值是 **`-1`**（本机现状 `download.speedLimitMB = -1`）。

**修复**：`v <= 0 ? -1.0 : qBound(0.1, v, 20.0)`，或 UI 用显式"不限速"开关直接映射到 `-1`（**不要用滑块 0 表示不限速**）。

### 🟡 F6（低危）透明度没有 clamp，与其它外观项不一致

`setSidebarOpacity` / `setContentOpacity` 直接赋值；而 `setBackgroundBlur` / `setCropX` / `setCropY` 都有 `qBound(0,1)`。
传 5.0 / -1 → 界面异常。

### 🟡 F7（低危）多个枚举项无范围校验

`setGcMode` / `setProcessPriority` / `setFileDownloadSource` / `setListDownloadSource` 全是裸赋值。传入越界值（如 99）会一路带到启动参数或数组索引。

### 🟡 F8（低危）`setAutoJoinServer` 无格式校验

该值最终拼进游戏命令行 `--server <addr>`。若含空格与 `--`（如 `x --username someonelse`），可给游戏塞额外参数。

**修复**：只接受 `host[:port]`，拒绝空格/引号。

### 🟡 F9（低危）敏感词黑名单 `"key"` 过宽

`key.contains("key")` 会命中任何含 "key" 的**合法**键（如将来加 `hotkey/...`），造成导入导出丢设置；同时对真正敏感但命名不含这些词的键（如 `account/lastUsername`）无效。

### 🟡 F10（低危）`versionId` 直接拼进 QSettings key

`s.value("versionMemory/" + versionId + "/mode")` —— 若 versionId 含 `/`，会污染命名空间（写入到别的组）。当前版本 id 来自目录名，风险低，但导入的设置可携带任意 id。

### 🟡 F11（低危）`setMaxMemory` 日志打的是原始输入

```cpp
m_maxMemoryMB = qBound(m_minMemoryMB, mb, 32768);
qCInfo(logUI) << "游戏内存: " << mb << "MB";   // mb 是输入，不是实际生效值
```
排查"我设了但没生效"时会被日志误导。

### 观察项（非缺陷）
- `minMemoryMB` 下限硬编码 256MB，上限 32768MB；`maxMemoryMB` 无"不超过物理内存"的约束 —— 设置页 UI 应基于 `getMemoryStatus()` 动态限制。
- `setWindowWidth/Height` 有范围（100–7680 / 100–4320）但未考虑当前屏幕尺寸。

---

## 六、待影决策

1. **设置页放哪**：独立全屏页（与下载页同级，侧栏「设置」进入）还是主页面内的一栏？现有侧栏已有「设置」项，建议做独立全屏页。
2. **导入导出保留吗**：保留则必须按 F1 白名单化；不保留则直接删掉这两个入口，减少攻击面。
3. **命令字段（启动前/退出后）要不要保留**：主流启动器都有，但有 RCE 面。保留则 UI 必须带风险提示 + 不参与导入。
4. **全局默认 vs 版本覆盖的关系**：现在用户只能在版本设置里逐版本改 GC/全屏/自动进服等，没有"全局默认"。设置页要做成"全局默认 → 版本可覆盖"吗？
5. **外观页（自定义背景/透明度/模糊/裁剪）现在就做还是后面做**：它牵连壁纸选择和预览交互，工作量明显大于其它页。

---

## 七、测试计划（待执行）

| # | 项 | 方法 | 状态 |
|---|---|---|---|
| T1 | 内存 clamp（setter 路径） | 调 setMin/setMax 传越界值，读回 | 待测 |
| T2 | 内存 clamp（load 路径 F3） | 注入 maxMB=999999 / minMB=-5 → 重启 → 读回 | ✅ **失败（确认缺陷）**：999999 未 clamp；-5 读成 4294967291 |
| T3 | 命令注入（F1） | 构造含 preLaunchCommand 的 ini → 导入 → 检查 QSettings 是否写入（**不实际执行**） | 待测 |
| T4 | deleteVersion 遍历（F2） | 只做路径拼接断言，**绝不实际删除** | 待测 |
| T5 | 限速 0 值（F5） | 代码断言 + 读现状值 | ✅ **确认**：现状 -1 是不限速；传 0 会变 0.1 |
| T6 | 枚举越界（F7） | 注入 gcMode=99 → 重启 → 读回 | ✅ **失败（确认缺陷）**：99 原样保留 |
| T7 | 导入导出往返 | 导出 → 改值 → 导入 → 值应恢复 | 待测 |
| T8 | 语言切换是否需要重启 | 切 languageIndex 看 languageChanged | 待测 |

> T1–T8 需要额外收益才值得做：**F1/F2 已由代码证据充分证明**，不必真去执行命令或删目录。建议 T2/T5/T6/T7 用真实调用验证（安全、无副作用），T3/T4 保持静态结论。
