# UI 契约检查：把"已经踩过并且已经修好"的坑，变成构建期硬失败。
# 用法：powershell -File tools/check-ui-contract.ps1 -UiDir <ui 目录>
param(
    [Parameter(Mandatory = $true)][string]$UiDir
)

$ErrorActionPreference = 'Stop'
$files = Get-ChildItem -Path $UiDir -Recurse -File -Include *.qml, *.js
if ($files.Count -eq 0) { Write-Host "no QML files under $UiDir"; exit 1 }

$problems = New-Object System.Collections.Generic.List[string]

function Add-Problem([string]$file, [int]$line, [string]$msg) {
    $problems.Add(($file + ':' + $line + '  ' + $msg))
}

foreach ($f in $files) {
    $rel = $f.FullName.Substring($UiDir.Length).TrimStart([char]92)
    # 必须显式按 UTF-8 读：PS5.1 的 Get-Content 默认按系统 ANSI(GBK) 解码无 BOM 的
    # UTF-8 文件，中文注释会被解成乱码字节，随机命中"emoji/符号"规则 → 假失败。
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $i + 1
        $t = $lines[$i]

        # 1) 版本号装饰重复：appVersion 已是完整显示串（含 v 前缀，见 src/version.h）
        if ($t -match '["'']v["'']\s*\+') { Add-Problem $rel $ln '版本号前缀重复：appVersion 已含 v，禁止再拼' }
        if ($t -match 'appVersion\s*\+') { Add-Problem $rel $ln 'appVersion 被拼接/装饰，应原样显示' }

        # 2) emoji / 符号当图标（项目铁律：图标只用 lucide SVG）
        #    只查真正的 QML 代码行：注释里的箭头和符号不是图标，不该被这条规则误伤
        $isComment = $t.TrimStart().StartsWith('//')
        if (-not $isComment -and ($t -match '[\uD800-\uDFFF]' -or $t -match '[\u2190-\u21FF\u2600-\u27BF\u2B00-\u2BFF]')) {
            Add-Problem $rel $ln '疑似 emoji/符号做图标，图标须用 qml/icons/lucide 下的 SVG'
        }

        # 3) SpringAnimation 实测数值发散到 ±Infinity
        if ($t -match 'SpringAnimation') { Add-Problem $rel $ln '禁止 SpringAnimation（会发散到 ±Infinity）' }

        # 4) font.pixelSize 是 int，小数会让整页加载失败
        if ($t -match 'font\.pixelSize\s*:\s*-?\d+\.\d+') {
            Add-Problem $rel $ln 'font.pixelSize 是 int，不能写小数'
        }
    }
}

if ($problems.Count -gt 0) {
    Write-Host 'UI contract violations:' -ForegroundColor Red
    foreach ($p in $problems) { Write-Host ('  ' + $p) -ForegroundColor Red }
    exit 1
}

Write-Host ('UI contract OK (' + $files.Count + ' files)')
exit 0
