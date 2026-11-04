<#
.SYNOPSIS
  启动浮层安全探针：用后端假状态机（--ui-demo-*）画浮层，通过应用自带的
  ScreenshotServer（127.0.0.1:9999）抓图与执行 QML 表达式，绝不启动游戏。

.DESCRIPTION
  取代旧的 overlay-probe.ps1（那个会真点"启动"按钮，坐标算错就真的把 Minecraft 起起来，
  2026-11-04 已经误启动过两次）。

  为什么不用鼠标模拟：无人值守环境下 SetForegroundWindow 会静默失败，
  SendMessage 的 WM_LBUTTON* 到 Qt 也不生效（实测）。应用本身带 HTTP 接口：
    GET  /screenshot        → window->grabWindow() 的 PNG（逻辑像素，和用户看到的一致）
    POST /eval {"qml":"..."} → 在 QML 上下文求值，例如 backend.cancelLaunch()
  用它既准又不依赖前台窗口。

  浮层状态全部由 LaunchBackend::demoLaunch() 的假状态机驱动（不检测 Java、不拉文件、不起进程）。

.EXAMPLE
  .\overlay-demo.ps1 -Mode online -WaitMs 2500 -Out shots/or-a.png
  .\overlay-demo.ps1 -Mode online -WaitMs 2500 -Eval 'backend.cancelLaunch()' -Out shots/or-cancel.png
  .\overlay-demo.ps1 -Mode online-fail -Size 800x550 -WaitMs 4000 -Out shots/or-err-800.png
#>
param(
    [ValidateSet('ok','fail','online','online-fail')][string]$Mode = 'ok',
    [string]$Size = '',
    [int]$WaitMs = 2500,
    [string]$Eval = '',
    [string]$Out = 'shot-overlay.png',
    [string]$Exe = '',
    [int]$Port = 9999
)
$ErrorActionPreference = 'Stop'
if ($Exe -eq '') {
    $Exe = Join-Path (Split-Path -Parent $PSScriptRoot) 'build\Release\ShadowLauncher.exe'
}
if (-not (Test-Path $Exe)) { throw "exe not found: $Exe" }

$launchArgs = @('--ui-next', '--ui-demo-launch')
switch ($Mode) {
    'fail'        { $launchArgs += '--ui-demo-fail' }
    'online'      { $launchArgs += '--ui-demo-online' }
    'online-fail' { $launchArgs += @('--ui-demo-fail', '--ui-demo-online') }
}
if ($Size -ne '') { $launchArgs += @('--ui-size', $Size) }

$base = 'http://127.0.0.1:' + $Port
$proc = Start-Process -FilePath $Exe -ArgumentList $launchArgs -PassThru
try {
    # 等 ScreenshotServer 起来（应用首帧渲染后开始监听）
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 400
        $proc.Refresh()
        if ($proc.HasExited) { throw ('process exited with code ' + $proc.ExitCode) }
        try {
            $null = Invoke-WebRequest -Uri ($base + '/screenshot') -UseBasicParsing -TimeoutSec 2
            $ready = $true; break
        } catch { }
    }
    if (-not $ready) { throw 'screenshot server not reachable' }

    Start-Sleep -Milliseconds $WaitMs

    if ($Eval -ne '') {
        $body = @{ qml = $Eval } | ConvertTo-Json -Compress
        $resp = Invoke-WebRequest -Uri ($base + '/eval') -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 5
        ('eval -> ' + $resp.Content)
        Start-Sleep -Milliseconds 800
    }

    $img = Invoke-WebRequest -Uri ($base + '/screenshot') -UseBasicParsing -TimeoutSec 10
    [System.IO.File]::WriteAllBytes($Out, $img.Content)
    ('captured ' + $Out + ' mode=' + $Mode)
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
