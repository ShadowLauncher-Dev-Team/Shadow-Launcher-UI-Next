Add-Type -AssemblyName System.Drawing
foreach ($name in @('ui-bar-loading','ui-bar-ready')) {
  $path = Join-Path 'D:\latest-code\shadow-v2\design\shots' ($name + '.png')
  $b = [System.Drawing.Bitmap]::FromFile($path)
  $n = 0; $first = @()
  for ($y = 0; $y -lt 10; $y++) {
    for ($x = 0; $x -lt $b.Width; $x++) {
      $c = $b.GetPixel($x, $y)
      if ($c.B -gt 120 -and $c.B -gt ($c.R + 30)) { $n++; if ($first.Count -lt 4) { $first += ("$x,$y") } }
    }
  }
  $b.Dispose()
  Write-Output ($name + ': bluePixels=' + $n + ' first=' + ($first -join ' '))
}