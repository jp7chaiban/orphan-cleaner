<#
.SYNOPSIS
  Draws the Orphan Cleaner icon with GDI+ (System.Drawing, built into Windows) and writes:
    assets\icon.ico            multi-size icon for the exe and window (16-256 px)
    assets\icon.png            512 px logo for the README
    assets\social-preview.png  1280x640 image for the GitHub social preview
  The drawing matches assets\icon.svg (48 px and up) and assets\icon-small.svg (below 48 px).
  Only needed after changing the design; the outputs are committed.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repo   = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $repo 'assets'

function C([string]$hex, [int]$alpha = 255) {
    $c = [Drawing.ColorTranslator]::FromHtml($hex); [Drawing.Color]::FromArgb($alpha, $c.R, $c.G, $c.B)
}
function RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath; $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); $p
}
function RoundPen($color, [single]$width) {
    $pen = New-Object Drawing.Pen $color, $width
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen
}
function Disc($g, $brush, [single]$cx, [single]$cy, [single]$r) { $g.FillEllipse($brush, $cx - $r, $cy - $r, 2 * $r, 2 * $r) }
function Solid([string]$hex, [int]$alpha = 255) { New-Object Drawing.SolidBrush (C $hex $alpha) }

# Detailed art on a 256-unit canvas (see icon.svg).
function Draw-Detailed($g) {
    $bg = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 8, 8), (New-Object Drawing.PointF 248, 248), (C '#5B5BF0'), (C '#1E1B4B')
    $g.FillPath($bg, (RoundRect 8 8 240 240 56))
    $g.DrawPath((New-Object Drawing.Pen (C '#FFFFFF' 36), 1), (RoundRect 8.5 8.5 239 239 55.5))

    $link = RoundPen (C '#E0E7FF') 14
    $g.DrawLine($link, 78, 78, 78, 178)                       # live branch
    $g.DrawLine($link, 78, 78, 113, 113)                      # cut branch, first half
    $faint = Solid '#E0E7FF' 115
    Disc $g $faint 143 143 7; Disc $g $faint 158 158 7        # cut branch, fading remainder
    $g.DrawLine((RoundPen (C '#FDBA4D') 8), 104, 136, 136, 104)   # cut mark

    Disc $g (Solid '#FFFFFF') 78 78 26; Disc $g (Solid '#4F46E5') 78 78 10
    Disc $g (Solid '#C7D2FE') 78 182 20

    $glowPath = New-Object Drawing.Drawing2D.GraphicsPath; $glowPath.AddEllipse(122, 122, 112, 112)
    $glow = New-Object Drawing.Drawing2D.PathGradientBrush $glowPath
    $glow.CenterColor = C '#FB923C' 140; $glow.SurroundColors = @(C '#FB923C' 0)
    $g.FillPath($glow, $glowPath)
    $orphan = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 0, 144), (New-Object Drawing.PointF 0, 212), (C '#FDBA4D'), (C '#F97316')
    Disc $g $orphan 178 178 34
    $g.DrawEllipse((New-Object Drawing.Pen (C '#FFFFFF' 90), 3), 144, 144, 68, 68)
    $x = RoundPen (C '#FFFFFF') 9
    $g.DrawLine($x, 164, 164, 192, 192); $g.DrawLine($x, 192, 164, 164, 192)
}

# Simplified art on a 32-unit canvas (see icon-small.svg).
function Draw-Small($g) {
    $bg = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 0, 0), (New-Object Drawing.PointF 32, 32), (C '#5B5BF0'), (C '#1E1B4B')
    $g.FillPath($bg, (RoundRect 0.5 0.5 31 31 7))
    $link = RoundPen (C '#E0E7FF') 2.6
    $g.DrawLine($link, 9, 9, 9, 23); $g.DrawLine($link, 9, 9, 13.5, 13.5)
    Disc $g (Solid '#FFFFFF') 9 9 4; Disc $g (Solid '#C7D2FE') 9 23.5 2.8
    Disc $g (Solid '#F97316') 22 22 6.5
    $x = RoundPen (C '#FFFFFF') 1.9
    $g.DrawLine($x, 19.4, 19.4, 24.6, 24.6); $g.DrawLine($x, 24.6, 19.4, 19.4, 24.6)
}

function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    @($bmp, $g)
}

function Render-Icon([int]$size) {
    $bmp, $g = New-Canvas $size $size
    if ($size -ge 48) { $g.ScaleTransform($size / 256, $size / 256); Draw-Detailed $g }
    else { $g.ScaleTransform($size / 32, $size / 32); Draw-Small $g }
    $g.Dispose(); $bmp
}

# Classic icon frame: BITMAPINFOHEADER + 32-bit BGRA rows bottom-up + 1-bit AND mask.
# (Used below 256 px; .NET's Icon class can't decode PNG frames, and the window icon goes through it.)
function DibFrame($bmp) {
    $w = $bmp.Width; $h = $bmp.Height
    $data = $bmp.LockBits((New-Object Drawing.Rectangle 0, 0, $w, $h), 'ReadOnly', ([Drawing.Imaging.PixelFormat]::Format32bppArgb))
    $px = New-Object byte[] ($data.Stride * $h)
    [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length); $bmp.UnlockBits($data)
    $maskStride = [int]([math]::Ceiling($w / 32) * 4)
    $out = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter $out
    $bw.Write([UInt32]40); $bw.Write([Int32]$w); $bw.Write([Int32]($h * 2)); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]0); $bw.Write([UInt32]($w * $h * 4 + $maskStride * $h)); $bw.Write([Int32]0); $bw.Write([Int32]0); $bw.Write([UInt32]0); $bw.Write([UInt32]0)
    for ($y = $h - 1; $y -ge 0; $y--) { $bw.Write($px, $y * $data.Stride, $w * 4) }
    $bw.Write((New-Object byte[] ($maskStride * $h)))   # all-zero mask: alpha channel decides
    $bw.Flush(); $out.ToArray()
}

# ---- icon.ico: 256 px as PNG, smaller sizes as classic bitmaps ----
$sizes = 256, 128, 64, 48, 32, 24, 16
$blobs = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($s in $sizes) {
    $b = Render-Icon $s
    if ($s -ge 256) { $frame = New-Object IO.MemoryStream; $b.Save($frame, [Drawing.Imaging.ImageFormat]::Png); $blobs.Add($frame.ToArray()) }
    else { $blobs.Add((DibFrame $b)) }
    $b.Dispose()
}
$ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter $ms
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32); $bw.Write([UInt32]$blobs[$i].Length); $bw.Write([UInt32]$offset)
    $offset += $blobs[$i].Length
}
foreach ($blob in $blobs) { $bw.Write($blob) }
$bw.Flush(); [IO.File]::WriteAllBytes((Join-Path $assets 'icon.ico'), $ms.ToArray())

# ---- icon.png: README logo ----
$logo = Render-Icon 512; $logo.Save((Join-Path $assets 'icon.png'), [Drawing.Imaging.ImageFormat]::Png); $logo.Dispose()

# ---- social-preview.png: 1280x640 ----
$bmp, $g = New-Canvas 1280 640
$bg = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Rectangle 0, 0, 1280, 640), (C '#0F172A'), (C '#312E81'), 30
$blend = New-Object Drawing.Drawing2D.ColorBlend 3
$blend.Colors = @((C '#0F172A'), (C '#1E1B4B'), (C '#312E81')); $blend.Positions = @(0, 0.6, 1)
$bg.InterpolationColors = $blend
$g.FillRectangle($bg, 0, 0, 1280, 640)
for ($i = 12; $i -ge 1; $i--) {   # soft shadow under the icon
    $g.FillPath((Solid '#000000' 9), (RoundRect (96 + 300 * 8 / 256 - $i) (194 + 300 * 8 / 256 - $i) (300 * 240 / 256 + 2 * $i) (300 * 240 / 256 + 2 * $i) (300 * 56 / 256 + $i)))
}
$icon = Render-Icon 300; $g.DrawImage($icon, 96, 170, 300, 300); $icon.Dispose()
$px = [Drawing.GraphicsUnit]::Pixel
$g.DrawString('Orphan Cleaner', (New-Object Drawing.Font 'Segoe UI', 84, ([Drawing.FontStyle]::Bold), $px), (Solid '#FFFFFF'), 452, 168)
$g.DrawString("Find and kill the processes your`ncoding agents leave behind.", (New-Object Drawing.Font 'Segoe UI', 36, ([Drawing.FontStyle]::Regular), $px), (Solid '#C7D2FE'), 458, 290)
$dot = [string][char]0x00B7   # middle dot, kept ASCII-safe for Windows PowerShell 5.1
$g.DrawString("Windows  $dot  macOS  $dot  Linux  $dot  Agent skill", (New-Object Drawing.Font 'Segoe UI Semibold', 28, ([Drawing.FontStyle]::Regular), $px), (Solid '#FDBA4D'), 460, 418)
$g.Dispose(); $bmp.Save((Join-Path $assets 'social-preview.png'), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

Get-ChildItem $assets -File | Select-Object Name, Length | Format-Table -AutoSize | Out-String | Write-Host
