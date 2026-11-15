# 参与开发

面向要改这份代码的人。只想用启动器的话，看 [README](README.md) 就够了。

## 环境

Qt 6.8（`msvc2022_64`）+ Visual Studio 2022（C++ 工作负载）+ CMake 3.21。

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 \
      -DCMAKE_PREFIX_PATH="C:/Qt/6.8.3/msvc2022_64"
cmake --build build --config Release --parallel
```

清构建产物只删已知文件，`Remove-Item build -Recurse -Force` 这种写法不要用：

```powershell
cmake --build build --target clean
```

编译前必须关掉正在运行的 `ShadowLauncher.exe`，否则链接阶段会报 LNK1104（exe 被占用）。

## 调试开关

| 参数 | 用途 |
|---|---|
| `--log-selftest` | 日志系统自检（重复行折叠、文件头、告警摘要、保留份数），跑完即退出 |
| `--screenshot <path>` | 启动后截图保存，用于界面回归 |
| `--navigate <page>` | 直接跳到指定页面 |
| `--ui-selftest-settings` | 设置页逐一巡视，检查每个 pane 能否渲染 |
| `--ui-next-mode / --ui-next-density / --ui-next-size` | 覆盖外观模式、密度、窗口尺寸 |

日志位置：`<exe目录>/logs/shadow_launcher_<时间戳>.log`，一次运行一个文件，只留最近 10 份；告警与错误另存 `logs/errors.log`（跨会话保留，1 MB 滚动）。游戏本身的原生输出全量写 `<游戏目录>/logs/shadow-jvm-output.log`，安装器的写 `logs/installer-last.log`。

上一次运行若是被强杀或崩溃，下次启动会在日志首行写明「上一次运行未正常结束」—— 排查「莫名其妙退出」时先看这一行。

## 界面实现约束

这些都不是风格偏好，是踩过的坑，改界面前先读。设计层面的规范（首屏准入、Token、验收 rubric）在 [design/DESIGN_SPEC.md](design/DESIGN_SPEC.md)。

1. **图标一律 SVG**（`icons/lucide/*.svg`），禁止 emoji 或 Unicode 符号当图标。
2. **禁止 `SpringAnimation`**：实测数值会发散到 `-Infinity`，控件直接消失。
3. **禁止整窗 `layer.enabled` + `MultiEffect`**：会触发纹理重分配，表现为文字瞬间放大、控件消失。单个小图标上色用 `MultiEffect` 可以。
4. **常态不说话**：不显示「就绪 / 准备就绪」，只有异常才提示。
5. 颜色、间距、圆角、动效时长一律取自 `Theme`，不在页面里写死数值。
6. 动画只用 `Theme.dur*` / `Theme.ease*` 里的值；`font.pixelSize` 一律整数。

## 文档索引

- [CODE_INDEX.md](CODE_INDEX.md) —— 全量代码索引（模块职责、关键函数、改动的来龙去脉）
- [DOWNLOAD_CONTRACT.md](DOWNLOAD_CONTRACT.md) —— 下载引擎的接口契约与状态机
- [design/DESIGN_SPEC.md](design/DESIGN_SPEC.md) —— 界面设计规范与历次验收记录
- [PROJECT_STATUS.md](PROJECT_STATUS.md) —— 当前阶段与已知问题

## 改动习惯

- 每完成一处功能改动，同步更新 [CODE_INDEX.md](CODE_INDEX.md)（模块职责、关键函数、为什么这么改）。
- 下载相关的改动先读 [DOWNLOAD_CONTRACT.md](DOWNLOAD_CONTRACT.md)：里面有状态机和失败重试的约定，绕开它改很容易把「断点续传」变成「每次从零开始」。
- 界面改动要在真机上跑起来看，不能只看 diff。
