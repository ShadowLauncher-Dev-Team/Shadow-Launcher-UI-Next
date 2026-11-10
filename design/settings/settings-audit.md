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

## 五·补、自检实证结果（`--ui-selftest-settings`）

为避免只靠读代码下结论，项目增加了设置自检钩子：启动时调用真实的 `SettingsBackend`，把断言结果打进日志。

```
ShadowLauncher.exe --ui-next --ui-selftest-settings
```

**2026-11-10 实测输出**（跑前 `reg export` 备份、跑后 `reg import` 恢复，已确认恢复为 minMB=512 / maxMB=2304 / auto=true / gcMode=0 / speedLimit=-1）：

| 断言 | 期望 | 实际 | 结果 |
|---|---|---|---|
| `importSettingsFromFile` | true | true | PASS |
| **F1 导入后的 preLaunchCommand** | 空（应拒绝） | **`echo SELFTEST_MARKER`** | **FAIL** |
| F3 导入后的 maxMB | ≤ 32768 | **999999** | FAIL |
| F3 导入后的 minMB | ≥ 256 | **-5** | FAIL |
| F7 导入后的 gcMode | 0..3 | **99** | FAIL |
| T1 `setMaxMemory(999999)` | 32768 | 32768 | PASS |
| T1 `setMinMemory(-5)` | 256 | 256 | PASS |
| F5 `setDownloadSpeedLimitMB(0)` | -1 或 0.1 | **0.1** | FAIL |
| F7 `setGcMode(99)` | 0..3 | **99** | FAIL |
| T7 导出 → 改 → 导入 往返 | 恢复原值 | 恢复原值 | PASS |
| T8 切语言后 languageChanged | true | true | PASS |

### 这组数据的意义

**T1 PASS 而 F3 FAIL** —— 两者对比直接锁定问题位置：

- **setter 路径是好的**（`setMaxMemory(999999)` 确实变成 32768）；
- **导入 / 加载路径完全绕过校验**（同一份数据经 ini 导入后保留 999999）。

所以修复不用动所有 setter，只需在 **F1 导入（白名单）** 和 **F3 `loadSettings`（补 clamp）** 两处收口。

**F1 的实证细节**：ini 里写的 `echo SELFTEST_MARKER` 原样进入了 `preLaunchCommand`。本次自检**没有真的启动游戏**，所以命令未被执行；但链路已确认 —— 用户下次点启动时 `cmd.exe /c echo SELFTEST_MARKER` 就会跑。


---

## 五·补2、修复记录（2026-11-10）

> 影的决定：设置页做成独立全屏页；**导入导出整个后端逻辑删除**；启动前/退出后命令保留；建立「全局默认 → 版本覆盖」两层；外观页独立、后端准备重写。
> 本轮先把后端问题修完（预备删除的除外）。

| 编号 | 修复内容 | 验证方式 | 结果 |
|---|---|---|---|
| **F1/F4/F9** | **删除** `exportSettingsToFile` / `importSettingsFromFile` / `exportSettingsPreview`（SettingsBackend + ShadowBackend 转发 + 头文件声明全部移除） | 构建通过；攻击链从源头消失 | ✅ 已删除 |
| **F2** | `deleteVersion` 双重校验：`isSafeVersionId()`（拒空/`.`/`..`/路径分隔符）+ `QDir::cleanPath` 前缀确认目标仍在 `<gameDir>/versions/` 下 | `isSafeVersionId` 由 F10 断言实证有效；不实际调用以免误删 | ✅ 已修 |
| **F3** | `loadSettings` 全量 clamp：内存（256..32768 且保证 min≤max）、语言(0..8)、autoLangMode(0..2)、透明度/模糊/裁剪(0..1)、窗口尺寸(100..7680 / 100..4320)、gcMode(0..3)、processPriority(0..2)、下载源(0..2)、限速(≤0→-1) | **跨进程**：注入非法值→重启→读回 | ✅ 全部夹回 |
| **F5** | `setDownloadSpeedLimitMB`：`v < 0` → `v <= 0`，0 表示不限速 | 自检 | ✅ 0 → -1 |
| **F6** | `setSidebarOpacity` / `setContentOpacity` 加 `qBound(0,1)` | 自检 | ✅ 5.0→1 / -1→0 |
| **F7** | `setGcMode`(0..3) / `setProcessPriority`(0..2) / `setFileDownloadSource`(0..2) / `setListDownloadSource`(0..2) 加范围 | 自检 | ✅ 99→3 / 99→2 / 9→2 / -3→0 |
| **F8** | `setAutoJoinServer` 加 `isSafeServerAddress()`：只接受 `[A-Za-z0-9._:-]{1,255}`，非法**拒绝**（不静默存下）；`loadSettings` 读历史值时同样校验，非法丢弃 | 自检 | ✅ 非法地址被拒 |
| **F10** | 新增 `isSafeVersionId()`，19 处 `setVersion*` 写盘前校验 | 自检 | ✅ `../evil` 被拒 |
| **F11** | `setMaxMemory` 日志改为「请求=X 生效=Y」 | 代码审查 | ✅ 已修 |

### 修复后的自检输出（`--ui-selftest-settings`，2026-11-10 13:50）

```
T1 setMaxMemory(999999)         期望=32768   实际=32768   PASS
T1 setMinMemory(-5)             期望=256     实际=256     PASS
F5 setDownloadSpeedLimitMB(0)   期望=-1      实际=-1      PASS
F5 setDownloadSpeedLimitMB(30)  期望=20      实际=20      PASS
F6 setSidebarOpacity(5.0)       期望=1       实际=1       PASS
F6 setContentOpacity(-1)        期望=0       实际=0       PASS
F7 setGcMode(99)                期望=3       实际=3       PASS
F7 setProcessPriority(99)       期望=2       实际=2       PASS
F7 setFileDownloadSource(9)     期望=2       实际=2       PASS
F7 setListDownloadSource(-3)    期望=0       实际=0       PASS
F8 合法地址应保留               期望=mc.example.com:25565  实际=mc.example.com:25565  PASS
F8 非法地址应被拒绝             期望=mc.example.com:25565  实际=mc.example.com:25565  PASS
F10 setVersionMemoryMode(../evil) 期望=0     实际=0       PASS
T8 切语言后 languageChanged     期望=true    实际=true    PASS
```

### 跨进程 clamp 验证（注入 → 重启 → 读回）

```
minMB      -5      → 256
maxMB      999999  → 32768
gcMode     99      → 3
priority   99      → 2
fileSource 9       → 2
sidebarOp  5.0     → 1
autoJoin   'srv --username evil' → (空，被丢弃)
```

### 仍然保留、需要设置页 UI 兜的
- `maxMemoryMB` 上限 32768 仍与物理内存无关 —— 设置页应按 `getMemoryStatus()` 动态限制。
- `preLaunchCommand` / `postExitCommand` 仍经 `cmd.exe /c` 执行（这是功能本身），UI 必须带风险提示。
- `languageIndex` 的合法上限 8 是保守估计（当前实际用 0..2），做语言页时以真实语言表为准。

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
| T1 | 内存 clamp（setter 路径） | 调 setMin/setMax 传越界值，读回 | ✅ **通过**：32768 / 256 |
| T2 | 内存 clamp（load 路径 F3） | 注入 maxMB=999999 / minMB=-5 → 重启 → 读回 | ✅ **失败（确认缺陷）**：999999 未 clamp；-5 读成 4294967291 |
| T3 | 命令注入（F1） | 构造含 preLaunchCommand 的 ini → 导入 → 检查是否写入（**不实际执行**） | ✅ **失败（确认 RCE 链）**：`echo SELFTEST_MARKER` 原样写入 |
| T4 | deleteVersion 遍历（F2） | 只做路径拼接断言，**绝不实际删除** | ✅ 静态确认（路径未校验） |
| T5 | 限速 0 值（F5） | 代码断言 + 读现状值 | ✅ **确认**：现状 -1 是不限速；传 0 会变 0.1 |
| T6 | 枚举越界（F7） | 注入 gcMode=99 → 重启 → 读回 | ✅ **失败（确认缺陷）**：99 原样保留 |
| T7 | 导入导出往返 | 导出 → 改值 → 导入 → 值应恢复 | ✅ **通过** |
| T8 | 语言切换是否需要重启 | 切 languageIndex 看 languageChanged | ✅ **通过**：置 true |

> T1–T8 已全部执行。F1 实证到「值被写入」这一步（未执行命令），F2 保持静态结论（不冒险删目录）。
