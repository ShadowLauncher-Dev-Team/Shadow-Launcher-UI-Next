$s = 'D:\latest-code\shadow-v2\tools\ui_click.ps1'
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700
Start-Process -FilePath 'D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe'
Start-Sleep -Seconds 8
pwsh -NoProfile -File $s -xr 0.07 -yr 0.223 -out '' | Out-Null
Start-Sleep -Milliseconds 900
pwsh -NoProfile -File $s -xr 0.372 -yr 0.1226 -out '' | Out-Null
Start-Sleep -Seconds 8
pwsh -NoProfile -File $s -xr 0.33 -yr 0.42 -out '' | Out-Null
Start-Sleep -Milliseconds 1200
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-detail-loading.png' -TimeoutSec 30 | Out-Null
Start-Sleep -Seconds 14
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-detail-ready.png' -TimeoutSec 30 | Out-Null
Write-Output 'done'