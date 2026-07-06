@echo off
setlocal enabledelayedexpansion

echo ------------------------------------------
echo OLTogether Multiplayer - Compile + Launch
echo ------------------------------------------

set UDK=C:\Outlast-Level-Editor\Binaries\Win32\UDK.com
set SRC=C:\Outlast-Level-Editor\UDKGame\Script\Multiplayer.u
set "GAME_DIR=C:\Program Files (x86)\Steam\steamapps\common\Outlast\OLGame\CookedPCConsole"
set DST_DIR=%GAME_DIR%\MultiplayerContent
set DST=%DST_DIR%\Multiplayer.u
set "GAME=C:\Program Files (x86)\Steam\steamapps\common\Outlast\Binaries\Win64\OLGame.exe"
set BRIDGE_SCRIPT=%~dp0OutlastTogether.py

REM ------ Kill existing instances ------
echo [0/4] Killing existing game and server instances...
taskkill /F /IM OLGame.exe >nul 2>&1
taskkill /F /IM python.exe >nul 2>&1
taskkill /F /IM py.exe >nul 2>&1
timeout /t 1 /nobreak >nul

REM ------ Find Python ------
set PY=python
where python >nul 2>&1
if errorlevel 1 (
    where py >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Python not found. Install Python or add it to PATH.
        pause
        exit /b 1
    )
    set PY=py
)

REM ------ Compile ------
echo [1/4] Compiling UnrealScript...
"%UDK%" make

if errorlevel 1 (
    echo.
    echo Compile failed.
    pause
    exit /b 1
)

REM ------ Copy ------
echo [2/4] Copying Multiplayer.u to game directory...
mkdir "%DST_DIR%" 2>nul
copy /Y "%SRC%" "%DST%" >nul

if not exist "%DST%" (
    echo.
    echo Copy failed - destination: %DST%
    pause
    exit /b 1
)

REM ------ Kill old server ------
echo [3/4] Starting TCP relay server...
taskkill /F /IM python.exe >nul 2>&1
taskkill /F /IM py.exe >nul 2>&1

REM Start server in its own window so you can watch relay logs
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%PY%' -ArgumentList '%BRIDGE_SCRIPT%'"

REM Wait for bridge to initialize
timeout /t 2 /nobreak >nul

echo Close the bridge window to shut down.
echo.
exit /b 0
