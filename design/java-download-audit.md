# Java 下载 —— 后端实现调研与缺陷排查（第 1 步）

> 日期：2026-11-06 · 分支：main · 结论基于**真机实测 + 代码审查**，每条都标明证据来源。
> 目的：为「下载页 → Java」新页面定基线；同时排查 Forge/启动流程里已有的 Java 下载。

---

## 一、现状：Java 下载有三条独立通路

| # | 入口 | 实现 | 用什么下载 | 落盘位置 |
|---|------|------|-----------|---------|
| A | 设置页／新 Java 页（手动） | `JavaBackend`（`java_backend.cpp`） | `FileDownloader`（单线程） | `QDir::currentPath()/java_cache` ← **错** |
| B | 一键安装「所需 Java」 | `JavaRuntimeInstaller` | `HttpClient::downloadWithReply`（>4MB 分片 8 连接） | `applicationDirPath()/java_cache/{major}` |
| C | 启动 / Forge·NeoForge·OptiFine 安装时缺 Java | `ModLoaderInstaller::downloadAndExtractJava` | **裸 QNetworkReply + QEventLoop，单连接，180s 超时** | `applicationDirPath()/java_cache/{major}` |

三条路各写一遍"列目录 → 抓 zip → 解压"，**行为不一致**（只有 B 有分片/重试/取消）。

版本策略：A 跟随用户选择（8/11/17/18/19/20/21/25 × jdk/jre × x64/x32）；B、C 固定 **JDK**（2026-08-17 起，因为 Adoptium JRE 裁掉了 `jdk.crypto.ec`，NeoForge 1.21.8+ 会崩）。

---

## 二、实测记录（今天 22:5x）

### 1. 镜像数据完整性（18 条 URL 全扫）

| 路径 | 结果 |
|------|------|
| 8/11/17/21/25 × jdk/jre × **x64**/windows | 全部 200，各 1 个 zip |
| 8/11/17 × jdk/jre × **x32**/windows | 全部 200（8u472b08 / 11.0.29 / 17.0.17） |
| **21、25 × x32** | **404 —— 镜像没有 32 位构建** |

### 2. 镜像的 UA 风控（重要）

| 请求 | 结果 |
|------|------|
| 不带 User-Agent | **403 Forbidden** |
| `Mozilla/5.0 (Windows NT 10.0; Win64; x64)` | **403 Forbidden** |
| `ShadowLauncher/1.0` | 200 / 206 ✓ |
| `Mozilla/5.0 ShadowLauncher/1.0` | 200 ✓ |

→ 目前三条通路都显式设了 `ShadowLauncher/1.0`，**这条暂时安全**；但一旦有人把 UA 改成浏览器串就会全线 403。

### 3. 8 并发 Range 压测（源站限速探针）

8 并发 × 1.5MB × 3 轮 = 24 个 206，全部成功、无 429。→ 分片下载本身不会被源站拒绝。

### 4. 下载页通路（A）真机全流程

`/eval` → `javaBackend.downloadJavaFileTo("OpenJDK8U-jdk_x64_...zip", "D:/tmp/javatest", 106457258)`

```
[夸父] 线程完成 字节=106457258
[夸父] 合并完成 SHA1校验=通过
[夸父] [完成] 下载完成: 1/1 文件, 101.5 MB, 速度 47.3 MB/s
```
→ **A 的下载引擎是好的**（单线程 47MB/s）。

### 5. 一键安装（B）真机

`javaBackend.installRequiredJavas()` →

```
全部 Java 就绪（已安装 0 个，跳过 3 个）
```

因为系统检测到 4 个 Java：21.0.12(C:\\21)、17.0.20(Program Files)、25.0.1(MC 官方 runtime)、1.8.0.51(MC jre-legacy)。→ **跳过逻辑是对的**；也意味着本机无法直接验证 B 的下载段（需要干净环境）。

### 6. 关键实测发现：安装目录不一致

```
backend.javaBackend.javaInstallDir() = D:/latest-code/shadow-v2/java_cache
```
而 B/C 与 `findJavaPath` 扫描的是 `<exeDir>/java_cache` = `build/Release/java_cache`（当前为空）。
两个目录**不是同一个**。

---

## 三、缺陷清单（按严重度）

### P0-1 A 通路落盘目录是 `QDir::currentPath()`，不是 exeDir ★实测确认
`src/backend/java_backend.cpp:306-310`
```cpp
QString JavaBackend::javaInstallDir() const {
    return QDir::currentPath() + "/java_cache";   // ← 进程工作目录
}
```
- 从桌面快捷方式（Start in 为空/别处）、从别的程序拉起、或调试时 CWD 不同 → **页面下载的 Java 落在别处**，启动器永远说"没装 Java"。
- 这就是"下载了但没用"的典型观感，容易被当成"下载失败"。
- 修：统一 `QCoreApplication::applicationDirPath()`（B/C 已经是）。

### P0-2 `installJavaAsync` 可重入，`m_job` 没有占用保护
`src/core/java_runtime_installer.cpp:612-623`（入口直接 `m_job = InstallJob{}`）
- 场景：设置页点"一键安装 Java"的同时，用户点了启动 → `installJavaForLaunch` 也进来 → `m_job` 被覆盖，前一次的 `onDone` 永远不回调 → 界面永久"正在安装"，且 `m_running` 卡 true。
- 修：入口判 `m_job.lock`/新增 `m_jobActive`，忙时直接回调失败（"已有 Java 安装任务在进行"）。

### P0-3 C 通路（Forge 缺 Java 时）是最脆的一段
`src/core/mod_loader_installer.cpp:2741-2764`
```cpp
zipTimer.start(180000);          // 190MB 需要 ≥1.06MB/s
...
QByteArray zipData = zipReply->readAll();   // 整包进内存（JDK17 = 190MB，峰值 ~400MB）
```
- **无分片、无重试、无镜像兜底、无断点续传**；一次抖动 = Forge 安装整体失败，提示"自动下载失败，请先在设置里下载 Java"。
- 与 B 是同一件事的第二套实现（B 有分片+重试+取消）。
- 修：把 C 改成调用 B 的 `installJavaAsync`（同锁、同缓存、同校验），删掉这套阻塞实现。

### P1-4 分片任一失败 → 整体失败，不降级单连接
`src/core/http_client.cpp:585-592` 与对比 `:464-474`（探测失败会降级）
- Java 大包（141-190MB，8 片）最容易踩；慢片/单连接被重置就整单失败。
- 修：`finishAll(false, ...)` 之前先尝试"整包单连接重下"一次（已有 `startSingle`）。

### P1-5 启动时"清理残留"可能删掉刚装好的 Java
`java_runtime_installer.cpp:55-91`（构造即执行，主线程同步）
- 对每个数字目录跑 `verifyJavaMajor`（`java -version`，`waitForFinished(8000)`）→ 超时返回 0 → 判"残缺"→ `removeRecursively()`。
- 冷盘/杀软正在扫新解压的 190MB JDK 时，8 秒很容易不够 → **下次启动把好 Java 删了**；用户观感"装了又没了"。
- 修：清理只在"有 .tmp zip 或 java.exe 不存在"时执行；版本/完整性不明时**不动**（宁可留）。

### P1-6 32 位系统上 21/25 必然失败，文案误导
- 实测 `21/x32`、`25/x32` = 404。
- `stepFetchZipList` 报"获取 Java 21 文件列表失败: ..."，用户不知道是"镜像无 32 位构建"。
- 修：x32 且 major ≥ 21 → 直接给出明确文案（不支持/建议装 17）。

### P1-7 「取最后一个 zip = 最新」靠字符串序猜
`java_runtime_installer.cpp:724`、`mod_loader_installer.cpp:2737`
- 镜像里多补丁版本共存时（历史出现过 `8u472` 与 `8u504` 并存）字符串序恰好对；但一旦出现 `..._8u99` 与 `..._8u504` 就选错。
- 修：从文件名里抓 `8u(\d+)|(\d+)\.(\d+)\.(\d+)` 比数值。

### P2-8 页面取消不真取消
`java_backend.cpp:359-367`：`deleteLater()` 后网络回复仍活着，再点下载会往同一路径写 → 半截文件。
修：用 `FileDownloader` 的取消/或落 `.part` 再改名。

### P2-9 页面只会"下载 zip 到文件夹"，没有解压/校验/登记
新页面要可用，必须补：解压到 `java_cache/{major}` + `verifyJavaMajor`/`isJavaComplete` 校验 + 失败清理（复用 B 的 `installJavaAsync` 最省事）。

### P2-10 `hasCryptoEcModule` 对 Java 8 恒 true
`java_runtime_installer.cpp:568-569`。影响小（Java 8 无模块裁剪），记录在案。

---

## 四、对新 Java 页（第 2、3 步）的直接影响

1. **页面的"下载"必须落到 `applicationDirPath()/java_cache`**，否则与启动器扫描脱节（P0-1）。
2. 页面需要的能力，后端目前缺：
   - 已安装列表（major / 类型 / 路径 / 是否完整）
   - 单版本"安装"（下载→解压→校验→登记），而不是只下载 zip
   - 真取消 + 进度（A 已能报进度，缺取消）
   - 删除某个缓存 Java
3. 现有 `javaVersions/javaTypes/javaArchs/javaOSes/javaFiles` 级联查询可用（实测 8 个版本、2 个文件）。

---

## 五、建议的修复顺序（等确认后执行）

1. P0-1 目录统一（1 行级）
2. P0-2 安装互斥（`m_jobActive`）
3. P0-3 C 通路改走 B（删掉阻塞实现）
4. P1-4 分片失败降级单连接
5. P1-5 清理逻辑收紧
6. P1-6/1-7 文案与版本排序
7. P2-8/2-9 页面取消 + 安装能力

> 以上 1–6 属于"后端 bug 修复"，可直接做；7 属于新页面所需能力，建议与第 3 步一起做。
