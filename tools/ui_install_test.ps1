$mods = 'D:\Minecraft\.minecraft\mods'
$before = @(Get-ChildItem $mods -File -ErrorAction SilentlyContinue).Count
Write-Output ('mods before: ' + $before)
cd D:\latest-code\shadow-v2
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700
Start-Process -FilePath build\Release\ShadowLauncher.exe -ArgumentList '--ui-next --ui-download --ui-tab 1 --ui-detail-first'
Start-Sleep -Seconds 22
pwsh -NoProfile -File tools\ui_click.ps1 -xr 0.847 -yr 0.224 -out '' | Out-Null
Start-Sleep -Seconds 6
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'design\shots\nui-install-mid.png' -TimeoutSec 30 | Out-Null
Start-Sleep -Seconds 14
$after = @(Get-ChildItem $mods -File -ErrorAction SilentlyContinue)
Write-Output ('mods after: ' + $after.Count)
$after | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { '  ' + $_.Name + '  ' + [Math]::Round($_.Length/1kb) + 'KB  ' + $_.LastWriteTime.ToString('HH:mm:ss') }
'--- log ---'
(Get-Content build\Release\logs\shadow_launcher_2026-11-06.log | Select-String -Pattern 'modFileDownload|下载完成|下载失败|下载中' | Select-Object -Last 6 | ForEach-Object { $_.Line })