param([string]$Exe, [string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class U2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[U2]::SetProcessDPIAware() | Out-Null
$proc = Start-Process -FilePath $Exe -ArgumentList '--ui-next' -PassThru
for ($i=0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 400
  $proc.Refresh()
  if ($proc.HasExited) { throw "exited" }
  if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { break }
}
Start-Sleep -Seconds 4
$h = $proc.MainWindowHandle
[U2]::SetForegroundWindow($h) | Out-Null
$r = New-Object U2+RECT
[U2]::GetWindowRect($h, [ref]$r) | Out-Null
[U2]::SetCursorPos(($r.L + 390), ($r.T + 810)) | Out-Null
Start-Sleep -Milliseconds 150
[U2]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 60
[U2]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 1500

$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc(); [U2]::PrintWindow($h, $hdc, 2) | Out-Null; $g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# 立刻杀掉，避免走到"启动游戏进程"
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Get-Process java, javaw -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddMinutes(-2) } | Stop-Process -Force -ErrorAction SilentlyContinue
"captured + killed"