
$ErrorActionPreference='Stop'
$exe='D:\latest-code\shadow-v2\build\Release\ShadowLauncher.exe'
Start-Process -FilePath $exe -ArgumentList @('--ui-next') -WorkingDirectory 'D:\latest-code\shadow-v2\build\Release'
$base='http://127.0.0.1:9999'
$ok=$false
for($i=0;$i -lt 70;$i++){ Start-Sleep -Milliseconds 500; try{ $null=Invoke-WebRequest -Uri ($base+'/screenshot') -UseBasicParsing -TimeoutSec 2; $ok=$true; break }catch{} }
if(-not $ok){ throw 'server not ready' }
Start-Sleep -Milliseconds 1500
$q = @'
(function(){
  var s = backend.settings();
  var out = 'auto=' + s.autoMemoryEnabled;
  out += ' | 空Forge=' + backend.recommendMemoryForVersion('1.20.1-Forge_47.4.10');
  out += ' | 425mod=' + backend.recommendMemoryForVersion('香草纪元：食旅纪行-Release2.7.1');
  return out;
})()
'@
$j = @{ qml = $q } | ConvertTo-Json -Compress
$b = [System.Text.Encoding]::UTF8.GetBytes($j)
$r = Invoke-WebRequest -Uri ($base+'/eval') -Method Post -Body $b -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 20
Write-Output ([System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()))
