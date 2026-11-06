param()
Add-Type -Namespace W2 -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
'@
$p = Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output "no window"; exit 1 }
[void][W2.Win]::ShowWindow($p.MainWindowHandle, 9)   # SW_RESTORE
Start-Sleep -Milliseconds 250
[void][W2.Win]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 250
Write-Output ("restored " + $p.MainWindowHandle)
