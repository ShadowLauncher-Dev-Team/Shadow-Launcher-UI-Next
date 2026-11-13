param([int]$X, [int]$Y, [int]$Count = 6, [int]$Delay = 55, [string]$Prefix)
# 必须**最先**声明 DPI 感知：否则 GetClientRect/ClientToScreen 返回的是被虚拟化的逻辑坐标，
# 而截图是物理像素 —— 两者差 1.25 倍，点击会整体偏移（实测点到了隔壁 tab）。
Add-Type -MemberDefinition @"
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
"@ -Name Dpi -Namespace Native | Out-Null
[void][Native.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CB {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct RECT { public int L, T, R, B; }
  public struct POINT { public int X, Y; }
}
"@
$p = Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output "no proc"; exit 1 }
# MainWindowHandle 对 Qt 的无边框窗口经常给 0，拿到的句柄也可能属于被隐藏的
# 那个窗口（实测 client 0x0 at -32000,-32000，点击全落到屏幕外）。
# 改成枚举该进程所有顶层窗口，取「可见 + 有非零客户区 + 面积最大」的那个。
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinFind {
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  delegate bool EnumProc(IntPtr h, IntPtr l);
  public struct RECT { public int L, T, R, B; }
  public static IntPtr Find(uint target) {
    IntPtr best = IntPtr.Zero; long bestArea = 0;
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != target || !IsWindowVisible(h)) return true;
      RECT r; if (!GetClientRect(h, out r)) return true;
      long w = r.R - r.L, hh = r.B - r.T;
      if (w > 100 && hh > 100 && w * hh > bestArea) { bestArea = w * hh; best = h; }
      return true;
    }, IntPtr.Zero);
    return best;
  }
}
"@
$h = [WinFind]::Find([uint32]$p.Id)
if ($h -eq [IntPtr]::Zero) { Write-Output "no visible window"; exit 1 }
[void][CB]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 250
$r = New-Object CB+RECT
[void][CB]::GetClientRect($h, [ref]$r)
$pt = New-Object CB+POINT
[void][CB]::ClientToScreen($h, [ref]$pt)
$cx = $pt.X; $cy = $pt.Y
$cw = $r.R - $r.L; $ch = $r.B - $r.T
Write-Output ("client " + $cw + "x" + $ch + " at " + $cx + "," + $cy)
[void][CB]::SetCursorPos($cx + $X, $cy + $Y)
Start-Sleep -Milliseconds 40
[CB]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
[CB]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
for ($i = 0; $i -lt $Count; $i++) {
  $bmp = New-Object System.Drawing.Bitmap($cw, $ch)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($cx, $cy, 0, 0, (New-Object System.Drawing.Size($cw, $ch)))
  $bmp.Save("$Prefix$i.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Start-Sleep -Milliseconds $Delay
}
Write-Output "done"