
$ErrorActionPreference='Stop'
$exe='D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe'
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
Start-Process -FilePath $exe -ArgumentList @('--ui-next') -WorkingDirectory 'D:\latest-code\shadow-v2\build\Release'
$base='http://127.0.0.1:9999'
$ok=$false
for($i=0;$i -lt 60;$i++){ Start-Sleep -Milliseconds 400; try{ $null=Invoke-WebRequest -Uri ($base+'/screenshot') -UseBasicParsing -TimeoutSec 2; $ok=$true; break }catch{} }
if(-not $ok){ throw 'server not ready' }
Start-Sleep -Milliseconds 1200
# 开始导入
$zip = "C:/Users/<用户名>/Desktop/香草纪元：食旅纪行Release2.7.1 （含MCEF）.zip"
$j1 = @{ qml = "backend.modpackImporter.startImport('" + $zip + "')" } | ConvertTo-Json -Compress
$b1 = [System.Text.Encoding]::UTF8.GetBytes($j1)
$null = Invoke-WebRequest -Uri ($base+'/eval') -Method Post -Body $b1 -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 10
Write-Output 'import started'
Start-Sleep -Seconds 4
# 取消
$j2 = @{ qml = 'backend.modpackImporter.cancelImport()' } | ConvertTo-Json -Compress
$b2 = [System.Text.Encoding]::UTF8.GetBytes($j2)
$r2 = Invoke-WebRequest -Uri ($base+'/eval') -Method Post -Body $b2 -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 10
Write-Output ('cancel -> ' + $r2.Content)
Start-Sleep -Milliseconds 900
$s1 = Invoke-WebRequest -Uri ($base+'/screenshot') -UseBasicParsing -TimeoutSec 10
[System.IO.File]::WriteAllBytes('D:\latest-code\shadow-v2\card_cancel_now.png', $s1.Content)
Write-Output 'shot1 (0.9s after cancel)'
Start-Sleep -Seconds 5
$s2 = Invoke-WebRequest -Uri ($base+'/screenshot') -UseBasicParsing -TimeoutSec 10
[System.IO.File]::WriteAllBytes('D:\latest-code\shadow-v2\card_cancel_after.png', $s2.Content)
Write-Output 'shot2 (5.9s after cancel)'
