Add-Type -AssemblyName System.Drawing

$outDir = 'C:\Users\mu\Desktop\code\thirty\HarmonyMarkdownWorkbench\AppScope\resources\base\media'

function New-GradientBackground([string]$path) {
  $size = 1024
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
  $c1 = [System.Drawing.Color]::FromArgb(255, 32, 42, 78)
  $c2 = [System.Drawing.Color]::FromArgb(255, 74, 104, 224)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 90)
  $g.FillRectangle($brush, $rect)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $brush.Dispose(); $bmp.Dispose()
}

function New-Foreground([string]$path) {
  $size = 1024
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $font = New-Object System.Drawing.Font('Segoe UI', 560, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $rectF = New-Object System.Drawing.RectangleF(0, -40, $size, $size)
  $g.DrawString('M', $font, [System.Drawing.Brushes]::White, $rectF, $sf)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $font.Dispose(); $sf.Dispose(); $bmp.Dispose()
}

New-GradientBackground (Join-Path $outDir 'background.png')
New-Foreground (Join-Path $outDir 'foreground.png')
Write-Host 'icons generated'