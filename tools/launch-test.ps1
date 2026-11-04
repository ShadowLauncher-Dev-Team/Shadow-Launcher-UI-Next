param([string]$Exe, [string]$Out1, [string]$Out2)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;using System.Text;
public class U {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[U]::SetProcessDPIAware() | Out-Null
function ClickAt([int]$x, [int]$y) {
  [U]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 120
  [U]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [U]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
}
function Grab([IntPtr]$h, [string]$out) {
  $r = New-Object U+RECT
  [U]::GetWindowRect($h, [ref]$r) | Out-Null
  $w = $r.R - $r.L; $hh = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap($w, $hh)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [U]::PrintWindow($h, $hdc, 2) | Out-Null
  $g.ReleaseHdc($hdc); $g.Dispose()
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  return "$w x $hh"
}

$proc = Start-Process -FilePath $Exe -ArgumentList '--ui-next' -PassThru
$h = [IntPtr]::Zero
for ($i=0; $i -lt 50; $i++) {
  Start-Sleep -Milliseconds 400
  $proc.Refresh()
  if ($proc.HasExited) { throw ("exited " + $proc.ExitCode) }
  if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { $h = $proc.MainWindowHandle
    $rr = New-Object U+RECT; [U]::GetWindowRect($h, [ref]$rr) | Out-Null
    if (($rr.R-$rr.L) -gt 300) { break } }
}
Start-Sleep -Seconds 4
$r = New-Object U+RECT
[U]::GetWindowRect($h, [ref]$r) | Out-Null
"window $($r.R-$r.L) x $($r.B-$r.T) at $($r.L),$($r.T)"
[U]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400

# 点「启动游戏」（窗口内偏移）
ClickAt ($r.L + 390) ($r.T + 810)
Start-Sleep -Milliseconds 1600
"overlay: " + (Grab $h $Out1)

# 点浮层右下「取消启动」
ClickAt ($r.L + 1109) ($r.T + 665)
Start-Sleep -Milliseconds 1400
"after cancel: " + (Grab $h $Out2)

Start-Sleep -Milliseconds 300
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
"done"