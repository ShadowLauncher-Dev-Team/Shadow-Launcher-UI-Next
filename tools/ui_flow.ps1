$s = 'D:\latest-code\shadow-v2\tools\ui_click.ps1'
# 1) 搜索（空条件，触发一轮请求）
pwsh -NoProfile -File $s -xr 0.2917 -yr 0.3406 -out '' | Out-Null
Start-Sleep -Milliseconds 200
# 2) 搜索还在飞时点「重置条件」——旧后端会永久卡死
pwsh -NoProfile -File $s -xr 0.4025 -yr 0.3406 -out '' | Out-Null
Start-Sleep -Milliseconds 400
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-reset-mid.png' -TimeoutSec 30 | Out-Null
Start-Sleep -Seconds 7
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-reset-done.png' -TimeoutSec 30 | Out-Null
# 3) 离开下载页（点侧栏「启动」）——条必须立刻灭
pwsh -NoProfile -File $s -xr 0.07 -yr 0.151 -out 'D:\latest-code\shadow-v2\design\shots\ui-exit.png' | Out-Null
'done'