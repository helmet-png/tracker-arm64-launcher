# Repairs an existing .trk project whose video was a movie file (mp4 etc.)
# opened by the old x64 Xuggle engine, which the native ARM64 JVM cannot load.
# Converts the referenced video to a full-resolution JPG sequence and rewrites
# the project's video source to point at it (original saved as .trk.bak).
# Full resolution is required so tracked points and calibration stay aligned.
#
# Output (via %TEMP% files, read by tracker_launch.bat):
#   trk_path.txt = path of the (repaired) .trk to open with the ARM64 JVM,
#                  or the literal string X64 when the sequence cannot fit in
#                  RAM (the bat then falls back to the bundled x64 Tracker).
#   trk_xmx.txt  = Java heap size in MB.
param([Parameter(Mandatory=$true)][string]$Trk)

$ErrorActionPreference = "Stop"
$pathFile = Join-Path $env:TEMP "trk_path.txt"
$xmxFile  = Join-Path $env:TEMP "trk_xmx.txt"
$ramMB    = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
$budgetMB = [math]::Round($ramMB * 0.5)
$trkDir   = [IO.Path]::GetDirectoryName($Trk)

[xml]$doc = Get-Content $Trk -Raw
$videoNode = $doc.SelectSingleNode("//property[@name='videoclip']/object/property[@name='video']/object")

# no video at all -> just open it
if (-not $videoNode) {
    $Trk | Out-File $pathFile -Encoding Default -NoNewline
    "2048" | Out-File $xmxFile -Encoding ASCII -NoNewline
    Write-Host "No video in project; opening as-is."
    exit 0
}

# already an image sequence -> compute heap from the existing frames and open
if ($videoNode.class -match "ImageVideo") {
    $first = ($videoNode.SelectSingleNode("property[@name='path']")).InnerText
    $firstPath = if ([IO.Path]::IsPathRooted($first)) { $first } else { Join-Path $trkDir $first }
    $n = @($videoNode.SelectNodes("property[@name='paths']/property")).Count
    $xmx = 2048
    if ((Test-Path $firstPath) -and $n -gt 0) {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($firstPath)
        $xmx = [math]::Max(2048, [math]::Round($n * $img.Width * $img.Height * 4 * 1.4 / 1MB + 600))
        $img.Dispose()
    }
    $Trk | Out-File $pathFile -Encoding Default -NoNewline
    "$xmx" | Out-File $xmxFile -Encoding ASCII -NoNewline
    Write-Host "Project already uses an image sequence; opening (heap $xmx MB)."
    exit 0
}

# --- movie-based video: locate the source file ---
Write-Host "Old project uses a movie video the ARM64 build cannot load. Repairing..."
$vidPath = $null
foreach ($prop in @("path", "absolutePath")) {
    $node = $videoNode.SelectSingleNode("property[@name='$prop']")
    if ($node) {
        $p = $node.InnerText
        foreach ($cand in @($p, (Join-Path $trkDir $p), (Join-Path $trkDir ([IO.Path]::GetFileName($p))))) {
            if (Test-Path $cand) { $vidPath = (Resolve-Path $cand).Path; break }
        }
    }
    if ($vidPath) { break }
}
if (-not $vidPath) {
    Write-Host "ERROR: cannot find the video file this project references."
    Write-Host "Put the original video next to the .trk and try again."
    exit 1
}

# find ffmpeg: PATH first, then any winget BtbN package
$ffdir = $null
$cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($cmd) {
    $ffdir = Split-Path $cmd.Source
} else {
    $pkg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter "BtbN.FFmpeg*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) { $ffdir = (Get-ChildItem $pkg.FullName -Recurse -Filter ffmpeg.exe | Select-Object -First 1).DirectoryName }
}
if (-not $ffdir) { Write-Host "ERROR: ffmpeg not found. Install with: winget install BtbN.FFmpeg.GPL.8.1"; exit 1 }

# --- probe: repair MUST keep full resolution and every frame, or tracked
#     point/calibration coordinates and frame numbers would shift ---
$probe = (& "$ffdir\ffprobe.exe" -v 0 -select_streams v:0 -show_entries "stream=avg_frame_rate,width,height:format=duration" -of csv=p=0 "$vidPath") -join ","
$parts = $probe -split ","
$w = [int]$parts[0]; $h = [int]$parts[1]; $fpsRaw = $parts[2]; $dur = [double]$parts[3]
$fps = 30.0
if ($fpsRaw -match '^(\d+)/(\d+)$' -and [double]$Matches[2] -ne 0) {
    $fps = [double]$Matches[1] / [double]$Matches[2]
} elseif ($fpsRaw -match '^[0-9.]+$') {
    $fps = [double]$fpsRaw
}
if ($fps -le 0) { $fps = 30.0 }
$estFrames = [math]::Ceiling($dur * $fps)
$frameMB = $w * $h * 4 * 1.4 / 1MB
$needMB = [math]::Round($estFrames * $frameMB + 600)

if ($needMB -gt $budgetMB) {
    Write-Host ("Video too long for RAM ({0} frames at {1}x{2} needs ~{3} MB). Falling back to the bundled x64 Tracker for this project." -f $estFrames, $w, $h, $needMB)
    "X64" | Out-File $pathFile -Encoding Default -NoNewline
    "0" | Out-File $xmxFile -Encoding ASCII -NoNewline
    exit 0
}

# --- extract full-resolution frames next to the video ---
$name = [IO.Path]::GetFileNameWithoutExtension($vidPath)
$out = Join-Path ([IO.Path]::GetDirectoryName($vidPath)) ($name + "_frames")
New-Item -ItemType Directory -Force -Path $out | Out-Null
& "$ffdir\ffmpeg.exe" -y -loglevel error -stats -i "$vidPath" -qscale:v 2 "$out\frame_%05d.jpg"
$frames = @(Get-ChildItem $out -Filter "frame_*.jpg" | Sort-Object Name)
if ($frames.Count -eq 0) { Write-Host "ERROR: no frames produced"; exit 1 }

# --- rewrite the trk's video object as an ImageVideo ---
$dtms = [math]::Round(1000.0 / $fps, 6)
$newVideo = $doc.CreateElement("object")
$newVideo.SetAttribute("class", "org.opensourcephysics.media.core.ImageVideo")
$addProp = {
    param($parent, $name, $type, $text)
    $e = $doc.CreateElement("property")
    $e.SetAttribute("name", $name); $e.SetAttribute("type", $type)
    if ($null -ne $text) { $e.InnerText = $text }
    [void]$parent.AppendChild($e)
    return $e
}
[void](& $addProp $newVideo "path" "string" "$out\$($frames[0].Name)")
$pathsEl = & $addProp $newVideo "paths" "array" $null
$pathsEl.SetAttribute("class", "[Ljava.lang.String;")
for ($i = 0; $i -lt $frames.Count; $i++) {
    [void](& $addProp $pathsEl "[$i]" "string" "$out\$($frames[$i].Name)")
}
[void](& $addProp $newVideo "delta_t" "double" "$dtms")
[void]$videoNode.ParentNode.ReplaceChild($newVideo, $videoNode)

$fcNode = $doc.SelectSingleNode("//property[@name='videoclip']/object/property[@name='video_framecount']")
if ($fcNode) { $fcNode.InnerText = "$($frames.Count)" }

Copy-Item $Trk "$Trk.bak" -Force
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$writer = [System.Xml.XmlWriter]::Create($Trk, $settings)
$doc.Save($writer)
$writer.Close()

$xmx = [math]::Max(2048, [math]::Round($frames.Count * $frameMB + 600))
$Trk | Out-File $pathFile -Encoding Default -NoNewline
"$xmx" | Out-File $xmxFile -Encoding ASCII -NoNewline
Write-Host ("REPAIRED: {0} frames @ {1} fps, heap {2} MB. Original backed up as .trk.bak" -f $frames.Count, [math]::Round($fps,3), $xmx)
