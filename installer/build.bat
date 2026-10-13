@echo off
setlocal
cd /d "%~dp0"
echo ==============================================
echo  NutNotes Setup Builder
echo ==============================================
python build.py
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Build failed! Check the output above.
    pause
    exit /b %ERRORLEVEL%
)
echo.
pause
