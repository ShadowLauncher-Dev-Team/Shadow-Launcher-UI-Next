
$ErrorActionPreference = 'Stop'
$exe = 'D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe'
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
$proc = Start-Process -FilePath $exe -ArgumentList @('--ui-next','--ui-demo-launch') -PassThru
$base = 'http://127.0.0.1:9999'
$ready = $false
for ($i=0; $i -lt 60; $i++) {
  Start-Sleep -Milliseconds 400
  try { $null = Invoke-WebRequest -Uri ($base+'/screenshot') -UseBasicParsing -TimeoutSec 2; $ready=$true; break } catch {}
}
if (-not $ready) { throw 'server not ready' }
Start-Sleep -Milliseconds 1500
$body = @{ qml = "backend.demoPrecheckFail('核心 Jar：未找到版本 jar 文件')" } | ConvertTo-Json -Compress
$null = Invoke-WebRequest -Uri ($base+'/eval') -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 5
Write-Output 'fail triggered; waiting for analysis...'
Start-Sleep -Milliseconds 3000
$body2 = @{ qml = "JSON.stringify({type: backend.lastCrash.type, reason: backend.lastCrash.reason, desc: backend.lastCrash.description, suggestions: backend.lastCrash.suggestions, rules: backend.lastCrash.matchedRules, report: backend.lastCrash.reportFilePath, analyzing: backend.crashAnalyzing})" } | ConvertTo-Json -Compress
$r2 = Invoke-WebRequest -Uri ($base+'/eval') -Method Post -Body $body2 -ContentType 'application/json' -UseBasicParsing -TimeoutSec 5
Write-Output ('STATE: ' + $r2.Content)
$body3 = @{ qml = "backend.exportCrashLogs('')" } | ConvertTo-Json -Compress
$r3 = Invoke-WebRequest -Uri ($base+'/eval') -Method Post -Body $body3 -ContentType 'application/json' -UseBasicParsing -TimeoutSec 20
Write-Output ('EXPORT: ' + $r3.Content)
$body4 = @{ qml = "backend.cancelLaunch()" } | ConvertTo-Json -Compress
$null = Invoke-WebRequest -Uri ($base+'/eval') -Method Post -Body $body4 -ContentType 'application/json' -UseBasicParsing -TimeoutSec 5
Start-Sleep -Milliseconds 900
$s = Invoke-WebRequest -Uri ($base+'/screenshot') -UseBasicParsing -TimeoutSec 10
[System.IO.File]::WriteAllBytes('D:\latest-code\shadow-v2\pre_closed.png', $s.Content)
Write-Output 'closed-shot saved'
Start-Sleep -Milliseconds 300
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
