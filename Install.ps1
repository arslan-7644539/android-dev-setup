[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Check,
    [string]$Config,
    [switch]$Yes,
    [switch]$NoColor
)

$ErrorActionPreference = 'Stop'

if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Config) { $Config = Join-Path $PSScriptRoot "config.json" }

. (Join-Path $PSScriptRoot "lib\Console.ps1")
Set-ConsoleColorMode -NoColor:$NoColor

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
try { Start-Transcript -Path $logFile -NoClobber | Out-Null } catch {}

$JavaInstaller  = Join-Path $PSScriptRoot "packages\Java17-Setup.exe"
$CmdlineZip     = Join-Path $PSScriptRoot "packages\commandlinetools-win.zip"
$CleanEnvScript = Join-Path $PSScriptRoot "tools\Clean-AndroidEnv.ps1"

function Get-SdkManagerPath {
    param([string]$InstallRoot)
    Join-Path $InstallRoot "cmdline-tools\latest\bin\sdkmanager.bat"
}

# Mirrors the original batch priority: JAVA_HOME, then PATH, then common
# install dirs - checks only the FIRST candidate found, not all of them.
function Test-JavaVersion {
    $result = @{ Ok = $false; Home = $null; Version = $null }
    $javaHome = $null

    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
        $javaHome = $env:JAVA_HOME
    }

    if (-not $javaHome) {
        $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $javaHome = Split-Path (Split-Path $cmd.Source -Parent) -Parent
        }
    }

    if (-not $javaHome) {
        foreach ($pattern in @(
            "C:\Program Files\Java\jdk-*",
            "C:\Program Files\Java\jre-*",
            "C:\Program Files\Eclipse Adoptium\jdk-*",
            "C:\Program Files\Microsoft\jdk-*"
        )) {
            $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found -and (Test-Path (Join-Path $found.FullName "bin\java.exe"))) {
                $javaHome = $found.FullName
                break
            }
        }
    }

    if (-not $javaHome) { return $result }

    $result.Home = $javaHome
    $javaExe = Join-Path $javaHome "bin\java.exe"
    if (-not (Test-Path $javaExe)) { return $result }

    # java -version writes to stderr by design; with $ErrorActionPreference
    # = 'Stop' at script scope, capturing that via 2>&1 would otherwise be
    # promoted to a terminating exception instead of just being text.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $javaExe -version 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($out -match 'version\s+"([\d._]+)"') {
        $version = $Matches[1]
        $result.Version = $version
        $parts = $version -split '\.'
        $major = [int]$parts[0]
        if ($major -eq 1 -and $parts.Count -gt 1) { $major = [int]$parts[1] } # legacy 1.8.x scheme
        if ($major -ge 17) { $result.Ok = $true }
    }

    return $result
}

# Vendor Java installers write JAVA_HOME to the registry (Machine/User scope)
# but the already-running PowerShell process keeps its original env block -
# it won't see that until we pull it in explicitly. Mirrors the original
# batch script's :REFRESH_JAVA_ENV step. User scope wins if both are set.
function Sync-JavaEnvFromRegistry {
    foreach ($scope in 'Machine', 'User') {
        $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', $scope)
        if ($javaHome -and (Test-Path (Join-Path $javaHome "bin\java.exe"))) {
            $env:JAVA_HOME = $javaHome
            $env:Path = "$javaHome\bin;$env:Path"
        }
    }
}

function Install-JavaSilently {
    if (-not (Test-Path $JavaInstaller)) {
        Write-Fail "Bundled Java installer was not found: $JavaInstaller"
        Write-Info "Your folder must contain packages\Java17-Setup.exe and packages\commandlinetools-win.zip"
        throw "Bundled Java installer missing."
    }

    Write-Info "Bundled Java installer found: $JavaInstaller"

    if ($DryRun) {
        Write-DryRun "Would silently install Java 17 from Java17-Setup.exe"
        return @{ Ok = $true; Home = "(not installed - dry run)"; Version = $null }
    }

    Write-Info "Installing Java 17 silently (no clicks required)..."
    Start-Process -FilePath $JavaInstaller -ArgumentList "/s" -Wait
    Sync-JavaEnvFromRegistry

    $state = Test-JavaVersion
    if ($state.Ok) { return $state }

    Write-Warn "Silent install did not complete automatically."
    Write-Info "Opening the installer for one-time manual completion..."
    Start-Process -FilePath $JavaInstaller -Wait
    Sync-JavaEnvFromRegistry

    $state = Test-JavaVersion
    if (-not $state.Ok) {
        Write-Fail "Java was installed but could not be detected."
        Write-Info "Check that Java17-Setup.exe installed Java 17, or open a NEW terminal and run: java -version"
        throw "Java 17+ could not be detected after installation."
    }
    return $state
}

# Child processes (sdkmanager.bat, gradle, ...) read $env:JAVA_HOME
# directly. Our own detection can find a valid JDK via a filesystem glob
# even when JAVA_HOME itself is unset or stale, but that doesn't help
# those child processes unless we actually (re)export it - and fix a
# broken persisted value so future terminal sessions work too.
function Set-JavaHomeEnv {
    param([string]$JavaHome)

    $env:JAVA_HOME = $JavaHome

    $userJavaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    $userJavaHomeValid = $userJavaHome -and (Test-Path (Join-Path $userJavaHome "bin\java.exe"))
    if (-not $userJavaHomeValid) {
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $JavaHome, 'User')
        Write-Info "Corrected stale/missing JAVA_HOME (User scope) -> $JavaHome"
    }
}

# Even a corrected registry JAVA_HOME doesn't help a terminal that was
# already open before the fix - Windows only loads env vars into a
# process at the moment it starts, so an old shell keeps whatever it
# had. gradlew reads $env:JAVA_HOME every time, so a stale terminal
# building any Android project reproduces the exact "invalid directory"
# error even after this installer fixed the registry. Setting
# org.gradle.java.home in the per-user global gradle.properties makes
# Gradle use the confirmed-correct JDK directly, for every project on
# this machine, regardless of which terminal or how stale its env is.
function Set-GradleJavaHome {
    param([string]$JavaHome)

    $gradleDir = Join-Path $HOME ".gradle"
    if (-not (Test-Path $gradleDir)) {
        New-Item -ItemType Directory -Path $gradleDir | Out-Null
    }
    $gradleProps = Join-Path $gradleDir "gradle.properties"

    # .properties files treat \ as an escape character - a Windows path
    # needs its backslashes doubled or Gradle mis-parses the value.
    $escapedHome = $JavaHome -replace '\\', '\\'
    $newLine = "org.gradle.java.home=$escapedHome"

    $lines = @()
    if (Test-Path $gradleProps) {
        $lines = @(Get-Content -LiteralPath $gradleProps)
    }

    $existingIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*org\.gradle\.java\.home\s*=') { $existingIndex = $i; break }
    }

    if ($existingIndex -ge 0) {
        if ($lines[$existingIndex] -eq $newLine) { return }
        $lines[$existingIndex] = $newLine
    } else {
        $lines += $newLine
    }

    Set-Content -LiteralPath $gradleProps -Value $lines
    Write-Info "Set org.gradle.java.home in $gradleProps -> $JavaHome"
}

# Invoke-WebRequest's own progress rendering is a plain OS progress dialog
# (the blue "Writing web request..." banner) that doesn't match the rest
# of this tool's output. Streaming the response ourselves gives us a
# colored, in-place progress bar instead.
function Invoke-DownloadWithProgress {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Label = "Downloading"
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.UserAgent = "android-dev-setup"
    $response = $request.GetResponse()
    $totalBytes = $response.ContentLength

    $responseStream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::Create($OutFile)
    $buffer = New-Object byte[] 65536
    $totalRead = 0L
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastDraw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        while (($read = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $totalRead += $read

            if ($lastDraw.ElapsedMilliseconds -ge 150 -or $totalRead -eq $totalBytes) {
                $percent = if ($totalBytes -gt 0) { [int](($totalRead / $totalBytes) * 100) } else { 0 }
                $speed = if ($sw.Elapsed.TotalSeconds -gt 0) { ($totalRead / 1MB) / $sw.Elapsed.TotalSeconds } else { 0 }
                Write-DownloadProgress -Percent $percent -DoneMB ($totalRead / 1MB) -TotalMB ($totalBytes / 1MB) -SpeedMBs $speed -Label $Label
                $lastDraw.Restart()
            }
        }
    } finally {
        $fileStream.Close()
        $responseStream.Close()
        $response.Close()
    }
    Write-Host ""
}

# Google doesn't publish a permanently-stable "latest" alias for this URL -
# the build number in cmdlineToolsUrl (config.json) will eventually go
# stale and need updating. Manually placing the zip in packages\ always
# still works and takes priority over downloading.
function Get-CmdlineToolsZip {
    param([PSCustomObject]$Cfg)

    if (Test-Path $CmdlineZip) { return }

    if (-not $Cfg.cmdlineToolsUrl) {
        Write-Fail "Android Command Line Tools package not found."
        Write-Info "Expected: $CmdlineZip"
        Write-Info "Please put commandlinetools-win.zip inside: $(Join-Path $PSScriptRoot 'packages')"
        throw "Android Command Line Tools package not found."
    }

    if ($DryRun) {
        Write-DryRun "Would download commandlinetools-win.zip from $($Cfg.cmdlineToolsUrl)"
        return
    }

    Write-Info "commandlinetools-win.zip not found locally - downloading from Google..."
    Write-Info $Cfg.cmdlineToolsUrl
    try {
        Invoke-DownloadWithProgress -Url $Cfg.cmdlineToolsUrl -OutFile $CmdlineZip -Label "cmdline-tools"
    } catch {
        if (Test-Path $CmdlineZip) { Remove-Item -LiteralPath $CmdlineZip -Force -ErrorAction SilentlyContinue }
        throw "Failed to download Android Command Line Tools: $($_.Exception.Message)"
    }

    if ($Cfg.cmdlineToolsSha256) {
        $actualHash = (Get-FileHash -Path $CmdlineZip -Algorithm SHA256).Hash
        if ($actualHash -ne $Cfg.cmdlineToolsSha256) {
            Remove-Item -LiteralPath $CmdlineZip -Force -ErrorAction SilentlyContinue
            throw "Downloaded commandlinetools-win.zip failed checksum verification (got $actualHash, expected $($Cfg.cmdlineToolsSha256))."
        }
        Write-Ok "Checksum verified."
    }

    Write-Ok "Downloaded commandlinetools-win.zip."
}

function Test-Installation {
    param(
        [string]$InstallRoot,
        [PSCustomObject]$Cfg,
        [string]$SdkManagerPath
    )

    $failed = $false

    $checks = @(
        @{ Name = "Platform Tools / ADB"; Path = Join-Path $InstallRoot "platform-tools\adb.exe" }
        @{ Name = "Android $($Cfg.androidPlatform)"; Path = Join-Path $InstallRoot "platforms\android-$($Cfg.androidPlatform)" }
        @{ Name = "Build Tools $($Cfg.buildTools)"; Path = Join-Path $InstallRoot "build-tools\$($Cfg.buildTools)" }
        @{ Name = "NDK $($Cfg.ndk)"; Path = Join-Path $InstallRoot "ndk\$($Cfg.ndk)" }
        @{ Name = "CMake $($Cfg.cmake)"; Path = Join-Path $InstallRoot "cmake\$($Cfg.cmake)" }
        @{ Name = "SDK Manager"; Path = $SdkManagerPath }
    )

    foreach ($c in $checks) {
        if (Test-Path $c.Path) { Write-Ok $c.Name } else { Write-Fail $c.Name; $failed = $true }
    }

    $javaState = Test-JavaVersion
    if ($javaState.Ok) { Write-Ok "Java 17+" } else { Write-Fail "Java 17+"; $failed = $true }

    return @{ Failed = $failed; JavaState = $javaState }
}

function Invoke-Check {
    param([PSCustomObject]$Cfg)

    Write-Banner "ANDROID SETUP - CHECK MODE"
    Write-Step "Verifying current environment against $($Cfg.installRoot)..."

    $sdkManager = Get-SdkManagerPath -InstallRoot $Cfg.installRoot
    $verify = Test-Installation -InstallRoot $Cfg.installRoot -Cfg $Cfg -SdkManagerPath $sdkManager

    Write-Host ""
    if ($verify.Failed) {
        Write-Warn "Some components are missing or not configured."
        return 1
    }

    Write-Ok "Environment looks complete."
    return 0
}

function Invoke-Install {
    param([PSCustomObject]$Cfg)

    $InstallRoot = $Cfg.installRoot
    $SdkManager = Get-SdkManagerPath -InstallRoot $InstallRoot

    Write-Banner
    if ($DryRun) {
        Write-Host "  DRY RUN - no files will be deleted, no packages installed," -ForegroundColor Magenta
        Write-Host "  no environment variables changed." -ForegroundColor Magenta
        Write-Host ""
    }
    Write-Host "This installer will prepare a CLEAN Android development"
    Write-Host "environment for building Android applications."
    Write-Host ""
    Write-Host "REQUIRES: Java 17 or newer (installed automatically if missing)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "CLEANUP:"
    Write-Host "  - Existing $InstallRoot will be removed."
    Write-Host "  - Old/wrong ANDROID_HOME, ANDROID_SDK_ROOT (User + Machine)"
    Write-Host "    will be detected and reset."
    Write-Host "  - Android SDK/NDK/CMake PATH entries will be cleaned."
    Write-Host ""
    Write-Host "INSTALLS:"
    Write-Host "  - Android Command Line Tools"
    Write-Host "  - Platform Tools / ADB"
    Write-Host "  - Android $($Cfg.androidPlatform) platform"
    Write-Host "  - Build Tools $($Cfg.buildTools)"
    Write-Host "  - NDK $($Cfg.ndk)"
    Write-Host "  - CMake $($Cfg.cmake)"
    Write-Host ""
    Write-Host "JAVA:"
    Write-Host "  - Existing Java 17+ will NOT be uninstalled or touched."
    Write-Host "  - If missing, bundled Java17-Setup.exe is installed silently."
    Write-Host ""
    Write-Host "NOT TOUCHED:"
    Write-Host "  - Project files outside $InstallRoot, Node.js/npm, Git,"
    Write-Host "    unrelated PATH entries, emulators/system images."
    Write-Host ""

    if (-not $Yes) {
        $resp = Read-Host "Start CLEAN + FRESH Android setup? [Y/N]"
        if ($resp -notmatch '^[Yy]') {
            Write-Host ""
            Write-Host "Setup cancelled. No installation was started."
            Write-Host ""
            return 0
        }
    }

    Write-Step "[1/7] Checking Java..."
    $javaState = Test-JavaVersion
    if ($javaState.Ok) {
        Write-Ok "Java 17+ detected."
        Write-Info "Existing Java will be preserved."
        Write-Info "Java Home: $($javaState.Home)"
    } else {
        Write-Warn "Java 17+ was not detected."
        $javaState = Install-JavaSilently
        Write-Ok "Java 17+ detected successfully."
        Write-Info "Java Home: $($javaState.Home)"
    }

    if (-not $DryRun) {
        Set-JavaHomeEnv -JavaHome $javaState.Home
        Set-GradleJavaHome -JavaHome $javaState.Home
    } else {
        Write-DryRun "Would set org.gradle.java.home in $HOME\.gradle\gradle.properties -> $($javaState.Home)"
    }

    Write-Step "[2/7] Detecting and cleaning old/wrong Android environment..."
    if (-not (Test-Path $CleanEnvScript)) {
        throw "tools\Clean-AndroidEnv.ps1 was not found: $CleanEnvScript"
    }
    & $CleanEnvScript -NewRoot $InstallRoot -DryRun:$DryRun -NoColor:$NoColor

    Write-Step "[3/7] Removing old $InstallRoot..."
    if ($DryRun) {
        if (Test-Path $InstallRoot) {
            Write-DryRun "Would remove $InstallRoot"
        } else {
            Write-Info "$InstallRoot does not exist, nothing to remove."
        }
        Write-DryRun "Would create fresh $InstallRoot"
    } else {
        if (Test-Path $InstallRoot) {
            Write-Info "Removing $InstallRoot ..."
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $InstallRoot) {
            Write-Fail "Could not remove $InstallRoot."
            Write-Info "Close Android Studio, Gradle, ADB or other processes that may be using it and run this installer again."
            throw "Could not remove $InstallRoot."
        }
        New-Item -ItemType Directory -Path $InstallRoot | Out-Null
        if (-not (Test-Path $InstallRoot)) {
            throw "Could not create $InstallRoot."
        }
        Write-Ok "Fresh $InstallRoot created."
    }

    Get-CmdlineToolsZip -Cfg $Cfg

    Write-Step "[4/7] Extracting Android Command Line Tools..."
    if ($DryRun) {
        Write-DryRun "Would extract $CmdlineZip to $InstallRoot\cmdline-tools\latest"
    } else {
        $tempExtract = Join-Path $env:TEMP "android-cmdline-tools"
        if (Test-Path $tempExtract) { Remove-Item -LiteralPath $tempExtract -Recurse -Force }
        New-Item -ItemType Directory -Path $tempExtract | Out-Null

        Expand-Archive -LiteralPath $CmdlineZip -DestinationPath $tempExtract -Force

        New-Item -ItemType Directory -Path (Join-Path $InstallRoot "cmdline-tools") -Force | Out-Null

        $extracted = Join-Path $tempExtract "cmdline-tools"
        if (Test-Path $extracted) {
            Move-Item -LiteralPath $extracted -Destination (Join-Path $InstallRoot "cmdline-tools\latest")
        } else {
            Write-Fail "Expected cmdline-tools folder was not found in the zip."
            Write-Info "The ZIP should contain: cmdline-tools\bin, lib, source.properties"
            throw "Expected cmdline-tools folder was not found in the zip."
        }

        if (-not (Test-Path $SdkManager)) {
            throw "sdkmanager.bat was not found: $SdkManager"
        }

        Write-Ok "Android Command Line Tools installed."
    }

    Write-Step "[5/7] Installing required Android packages..."

    $packages = [ordered]@{
        "Platform Tools"                  = "platform-tools"
        "Android $($Cfg.androidPlatform)" = "platforms;android-$($Cfg.androidPlatform)"
        "Build Tools $($Cfg.buildTools)"  = "build-tools;$($Cfg.buildTools)"
        "NDK $($Cfg.ndk)"                 = "ndk;$($Cfg.ndk)"
        "CMake $($Cfg.cmake)"             = "cmake;$($Cfg.cmake)"
    }

    if ($DryRun) {
        foreach ($label in $packages.Keys) { Write-DryRun "Would install $label ($($packages[$label]))" }
    } else {
        # Licenses must be accepted BEFORE installing - sdkmanager silently
        # skips any package whose license isn't accepted yet (and still
        # exits 0), so accepting after the fact is too late on a fresh SDK
        # root with no prior license acceptance. Piping "y" answers straight
        # into a PowerShell pipeline isn't reliable here: sdkmanager is slow
        # to reach the prompt (fetching the remote repo index first), and by
        # the time it reads stdin, PowerShell's pipe has already closed -
        # the process sees EOF instead of "y". A real file redirected via
        # cmd's "<" doesn't have that race.
        Write-Info "Accepting Android SDK licenses..."
        $yesFile = Join-Path $env:TEMP "android-dev-setup-license-yes.txt"
        (1..50 | ForEach-Object { "y" }) | Out-File -FilePath $yesFile -Encoding ascii
        try {
            cmd /c "`"$SdkManager`" --sdk_root=`"$InstallRoot`" --licenses < `"$yesFile`"" | Out-Null
        } finally {
            Remove-Item -LiteralPath $yesFile -Force -ErrorAction SilentlyContinue
        }

        # sdkmanager's own console output (deprecation warnings, its own
        # progress bar) is noisy and doesn't match this tool's style, so
        # each package is installed one at a time with our own status
        # line - full sdkmanager output is only shown if a package fails,
        # for debugging. Capturing via cmd's own "2>&1" (like the license
        # step above) avoids PowerShell wrapping sdkmanager's stderr as an
        # ErrorRecord and auto-printing it regardless of our own handling.
        foreach ($label in $packages.Keys) {
            $pkgId = $packages[$label]
            Write-Info "Installing $label..."

            $output = cmd /c "`"$SdkManager`" --sdk_root=`"$InstallRoot`" $pkgId 2>&1"
            if ($LASTEXITCODE -ne 0) {
                Write-Host ($output -join "`n")
                throw "Failed to install $label (sdkmanager exit code $LASTEXITCODE)."
            }
            Write-Ok "$label installed."
        }
    }

    Write-Step "[6/7] Configuring Android environment variables..."
    if ($DryRun) {
        Write-DryRun "Would set ANDROID_HOME = $InstallRoot (User)"
        Write-DryRun "Would set ANDROID_SDK_ROOT = $InstallRoot (User)"
        Write-DryRun "Would add to User PATH: $InstallRoot\platform-tools, $InstallRoot\cmdline-tools\latest\bin"
    } else {
        [Environment]::SetEnvironmentVariable('ANDROID_HOME', $InstallRoot, 'User')
        [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $InstallRoot, 'User')

        $pathEntries = @(
            (Join-Path $InstallRoot "platform-tools"),
            (Join-Path $InstallRoot "cmdline-tools\latest\bin")
        )
        $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($currentPath -split ';' | Where-Object { $_.Trim() })
        foreach ($entry in $pathEntries) {
            if ($parts -notcontains $entry) { $parts += $entry }
        }
        [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')

        $env:ANDROID_HOME = $InstallRoot
        $env:ANDROID_SDK_ROOT = $InstallRoot
        $env:Path = "$InstallRoot\platform-tools;$InstallRoot\cmdline-tools\latest\bin;$env:Path"

        Write-Ok "ANDROID_HOME = $InstallRoot"
        Write-Ok "ANDROID_SDK_ROOT = $InstallRoot"
        Write-Ok "Android PATH entries configured."
    }

    Write-Step "[7/7] Verifying installation..."
    $verify = Test-Installation -InstallRoot $InstallRoot -Cfg $Cfg -SdkManagerPath $SdkManager

    if ($verify.Failed -and -not $DryRun) {
        throw "SETUP FAILED - one or more required components are missing. Review the errors above."
    }

    if ($DryRun) {
        Write-Host ""
        Write-Info "Dry run complete - no changes were made to your system."
        return 0
    }

    Write-Summary -Title "SETUP COMPLETE" -Elapsed $sw.Elapsed -Fields ([ordered]@{
        "SDK Root"    = $InstallRoot
        "Android"     = $Cfg.androidPlatform
        "Build Tools" = $Cfg.buildTools
        "NDK"         = $Cfg.ndk
        "CMake"       = $Cfg.cmake
        "Java Home"   = $verify.JavaState.Home
    })

    Write-Info "Open a NEW PowerShell/CMD window before building."
    return 0
}

$exitCode = 0
try {
    if (-not (Test-Path $Config)) {
        throw "Config file not found: $Config"
    }
    $cfg = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json

    if ($Check) {
        $exitCode = Invoke-Check -Cfg $cfg
    } else {
        $exitCode = Invoke-Install -Cfg $cfg
    }
}
catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    $exitCode = 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}

exit $exitCode
