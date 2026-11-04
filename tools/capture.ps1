param([string]$Exe, [string]$Out, [int]$W = 0, [int]$H = 0, [int]$WaitMs = 6000)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$proc = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Milliseconds 2500
$proc.Refresh()
$h = $proc.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 2500; $proc.Refresh(); $h = $proc.MainWindowHandle }
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $proc.Id -Force; throw "no window handle" }
if ($W -gt 0) { [W]::SetWindowPos($h, [IntPtr]::Zero, 60, 40, $W, $H, 0x0040) | Out-Null }
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds $WaitMs
$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $proc.Id -Force
"captured $Out ($w x $hh)"