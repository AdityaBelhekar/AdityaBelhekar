# Builds the README images into assets\: the hero card and the project cards.
# Run: powershell -File card.ps1   (edit the text below, re-run, commit assets\*.jpg)
# Keep this file ASCII-only; Windows PowerShell misreads UTF-8 without a BOM.
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class CardBg {
    // Flat colour with a soft vignette and monochrome film grain. Fixed seed so rebuilds are identical.
    public static Bitmap Make(int w, int h, Color c, double grain) {
        var bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb);
        var d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, bmp.PixelFormat);
        var buf = new byte[d.Stride * h];
        var rnd = new Random(3301);
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
            double dx = (x - w / 2.0) / (w / 2.0), dy = (y - h / 2.0) / (h / 2.0);
            double v = 1.6 - 0.9 * (dx * dx * 0.7 + dy * dy);   // lifts the centre a little
            double n = Math.Abs(rnd.NextDouble() + rnd.NextDouble() - 1) * grain;
            int i = y * d.Stride + x * 3;
            buf[i]     = Clamp(c.B * v + n);
            buf[i + 1] = Clamp(c.G * v + n);
            buf[i + 2] = Clamp(c.R * v + n);
        }
        Marshal.Copy(buf, 0, d.Scan0, buf.Length);
        bmp.UnlockBits(d);
        return bmp;
    }
    // Turns a grey cutout into a tinted overlay: brightness becomes opacity, and the colour
    // switches from l to r where the placed image crosses the card's diagonal cut.
    public static Bitmap Tint(Image src, Color l, Color r, double ox, double oy, double s,
                              double cutTop, double cutBottom, double cardH, double floor, double strength) {
        var a = new Bitmap(src);  // 32bpp ARGB copy
        var rect = new Rectangle(0, 0, a.Width, a.Height);
        var d = a.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        var buf = new byte[d.Stride * a.Height];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        for (int y = 0; y < a.Height; y++) {
            double cut = cutTop + (cutBottom - cutTop) * (oy + y * s) / cardH;
            for (int x = 0; x < a.Width; x++) {
                int i = y * d.Stride + x * 4;
                double lum = (0.114 * buf[i] + 0.587 * buf[i + 1] + 0.299 * buf[i + 2]) / 255 * buf[i + 3] / 255;
                double v = Math.Max(0, (lum - floor) / (1 - floor));  // floor drops the haze around the cutout
                Color c = ox + x * s < cut ? l : r;
                buf[i] = c.B; buf[i + 1] = c.G; buf[i + 2] = c.R;
                buf[i + 3] = Clamp(255 * v * strength);
            }
        }
        Marshal.Copy(buf, 0, d.Scan0, buf.Length);
        a.UnlockBits(d);
        return a;
    }
    // Greyscale copy with the red and blue channels pulled d pixels apart: a glitch fringe on edges
    public static Bitmap Glitch(Image src, int d, double gain) {
        var a = new Bitmap(src);
        var bd = a.LockBits(new Rectangle(0, 0, a.Width, a.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        var buf = new byte[bd.Stride * a.Height];
        Marshal.Copy(bd.Scan0, buf, 0, buf.Length);
        var o = (byte[])buf.Clone();
        for (int y = 0; y < a.Height; y++) for (int x = 0; x < a.Width; x++) {
            int row = y * bd.Stride, i = row + x * 4;
            o[i]     = Clamp(Lum(buf, row + Math.Max(0, x - d) * 4) * gain);
            o[i + 1] = Clamp(Lum(buf, i) * gain);
            o[i + 2] = Clamp(Lum(buf, row + Math.Min(a.Width - 1, x + d) * 4) * gain);
        }
        Marshal.Copy(o, 0, bd.Scan0, o.Length);
        a.UnlockBits(bd);
        return a;
    }
    static double Lum(byte[] b, int i) { return 0.114 * b[i] + 0.587 * b[i + 1] + 0.299 * b[i + 2]; }
    static byte Clamp(double c) { return (byte)Math.Max(0, Math.Min(255, c)); }
}
'@

$W = 1916; $H = 821
$black = '#08070B'; $red = '#D21319'; $blue = '#3350FF'; $stone = '#AFAEA2'

function C($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
function Brush($hex) { New-Object Drawing.SolidBrush (C $hex) }

$bmp = [CardBg]::Make($W, $H, (C $black), 30)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$fmt = [Drawing.StringFormat]::GenericTypographic.Clone()
$fmt.FormatFlags = $fmt.FormatFlags -bor [Drawing.StringFormatFlags]::MeasureTrailingSpaces

# Text as an outline path at the origin, drawn at 100px; $track adds letterspacing
function P($s, $family, $style = 0, $track = 0) {
    $ff = New-Object Drawing.FontFamily $family
    $font = New-Object Drawing.Font $ff, 100, ([Drawing.FontStyle]$style), ([Drawing.GraphicsUnit]::Pixel)
    $path = New-Object Drawing.Drawing2D.GraphicsPath; $x = 0
    foreach ($c in $(if ($track) { $s.ToCharArray() } else { , $s })) {
        $c = [string]$c
        $path.AddString($c, $ff, $style, 100, (New-Object Drawing.PointF $x, 0), $fmt)
        $x += $g.MeasureString($c, $font, [Drawing.PointF]::Empty, $fmt).Width + $track
    }
    , $path
}
# Places a path. -Ht fits the ink box to a height at x,y. -Sc scales the raw 100px text from
# its line origin, so rows of monospace text share a baseline. Fills unless $hex is empty.
function Put($path, $x, $y, $hex, $Ht = 0, $Sc = 0, [switch]$Right, [switch]$Center) {
    $b = $path.GetBounds(); $s = 1.0
    if ($Sc) { $s = $Sc } elseif ($Ht) { $s = $Ht / $b.Height }
    $tx = $x; if ($Right) { $tx = $x - $b.Width * $s }; if ($Center) { $tx = $x - $b.Width * $s / 2 }
    $m = New-Object Drawing.Drawing2D.Matrix
    $m.Translate($tx, $y); $m.Scale($s, $s)
    if (-not $Sc) { $m.Translate(-$b.X, -$b.Y) }
    $path.Transform($m)
    if ($hex) { $g.FillPath((Brush $hex), $path) }
}

# The diagonal cut between the two teams
$cutTop = 1040; $cutBottom = 876
$left = New-Object Drawing.Drawing2D.GraphicsPath
$left.AddPolygon([Drawing.PointF[]]@((New-Object Drawing.PointF 0, 0), (New-Object Drawing.PointF $cutTop, 0), (New-Object Drawing.PointF $cutBottom, $H), (New-Object Drawing.PointF 0, $H)))
# Centred text that is red left of the cut and blue right of it, with a few rows knocked
# sideways like a corrupted scanline. Each displaced row leaves a ghost in the other colour.
$bands = @(@(322, 342, 24), @(486, 516, -28))  # y0, y1, shift
function Sides($path, $lc, $rc) {
    $base = $g.Clip
    $g.SetClip($left, [Drawing.Drawing2D.CombineMode]::Intersect); $g.FillPath($lc, $path)
    $g.Clip = $base; $g.SetClip($left, [Drawing.Drawing2D.CombineMode]::Exclude); $g.FillPath($rc, $path)
    $g.Clip = $base
}
function Shifted($path, $dx) {
    $c = $path.Clone(); $m = New-Object Drawing.Drawing2D.Matrix; $m.Translate($dx, 0); $c.Transform($m); , $c
}
function Split($s, $family, $y, $ht, $cx = $W / 2) {
    $p = P $s $family; Put $p $cx $y '' -Ht $ht -Center
    $r = Brush $red; $b = Brush $blue
    $ghostR = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(150, (C $red)))
    $ghostB = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(150, (C $blue)))
    $g.SetClip((New-Object Drawing.Rectangle 0, 0, $W, $H))
    foreach ($bd in $bands) { $g.SetClip((New-Object Drawing.Rectangle 0, $bd[0], $W, ($bd[1] - $bd[0])), [Drawing.Drawing2D.CombineMode]::Exclude) }
    Sides $p $r $b
    foreach ($bd in $bands) {
        $g.SetClip((New-Object Drawing.Rectangle 0, $bd[0], $W, ($bd[1] - $bd[0])))
        Sides (Shifted $p ($bd[2] * 1.6)) $ghostB $ghostR
        Sides (Shifted $p $bd[2]) $r $b
    }
    $g.ResetClip()
}

# Scorpion behind everything, tinted to match whichever side of the cut it is on
$art = [Drawing.Image]::FromFile("$PSScriptRoot\assets\scorpion.png")
$artScale = 1.15; $artX = ($W - $art.Width * $artScale) / 2; $artY = -170
$tinted = [CardBg]::Tint($art, (C $red), (C $blue), $artX, $artY, $artScale, $cutTop, $cutBottom, $H, 0.22, 0.5)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($tinted, [float]$artX, [float]$artY, [float]($art.Width * $artScale), [float]($art.Height * $artScale))
$art.Dispose(); $tinted.Dispose()

$g.DrawLine((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(70, (C $stone))), 2), $cutTop, 0, $cutBottom, $H)

$m = 80  # side margin
Put (P 'RED TEAM' 'Impact') $m 60 $red -Ht 40
Put (P '// OFFENCE' 'Consolas' 1 8) $m 116 $red -Ht 18
Put (P 'BLUE TEAM' 'Impact') ($W - $m) 60 $blue -Ht 40 -Right
Put (P 'DEFENCE //' 'Consolas' 1 8) ($W - $m) 116 $blue -Ht 18 -Right

Split '0xAD1' 'Impact' 240 340 1024  # nudged right so the cut falls between 0x and AD1

$y = 300
foreach ($l in '$ nmap -sV -p- target', '$ gobuster dir -u target', '$ sqlmap --batch', '$ hydra -l admin', '$ nc -lvnp 4444') {
    Put (P $l 'Consolas' 1) $m $y $red -Sc 0.21; $y += 38
}
$y = 300
foreach ($l in '$ tail -f auth.log', '$ tcpdump -i eth0', '$ fail2ban-client status', '$ ufw default deny', '$ grep -c Failed') {
    Put (P $l 'Consolas' 1) ($W - $m) $y $blue -Sc 0.21 -Right; $y += 38
}

Put (P 'BREAK. DEFEND. REPEAT.' 'Consolas' 1 14) ($W / 2) 686 $stone -Ht 26 -Center
Put (P 'CYBERSECURITY / FINAL YEAR CSE / PUNE, INDIA' 'Consolas' 1 6) ($W / 2) 742 $stone -Ht 18 -Center
Put (P 'ADITYA BELHEKAR' 'Consolas' 1 6) $m 738 $red -Ht 22
Put (P '127.0.0.1' 'Consolas' 1 6) ($W - $m) 738 $blue -Ht 22 -Right

$jpeg = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$q = New-Object Drawing.Imaging.EncoderParameters 1
$q.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality, [long]92)
function SaveJpg($name) {
    $bmp.Save("$PSScriptRoot\assets\$name.jpg", $jpeg, $q); $g.Dispose(); $bmp.Dispose()
    "assets\$name.jpg  $([int]((Get-Item "$PSScriptRoot\assets\$name.jpg").Length / 1KB)) KB"
}
SaveJpg 'card'

# Project cards, shown side by side under the hero
function ProjectCard($name, $tag, $title, $hex, $lines, $foot) {
    $cw = 900; $ch = 520; $pad = 50
    $bmp = [CardBg]::Make($cw, $ch, (C $black), 30)
    $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
    $g.FillRectangle((Brush $hex), 0, 0, $cw, 8)
    Put (P $tag 'Consolas' 1 8) $pad 60 $hex -Ht 18
    Put (P $title 'Impact') $pad 110 $hex -Ht 110
    $y = 256; foreach ($l in $lines) { Put (P $l 'Consolas' 1) $pad $y $stone -Sc 0.30; $y += 44 }
    Put (P $foot 'Consolas' 1 6) $pad 468 $hex -Ht 18
    Put (P 'OPEN ->' 'Consolas' 1 6) ($cw - $pad) 468 $stone -Ht 18 -Right
    SaveJpg $name
}
ProjectCard 'agentshield' '01 // BLUE TEAM' 'AGENTSHIELD' $blue @(
    'Runtime security layer for AI agents.',
    'Catches prompt injection, jailbreaks,',
    'tool abuse and memory poisoning',
    'before the agent acts.'
) 'PIP INSTALL AGENTSHIELD-X'
ProjectCard 'sheep' '02 // EXPERIMENT' 'SHEEP' $red @(
    'A sandbox where AI models argue,',
    'test and prove each other wrong,',
    'chasing answers that are actually new.'
) 'MULTI-MODEL / ADVERSARIAL'

# Canvas for the full-width sections below the hero
function Canvas($cw, $ch) {
    $script:bmp = [CardBg]::Make($cw, $ch, (C $black), 30)
    $script:g = [Drawing.Graphics]::FromImage($script:bmp)
    $script:g.SmoothingMode = 'AntiAlias'; $script:g.InterpolationMode = 'HighQualityBicubic'
}
# A shell prompt line: stone "$", then the command in colour
function Prompt($cmd, $x, $y, $hex) {
    Put (P '$' 'Consolas' 1) $x $y $stone -Sc 0.5
    Put (P $cmd 'Consolas' 1) ($x + 56) $y $hex -Sc 0.5
}

# Thin section header
function Strip($name, $cmd, $hex) {
    Canvas 1916 150
    Prompt $cmd 80 46 $hex
    $x = 80 + 56 + $cmd.Length * 27.5 + 36
    $g.DrawLine((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(110, (C $hex))), 2), [float]$x, 78, 1836, 78)
    SaveJpg $name
}
Strip 'projects' 'ls ./projects' $blue
Strip 'fortune' 'fortune' $red

# About section: bio on the left, portrait on the right
Canvas 1916 760
Prompt 'whoami' 80 66 $red
$p = P 'HELLO, I''M' 'Impact'; Put $p 80 164 $red -Ht 92
Put (P 'ADITYA.' 'Impact') ($p.GetBounds().Right + 30) 164 $blue -Ht 92
$y = 300
foreach ($l in 'Final year CSE student from Pune, India.',
               'Into cybersecurity, Linux, and figuring out',
               'how systems work and how they break.',
               'I like building small tools along the way.') {
    Put (P $l 'Consolas' 1) 80 $y $stone -Sc 0.30; $y += 46
}
$y = 524; $i = 0
foreach ($row in @('alias', '0xAD1'), @('study', 'final year cse, des pune university'),
                 @('into', 'cybersecurity, offence and defence'), @('os', 'linux, fedora right now')) {
    Put (P $row[0] 'Consolas' 1) 80 $y @($red, $blue)[$i++ % 2] -Sc 0.30
    Put (P $row[1] 'Consolas' 1) 250 $y $stone -Sc 0.30
    $y += 46
}
$photo = [Drawing.Image]::FromFile("$PSScriptRoot\assets\portrait.png")
$pw = 536; $ph = 620
$crop = New-Object Drawing.Bitmap $pw, $ph
$cg = [Drawing.Graphics]::FromImage($crop); $cg.InterpolationMode = 'HighQualityBicubic'
$srcH = $photo.Width * $ph / $pw
$cg.DrawImage($photo, (New-Object Drawing.RectangleF 0, 0, $pw, $ph), (New-Object Drawing.RectangleF 0, 90, $photo.Width, $srcH), [Drawing.GraphicsUnit]::Pixel)
$glitch = [CardBg]::Glitch($crop, 7, 0.9)
$g.DrawImage($glitch, 1300, 70, $pw, $ph)
$cg.Dispose(); $crop.Dispose(); $glitch.Dispose(); $photo.Dispose()
SaveJpg 'whoami'
