$ErrorActionPreference='Stop'
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Start-Process -FilePath 'D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe' -ArgumentList '--ui-next'
Start-Sleep -Seconds 7
function Eval([string]$qml){ $b=@{qml=$qml}|ConvertTo-Json -Compress; (Invoke-RestMethod -Uri 'http://127.0.0.1:9999/eval' -Method Post -ContentType 'application/json' -Body $b -TimeoutSec 30).value }
Eval "backend.searchModsEx('','','',[],'','',0,30,''); 'ok'" | Out-Null
Start-Sleep -Seconds 7
Write-Output ("mod p0: " + (Eval "JSON.stringify(backend.resourcePoolState('mod'))"))
Eval "backend.searchModsEx('','','',[],'','',30,30,''); 'ok'" | Out-Null
Start-Sleep -Seconds 7
Write-Output ("mod p1: " + (Eval "JSON.stringify(backend.resourcePoolState('mod'))"))