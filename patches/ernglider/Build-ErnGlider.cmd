@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>&1
if errorlevel 1 (
  python "%~dp0build_ernglider_optimized.py" %*
) else (
  py -3 "%~dp0build_ernglider_optimized.py" %*
)
if errorlevel 1 echo Build failed. See error above.
pause
