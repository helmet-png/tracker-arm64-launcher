# Converts a video to a JPG sequence and builds a minimal .trk project
# with the correct frame rate, so Tracker opens it fully configured.
# Writes the .trk path to %TEMP%\trk_path.txt and the Java heap size (MB)
# to %TEMP%\trk_xmx.txt. If the full sequence cannot fit in RAM, frames are
# sampled every Nth frame and delta_t is adjusted so timing stays exact.
param([Parameter(Mandatory=$true)][string]$Video)

$ErrorActionPreference = "Stop"

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

# --- probe fps, dimensions, duration ---
$probe = (& "$ffdir\ffprobe.exe" -v 0 -select_streams v:0 -show_entries "stream=avg_frame_rate,width,height:format=duration" -of csv=p=0 "$Video") -join ","
$parts = $probe -split ","
$w = [int]$parts[0]; $h = [int]$parts[1]; $fpsRaw = $parts[2]; $dur = [double]$parts[3]
$fps = 30.0
if ($fpsRaw -match '^(\d+)/(\d+)$' -and [double]$Matches[2] -ne 0) {
    $fps = [double]$Matches[1] / [double]$Matches[2]
} elseif ($fpsRaw -match '^[0-9.]+$') {
    $fps = [double]$fpsRaw
}
if ($fps -le 0) { $fps = 30.0 }

# output dimensions (width capped at 1280 for tracking speed)
$ow = [math]::Min(1280, $w); $oh = [math]::Round($h * $ow / $w / 2) * 2

# --- memory budget: Tracker's ImageVideo loads EVERY frame into RAM ---
$ramMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
$budgetMB = [math]::Round($ramMB * 0.5)
$estFrames = [math]::Ceiling($dur * $fps)
$frameMB = $ow * $oh * 4 * 1.4 / 1MB
$maxFrames = [math]::Floor(($budgetMB - 600) / $frameMB)
$every = 1
if ($estFrames -gt $maxFrames) {
    $every = [math]::Ceiling($estFrames / $maxFrames)
    Write-Host ("NOTE: video is long ({0} frames). Keeping every {1}th frame so it fits in RAM; effective rate {2} fps." -f $estFrames, $every, [math]::Round($fps/$every,3))
}

# --- extract frames ---
$name = [IO.Path]::GetFileNameWithoutExtension($Video)
$out = Join-Path ([IO.Path]::GetDirectoryName($Video)) ($name + "_frames")
New-Item -ItemType Directory -Force -Path $out | Out-Null
$vf = "scale=${ow}:${oh}"
if ($every -gt 1) { $vf = "select='not(mod(n\,$every))',$vf" }
& "$ffdir\ffmpeg.exe" -y -loglevel error -stats -i "$Video" -vf $vf -fps_mode vfr -qscale:v 2 "$out\frame_%05d.jpg"

$frames = @(Get-ChildItem $out -Filter "frame_*.jpg" | Sort-Object Name)
if ($frames.Count -eq 0) { Write-Host "ERROR: no frames produced"; exit 1 }

# --- build minimal .trk (paths relative to trk location; delta_t in ms) ---
$dtms = [math]::Round($every * 1000.0 / $fps, 6)
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<object class="org.opensourcephysics.cabrillo.tracker.TrackerPanel">')
[void]$sb.AppendLine('    <property name="videoclip" type="object">')
[void]$sb.AppendLine('        <object class="org.opensourcephysics.media.core.VideoClip">')
[void]$sb.AppendLine('            <property name="video" type="object">')
[void]$sb.AppendLine('                <object class="org.opensourcephysics.media.core.ImageVideo">')
[void]$sb.AppendLine("                    <property name=""path"" type=""string"">$($frames[0].Name)</property>")
[void]$sb.AppendLine('                    <property name="paths" type="array" class="[Ljava.lang.String;">')
for ($i = 0; $i -lt $frames.Count; $i++) {
    [void]$sb.AppendLine("                        <property name=""[$i]"" type=""string"">$($frames[$i].Name)</property>")
}
[void]$sb.AppendLine('                    </property>')
[void]$sb.AppendLine("                    <property name=""delta_t"" type=""double"">$dtms</property>")
[void]$sb.AppendLine('                </object>')
[void]$sb.AppendLine('            </property>')
[void]$sb.AppendLine("            <property name=""video_framecount"" type=""int"">$($frames.Count)</property>")
[void]$sb.AppendLine('            <property name="startframe" type="int">0</property>')
[void]$sb.AppendLine('            <property name="stepsize" type="int">1</property>')
[void]$sb.AppendLine('        </object>')
[void]$sb.AppendLine('    </property>')
[void]$sb.AppendLine('</object>')

$trk = Join-Path $out ($name + ".trk")
[IO.File]::WriteAllText($trk, $sb.ToString())

# --- report back to the launcher ---
$xmx = [math]::Max(2048, [math]::Round($frames.Count * $frameMB + 600))
$trk | Out-File -FilePath (Join-Path $env:TEMP "trk_path.txt") -Encoding Default -NoNewline
$xmx | Out-File -FilePath (Join-Path $env:TEMP "trk_xmx.txt") -Encoding ASCII -NoNewline
Write-Host ("OK: {0} frames @ {1} fps, heap {2} MB" -f $frames.Count, [math]::Round($fps/$every,3), $xmx)
