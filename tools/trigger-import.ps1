
$ErrorActionPreference = 'Stop'
$zip = $env:SHADOW_TEST_ZIP
if (-not $zip) { Write-Error "请先设置 SHADOW_TEST_ZIP 为整合包 zip 的路径"; exit 1 }
$qml = "backend.modpackImporter.startImport('" + $zip + "')"
$json = @{ qml = $qml } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
try {
  $r = Invoke-WebRequest -Uri 'http://127.0.0.1:9999/eval' -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 10
  Write-Output ('eval -> ' + $r.Content)
} catch {
  Write-Output ('eval failed: ' + $_.Exception.Message)
}
