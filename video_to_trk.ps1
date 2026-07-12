# Converts a video to a JPG sequence and builds a minimal .trk project
# with the correct frame rate, so Tracker opens it fully configured.
# Prints nothing on success; writes the .trk path to %TEMP%\trk_path.txt
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

# --- detect frame rate (ffprobe returns e.g. "30/1" or "30000/1001") ---
$fpsRaw = (& "$ffdir\ffprobe.exe" -v 0 -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$Video" | Select-Object -First 1).Trim()
$fps = 30.0
if ($fpsRaw -match '^(\d+)/(\d+)$' -and [double]$Matches[2] -ne 0) {
    $fps = [double]$Matches[1] / [double]$Matches[2]
} elseif ($fpsRaw -match '^[0-9.]+$') {
    $fps = [double]$fpsRaw
}
if ($fps -le 0) { $fps = 30.0 }

# --- extract frames (width capped at 1280 for speed) ---
$name = [IO.Path]::GetFileNameWithoutExtension($Video)
$out = Join-Path ([IO.Path]::GetDirectoryName($Video)) ($name + "_frames")
New-Item -ItemType Directory -Force -Path $out | Out-Null
& "$ffdir\ffmpeg.exe" -y -loglevel error -stats -i "$Video" -vf "scale='min(1280,iw)':-2" -qscale:v 2 "$out\frame_%05d.jpg"

$frames = @(Get-ChildItem $out -Filter "frame_*.jpg" | Sort-Object Name)
if ($frames.Count -eq 0) { Write-Host "ERROR: no frames produced"; exit 1 }

# --- build minimal .trk (paths relative to trk location; delta_t in ms) ---
$dtms = [math]::Round(1000.0 / $fps, 6)
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
[IO.File]::WriteAllText($trk, $sb.ToString())   # UTF-8-compatible, no BOM (content is ASCII)

# hand the trk path back to the bat via a temp file (ANSI so cmd can read it)
$trk | Out-File -FilePath (Join-Path $env:TEMP "trk_path.txt") -Encoding Default -NoNewline
Write-Host ("OK: " + $frames.Count + " frames @ " + [math]::Round($fps,3) + " fps")
