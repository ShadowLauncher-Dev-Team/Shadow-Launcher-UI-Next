# Shadow Launcher 开发准则

> 从 `~/.dsh/AGENTS.md` 提炼的启动器开发约束 + 完整开发流程。改动前先读完。

## 一、禁止事项

### 用户数据（最重）

- **禁止**为"改名好看"动 `setOrganizationName("ShadowTeam")`。它是 QSettings 存储键，决定 `%APPDATA%\ShadowTeam\Shadow Launcher`；动它必须同时写一次性迁移，否则用户配置、令牌、壁纸全部读不到。
- **禁止**未经询问做影响用户数据或不可逆的操作：删文件、迁移、改存储键、清理目录。
- **禁止**让启动器处于关闭状态。构建后必须真启动一次做验收，不是截个图就算。

### 版本与资源

- **禁止**只改一处版本号。三处必须同步：`src/version.h` 的 `SHADOW_DISPLAY_VERSION`、`CMakeLists.txt` 的 `project(... VERSION x.y.z)`、`resources/app.rc` 的 FILEVERSION / PRODUCTVERSION。数字元组不放 `-beta`，后缀只进 ProductVersion 字符串。
- **禁止**用 emoji / Unicode 字符当图标或装饰。一律 SVG 或纯文字。
- **禁止**手绘像素图标。`resources/icons/app.svg` 是唯一矢量源，PNG 全部由它导出。

### Git 与协作

- **禁止**直推 `main`：受 repository ruleset 保护，直推会得到 `GH013 ... must be made through a pull request`。
- **禁止**对 `main` 做 force push；**禁止**自行执行历史重写（`git filter-repo` 等）。
- **禁止**把 `AGENT.md` 放在仓库根。全局规则只放 `~/.dsh/AGENTS.md`（该文件曾被加进仓库又回滚，别再犯）。
- **禁止「完成任务就自动 commit」**。提交只解决「这个改动对仓库有价值」，不是打卡。文档、说明、临时产物默认**不入库**；要入库先问一句。

### 隐私与凭据

- **禁止**任何隐私信息入库或推送：真实姓名、个人邮箱（含提交作者邮箱）、手机号、住址、社交账号、本机用户名与绝对路径、token／密钥、服务器 IP、他人信息。
- **禁止**让用户把 token 粘贴进对话。用 `git credential fill` 或 `gh` 的 keyring。
- **禁止**打印 token、把 token 写进文件、写进 commit 或 PR 正文、留在临时脚本里。
- **拿不准的一律按隐私处理：先停下问，不许自行判断"这个应该不算敏感"。**

## 二、开发流程

| 步骤 | 做什么 | 硬要求 |
|---|---|---|
| 1 查上下文 | 读 `CODE_INDEX.md` + `memory search` | 没有上下文不许动手 |
| 2 定根因 | 先复现、实测、看日志 | **禁止靠猜**；猜错了就是二次返工 |
| 3 改代码 | 小改用 `edit`，批量替换用 Python | 编码不能坏 |
| 4 构建 | `cmake --build build --config Release --target ShadowLauncher` | 0 error |
| 5 验证 | 离屏测量 / 日志无 QML 报错 / 真启动验收 | 数字不变＝没跑起来，别信 |
| 6 提交 | 代码改动才 commit；同时更新 `CODE_INDEX.md` + `memory append` | 三件套缺一不可；**纯文档/临时产物不提交** |
| 7 交付 | 建分支 → push → PR → 等 CLEAN → 合并 → 删分支 → `git pull --ff-only` | 不直推 main |

### 提交前必跑（命中任意一条就停下问）

```powershell
git grep -I -n -F "<本机用户名>"
git log --all --format="%ae" | Sort-Object -Unique
git grep -I -n -E "ghp_[A-Za-z0-9]{30}|sk-[A-Za-z0-9]{20}|BEGIN (RSA|OPENSSH) PRIVATE KEY"
git add -A --dry-run
```

## 三、常见坑（速查）

- **PATH 是启动时快照**：新装工具当场用不了，用全路径调用。
- **exe 被占用**：`LNK1104` 时不要杀进程，用 `Move-Item` 重命名运行中的 exe 再构建。
- **部署目录缺 `qoffscreen.dll`**：设 `QT_QPA_PLATFORM=offscreen` 会静默退出，量到的全是空壳。
- **缩略图必须设 `sourceSize`**：否则 Qt 按原图分辨率解码，大量卡片会吃几百 MB 内存。
- **整排 delegate 的重建不能挂在鼠标频率的信号上**：区分"结构变化"和"数值变化"两个信号。
- **玩偶测试无窗口**：验证优先用离屏/假 DOM 跑断言，不要弹窗挡住用户。
- **注入页面的 JS 必须用假 DOM 跑一遍**：`node --check` 只查语法，查不出运行时抛错被 `try` 吞掉。
- **VitePress 遇 dead link 直接构建失败**（不是警告）。
