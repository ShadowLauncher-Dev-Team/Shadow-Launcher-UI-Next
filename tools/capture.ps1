param([string]$Exe, [string]$Out, [int]$W = 0, [int]$H = 0, [int]$WaitMs = 6000, [string]$Extra = "", [int]$HoverX = -1, [int]$HoverY = -1)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;using System.Text;
public class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[W]::SetProcessDPIAware() | Out-Null

$psi = @{ FilePath = $Exe; PassThru = $true }
if ($Extra -ne "") { $psi.ArgumentList = $Extra.Split(" ") }
$proc = Start-Process @psi

$h = [IntPtr]::Zero
for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 400
    $proc.Refresh()
    if ($proc.HasExited) { throw ("process exited with code " + $proc.ExitCode) }
    $cand = $proc.MainWindowHandle
    if ($cand -ne [IntPtr]::Zero) {
        $rr = New-Object W+RECT
        [W]::GetWindowRect($cand, [ref]$rr) | Out-Null
        if (($rr.R - $rr.L) -gt 300) { $h = $cand; break }
    }
}
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; throw "no suitable window" }

$sb = New-Object System.Text.StringBuilder 256
[W]::GetWindowText($h, $sb, 256) | Out-Null
if ($W -gt 0) {
    [W]::ShowWindow($h, 9) | Out-Null
    [W]::SetWindowPos($h, [IntPtr]::Zero, 60, 40, $W, $H, 0x0040) | Out-Null
}
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds $WaitMs
if ($HoverX -ge 0 -and $HoverY -ge 0) {
    $rp = New-Object W+RECT
    [W]::GetWindowRect($h, [ref]$rp) | Out-Null
    [W]::SetCursorPos($rp.L + $HoverX, $rp.T + $HoverY) | Out-Null
    Start-Sleep -Milliseconds 700
    "hover at +$HoverX,+$HoverY"
}

$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
"window: " + $sb.ToString() + "  rect: $w x $hh @ ($($r.L),$($r.T))"
if ($w -le 0 -or $hh -le 0 -or $w -gt 4000 -or $hh -gt 4000) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; throw "bad rect" }

$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [W]::PrintWindow($h, $hdc, 2)     # PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc)
$g.Dispose()
if (-not $ok) { $bmp.Dispose(); Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; throw "PrintWindow failed" }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
"captured $Out ($w x $hh)"