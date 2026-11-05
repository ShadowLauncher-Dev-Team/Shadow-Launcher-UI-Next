$s = 'D:\latest-code\shadow-v2\tools\ui_click.ps1'
pwsh -NoProfile -File $s -xr 0.6425 -yr 0.1226 -out '' | Out-Null
Start-Sleep -Seconds 10
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-pack.png' -TimeoutSec 30 | Out-Null
pwsh -NoProfile -File $s -xr 0.7408 -yr 0.1226 -out '' | Out-Null
Start-Sleep -Seconds 10
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-dp.png' -TimeoutSec 30 | Out-Null
Write-Output 'ok'