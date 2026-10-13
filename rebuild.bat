@echo off
setlocal
cd /d "%~dp0"
python tools\rebuild.py %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Build failed with exit code %ERRORLEVEL%.
    pause
    exit /b %ERRORLEVEL%
)
pause
