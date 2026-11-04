# 下载契约（DOWNLOAD_CONTRACT）草案 v0

> 状态：**待确认**（词表与"是否收敛成一个引擎"两件事需要影拍板）
> 依据：2026-11-05 只读调研（引擎层 / 整合包链 / 安装管线），以及仓库里既有的
> `下载引擎整改调研报告_2026-08-01.md`、`重构方案-下载进度显示.md`、`竞态诊断.md`。
> 目的：把"步骤、进度、速度、状态机、取消、重试"六件事定义成**可测试的不变量**，
> 之后所有修复都按这份契约来，不再各引擎各自打补丁。

---

## 0. 六条不变量（违反即 bug，不看感受）

1. **单一真相**：一个下载任务只有一个步骤模型、一个进度值、一个速度值。禁止"StepNode 管线 + QVariantList 双写"。
2. **进度单调**：任务内总进度只增不减；重建步骤、镜像回退、分母补差都不得让进度回退。
3. **完成 = 全部成功**：`finished(success)` 只在"目标文件全部存在且校验通过"时发出；有失败就是 `finished(false, failures)`。
4. **速度单源**：整个程序只有一处计算速度（传输层上报累计字节 + 时间），上层只做显示格式化，不再二次平滑/相加/减半。
5. **取消幂等**：`cancel()` 之后不再有任何进度/完成信号，任务对象可安全复用；`cancel()` 必须真正中止在途请求。
6. **终态不可逆**：`completed / failed / cancelled` 不得被后续事件改回 `active`。

---

## 1. 步骤词表（key 是契约，中文名只是默认显示）

key 不带流程前缀，**原版 / 加载器 / 整合包三条路径共用**；UI 按 key 查显示名。

| key | 默认显示名 | 说明 | 出现在 |
|---|---|---|---|
| `meta.resolve` | 解析整合包 | 读 manifest / index.json | 整合包 |
| `meta.overrides` | 解压整合包配置 | 本地解压，不走网络 | 整合包 |
| `base.json` | 下载版本信息 | version JSON | 原版 / 加载器 / 整合包 |
| `base.libraries` | 下载支持库 | libraries | 三路共用 |
| `base.assets` | 下载资源文件 | assets / index | 三路共用 |
| `base.jar` | 下载游戏本体 | client.jar | 三路共用 |
| `loader.installer` | 下载装载器安装器 | Fabric/Forge/OptiFine 安装器本体 | 加载器 |
| `loader.libs` | 下载装载器库 | 安装器依赖库 | 加载器 |
| `loader.install` | 安装装载器 | 运行安装器 | 加载器 |
| `mods.download` | 下载模组 | CF/MR 条目 | 整合包 |
| `mods.verify` | 校验下载结果 | sha1 / 大小 | 整合包 |
| `java.check` | 检查 Java | 版本探测 | 安装前 |
| `java.install` | 安装 Java | 自动补全 | 安装前 |
| `userdata.import` | 导入用户数据 | 可选 | 整合包 |

**禁止**：再造 `下载原版支持库文件` / `下载支持库` 这类同义不同名的字符串；同一 key 只允许一个默认显示名。
**权重**：每个 key 在任务里带 `weight`，总进度 = Σ(weight × 该步完成度) / Σweight，权重表集中在一处（`StepWeights`），不许散落在各安装函数里。

---

## 2. 状态机

```
pending ──► active ──► completed
   │           ├────► failed
   └───────────┴────► skipped     (隐藏步骤 / 无需要)
任务级：idle ─► running ─► (completed | failed | cancelled)
```

- 回退（completed → active）**非法**；现有 `showStep` 的保护要覆盖所有写入点。
- 任务级终态只能写一次；重复的 `finish` 调用直接丢弃并记日志（当前 `AssetDownloader::cancel` 与 `checkAllFinished` 有重复发 `allFinished` 的路径）。

---

## 3. 进度

- 总进度：`progress = max(prev, weighted)`（单调钳制），**重建步骤时保留 prev**，不再 `m_rawTotalProgress = 0`（`version_backend.cpp:6793-6794`）。
- 分母：任务开始时锁定总字节；后续若发现真实大小更大，只允许**上调分母**并把已完成字节同步上调，不得让百分比下降。
- 缓存命中：算"已完成"，但**不计入速度**（`AssetDownloader` 已有该规则，要推广）。
- 失败：不从完成数里加一（修 `asset_downloader.cpp:950-955`）。
- 单文件重下（镜像回退）：不得清零已完成字节（修 `version_downloader.cpp:1128-1129`）。

---

## 4. 速度

- **唯一来源**：传输层每 500ms 上报 `(bytesDelta, elapsedMs)` → 单次 EMA（α=0.3，窗口 2s）→ `bps`。
- 上层（VersionBackend / DownloadSession / 整合包任务）**只接收 bps**，禁止再平滑、再相加、再减半。
- 删除：`version_backend.cpp:3124-3153`（二次 EMA）、`:5425-5430`、`:5929-5933`、`modpack_install_task.cpp:71`（无数据减半）、`java_backend` 读引擎 MB/s 的旁路。
- 空闲：1.5s 无新字节 → 速度归零（不是衰减）。
- 单位：内部一律 `bytes/s`；格式化只在 QML（`KB/s` / `MB/s`，一位小数）。

---

## 5. 取消

- `cancel()`：置 `Cancelled` → **abort 所有在途 reply**（现在 `FileDownloader::pause()` 只停定时器，`file_downloader.cpp:247-253`）→ 清队列 → 删 `.tmp` → 发一次 `finished(false, cancelled)`。
- 之后：任何 in-flight 回调都必须早退（按 `m_state == Cancelled` 判断），不得再改步骤/进度。
- 复用：`start()` 前必须把 `cancelled / running / pending / failed 集合` 全部复位（对应整合包 `ModpackDownloader::start` 的漏清，`modpack_downloader.cpp:159-177`）。
- 卡死兜底：任务级看门狗 60s 无任何字节 → 判失败并复位 `m_running`（现在 `start()` 撞上 `m_running` 会静默 return，`:159-162`）。

---

## 6. 错误与重试（三层，职责不同）

| 层 | 责任 | 规则 |
|---|---|---|
| 传输层 | 单次请求 | 连接超时 / 首包超时 / 空闲看门狗；**读 HTTP 状态码**：429/503 读 `Retry-After`，指数退避（1→2→4s，上限 30s）；403/404 立即换源 |
| 文件层 | 单个文件 | 每文件独立重试预算 5 次，间隔 5/10/15/20s；重试前**完整复位**（含续传状态）；耗尽后进 `failedSet`，留给"补下"入口 |
| 任务层 | 一批/一包 | 批次 API 失败**不得作废整包**：批次级重试 2 次 + 退避；只有确定性错误（manifest 无效、404 源全无）才整体失败 |

- 校验：有 sha1 比 sha1；无 sha1 比大小；**大小未知不得直接判定成功**（现在 `mod_download_engine.cpp:419-433` 的非空即过要改）。
- 部分失败：任务结束状态必须是 `failed(failures=[...])`，并保留已完成文件；UI 给"重试失败项"入口（现在只能整包重来）。

---

## 7. 目标结构（A 方案：收敛成一个引擎）

```
DownloadTask（任务：步骤模型 + 进度 + 状态机 + 取消）
   └─ Transport（唯一传输层：QNAM 单例、分片、重试、退避、限速、看门狗、速度上报）
         ▲
         ├─ BaseInstaller   （产 base.json / libraries / assets / jar 条目）
         ├─ LoaderInstaller （产 loader.* 条目）
         ├─ ModpackInstaller（产 meta.* / mods.* / overrides 条目）
         └─ JavaInstaller   （产 java.* 条目）
```

- 只有 `Transport` 碰 `QNetworkAccessManager`；现在夸父"每线程一个 QNAM"（`file_downloader.cpp:684`）是连接爆炸的根因。
- 并发默认 16（上限 24），每 host 8；镜像单独限额并遵守 429。
- 七个引擎收敛为：Transport + 4 个 Installer（任务类型）。

---

## 8. 五条验收用例（先写脚本/自检，再改代码）

1. **单调**：任意时刻采样总进度，序列必须非递减（模拟镜像回退、分母补差、步骤重建）。
2. **真完成**：把 1 个文件改成永远 404，任务必须以 `failed` 结束，且**不得**出现 100% 完成。
3. **取消幂等**：`cancel()` 后统计信号，`finished` 恰好一次，之后 0 条进度信号；再 `start()` 一次能正常跑完。
4. **速度单源**：注入固定速率假服务器（如 2MB/s），UI 速度读数在 ±20% 内，且换页/换卡片不跳变。
5. **批次容错**：模拟 CF 批次接口 429 两次后成功，整包仍能安装完成（不得回滚）。

---

## 8.5 已定位的 P0 挂死（不依赖契约，先修，1–3 行级）

调研（安装管线）逐行确认，这三个是"进度中途卡死"的直接原因：

| # | 现象 | 位置 | 改法 | 状态 |
|---|---|---|---|---|
| H1 | 自动修复成功后合并安装不续跑（停在半装态） | `version_backend.cpp:274-275`（同型 294-295） | 先取值再 `clear()`：`QString ver = m_autoRepairVersionId; m_autoRepairVersionId.clear();` | ✅ 已修 |
| H2 | 校验步骤永远等不到 `verifyFinished` | `version_backend.cpp:3811-3817`（并发守卫直接 return） | 改成**排队**：记 `m_pendingVerifyId`，当前校验清理后自动补跑（不能发 false——verifyFinished 不带版本号，会让别人的链路误判失败） | ✅ 已修 |
| H3 | 加载器侧静默退出，MC 完成分支两边都不进 → 永挂 | `version_backend.cpp:5527` + `2159-2171` | 未找到 session 时置 `ctx->failed`、`mcDownloadDone` 并走 `finishInstall` 失败收尾 | ✅ 已修 |

另有两条"次致命"：
- `mod_loader_installer.cpp:1880-1897,1986` `finishLibs` 非幂等，取消后同一轮可重复发 `installerLibsDone/Failed`。
- `version_downloader.cpp:878-882` 双旗标（`m_libTasksDone && m_assetTasksDone`）缺一即永久等待，且**无超时**。

## 8.6 步骤名称即路由协议（必须一起改）

- 事件路由靠中文子串：`findStepByName 6883-6892`、`findLoaderVerifyStep 6904-6914`（含"完整性"且排除"资源"）、`findLoaderInstallStep 6916-6926`（含"安装"且排除"安装器库"）。
- 步骤索引被硬编码：MC 校验恒为 `idx=3`（`1046/2019/2153/2790`），但 OptiFine 步骤表 `5747-5754` 的 idx=3 是"下载 OptiFine 主文件"→ 会把主文件当校验步骤标完成。
- 同义步骤权重不一致：libraries 纯原版 3.0 vs 合并 8.0（`734-738` vs `5368-5378`）。
- **结论**：S0 定稿词表时必须同时把"按名字找步骤"换成"按 key 找步骤"，否则改名会直接改坏路由。

## 9. 迁移顺序（每步都能独立验收）

| 阶段 | 内容 | 关键文件 |
|---|---|---|
| S0a | **先修 3 个 P0 挂死（H1/H2/H3）+ 看门狗**（不依赖契约，能立刻见效） | `version_backend.cpp:274/3811/5527`、`version_downloader.cpp:878` |
| S0 | 本契约定稿 + 词表落地（`StepKeys` 单一来源）+ 路由改按 key | `step_pipeline.*`、`version_backend.cpp:735/5343/5748`、`6883-6926` |
| S1 | 传输层收敛：单例 QNAM + 并发上限 + HTTP 状态码退避 + 速度单源 | `file_downloader.cpp:684`、`asset_downloader.cpp`、`version_backend.cpp:3124` |
| S2 | 文件级重试 + 失败不计完成 + 取消真中止 | `file_downloader.cpp:1235/1303/247`、`asset_downloader.cpp:950` |
| S3 | 增量安装 + "补下失败项" + 部分失败语义 | `modpack_install_task.cpp:516/530`、`modpack_downloader.cpp:159/591` |
| S4 | 进度单调 + 步骤双写消除 | `version_backend.cpp:6766-6790/6793` |
| S5 | UI 下载页 / 整合包导入页（接稳定契约） | `ui/` 新增 |

---

## 11. 下载设置：每项必须有消费点（2026-11-05 接线审查）

旧 UI「下载设置」共 4 项。逐项追到消费点后，**只有 1 项完全生效**：

| 设置 | 存储键 | 声称的消费点 | 实际状态 |
|---|---|---|---|
| 文件下载源 `fileDownloadSource` | `download/fileSource` | VersionDownloader 选源（`version_downloader.cpp:280/490`） | ✅ 版本安装生效；❌ 模组/整合包（精卫）不读——`ModDownloadEngine::setSourcePolicy` **从未被调用** |
| 列表下载源 `listDownloadSource` | `download/listSource` | 只写进 `DownloadConfig::listSource`（`version_backend.cpp:885`） | ❌ **完全悬空**：全仓库没有任何读取点 |
| 下载线程数 `maxDownloadThreads` | `download/threadLimit` | `cfg.maxWorkers` → FileDownloader / AssetDownloader（`:887`） | ✅ 生效，但默认 64 过高；精卫固定 12 不读设置 |
| 限速 `downloadSpeedLimitMB` | `download/speedLimitMB` | AssetDownloader 有闸门（`asset_downloader.cpp:758`） | ⚠️ 半悬空：FileDownloader 只 `setSpeedLimitMB` 存值、**从不读取**（`file_downloader.h:107`），大文件下载不受限 |

### 强制规则（施工时逐条验收，违反就是返工）

1. **一个设置 = 一个消费点**，并在代码注释里写明"生效时机"（立即 / 下次任务）。
2. **没接线就删掉**，不做"看起来能调"的滑杆。宁可少一项，不可假一项。
3. 每个设置必须有**可观测验收**：
   - 限速 → 假服务器固定码率，实测吞吐落在设定值 ±20%；
   - 线程数 → 抓同时在途请求数峰值；
   - 源策略 → 抓请求 host 分布（官方/镜像比例）。
4. 设置写入要能落到运行时：现在 `DownloadConfig` 只在下载器创建时读一次，**运行中改设置不生效**
   → **已定（2026-11-05 影）**：采用"**下次下载生效**"。设置页每项旁标注这句，
   不做令牌桶热更新；任务开始时统一读一次配置快照即可。

### 源策略的三个域（2026-11-05 影澄清，禁止混用）

「版本列表源」**只指 MC 版本清单**，不能拿去管模组列表。三个域的源完全不同：

| 域 | 官方 | 镜像 | 谁管 | 设置项 |
|---|---|---|---|---|
| **MC 版本清单** | Mojang `launchermeta/piston-meta`、`version_manifest` | BMCLAPI `bmclapi2.bangbang93.com` | `VersionBackend` 列表/JSON/资源索引 + 加载器元数据（Forge/Fabric/NeoForge/OptiFine meta，`shadow_backend.cpp:4002/4102/4262/4463`） | **`listDownloadSource`（版本列表源）→ 接这里** |
| **模组/光影平台** | Modrinth API、CurseForge API | MCIM `mod.mcimirror.top` | `ResourceFetchEngine` / `CfApi` / `ModpackDownloader` | **不加用户设置**：MCIM 稳定性不足，用户选它=自己踩坑。改成内部策略：官方优先，MCIM 仅作并发探测/失败降级 |
| **文件 CDN** | Mojang `libraries.minecraft.net`、CF edge 域名 | BMCLAPI files、MCIM `/files` | `FileDownloader` / `AssetDownloader` / `ModDownloadEngine` | `fileDownloadSource`（文件下载源）→ MC 文件；模组文件走"官方 CDN 变体自动展开"（`expandCfDownloadUrls`），也不加设置 |

**现状问题（要在 S1 一并处理）**：模组搜索目前是**硬编码 MCIM 优先**（`resource_backend.cpp:613` 起十余处全是 `mod.mcimirror.top/modrinth/v2/search`，`cf_api.cpp:25` 同样镜像优先）→ MCIM 一挂，搜索整块不可用。改为"官方优先 + MCIM 降级"，并加 30s 健康探测缓存，避免每次请求都先撞一次镜像。

### 四项设置的消费点与验收（2026-11-05 实测版）

| 设置 | 真实消费点 | 验收方法 | 状态 |
|---|---|---|---|
| 文件下载源 `fileSource` | `VersionDownloader` 选镜像对象（jar/libs/assets 的 host）；加载器安装器库下载 | 改档后 `backend.downloadSourceSummary()` 的 preferOfficial 变化；装一次原版看日志 host | ✅ 已接（既有），未逐档实测 |
| 版本列表源 `listSource` | `VersionManager` 版本清单主源/兜底源；整合包导入的 MC 版本清单 | `/eval`：`backend.listDownloadSource=0` → 主源 bmclapi；=1/2 → launchermeta | ✅ 实测（`d8ab617`） |
| 下载限速 `speedLimitMB` | `FileDownloader::applySpeedLimit()`（全局虚拟时钟）；`AssetDownloader` 的并发门控 | `backend.downloadProbe(url, limitKBps, ms)` 实测：1MB/s 档 0.99MB/s、4MB/s 档 3.84MB/s | ✅ 实测（`686ceb6`） |
| 并发线程 `threadLimit` | `FileDownloader::setMaxThreads`（夹 1..24）→ `AssetDownloader` 并发 | `/eval`：残留 64 → 24、set 64 → 24、set 0 → 1 | ✅ 实测（`686ceb6`） |

**注**：精卫（模组下载引擎）固定 12 并发，刻意不跟 `threadLimit` 走 —— MCIM 18+ 会限流饿死连接；
若要让它可配，必须先做主机级限流，否则「设置调大 → 下载反而挂死」。

### 施工进度与验收记录（2026-11-05 夜）

| 切片 | 状态 | 提交 | 验收方式（可复现） |
|---|---|---|---|
| S0 步骤 key 词表 + 按 key 路由 | ✅ | `032328e` `38cc45c` | 自检 `backend.downloadSelfcheck()` → `PASS stepkeys=22 legacy=15`；4 条安装路径共用 key；OptiFine「主文件当校验」误标已修 |
| 终态不可逆 + 完成即 100% | ✅ | `38cc45c` | 自检第 3/4 组：completed 后 setPercentage/setByteProgress 拉不回、setActive 不生效；重试复位必须显式 forceStatus() |
| 限速真正生效（文件下载侧） | ✅ 实测 | `0984cec` `8972d19` | 本机 20MB 文件实测：不限速 32.5MB/s；1MB/s 档 **0.99MB/s**（首版 0.64，已按 Windows sleep 粒度修正）；4MB/s 档 3.84MB/s |
| 取消/暂停真中止 | ✅ 实测 | `0984cec` `55ea577` | 取消于 17,084,856 字节 → 600ms 后仍 17,084,856（grew=0），取消后无 allFinished；失败路径（404 / 主机拒绝）分别 595ms / 545ms 收敛不挂死 |
| 失败不计完成（assets） | ✅ | `0984cec` | 代码审查：成功才 +1，失败单列；allFinished(false) 语义不变 |
| 整合包批次重试/状态复位/停滞看门狗/部分失败 | ✅ 代码 | `7c0b6d4` | 代码审查 + 五路径状态推演；实测需真机导入整合包，待补 |
| 版本列表源真正生效 | ✅ | `d8ab617` | `/eval` 实测：listSource=0→主源 bmclapi；=1/2→launchermeta；`backend.downloadSourceSummary()` 现场可读 |
| 资源索引的源优先级 | ✅ 实测（/eval） | `23139fd` | 官方优先→镜像延迟 800ms 兜底；镜像优先→双源同时发；`downloadSourceSummary()` 现场可读两档 |
| 版本 JSON（3 源）/ 加载器列表（双源）的源优先级 | ⏳ 有意未接 | — | 仍是并发竞速：要接需在异步竞速里加"优先源先发+兜底延迟+done 计数不丢"，无真机安装验证就动会把"拉不到版本 JSON"变成新挂死点 |
| 429/503 按 Retry-After 退避 | ✅ 实测 | `878a84d` | 本机服务实测：一次 429(RA=1)→1191ms 后成功；永远 429→6659ms 收敛不挂死；同源连续 5 次限流判该源不可用 |
| S1 QNAM 收敛（线程局部） | ✅ 实测 | `3d82fe0` | 16 文件 → qnamCreated=6（旧实现 ≥16）；6 文件 → 5；两轮 16 文件均全部成功；QNAM 非线程安全，故收敛到 thread_local 而非全局单例 |
| S2 无 SHA1 文件的兜底重试 | ✅ 实测 | `4be6660` | 2MB 文件、前 8 次 500 后 200：修复前 file=0（占位 10MB 把真实数据判掉），修复后 file=2097152；主路径 42.1MB/s / 0.99MB/s 未回退；接受判定 7 条自检断言 |
| S2 文件级重试预算（每文件上限 + 部分失败清单） | ⏳ 部分 | — | 每文件已有 6 次尝试 + 源禁用阈值 5 + 限流上限 5；"失败文件清单"目前只在整合包链暴露 |
| S4 进度单调（active 步骤百分比可下降） | ⏳ | — | updateStep 允许 active 步骤的 pct 回退 |
| 并发默认值 64 → 16（上限 24） | ✅ | `6bbc5e5` | `/eval` 实测：历史配置 64 → 24（读时夹）、set 64 → 24、set 0 → 1 |
| 进度单调（active 不回退） | ✅ | `56399ba` | 自检第 3.5 组：active 回退被拒、字节口径回退被拒、forceStatus 复位后可重新从低处开始 |
| 取消后半截文件清理（MC 主链） | ⏳ | — | 实测取消后目标文件仍是满尺寸（预分配/合并产物）；整合包链有清理，主链待确认 |

**验收口径**：标 ✅ 的必须构建通过 + 自检 PASS + 应用启动正常；标"⚠️ 未实测"的表示逻辑已改但缺少真机下载验证，**不得当成已验收**。

### S1/S2 必须接的线

- 限速真正作用于 FileDownloader（令牌桶或按窗口 sleep，别只存变量）；
- `setSourcePolicy` 接到精卫（模组 / 整合包）；
- `listSource`：**接给 MC 版本清单域**（version_manifest / 版本 JSON / 资源索引 / 各加载器 meta）；
- 模组平台源：改为内部"官方优先 + MCIM 降级 + 健康缓存"，**不暴露给用户**；
- 线程数上限与契约并发上限对齐（默认 16，允许调到 24），并让精卫也读；
- 每项设置补一条自检（见第 8 节验收用例，扩展为 6/7/8 条）。

## 10. 待确认

- [ ] 是否采用 A 方案（收敛成一个引擎，约 1–2 周）
- [ ] 词表是否按第 1 节定稿（旧 UI 会短暂显示新名）
- [ ] 并发上限是否接受 16（当前夸父 64 + 山海经 64）
