$s = 'D:\latest-code\shadow-v2\tools\ui_click.ps1'
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700
Start-Process -FilePath 'D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe'
Start-Sleep -Seconds 8
pwsh -NoProfile -File $s -xr 0.07 -yr 0.223 -out '' | Out-Null
Start-Sleep -Milliseconds 900
pwsh -NoProfile -File $s -xr 0.4525 -yr 0.1226 -out '' | Out-Null
Start-Sleep -Seconds 9
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-shader.png' -TimeoutSec 30 | Out-Null
pwsh -NoProfile -File $s -xr 0.5525 -yr 0.1226 -out '' | Out-Null
Start-Sleep -Seconds 9
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-rp.png' -TimeoutSec 30 | Out-Null
Write-Output 'shots done'
(Get-Content 'D:\latest-code\shadow-v2\build\Release\logs\shadow_launcher_2026-11-06.log' | Select-String -Pattern 'QML|is not a type|Cannot assign|Error:' | Select-Object -Last 8) | ForEach-Object { $_.Line }