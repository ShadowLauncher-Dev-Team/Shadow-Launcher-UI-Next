
$ErrorActionPreference = 'Stop'
$zip = "C:/Users/<用户名>/Desktop/香草纪元：食旅纪行Release2.7.1 （含MCEF）.zip"
$qml = "backend.modpackImporter.startImport('" + $zip + "')"
$json = @{ qml = $qml } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
try {
  $r = Invoke-WebRequest -Uri 'http://127.0.0.1:9999/eval' -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 10
  Write-Output ('eval -> ' + $r.Content)
} catch {
  Write-Output ('eval failed: ' + $_.Exception.Message)
}
