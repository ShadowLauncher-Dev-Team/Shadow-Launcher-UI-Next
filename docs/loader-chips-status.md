# 版本列表加载器 chips · 已废弃（2026-11-05 决定移除）

## 结论

影决定：版本列表里的加载器 chips（Fabric / Forge / NeoForge / OptiFine）没必要显示，**已整块删除**。

- 删除的 QML：`ui/pages/DownloadPage.qml` 行内 `loadersOf(mc)` 函数 + 列表行里渲染 chips 的 `Row/Repeater`（18px 胶囊、`#101319` 底、`#242b36` 描边、10px 字）。
- 删除的 C++：**无**。chips 从头到尾是 QML 侧根据 `backend.installedVersions` 推断的，后端从未实现过映射表（见下「原计划」），因此本次只动 QML。
- 保留：已安装版本的绿点（`isInstalled(id)`），日期列位置不变。

## 原计划（作废，仅留档）

若要恢复全量 chips，需要三张后端映射表：Forge `promotions_slim.json`、Fabric `v2/versions/game`、NeoForge `maven-metadata.xml`；接口设想为 `loaderSupport` 缓存 + `loadersForMc(mc)` + `refreshLoaderSupport()`。该计划不再推进。