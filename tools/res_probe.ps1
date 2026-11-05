$ErrorActionPreference = 'Stop'
$exe = 'D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe'
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Start-Process -FilePath $exe -ArgumentList '--ui-next'
Start-Sleep -Seconds 7

function Eval([string]$qml) {
  $body = @{ qml = $qml } | ConvertTo-Json -Compress
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:9999/eval' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 30
  return $r.value
}
function State([string]$kind) {
  return (Eval "JSON.stringify(backend.resourcePoolState('$kind'))")
}

Write-Output '--- mod page sweep (empty query) ---'
foreach ($p in 0,1,2) {
  $off = $p * 30
  Eval "backend.searchModsEx('','','',[],'','',$off,30,''); 'ok'" | Out-Null
  Start-Sleep -Seconds 7
  Write-Output ("page {0}: {1}" -f $p, (State 'mod'))
}

Write-Output '--- search with query then reset immediately ---'
Eval "backend.searchModsEx('sodium','','',[],'','',0,30,''); 'ok'" | Out-Null
Start-Sleep -Milliseconds 250
Eval "backend.searchModsEx('','','',[],'','',0,30,''); 'ok'" | Out-Null
Start-Sleep -Seconds 8
Write-Output ("after reset: {0}" -f (State 'mod'))

Write-Output '--- switch tabs while pending ---'
Eval "backend.searchModsEx('','','',[],'','',0,30,''); 'ok'" | Out-Null
Start-Sleep -Milliseconds 300
Eval "backend.searchDatapacksEx('','',[],'',0,20,''); 'ok'" | Out-Null
Start-Sleep -Milliseconds 300
Eval "backend.searchShadersEx('',[],[],[],[],0,50,''); 'ok'" | Out-Null
Start-Sleep -Seconds 9
Write-Output ("mod:    {0}" -f (State 'mod'))
Write-Output ("shader: {0}" -f (State 'shader'))
Write-Output ("dp:     {0}" -f (State 'datapack'))

Write-Output '--- back to mod, page 1 must still work ---'
Eval "backend.searchModsEx('','','',[],'','',30,30,''); 'ok'" | Out-Null
Start-Sleep -Seconds 7
Write-Output ("mod p1: {0}" -f (State 'mod'))
