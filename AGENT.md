# AGENT.md — 在本仓库工作的 AI 必须遵守的规矩

> 适用范围：任何在本仓库（Shadow Launcher v2）读代码、改代码、提交、推送的 AI。
> 本文件优先级高于个人习惯与效率偏好。与用户当次指令冲突时，先问用户。

---

## 0. 铁律：隐私信息一律不入库、不推送

任何隐私信息都不得推送到远程，也不能 `git add` 后 `commit`。

隐私信息包括但不限于：

- 真实姓名（任何形式的真名、拼音全名、身份证姓名）
- 无关邮箱（个人 QQ 邮箱、163、Gmail、学校/公司邮箱等；提交作者邮箱同样算）
- 手机号、身份证号、住址、学校、公司、生日
- 社交账号（QQ、微信、B站、贴吧、Steam 好友码等）
- 本机用户名与绝对路径（如 `C:\Users\<名字>\...`、桌面文件名、个人下载目录结构）
- 令牌与密钥（API key、token、cookie、私钥、数据库连接串）
- 服务器 IP / 登录凭据 / 内网地址
- 他人的个人信息（内测玩家、贡献者、聊天记录、私聊截图）

**拿不准的一律按隐私处理：先停下询问用户，得到明确同意再执行。**
不许自行判断「这个应该不算敏感」「反正项目是开源的」。

---

## 1. 提交前必跑的三道检查

任何 `commit` / `push` 之前都要跑，命中任意一条就停下问用户。

```powershell
# ① 真实姓名 / 本机用户名（工作区 + 全部历史）
git grep -I -n -F "<本机用户名>"
git log --all --oneline -S "<本机用户名>"

# ② 个人邮箱（%ae = 每个公开提交都带着的标识，最容易被忽略的泄露点）
git log --all --format="%ae" | Sort-Object -Unique

# ③ 令牌 / 密钥 / 私钥
git grep -I -n -E "sk-[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{30}|AKIA[0-9A-Z]{16}|-----BEGIN .*PRIVATE KEY-----"
```

另外两条纪律：

- `git add -A` 之前先 `git add -A --dry-run` 看一眼，确认没有截图、日志、`dist/`、临时脚本混进去。
- 提交作者必须用公开身份：`user.name` = 项目公开名，`user.email` = GitHub noreply 邮箱。

---

## 2. 代码与文档里的路径规则

- 源码、测试、脚本、文档都不得写死本机路径与用户名。
- 需要真实目录时走环境变量（已有约定：`SHADOW_TEST_MINECRAFT_DIR`、`SHADOW_TEST_GAMEDIR`、`SHADOW_TEST_ZIP`、`HMCL_MOD_DATA_TXT`、`PCL_WIKI_ENTRIES_TXT`）。
- 文档/注释里的示例一律用占位符：`C:\Users\<用户名>\...`、`张三`、`Player`。
- 日志贴进 issue / 文档前先去敏（用户名、路径、token、服务器地址）。

---

## 3. 已经推出去的隐私怎么处理

**force push 不等于删除。** GitHub 会保留悬空对象，公开的 `events` 流里还留着旧 SHA，
用旧 SHA 直接取文件依旧可读（`raw.githubusercontent.com/<owner>/<repo>/<sha>/<path>`）。

判断「是否真的清干净」要两步实测：

1. `GET https://api.github.com/repos/<owner>/<repo>/events` —— 看有没有旧 SHA 露出来；
2. 拿那个旧 SHA 直接拉一个含隐私的文件，看内容是否可读。

彻底清除只有两条路，且都必须先征得用户同意：

- 找 GitHub Support 开单 purge（清 cached views / 悬空对象），不丢 stars；
- 删库重建（最彻底，丢 stars / issues / PR）。

历史重写（`git filter-repo`）会改变全部 commit hash，影响所有协作者 —— **不得自行执行，先问用户**。
已泄露时要主动报告，不许静默处理。

---

## 4. 本仓库的既有工作规则

- 每个任务完成后 commit 一次，同时更新 `CODE_INDEX.md` 与记忆。
- 动手前先查 `CODE_INDEX.md` 与记忆；**不要假设历史一定存在**（用户系统曾被重置过）。
- UI 硬规则：禁止 emoji / Unicode 字符作图标的装饰（图标用 `qml/icons/lucide/` 的 SVG）；颜色只走 `Theme.*`（页面局部调色板需先获批）；动画时长/曲线只用 `Theme.dur*` / `Theme.ease*`；`tools/check-ui-contract.ps1` 必须通过。
- 验收标准是真实运行：进程跑起来、看画面、读日志。不接受「代码看起来对」。
- 一次性产物（截图、临时 ps1、`dist/`、备份文件）不入库，靠 `.gitignore` 挡住。

---

## 5. 违规处置

发现已经提交或推送了隐私信息时：

1. 立刻停下当前任务，向用户报告「什么内容、在哪个文件/哪次提交、是否已推送」；
2. 等待用户指示，不要自行重写历史、不要自行删库；
3. 用户同意后再按第 3 节执行，并在完成后回报验证结果。
