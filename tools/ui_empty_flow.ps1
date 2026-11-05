$s = 'D:\latest-code\shadow-v2\tools\ui_click.ps1'
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700
Start-Process -FilePath 'D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe'
Start-Sleep -Seconds 8
pwsh -NoProfile -File $s -xr 0.07 -yr 0.223 -out '' | Out-Null
Start-Sleep -Milliseconds 900
pwsh -NoProfile -File $s -xr 0.372 -yr 0.1226 -out '' | Out-Null
Start-Sleep -Seconds 8
pwsh -NoProfile -File $s -xr 0.508 -yr 0.2207 -out '' | Out-Null
Start-Sleep -Milliseconds 400
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('zzzzqqqq')
Start-Sleep -Milliseconds 300
pwsh -NoProfile -File $s -xr 0.2917 -yr 0.3406 -out '' | Out-Null
Start-Sleep -Seconds 10
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-empty.png' -TimeoutSec 30 | Out-Null
Write-Output 'ok'