@echo off
REM 启动浮层安全演示：后端假状态机驱动真实浮层组件，不检测 Java、不拉文件、不起进程。
REM 正版/外置 6 节点（--ui-demo-online）；把 --ui-demo-online 换成 --ui-demo-fail 看失败态。
cd /d "%~dp0"
start "" "build\Release\ShadowLauncher.exe" --ui-next --ui-demo-launch --ui-demo-online
