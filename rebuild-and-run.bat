@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rebuild-and-run.ps1" %*
set "build_result=%errorlevel%"
if not "%build_result%"=="0" (
    echo.
    echo Rebuild or launch failed. See the error above.
    pause
)
exit /b %build_result%
