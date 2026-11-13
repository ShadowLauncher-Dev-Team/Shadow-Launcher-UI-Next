
$urls = @(
  "https://mediafilez.forgecdn.net/files/5848/216/alexscaves-2.0.2.jar",
  "https://mediafilez.forgecdn.net/files/5182/632/The_Undergarden-1.20.1-0.8.14.jar",
  "https://mediafilez.forgecdn.net/files/8436/689/legendarymonsters-2.1.21%20MC%201.20.1.jar",
  "https://mediafilez.forgecdn.net/files/7483/539/handcrafted-forge-1.20.1-3.0.6.jar",
  "https://mediafilez.forgecdn.net/files/5402/61/kotlinforforge-4.11.0-all.jar",
  "https://mediafilez.forgecdn.net/files/7550/220/AmbientSounds_FORGE_v6.3.4_mc1.20.1.jar",
  "https://mediafilez.forgecdn.net/files/7432/26/the_bumblezone-7.9.8%2b1.20.1-forge.jar",
  "https://mediafilez.forgecdn.net/files/5698/791/alexsmobs-1.22.9.jar"
)
$jobs = @()
for ($i = 0; $i -lt $urls.Count; $i++) {
  $u = $urls[$i]
  $out = "$env:TEMP\cc_$i.bin"
  $jobs += Start-Job -ScriptBlock {
    param($u, $out)
    $r = & curl.exe -s -o $out -m 60 -w "%{http_code}|%{size_download}|%{speed_download}" $u 2>&1
    return "$r"
  } -ArgumentList $u, $out
}
$jobs | Wait-Job -Timeout 90 | Out-Null
for ($i = 0; $i -lt $jobs.Count; $i++) {
  $res = Receive-Job -Job $jobs[$i]
  $size = if (Test-Path "$env:TEMP\cc_$i.bin") { [math]::Round((Get-Item "$env:TEMP\cc_$i.bin").Length/1KB,0) } else { 0 }
  Write-Output ("job" + $i + " -> " + $res + "  savedKB=" + $size)
}
$jobs | Remove-Job -Force
