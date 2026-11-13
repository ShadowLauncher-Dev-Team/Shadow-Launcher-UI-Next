
param([string]$Exe, [string]$Out, [int]$ClickX, [int]$ClickY, [int]$WaitMs = 5000, [string]$Extra = "")
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;using System.Text;
public class W2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[W2]::SetProcessDPIAware() | Out-Null
$psi = @{ FilePath = $Exe; PassThru = $true }
if ($Extra -ne "") { $psi.ArgumentList = $Extra.Split(" ") }
$proc = Start-Process @psi
$h = [IntPtr]::Zero
for ($i=0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 300
  $proc.Refresh()
  if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
    $rr = New-Object W2+RECT
    [W2]::GetWindowRect($proc.MainWindowHandle, [ref]$rr) | Out-Null
    if (($rr.R-$rr.L) -gt 300) { $h = $proc.MainWindowHandle; break }
  }
}
if ($h -eq [IntPtr]::Zero) { throw "no window" }
Start-Sleep -Milliseconds $WaitMs
$r = New-Object W2+RECT
[W2]::GetWindowRect($h, [ref]$r) | Out-Null
[W2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 300
[W2]::SetCursorPos($r.L + $ClickX, $r.T + $ClickY) | Out-Null
Start-Sleep -Milliseconds 200
[W2]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
[W2]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 1200
$w = $r.R-$r.L; $hh = $r.B-$r.T
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[W2]::PrintWindow($h, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Stop-Process -Id $proc.Id -Force
"clicked at $ClickX,$ClickY -> $Out ($w x $hh)"
