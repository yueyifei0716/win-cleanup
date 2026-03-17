@echo off
title WinCleanup
cd /d "%~dp0"

:: Try py313 conda env first, fallback to system python
where conda >nul 2>&1
if %errorlevel%==0 (
    call conda activate py313 2>nul
)

python app.py %*
