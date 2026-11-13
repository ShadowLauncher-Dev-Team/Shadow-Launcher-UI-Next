
param(
  [string]$Mode = "shot",
  [string]$Out = "shot.png",
  [int]$X1 = 0, [int]$Y1 = 0, [int]$X2 = 0, [int]$Y2 = 0,
  [int]$Ticks = 0, [int]$Steps = 24, [int]$X3 = -1, [int]$Y3 = -1, [string]$Out2 = "", [switch]$TopMost, [switch]$FullScreen, [switch]$PrintWin, [int]$Count = 8, [int]$DelayMs = 60, [int]$ClickX = -1, [int]$ClickY = -1
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int data, IntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[M]::SetProcessDPIAware() | Out-Null
$p = Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw "app not running" }
$h = $p.MainWindowHandle
[M]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE：窗口可能已最小化（rect 会是 -32000）
Start-Sleep -Milliseconds 300
[M]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 250
$r = New-Object M+RECT
[M]::GetWindowRect($h, [ref]$r) | Out-Null

function Shot($path) {
  $w = $r.R-$r.L; $hh = $r.B-$r.T
  $bmp = New-Object System.Drawing.Bitmap($w,$hh)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w,$hh)))
  $g.Dispose(); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  "saved $path"
}

if ($Mode -eq "wheel") {
  [M]::SetCursorPos($r.L+$X1, $r.T+$Y1) | Out-Null
  Start-Sleep -Milliseconds 150
  $delta = if ($Ticks -gt 0) { 120 } else { -120 }
  for ($i=0; $i -lt [Math]::Abs($Ticks); $i++) {
    [M]::mouse_event(0x0800, 0, 0, $delta, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
  }
  Start-Sleep -Milliseconds 400
  Shot $Out
}
elseif ($Mode -eq "burst") {
  # 连拍：用来抓转场动画中间帧（-ClickX/-ClickY 先点一下触发转场，再连拍 $Count 张，间隔 $DelayMs）
  if ($TopMost) {
    [M]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0003) | Out-Null
    Start-Sleep -Milliseconds 300
    $r = New-Object M+RECT
    [M]::GetWindowRect($h, [ref]$r) | Out-Null
  }
  # 点击用同步方式、且按下/抬起之间几乎不留空：runspace 版偶尔点不到（前台窗口抢不到），
  # 同步版把"按下→开拍"压到 ~40ms，仍能抓到 260ms 的入场动画。
  if ($ClickX -ge 0) {
    [M]::SetForegroundWindow($h) | Out-Null
    [M]::SetCursorPos($r.L+$ClickX, $r.T+$ClickY) | Out-Null
    Start-Sleep -Milliseconds 30
    [M]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [M]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  }
  if ($false) {
    $clickScript = {
      param($h, $x, $y)
      Add-Type @"
using System;using System.Runtime.InteropServices;
public class C2 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int data, IntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
      [C2]::SetForegroundWindow([IntPtr]$h) | Out-Null
      [C2]::SetCursorPos($x, $y) | Out-Null
      Start-Sleep -Milliseconds 60
      [C2]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
      Start-Sleep -Milliseconds 30
      [C2]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    }
    $ps = [powershell]::Create().AddScript($clickScript).AddArgument([int64]$h).AddArgument([int]($r.L+$ClickX)).AddArgument([int]($r.T+$ClickY))
    $null = $ps.BeginInvoke()
  } else {
    Start-Sleep -Milliseconds 60
  }
  if ($FullScreen) {
    Add-Type -AssemblyName System.Windows.Forms
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $r = New-Object M+RECT
    $r.L = $b.X; $r.T = $b.Y; $r.R = $b.X + $b.Width; $r.B = $b.Y + $b.Height
  }
  for ($k=1; $k -le $Count; $k++) {
    if ($PrintWin) {
      $w = $r.R-$r.L; $hh = $r.B-$r.T
      $bmp = New-Object System.Drawing.Bitmap($w,$hh)
      $gg = [System.Drawing.Graphics]::FromImage($bmp)
      $hdc = $gg.GetHdc()
      [M]::PrintWindow($h, $hdc, 2) | Out-Null   # PW_RENDERFULLCONTENT
      $gg.ReleaseHdc($hdc); $gg.Dispose()
      $bmp.Save(("{0}_{1}.png" -f $Out, $k), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    } else {
      Shot ("{0}_{1}.png" -f $Out, $k) | Out-Null
    }
    Start-Sleep -Milliseconds $DelayMs
  }
  "burst done: {0} x {1}ms" -f $Count, $DelayMs
  if ($TopMost) { [M]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x0003) | Out-Null }
}
elseif ($Mode -eq "probe") {
  # 拖动诊断：拖动中截图 + 松手后截图 + 前后窗口矩形（判断是否"实时跟随"还是"只有白框"）
  # -TopMost：浏览器等窗口可能压在上面，测拖动前把目标窗口临时置顶（-1=HWND_TOPMOST）
  if ($TopMost) {
    [M]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0003) | Out-Null
    Start-Sleep -Milliseconds 300
    $r = New-Object M+RECT
    [M]::GetWindowRect($h, [ref]$r) | Out-Null
  }
  Write-Output ("rect_before: {0},{1},{2},{3}" -f $r.L,$r.T,$r.R,$r.B)
  [M]::SetCursorPos($r.L+$X1, $r.T+$Y1) | Out-Null
  Start-Sleep -Milliseconds 200
  [M]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 120
  for ($i=1; $i -le $Steps; $i++) {
    $x = $X1 + ($X2-$X1) * $i / $Steps
    $y = $Y1 + ($Y2-$Y1) * $i / $Steps
    [M]::SetCursorPos($r.L+[int]$x, $r.T+[int]$y) | Out-Null
    Start-Sleep -Milliseconds 40
  }
  Start-Sleep -Milliseconds 400
  $rm = New-Object M+RECT
  [M]::GetWindowRect($h, [ref]$rm) | Out-Null
  Write-Output ("rect_mid: {0},{1},{2},{3}" -f $rm.L,$rm.T,$rm.R,$rm.B)
  Shot $Out
  [M]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 400
  $ra = New-Object M+RECT
  [M]::GetWindowRect($h, [ref]$ra) | Out-Null
  Write-Output ("rect_after: {0},{1},{2},{3}" -f $ra.L,$ra.T,$ra.R,$ra.B)
  if ($Out2 -ne "") { Shot $Out2 }
  if ($TopMost) { [M]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x0003) | Out-Null }
}
elseif ($Mode -eq "hold") {
  # 按住拖动并移动到目标点后**不松手**，先截图（用于验证"实时预览"这类中间态）
  [M]::SetCursorPos($r.L+$X1, $r.T+$Y1) | Out-Null
  Start-Sleep -Milliseconds 200
  [M]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 120
  for ($i=1; $i -le $Steps; $i++) {
    $x = $X1 + ($X2-$X1) * $i / $Steps
    $y = $Y1 + ($Y2-$Y1) * $i / $Steps
    [M]::SetCursorPos($r.L+[int]$x, $r.T+[int]$y) | Out-Null
    Start-Sleep -Milliseconds 25
  }
  Start-Sleep -Milliseconds 500
  Shot $Out
  Start-Sleep -Milliseconds 200
  [M]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
}
elseif ($Mode -eq "hold2") {
  # 按住拖动到 A 截图，再拖到 B 截图（验证「透出的启动页是否实时跟随」），最后松手
  [M]::SetCursorPos($r.L+$X1, $r.T+$Y1) | Out-Null
  Start-Sleep -Milliseconds 200
  [M]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 120
  for ($i=1; $i -le $Steps; $i++) {
    $x = $X1 + ($X2-$X1) * $i / $Steps
    $y = $Y1 + ($Y2-$Y1) * $i / $Steps
    [M]::SetCursorPos($r.L+[int]$x, $r.T+[int]$y) | Out-Null
    Start-Sleep -Milliseconds 25
  }
  Start-Sleep -Milliseconds 350
  Shot $Out
  if ($X3 -ge 0) {
    for ($i=1; $i -le $Steps; $i++) {
      $x = $X2 + ($X3-$X2) * $i / $Steps
      $y = $Y2 + ($Y3-$Y2) * $i / $Steps
      [M]::SetCursorPos($r.L+[int]$x, $r.T+[int]$y) | Out-Null
      Start-Sleep -Milliseconds 25
    }
    Start-Sleep -Milliseconds 350
    Shot $Out2
  }
  [M]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
}
elseif ($Mode -eq "drag") {
  [M]::SetCursorPos($r.L+$X1, $r.T+$Y1) | Out-Null
  Start-Sleep -Milliseconds 200
  [M]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # left down
  Start-Sleep -Milliseconds 120
  for ($i=1; $i -le $Steps; $i++) {
    $x = $X1 + ($X2-$X1) * $i / $Steps
    $y = $Y1 + ($Y2-$Y1) * $i / $Steps
    [M]::SetCursorPos($r.L+[int]$x, $r.T+[int]$y) | Out-Null
    Start-Sleep -Milliseconds 25
  }
  Start-Sleep -Milliseconds 150
  [M]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # left up
  Start-Sleep -Milliseconds 400
  Shot $Out
}
else {
  Shot $Out
}
