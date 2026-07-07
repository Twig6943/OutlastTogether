@echo off
setlocal EnableDelayedExpansion
title OutlastTogether Builder

echo ============================================================
echo  OutlastTogether EXE Builder
echo ============================================================
echo.

:: ── Check Python ────────────────────────────────────────────────
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Make sure it's installed and on PATH.
    pause & exit /b 1
)

:: ── Install / upgrade Nuitka (much lower AV false-positive rate ──
::    than PyInstaller, compiles to actual C code via MSVC/gcc)
echo [1/4] Installing / upgrading Nuitka...
python -m pip install --upgrade nuitka zstandard ordered-set >nul 2>&1
if errorlevel 1 (
    echo [WARN] pip upgrade had issues, continuing anyway...
)

:: ── Clean previous output ───────────────────────────────────────
echo [2/4] Cleaning previous build...
if exist "OutlastLauncher.dist"    rmdir /s /q "OutlastLauncher.dist"
if exist "OutlastLauncher.build"   rmdir /s /q "OutlastLauncher.build"
if exist "OutlastLauncher.exe" del /f /q "OutlastLauncher.exe"

:: ── Build with Nuitka ───────────────────────────────────────────
echo [3/4] Compiling with Nuitka (this may take a minute)...
echo.

python -m nuitka ^
    --standalone ^
    --onefile ^
    --windows-icon-from-ico=app_icon.ico ^
    --output-filename=OutlastLauncher.exe ^
    --windows-console-mode=attach ^
    --enable-plugin=tk-inter ^
    --include-data-files=app_icon.ico=app_icon.ico ^
    --company-name="OutlastTogether" ^
    --product-name="OutlastTogether Launcher" ^
    --file-version=1.0.0.0 ^
    --product-version=1.0.0.0 ^
    --file-description="OutlastTogether Multiplayer Launcher" ^
    --copyright="OutlastTogether" ^
    --mingw64 ^
    --assume-yes-for-downloads ^
    --nofollow-import-to=pytest ^
    --nofollow-import-to=unittest ^
    --nofollow-import-to=test ^
    --python-flag=no_docstrings ^
    OutlastTogether.py

if errorlevel 1 (
    echo.
    echo [ERROR] Compilation failed. See output above.
    pause & exit /b 1
)

:: ── Done ────────────────────────────────────────────────────────
echo.
echo [4/4] Done!
echo.
if exist "OutlastLauncher.exe" (
    echo  Output: %CD%\OutlastLauncher.exe
) else (
    echo  [WARN] Expected output file not found — check build logs above.
)
echo.
echo ============================================================
pause
