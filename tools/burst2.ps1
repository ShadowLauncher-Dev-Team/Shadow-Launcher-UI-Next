param(
  [int]$X = 0, [int]$Y = 0,
  [int]$Frames = 4, [int]$IntervalMs = 25,
  [string]$OutPrefix = "D:\\latest-code\\shadow-v2\\b"
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class B {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[B]::SetProcessDPIAware() | Out-Null
$p = Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw "app not running" }
$h = $p.MainWindowHandle
[B]::ShowWindow($h, 9) | Out-Null
[B]::SetWindowPos($h, [IntPtr](-1), 0,0,0,0, 0x0003) | Out-Null
[B]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 700
$r = New-Object B+RECT
[B]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
function Snap([string]$path) {
  $bmp = New-Object System.Drawing.Bitmap($w, $hh)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [void][B]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc); $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}
# 先把鼠标移开，避免 hover 影响判定
[B]::SetCursorPos($r.L + 60, $r.T + 420) | Out-Null
Start-Sleep -Milliseconds 200
Snap ($OutPrefix + "pre.png")
[B]::SetCursorPos($r.L + $X, $r.T + $Y) | Out-Null
Start-Sleep -Milliseconds 60
[B]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
[B]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
for ($i = 0; $i -lt $Frames; $i++) {
  Snap ($OutPrefix + $i + ".png")
  if ($IntervalMs -gt 0) { Start-Sleep -Milliseconds $IntervalMs }
}
[B]::SetCursorPos($r.L + 60, $r.T + 420) | Out-Null
Start-Sleep -Milliseconds 500
Snap ($OutPrefix + "post.png")
Write-Output ("done " + $w + "x" + $hh + " frames=" + $Frames)
