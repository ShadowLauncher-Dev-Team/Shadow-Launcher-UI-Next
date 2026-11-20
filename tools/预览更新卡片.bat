@echo off
chcp 65001 >nul
title 预览更新卡片（不影响任何文件）
echo 正在显示更新卡片：会依次走 等待/8%/25%/62%/87%/100% 六档，约 5 秒后自动关闭。
echo 这个模式只画窗口，不读写任何更新文件。
echo.
"%~dp0SLUpdater.exe" --card-test
echo.
echo 已结束。
pause
