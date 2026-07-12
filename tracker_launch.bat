@echo off
rem Unified Tracker launcher (native ARM64 Java, no x64 emulation).
rem Double-click        -> opens Tracker.
rem Drop a video on it  -> converts to frames, builds a .trk with the
rem                        correct frame rate, opens it in Tracker.
rem Drop a .trk on it   -> opens it; old movie-based projects are repaired
rem                        to image sequences first (or fall back to the
rem                        bundled x64 Tracker if too big for RAM).
setlocal

rem --- locate an ARM64/native JDK (Microsoft OpenJDK), newest first ---
set "JDK="
for /d %%j in ("C:\Program Files\Microsoft\jdk-*") do set "JDK=%%j"
if "%JDK%"=="" (
  echo ERROR: no JDK found under "C:\Program Files\Microsoft".
  echo Install one with:  winget install Microsoft.OpenJDK.21
  pause
  exit /b 1
)
set JAVAW="%JDK%\bin\javaw.exe"

rem --- locate the Tracker main jar (NOT tracker.jar, which is a starter) ---
set "TJAR="
for %%t in ("C:\Program Files\Tracker\tracker-*.jar") do set "TJAR=%%t"
if "%TJAR%"=="" (
  echo ERROR: Tracker not found in "C:\Program Files\Tracker".
  pause
  exit /b 1
)

rem stop Tracker from respawning itself on its bundled x64 JRE
set TRACKER_RELAUNCH=true

if "%~1"=="" (
  start "" %JAVAW% -Xmx2048m -jar "%TJAR%"
  exit /b 0
)

del "%TEMP%\trk_path.txt" 2>nul
del "%TEMP%\trk_xmx.txt" 2>nul

if /I "%~x1"==".trk" (
  echo Checking project video source...
  powershell -nop -ExecutionPolicy Bypass -File "%~dp0repair_trk.ps1" -Trk "%~1"
) else (
  echo Converting video for Tracker, please wait...
  powershell -nop -ExecutionPolicy Bypass -File "%~dp0video_to_trk.ps1" -Video "%~1"
)

if not exist "%TEMP%\trk_path.txt" (
  echo.
  echo FAILED. See messages above.
  pause
  exit /b 1
)
set /p TRK=<"%TEMP%\trk_path.txt"
set /p XMX=<"%TEMP%\trk_xmx.txt"

rem project too big for RAM as an image sequence -> use the bundled
rem x64 Tracker (slow, emulated, but it has a real video engine)
if "%TRK%"=="X64" (
  echo Opening with the bundled x64 Tracker...
  start "" "C:\Program Files\Tracker\Tracker.exe" "%~1"
  exit /b 0
)

echo Opening in Tracker: %TRK%  (heap %XMX% MB)
start "" %JAVAW% -Xmx%XMX%m -jar "%TJAR%" "%TRK%"
