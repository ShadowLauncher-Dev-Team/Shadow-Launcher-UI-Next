Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, System.IntPtr e);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
public struct RECT { public int Left, Top, Right, Bottom; }
'@
$p = Get-Process ShadowLauncher | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
[void][W.U]::SetForegroundWindow($h)
[void][W.U]::SetWindowPos($h, [IntPtr]::Zero, 100, 60, 1100, 720, 0x0040)
Start-Sleep -Milliseconds 800
$r = New-Object W.U+RECT; [void][W.U]::GetWindowRect($h, [ref]$r)
Write-Output ('size: ' + ($r.Right-$r.Left) + 'x' + ($r.Bottom-$r.Top))
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-grid-1100.png' -TimeoutSec 30 | Out-Null
# 点第一张卡（相对窗口 0.33 / 0.42）
$w = $r.Right-$r.Left; $hh = $r.Bottom-$r.Top
[void][W.U]::SetCursorPos([int]($r.Left + $w*0.33), [int]($r.Top + $hh*0.42))
Start-Sleep -Milliseconds 150
[W.U]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 60; [W.U]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Seconds 3
Invoke-WebRequest -Uri 'http://127.0.0.1:9999/screenshot' -OutFile 'D:\latest-code\shadow-v2\design\shots\ui-detail.png' -TimeoutSec 30 | Out-Null
Write-Output 'done'