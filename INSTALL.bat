@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Android Development Setup

:: ============================================================
:: CONFIGURATION
:: ============================================================

set "INSTALL_ROOT=C:\Android"
set "SDKMANAGER=%INSTALL_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat"

set "JAVA_INSTALLER=%~dp0packages\Java17-Setup.exe"
set "CMDLINE_ZIP=%~dp0packages\commandlinetools-win.zip"
set "CLEAN_ENV_PS1=%~dp0tools\Clean-AndroidEnv.ps1"

set "JAVA_OK=0"
set "JAVA_HOME_FOUND="
set "FAILED=0"

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
:: HEADER
:: ============================================================

cls
echo.
echo ============================================================
echo              ANDROID DEVELOPMENT SETUP
echo ============================================================
echo.
echo This installer will prepare a CLEAN Android development
echo environment for building Android applications.
echo.
echo CLEANUP:
echo   - Existing C:\Android will be removed.
echo   - Old/wrong ANDROID_HOME, ANDROID_SDK_ROOT (User + Machine)
echo     will be detected and reset.
echo   - Any old SDK folder they point to (e.g. a previous
echo     Android Studio SDK) will also be removed.
echo   - Android SDK/NDK/CMake PATH entries will be cleaned.
echo.
echo INSTALLS:
echo   - Android Command Line Tools
echo   - Platform Tools / ADB
echo   - Android 36 platform
echo   - Build Tools 36.0.0
echo   - NDK 27.1.12297006
echo   - CMake 3.22.1
echo.
echo JAVA:
echo   - Existing Java 17+ will NOT be uninstalled or touched.
echo   - If Java is missing, bundled Java17-Setup.exe from the
echo     packages folder will be installed silently (no clicks).
echo.
echo NOT TOUCHED:
echo   - Project files outside C:\Android
echo   - Node.js / npm
echo   - Git
echo   - Unrelated Windows PATH entries
echo   - Android emulators / system images
echo.

choice /C YN /N /M "Start CLEAN + FRESH Android setup? [Y/N] "

if errorlevel 2 goto CANCEL
if not errorlevel 1 goto CANCEL

:: ============================================================
:: STEP 1 - JAVA
:: ============================================================

echo.
echo ============================================================
echo [1/7] Checking Java...
echo ============================================================
echo.

call :CHECK_JAVA

if "%JAVA_OK%"=="1" (
    echo.
    echo       Java 17+ detected.
    echo       Existing Java will be preserved.
    echo       Java Home: %JAVA_HOME_FOUND%
    goto JAVA_DONE
)

echo       Java 17+ was not detected.
echo.

if not exist "%JAVA_INSTALLER%" (
    echo ============================================================
    echo ERROR: Bundled Java installer was not found.
    echo ============================================================
    echo.
    echo Expected file:
    echo %JAVA_INSTALLER%
    echo.
    echo Your folder must contain:
    echo.
    echo packages\
    echo    Java17-Setup.exe
    echo    commandlinetools-win.zip
    echo.
    pause
    exit /b 1
)

echo       Bundled Java installer found:
echo       %JAVA_INSTALLER%
echo.
echo       Installing Java 17 silently (no clicks required)...
echo.

start /wait "" "%JAVA_INSTALLER%" /s

:: Refresh environment variables into current BAT session
call :REFRESH_JAVA_ENV

:: Check Java again
call :CHECK_JAVA

if "%JAVA_OK%"=="1" (
    echo.
    echo       Java 17+ detected successfully.
    echo       Java Home: %JAVA_HOME_FOUND%
    goto JAVA_DONE
)

echo.
echo       Silent install did not complete automatically.
echo       Opening the installer for one-time manual completion...
echo.

start /wait "" "%JAVA_INSTALLER%"

call :REFRESH_JAVA_ENV
call :CHECK_JAVA

if "%JAVA_OK%"=="1" (
    echo.
    echo       Java 17+ detected successfully.
    echo       Java Home: %JAVA_HOME_FOUND%
) else (
    echo.
    echo ============================================================
    echo ERROR: Java was installed but could not be detected.
    echo ============================================================
    echo.
    echo Please check that Java17-Setup.exe installed Java 17.
    echo.
    echo You can also open a NEW CMD window and run:
    echo.
    echo     java -version
    echo.
    pause
    exit /b 1
)

:JAVA_DONE

:: ============================================================
:: STEP 2 - CLEAN ENVIRONMENT VARIABLES
:: ============================================================

echo.
echo ============================================================
echo [2/7] Detecting and cleaning old/wrong Android environment...
echo ============================================================
echo.

if not exist "%CLEAN_ENV_PS1%" (
    echo.
    echo ============================================================
    echo ERROR: tools\Clean-AndroidEnv.ps1 was not found.
    echo ============================================================
    echo.
    echo Expected file:
    echo %CLEAN_ENV_PS1%
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CLEAN_ENV_PS1%" -NewRoot "%INSTALL_ROOT%"

if errorlevel 1 (
    echo.
    echo ============================================================
    echo ERROR: Cleaning the old Android environment failed.
    echo ============================================================
    echo.
    pause
    exit /b 1
)

:: ============================================================
:: STEP 3 - REMOVE OLD ANDROID
:: ============================================================

echo.
echo ============================================================
echo [3/7] Removing old C:\Android...
echo ============================================================
echo.

if exist "%INSTALL_ROOT%" (
    echo       Removing %INSTALL_ROOT% ...
    rmdir /s /q "%INSTALL_ROOT%"
)

if exist "%INSTALL_ROOT%" (
    echo.
    echo ============================================================
    echo ERROR: Could not remove C:\Android.
    echo ============================================================
    echo.
    echo Close Android Studio, Gradle, ADB or other processes
    echo that may be using C:\Android and run this installer again.
    echo.
    pause
    exit /b 1
)

mkdir "%INSTALL_ROOT%"

if not exist "%INSTALL_ROOT%" (
    echo ERROR: Could not create C:\Android.
    pause
    exit /b 1
)

echo       Fresh C:\Android created.

:: ============================================================
:: CHECK COMMAND LINE TOOLS PACKAGE
:: ============================================================

if not exist "%CMDLINE_ZIP%" (
    echo.
    echo ============================================================
    echo ERROR: Android Command Line Tools package not found.
    echo ============================================================
    echo.
    echo Expected:
    echo %CMDLINE_ZIP%
    echo.
    echo Please put commandlinetools-win.zip inside:
    echo %~dp0packages\
    echo.
    pause
    exit /b 1
)

:: ============================================================
:: STEP 4 - COMMAND LINE TOOLS
:: ============================================================

echo.
echo ============================================================
echo [4/7] Extracting Android Command Line Tools...
echo ============================================================
echo.

if exist "%TEMP%\android-cmdline-tools" (
    rmdir /s /q "%TEMP%\android-cmdline-tools"
)

mkdir "%TEMP%\android-cmdline-tools"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"Expand-Archive -LiteralPath '%CMDLINE_ZIP%' -DestinationPath '%TEMP%\android-cmdline-tools' -Force"

if errorlevel 1 (
    echo.
    echo ERROR: Failed to extract Android Command Line Tools.
    pause
    exit /b 1
)

mkdir "%INSTALL_ROOT%\cmdline-tools" >nul 2>&1

if exist "%TEMP%\android-cmdline-tools\cmdline-tools" (

    move /Y ^
    "%TEMP%\android-cmdline-tools\cmdline-tools" ^
    "%INSTALL_ROOT%\cmdline-tools\latest" >nul

) else (

    echo.
    echo ============================================================
    echo ERROR: Expected cmdline-tools folder was not found.
    echo ============================================================
    echo.
    echo The ZIP should contain:
    echo.
    echo cmdline-tools\
    echo     bin\
    echo     lib\
    echo     source.properties
    echo.
    pause
    exit /b 1
)

if not exist "%SDKMANAGER%" (
    echo.
    echo ERROR: sdkmanager.bat was not found:
    echo %SDKMANAGER%
    echo.
    pause
    exit /b 1
)

echo       Android Command Line Tools installed.

:: ============================================================
:: STEP 5 - ANDROID PACKAGES
:: ============================================================

echo.
echo ============================================================
echo [5/7] Installing required Android packages...
echo ============================================================
echo.

echo       Installing:
echo       - Platform Tools
echo       - Android 36
echo       - Build Tools 36.0.0
echo       - NDK 27.1.12297006
echo       - CMake 3.22.1
echo.

call "%SDKMANAGER%" --sdk_root="%INSTALL_ROOT%" ^
    "platform-tools" ^
    "platforms;android-36" ^
    "build-tools;36.0.0" ^
    "ndk;27.1.12297006" ^
    "cmake;3.22.1"

if errorlevel 1 (
    echo.
    echo ============================================================
    echo ERROR: Android SDK package installation failed.
    echo ============================================================
    echo.
    pause
    exit /b 1
)

echo.
echo       Accepting Android SDK licenses...
echo.

echo y|call "%SDKMANAGER%" ^
    --sdk_root="%INSTALL_ROOT%" ^
    --licenses >nul 2>&1

echo       Android packages installed successfully.

:: ============================================================
:: STEP 6 - ENVIRONMENT VARIABLES
:: ============================================================

echo.
echo ============================================================
echo [6/7] Configuring Android environment variables...
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"[Environment]::SetEnvironmentVariable('ANDROID_HOME','C:\Android','User'); ^
 [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT','C:\Android','User'); ^
 $p=[Environment]::GetEnvironmentVariable('Path','User'); ^
 $a=@($p -split ';' | Where-Object {$_.Trim()}); ^
 foreach($x in @('C:\Android\platform-tools','C:\Android\cmdline-tools\latest\bin')){ ^
     if($a -notcontains $x){$a += $x} ^
 }; ^
 [Environment]::SetEnvironmentVariable('Path',($a -join ';'),'User')"

:: Also update current BAT session PATH
set "ANDROID_HOME=C:\Android"
set "ANDROID_SDK_ROOT=C:\Android"
set "PATH=C:\Android\platform-tools;C:\Android\cmdline-tools\latest\bin;%PATH%"

echo       ANDROID_HOME = C:\Android
echo       ANDROID_SDK_ROOT = C:\Android
echo       Android PATH entries configured.

:: ============================================================
:: STEP 7 - VERIFICATION
:: ============================================================

echo.
echo ============================================================
echo [7/7] Verifying installation...
echo ============================================================
echo.

set "FAILED=0"

if not exist "%INSTALL_ROOT%\platform-tools\adb.exe" (
    echo       [FAIL] Platform Tools / ADB
    set "FAILED=1"
) else (
    echo       [ OK ] Platform Tools / ADB
)

if not exist "%INSTALL_ROOT%\platforms\android-36" (
    echo       [FAIL] Android 36
    set "FAILED=1"
) else (
    echo       [ OK ] Android 36
)

if not exist "%INSTALL_ROOT%\build-tools\36.0.0" (
    echo       [FAIL] Build Tools 36.0.0
    set "FAILED=1"
) else (
    echo       [ OK ] Build Tools 36.0.0
)

if not exist "%INSTALL_ROOT%\ndk\27.1.12297006" (
    echo       [FAIL] NDK 27.1.12297006
    set "FAILED=1"
) else (
    echo       [ OK ] NDK 27.1.12297006
)

if not exist "%INSTALL_ROOT%\cmake\3.22.1" (
    echo       [FAIL] CMake 3.22.1
    set "FAILED=1"
) else (
    echo       [ OK ] CMake 3.22.1
)

if not exist "%SDKMANAGER%" (
    echo       [FAIL] SDK Manager
    set "FAILED=1"
) else (
    echo       [ OK ] SDK Manager
)

call :CHECK_JAVA

if "%JAVA_OK%"=="0" (
    echo       [FAIL] Java 17+
    set "FAILED=1"
) else (
    echo       [ OK ] Java 17+
)

:: ============================================================
:: FINAL RESULT
:: ============================================================

echo.

if "%FAILED%"=="1" (
    echo ============================================================
    echo                  SETUP FAILED
    echo ============================================================
    echo.
    echo One or more required components are missing.
    echo Review the errors above.
    echo.
    pause
    exit /b 1
)

echo ============================================================
echo              SETUP COMPLETED SUCCESSFULLY
echo ============================================================
echo.
echo SDK Root    : C:\Android
echo Android     : 36
echo Build Tools : 36.0.0
echo NDK         : 27.1.12297006
echo CMake       : 3.22.1
echo ADB         : Installed
echo Java        : 17+
echo.
echo Java Home   : %JAVA_HOME_FOUND%
echo.
echo IMPORTANT:
echo Open a NEW PowerShell/CMD window before building.
echo.
echo ============================================================
echo.

pause
exit /b 0


:: ============================================================
:: FUNCTION: CHECK JAVA
:: ============================================================

:CHECK_JAVA

set "JAVA_OK=0"
set "JAVA_HOME_FOUND="
set "JAVA_VERSION="
set "JAVA_MAJOR="

:: ------------------------------------------------------------
:: 1. Try JAVA_HOME
:: ------------------------------------------------------------

if defined JAVA_HOME (
    if exist "%JAVA_HOME%\bin\java.exe" (
        set "JAVA_HOME_FOUND=%JAVA_HOME%"
        goto CHECK_JAVA_VERSION
    )
)

:: ------------------------------------------------------------
:: 2. Search current PATH
:: ------------------------------------------------------------

where java >nul 2>&1

if not errorlevel 1 (

    for /f "delims=" %%J in ('where java 2^>nul') do (

        if exist "%%J" (

            for %%D in ("%%J\..\..") do (
                set "JAVA_HOME_FOUND=%%~fD"
            )

            goto CHECK_JAVA_VERSION
        )
    )
)

:: ------------------------------------------------------------
:: 3. Common Java installation locations
:: ------------------------------------------------------------

for /d %%D in (
    "C:\Program Files\Java\jdk-*"
    "C:\Program Files\Java\jre-*"
    "C:\Program Files\Eclipse Adoptium\jdk-*"
    "C:\Program Files\Microsoft\jdk-*"
) do (

    if exist "%%D\bin\java.exe" (
        set "JAVA_HOME_FOUND=%%~fD"
        goto CHECK_JAVA_VERSION
    )
)

exit /b 0


:CHECK_JAVA_VERSION

if not defined JAVA_HOME_FOUND exit /b 0

if not exist "%JAVA_HOME_FOUND%\bin\java.exe" exit /b 0

for /f "tokens=3 delims= " %%V in (
    '"%JAVA_HOME_FOUND%\bin\java.exe" -version 2^>^&1 ^| findstr /I "version"'
) do (
    set "JAVA_VERSION=%%V"
)

if not defined JAVA_VERSION exit /b 0

:: Remove quotation marks
set "JAVA_VERSION=%JAVA_VERSION:"=%"

:: Extract major version
for /f "tokens=1 delims=." %%V in ("%JAVA_VERSION%") do (
    set "JAVA_MAJOR=%%V"
)

:: Java 8 style: 1.8.x
if "%JAVA_MAJOR%"=="1" (
    for /f "tokens=2 delims=." %%V in ("%JAVA_VERSION%") do (
        set "JAVA_MAJOR=%%V"
    )
)

set /a JAVA_NUM=%JAVA_MAJOR% >nul 2>&1

if %JAVA_NUM% GEQ 17 (
    set "JAVA_OK=1"
)

exit /b 0


:: ============================================================
:: FUNCTION: REFRESH JAVA ENVIRONMENT
:: ============================================================

:REFRESH_JAVA_ENV

:: Reload machine JAVA_HOME
for /f "delims=" %%J in (
    'powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable(''JAVA_HOME'',''Machine'')"'
) do (
    if exist "%%J\bin\java.exe" (
        set "JAVA_HOME=%%J"
        set "JAVA_HOME_FOUND=%%J"
    )
)

:: Reload user JAVA_HOME
for /f "delims=" %%J in (
    'powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable(''JAVA_HOME'',''User'')"'
) do (
    if exist "%%J\bin\java.exe" (
        set "JAVA_HOME=%%J"
        set "JAVA_HOME_FOUND=%%J"
    )
)

:: Add detected Java to current session PATH
if defined JAVA_HOME_FOUND (
    set "PATH=%JAVA_HOME_FOUND%\bin;%PATH%"
)

exit /b 0


:: ============================================================
:: CANCEL
:: ============================================================

:CANCEL

echo.
echo ============================================================
echo Setup cancelled.
echo No installation was started.
echo ============================================================
echo.

pause
exit /b 0