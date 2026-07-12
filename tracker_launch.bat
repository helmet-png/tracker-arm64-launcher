@echo off
rem Unified Tracker launcher (native ARM64 Java, no x64 emulation).
rem Double-click        -> opens Tracker.
rem Drop a video on it  -> converts to frames, builds a .trk with the
rem                        correct frame rate, opens it in Tracker.
rem Drop a .trk on it   -> opens the project directly.
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

rem a dropped .trk project opens directly, no conversion
if /I "%~x1"==".trk" (
  start "" %JAVAW% -Xmx2048m -jar "%TJAR%" "%~1"
  exit /b 0
)

echo Converting video for Tracker, please wait...
del "%TEMP%\trk_path.txt" 2>nul
powershell -nop -ExecutionPolicy Bypass -File "%~dp0video_to_trk.ps1" -Video "%~1"
if not exist "%TEMP%\trk_path.txt" (
  echo.
  echo Conversion FAILED. See messages above.
  pause
  exit /b 1
)
set /p TRK=<"%TEMP%\trk_path.txt"
echo Opening in Tracker: %TRK%
start "" %JAVAW% -Xmx2048m -jar "%TJAR%" "%TRK%"
