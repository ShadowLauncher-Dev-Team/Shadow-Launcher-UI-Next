param([double]$xr, [double]$yr, [string]$out)
Add-Type -Namespace W3 -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
public struct RECT { public int Left, Top, Right, Bottom; }
'@
$p = Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output "no window"; exit 1 }
$h = $p.MainWindowHandle
[void][W3.U]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 200
$r = New-Object W3.U+RECT
[void][W3.U]::GetClientRect($h, [ref]$r)
$w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
$cx = [int]($w * $xr); $cy = [int]($hh * $yr)
$lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
[void][W3.U]::PostMessage($h, 0x0200, [IntPtr]0, $lp)   # WM_MOUSEMOVE
Start-Sleep -Milliseconds 60
[void][W3.U]::PostMessage($h, 0x0201, [IntPtr]1, $lp)   # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 80
[void][W3.U]::PostMessage($h, 0x0202, [IntPtr]0, $lp)   # WM_LBUTTONUP
Write-Output ("client {0}x{1} post {2},{3}" -f $w, $hh, $cx, $cy)
Start-Sleep -Milliseconds 900
if ($out) { Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile $out -TimeoutSec 30 | Out-Null; Write-Output ('saved ' + $out) }
