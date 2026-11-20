@echo off
chcp 65001 >nul
title 更新卡片预览
echo 正在打开更新卡片预览窗口（假进度，6 档循环，不会触发任何更新）
echo 卡片是独立置顶窗口，出现在屏幕中央；关掉启动器窗口即可结束预览。
echo.
start "" "%~dp0ShadowLauncher.exe" --ui-update-card
timeout /t 2 >nul
exit
