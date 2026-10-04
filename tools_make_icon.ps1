param(
  [string]$Out = "D:\Desktop\java\Qoder\test1\PowerToys\src\modules\fancyzones\FancyZonesLib\icon.ico",
  [string]$PreviewDir = ""
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# The mark is the app's own grid preview: accent tile, one dominant zone, two stacked zones.
$TILE  = [System.Drawing.Color]::FromArgb(255, 0x0F, 0x6C, 0xBD)
$MAIN  = [System.Drawing.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF)
$STACK = [System.Drawing.Color]::FromArgb(255, 0x4C, 0xC2, 0xFF)

function Add-RoundRect([System.Drawing.Drawing2D.GraphicsPath]$path, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $d = [math]::Min($r * 2, [math]::Min($w, $h))
  $r = $d / 2
  $path.StartFigure()
  [void]$path.AddArc($x, $y, $d, $d, 180, 90)
  [void]$path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  [void]$path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  [void]$path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
}

function Add-FilledRoundRect([System.Drawing.Graphics]$g, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r, [System.Drawing.Color]$color) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  Add-RoundRect $path $x $y $w $h $r
  $brush = New-Object System.Drawing.SolidBrush $color
  $g.FillPath($brush, $path)
  $brush.Dispose(); $path.Dispose()
}

function Draw-Mark([System.Drawing.Graphics]$g, [single]$size) {
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.Clear([System.Drawing.Color]::Transparent)

  # Small sizes are drawn on whole pixels: resampling a big master leaves the gaps between zones
  # as mud, and at 16px those gaps are the whole design.
  $sharp = $size -le 64
  function Q([single]$v) { if ($sharp) { return [single][math]::Round($v) } return $v }

  $s = $size
  $inset = Q($s * 0.02)
  $tileW = Q($s - 2 * ($s * 0.02))
  Add-FilledRoundRect $g $inset $inset $tileW $tileW (Q($s * 0.225)) $TILE

  $x0 = Q($s * 0.13)
  $y0 = $x0
  $inner = Q($s * 0.74)
  $gap = if ($sharp) { [math]::Max(1, [math]::Round($s * 0.055)) } else { $s * 0.055 }
  $mainW = Q(($inner - $gap) * 0.58)
  $stackW = Q($inner - $gap - $mainW)
  $stackH = Q(($inner - $gap) / 2)
  $mr = Q([math]::Min($s * 0.05, $mainW / 2))
  $sr = Q([math]::Min($s * 0.05, $stackW / 2))
  $mainR = [math]::Max(1, $mr)
  $stackR = [math]::Max(1, $sr)

  Add-FilledRoundRect $g $x0 $y0 $mainW $inner $mainR $MAIN
  $sx = Q($x0 + $mainW + $gap)
  Add-FilledRoundRect $g $sx $y0 $stackW $stackH $stackR $STACK
  Add-FilledRoundRect $g $sx (Q($y0 + $stackH + $gap)) $stackW $stackH $stackR $STACK
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 256)
$blobs = @()
foreach ($sz in $sizes) {
  $small = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gs = [System.Drawing.Graphics]::FromImage($small)
  Draw-Mark $gs $sz
  $gs.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $small.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $blobs += ,($ms.ToArray())
  if ($PreviewDir -ne "") {
    if (-not (Test-Path $PreviewDir)) { New-Item -ItemType Directory -Path $PreviewDir | Out-Null }
    $small.Save("$PreviewDir/icon_$sz.png", [System.Drawing.Imaging.ImageFormat]::Png)
  }
  $ms.Dispose(); $small.Dispose()
}

$headerSize = 6 + 16 * $blobs.Count
$offset = $headerSize
$dir = New-Object byte[] $headerSize
$dir[2] = 1
$dir[4] = [byte]($blobs.Count -band 0xFF)
$dir[5] = [byte](($blobs.Count -shr 8) -band 0xFF)
for ($i = 0; $i -lt $blobs.Count; $i++) {
  $sz = $sizes[$i]
  $b = $blobs[$i]
  $base = 6 + 16 * $i
  $dim = 0
  if ($sz -lt 256) { $dim = [byte]$sz }
  $dir[$base + 0] = $dim
  $dir[$base + 1] = $dim
  $dir[$base + 4] = 1
  $dir[$base + 6] = 32
  for ($k = 0; $k -lt 4; $k++) {
    $dir[$base + 8 + $k] = [byte](($b.Length -shr (8 * $k)) -band 0xFF)
    $dir[$base + 12 + $k] = [byte](($offset -shr (8 * $k)) -band 0xFF)
  }
  $offset += $b.Length
}

$fs = [System.IO.File]::Create($Out)
$fs.Write($dir, 0, $dir.Length)
foreach ($b in $blobs) { $fs.Write($b, 0, $b.Length) }
$fs.Close()
$total = $headerSize + ($blobs | Measure-Object -Property Length -Sum).Sum
Write-Output ("wrote {0} ({1} bytes, {2} images)" -f $Out, $total, $blobs.Count)
