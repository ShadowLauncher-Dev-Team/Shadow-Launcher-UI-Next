# 版本列表加载器 chips · 现状与续做说明（2026-11-05）

## 已实现（commit 4ea3415，已验证）

- QML `DownloadPage.loadersOf(mc)`：从 `backend.installedVersions` 里找 `mc-` 前缀的已安装版本，按后缀识别 Forge / NeoForge / Fabric / OptiFine，去重。
- 列表行在发布日期右侧渲染 chips（18px、圆角 4、`#101319` 底 + `#242b36` 描边、10px 字）。
- 无数据不占位。
- 实测（design/shot-r2-chips.png）：26.2 → Fabric + Forge；1.21.11 → Forge。

## 未实现（下一会话继续）

全量 chips 需要后端映射表，数据源三个（都不在 Mojang manifest 里）：

| 加载器 | 端点 | 解析 |
|---|---|---|
| Forge | `https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json` | key 形如 `1.20.1` / `1.20.1-recommended` → 支持该 MC |
| Fabric | `https://meta.fabricmc.net/v2/versions/game` | 数组项 `{version, stable}` → 支持该 MC |
| NeoForge | `https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml` | 版本号前缀 `20.4.` 对应 MC 1.20.4（主.次 → MC 1.次） |

## 计划中的接口

```cpp
// version_backend.h
Q_INVOKABLE QVariantList loadersForMc(const QString& mcVersion) const;  // ["forge","fabric"]
Q_INVOKABLE void refreshLoaderSupport();                                // 三个 GET，完成前返回空
```

- 缓存：`QHash<QString, QStringList> m_loaderSupport`，进程内缓存；失败不重试（避免卡启动）。
- QML：启动调用一次 `refreshLoaderSupport()`；`loadersOf()` 优先查后端结果，为空时退回当前的已安装推断。
- 表未回来时 chips 不显示，不造数据。

## 验证步骤（完成后必须做）

1. `--ui-next --ui-download` 启动，等表回来（日志应有 `[LoaderSupport]` 前缀）
2. 截图核对：1.20.1 应有 Forge + Fabric（+ NeoForge 视 1.20.1 支持情况）、1.21.11 应有 Fabric + Forge + NeoForge、1.20.6 应有 Fabric + Forge + NeoForge
3. 断网启动：chips 仍显示已安装推断部分，不报错、不卡启动
