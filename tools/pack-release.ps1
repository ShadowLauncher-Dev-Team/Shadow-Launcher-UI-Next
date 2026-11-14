# SPDX-License-Identifier: AGPL-3.0-or-later
# Shadow Launcher release packager for this checkout (shadow-v2).
#
# The stale pack.ps1 in the repo root still points at D:\latest-code\cpp (the
# old project). Here QML lives in ui/ and is compiled into the exe, so no QML
# source folder needs shipping -- only the Qt runtime, our own binaries and the
# EasyTier helpers.
param(
    [string]$ProjectRoot = "D:\latest-code\shadow-v2",
    [string]$QtDir       = "C:\Qt\6.8.3\msvc2022_64"
)
$ErrorActionPreference = "Stop"
$BuildDir = Join-Path $ProjectRoot "build\Release"
$DistRoot = Join-Path $ProjectRoot "dist"
$Stage    = Join-Path $DistRoot "ShadowLauncher"
$Windeployqt = Join-Path $QtDir "bin\windeployqt.exe"
$OneMB = 1048576

$verFile = Join-Path $ProjectRoot "src\version.h"
$ver = "v0.0.0"
if (Test-Path $verFile) {
    $m = Select-String -Path $verFile -Pattern 'SHADOW_DISPLAY_VERSION\s+"([^"]+)"' | Select-Object -First 1
    if ($m) { $ver = $m.Matches.Groups[1].Value }
}
Write-Host "Shadow Launcher packager  version=$ver"
Write-Host "  build : $BuildDir"
Write-Host "  stage : $Stage"

# ---- 0. preflight ----
$exe = Join-Path $BuildDir "ShadowLauncher.exe"
if (-not (Test-Path $exe)) { throw "ShadowLauncher.exe not found - build first" }
Get-Process ShadowLauncher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# ---- 1. clean staging ----
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

# ---- 2. our own binaries only (never the build's .exp/.lib/test exes) ----
foreach ($f in @("ShadowLauncher.exe", "SLUpdater.exe", "wv2login.exe", "WebView2Loader.dll", "agreement_consent.txt", "versions.json")) {
    $src = Join-Path $BuildDir $f
    if (Test-Path $src) { Copy-Item $src $Stage -Force; Write-Host "  + $f" }
    else { Write-Host "  ! missing $f" -ForegroundColor Yellow }
}
$binSrc = Join-Path $BuildDir "bin"
if (Test-Path $binSrc) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage "bin") | Out-Null
    Get-ChildItem $binSrc -File | Where-Object { $_.Extension -ne ".bak" } | Copy-Item -Destination (Join-Path $Stage "bin") -Force
    Write-Host ('  + bin/ (' + (Get-ChildItem (Join-Path $Stage 'bin') -File).Count + ' files)')
}

# ---- 3. Qt runtime via windeployqt ----
Write-Host "  windeployqt..."
Push-Location $Stage
try {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $Windeployqt "ShadowLauncher.exe" --no-translations --qmldir "$ProjectRoot\ui" 2>&1 |
        Where-Object { $_ -match "Warning|error|Cannot" } | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    $ErrorActionPreference = $prev
} finally { Pop-Location }

# ---- 4. MSVC runtime (windeployqt sometimes skips these) ----
$crt = @("vcruntime140.dll","vcruntime140_1.dll","msvcp140.dll","msvcp140_1.dll","msvcp140_2.dll","concrt140.dll")
$pfx86 = [Environment]::GetFolderPath('ProgramFilesX86')
$redist = Join-Path $pfx86 "Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC"
$redistDir = Get-ChildItem "$redist\*\x64\Microsoft.VC143.CRT" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
foreach ($d in $crt) {
    $dst = Join-Path $Stage $d
    if (Test-Path $dst) { continue }
    $cand = @((Join-Path $BuildDir $d), (Join-Path $env:WINDIR ("System32\" + $d)))
    if ($redistDir) { $cand = @((Join-Path $redistDir.FullName $d)) + $cand }
    $hit = $cand | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($hit) { Copy-Item $hit $dst -Force; Write-Host "  + $d" }
    else { Write-Host "  ! $d not found" -ForegroundColor Yellow }
}

# ---- 4b. graphics fallbacks: D3D shader compilers + software GL ----
# 没有这些，一台没装显卡驱动/没装 D3D 编译器的机器会黑屏或白屏；
# windeployqt 在 VCINSTALLDIR 未设置时找不到 dxcompiler/dxil，所以从 build 目录补齐。
foreach ($d in @("D3Dcompiler_47.dll","dxcompiler.dll","dxil.dll","opengl32sw.dll")) {
    $dst = Join-Path $Stage $d
    if (Test-Path $dst) { continue }
    $src = Join-Path $BuildDir $d
    if (Test-Path $src) { Copy-Item $src $dst -Force; Write-Host "  + $d (fallback)" }
}

# ---- 5. trim QuickControls2 styles: the app forces Basic (main_release.cpp) ----
$keep = @("Qt6QuickControls2.dll","Qt6QuickControls2Impl.dll","Qt6QuickControls2Basic.dll","Qt6QuickControls2BasicStyleImpl.dll")
Get-ChildItem (Join-Path $Stage "Qt6QuickControls2*.dll") -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin $keep } | Remove-Item -Force -ErrorAction SilentlyContinue
$qs = Join-Path $Stage "qml\QtQuick\Controls"
# 只删已知的风格目录；impl / designer 这些是模块骨架，删了 QML 会报
# "module QtQuick.Controls.impl is not installed"（实测过）。
if (Test-Path $qs) {
    $dropStyles = @("Fusion","Material","Universal","Imagine","FluentWinUI3","Windows","macOS","iOS","Android")
    Get-ChildItem $qs -Directory | Where-Object { $_.Name -in $dropStyles } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ('  kept controls dirs -> ' + ((Get-ChildItem $qs -Directory).Name -join ', '))
}

# ---- 6. never ship build leftovers ----
foreach ($junk in @("ShadowLauncher.exp","ShadowLauncher.lib","verify_test_result.txt","ModpackExportTest.exe")) {
    $p = Join-Path $Stage $junk
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  - $junk" }
}

# ---- 7. zip ----
$zip = Join-Path $DistRoot ("ShadowLauncher-" + $ver + "-win64.zip")
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($Stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
$files = (Get-ChildItem $Stage -Recurse -File).Count
$rawMB = [math]::Round(((Get-ChildItem $Stage -Recurse -File | Measure-Object Length -Sum).Sum) / $OneMB, 1)
$zipMB = [math]::Round((Get-Item $zip).Length / $OneMB, 1)
Write-Host ""
Write-Host ("DONE  " + $zip)
Write-Host ("      staged " + $files + " files, " + $rawMB + " MB  ->  zip " + $zipMB + " MB")