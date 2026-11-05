cd D:\latest-code\shadow-v2
foreach ($t in 2,3,4,5) {
  Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 700
  Start-Process -FilePath build\Release\ShadowLauncher.exe -ArgumentList ('--ui-next --ui-download --ui-tab ' + $t + ' --ui-detail-first')
  Start-Sleep -Seconds 20
  $out = 'design\shots\nui-detail-tab' + $t + '.png'
  Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile $out -TimeoutSec 30 | Out-Null
  Write-Output ($out + ' ' + (Get-Item $out).Length)
}
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
'--- qml errors ---'
(Get-Content build\Release\logs\shadow_launcher_2026-11-06.log | Select-String -Pattern 'is not a type|Cannot assign|Uncaught|QML Error' | Select-Object -Last 4 | ForEach-Object { $_.Line })
'--- version fetches ---'
(Get-Content build\Release\logs\shadow_launcher_2026-11-06.log | Select-String -Pattern 'MODRINTH-MOD|SHADER|RP-|MODPACK|获取 .* 个Mod版本' | Select-Object -Last 8 | ForEach-Object { $_.Line })