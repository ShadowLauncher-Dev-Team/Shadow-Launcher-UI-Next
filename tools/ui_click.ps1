param([double]$xr, [double]$yr, [string]$out)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, System.IntPtr e);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
public struct RECT { public int Left, Top, Right, Bottom; }
'@
$p = Get-Process ShadowLauncher -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
[void][W.U]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 300
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
$cx = [int]($r.Left + $w * $xr); $cy = [int]($r.Top + $hh * $yr)
[void][W.U]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 120
[W.U]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
[W.U]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Write-Output ("rect {0},{1} {2}x{3} click {4},{5}" -f $r.Left,$r.Top,$w,$hh,$cx,$cy)
Start-Sleep -Milliseconds 900
if ($out) { Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile $out -TimeoutSec 30 | Out-Null; Write-Output ('saved ' + $out) }