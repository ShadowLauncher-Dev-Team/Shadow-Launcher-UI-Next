
param([string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class W3 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[W3]::SetProcessDPIAware() | Out-Null
$p = Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw "app not running" }
$h = $p.MainWindowHandle
$r = New-Object W3+RECT
[W3]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R-$r.L; $hh = $r.B-$r.T
$bmp = New-Object System.Drawing.Bitmap($w,$hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w,$hh)))
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
"screen-captured $Out ($w x $hh)"
