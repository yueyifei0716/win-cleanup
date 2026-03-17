@echo off
title Building WinCleanup
cd /d "%~dp0"

where conda >nul 2>&1
if %errorlevel%==0 (
    call conda activate py313 2>nul
)

echo Building WinCleanup executable...
pyinstaller --noconfirm --onefile --windowed ^
    --name WinCleanup ^
    --add-data "ui;ui" ^
    --add-data "cleanup.ps1;." ^
    --hidden-import clr_loader ^
    --hidden-import pythonnet ^
    app.py

echo.
if exist dist\WinCleanup.exe (
    echo Build successful: dist\WinCleanup.exe
) else (
    echo Build failed!
)
pause
