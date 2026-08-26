@echo off
setlocal EnableExtensions

title Android Development Setup

:: ============================================================
:: ADMIN CHECK
:: ============================================================

net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo ============================================================
    echo ERROR: Administrator privileges are required.
    echo ============================================================
    echo.
    echo Please right-click INSTALL.bat
    echo and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

:: ============================================================
:: LAUNCH THE POWERSHELL INSTALLER
:: ============================================================
::
:: All setup logic lives in Install.ps1. This shim only elevates
:: (above) and hands off, so flags pass straight through, e.g.:
::   INSTALL.bat -DryRun
::   INSTALL.bat -Check
::   INSTALL.bat -Yes

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*

set "RESULT=%errorlevel%"
pause
exit /b %RESULT%
