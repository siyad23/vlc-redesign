@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-vlc.ps1" %*
exit /b %errorlevel%
