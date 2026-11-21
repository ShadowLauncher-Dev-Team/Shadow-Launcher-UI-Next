# Shadow Launcher 环境配置

> 本机实测版本，不是「建议版本」。换机器照此装。

## 一、工具链

| 组件 | 本机实际 | 说明 |
|---|---|---|
| 系统 | Windows 10/11 x64 | |
| MSVC | **14.44.35207**（VS 2022 Build Tools） | 生成器 `Visual Studio 17 2022` |
| Qt | **6.8.3 msvc2022_64** → `C:\Qt\6.8.3\msvc2022_64` | **机器上还有 6.5.3，选错就炸** |
| CMake | **4.4.0**，`C:\Python314\Scripts\cmake.exe` | pip 装的，**不在系统 PATH 靠前**；项目最低要求 3.21 |
| Python | 3.14 | 只给 `scripts/` 里的辅助脚本用 |
| PowerShell | 7.6.4 | 禁止用 5.x |

## 二、首次配置

在仓库根执行（路径按本机改）：

```powershell
& 'C:\Python314\Scripts\cmake.exe' -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_PREFIX_PATH=C:/Qt/6.8.3/msvc2022_64 `
  -DCMAKE_BUILD_TYPE=Release
```

`CMAKE_PREFIX_PATH` 必须指向 Qt 6.8.3，否则 POST_BUILD 的 windeployqt 找不到，构造出来的 exe 起不来。

## 三、日常构建

```powershell
# 全量
& 'C:\Python314\Scripts\cmake.exe' --build build --config Release

# 只启动器 / 只登录助手
& 'C:\Python314\Scripts\cmake.exe' --build build --config Release --target ShadowLauncher
& 'C:\Python314\Scripts\cmake.exe' --build build --config Release --target wv2login
```

**构建后 CMake 自动做两件事**（`CMakeLists.txt` 的 POST_BUILD）：

1. `windeployqt.exe` 拷 Qt 运行时，参数 `--qmldir ui --no-translations --no-compiler-runtime`
2. 把 `ui/` 整个拷到产物目录（QML 是外置的，改 QML 也要重新构建才生效）

产物：`build/Release/ShadowLauncher.exe`、`build/Release/wv2login.exe`。

## 四、CMake 选项

| 选项 | 默认 | 用途 |
|---|---|---|
| `SHADOW_ENABLE_BETA_GATE` | OFF | 内测密钥闸门。**新 UI 没有密钥输入页**，开了也只是「有密钥就放行」 |
| `SHADOW_BUILD_UI_NEXT_TESTS` | OFF | 新 UI 基础测试 |
| `SHADOW_BUILD_MODPACK_SELFTEST` | ON | 整合包自检可执行 |

## 五、本地密钥（不进版本库）

| 文件 | 是否入库 | 内容 |
|---|---|---|
| `src/secrets.h` | ✅ 入库 | 占位符，可安全提交 |
| `src/secrets_local.h` | ❌ 被 `.gitignore` 忽略 | 真实值，覆盖占位符 |

缺 `secrets_local.h` **能编译通过**，但正版登录会失败（clientId 是假的）——排查登录问题时先确认这个文件在。

## 六、运行时依赖

- **Qt DLL 与 QML 模块**：构建时自动部署，不用手动拷
- **WebView2 Runtime**：系统级组件（Win11 自带，Win10 需另装）。缺它时内嵌登录会弹「WebView2 运行时不可用」
- **WebView2Loader.dll**：`thirdparty/wv2login/sdk` 提供，构建时自动拷到 wv2login.exe 旁边

## 七、无窗口验证（离屏跑）

部署目录的 `platforms/` **只有 `qwindows.dll`**，直接设离屏会静默退出（进程起来又没了，量到的全是空壳）：

```powershell
Copy-Item "C:\Qt\6.8.3\msvc2022_64\plugins\platforms\qoffscreen.dll" "build\Release\platforms\"
$env:QT_QPA_PLATFORM = 'offscreen'
# 量完记得删掉，别留在产物目录里
Remove-Item "build\Release\platforms\qoffscreen.dll"
```

**判据：三次测量数字完全一样 = 根本没跑起来，不是「性能很好」。**

## 八、常见问题

| 现象 | 原因与处理 |
|---|---|
| `LNK1104 无法打开 ShadowLauncher.exe` | exe 正在运行被占用。**不要杀进程**，用 `Move-Item` 把运行中的 exe 改名再构建 |
| 命令找不到 `cmake` | 它是 pip 装的，用全路径 `C:\Python314\Scripts\cmake.exe` |
| 编译过了但程序起不来 | 检查 `CMAKE_PREFIX_PATH` 是否指向 Qt 6.8.3；确认 POST_BUILD 的 windeployqt 跑过 |
| 改了 QML 界面没变化 | QML 是 POST_BUILD 拷到产物的，得重新构建 |
| `git add docs/xxx` 无效果 | `.gitignore` 忽略了整个 `docs/`，要入库的文档放仓库根 |
