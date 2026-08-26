# Detects and removes old/wrong Android SDK environment configuration
# (ANDROID_HOME / ANDROID_SDK_ROOT in User + Machine scope, Android-related
# PATH entries, and leftover SDK folders outside the target install root)
# before INSTALL.bat sets up a fresh environment.

param(
    [Parameter(Mandatory = $true)]
    [string]$NewRoot
)

$ErrorActionPreference = 'Stop'
$NewRoot = $NewRoot.TrimEnd('\')

function Get-Var($name, $scope) {
    [Environment]::GetEnvironmentVariable($name, $scope)
}

# Paths that must never be auto-deleted even if a stray env var points at them.
$protected = @(
    'C:\', 'C:\Windows', 'C:\Program Files', 'C:\Program Files (x86)',
    'C:\Users', 'C:\ProgramData'
)

$oldDirs = New-Object System.Collections.Generic.List[string]

function Add-OldDir($path) {
    if (-not $path) { return }
    $full = $path.TrimEnd('\')
    if ($full -eq $NewRoot) { return }
    if ($protected -contains $full) { return }
    if ($full.Length -lt 8) { return }
    if (-not (Test-Path -LiteralPath $full)) { return }
    if (-not $oldDirs.Contains($full)) { $oldDirs.Add($full) }
}

# Collect old SDK locations from both scopes, then clear the variables.
foreach ($scope in 'User', 'Machine') {
    Add-OldDir (Get-Var 'ANDROID_HOME' $scope)
    Add-OldDir (Get-Var 'ANDROID_SDK_ROOT' $scope)
    [Environment]::SetEnvironmentVariable('ANDROID_HOME', $null, $scope)
    [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $null, $scope)
}

# Android Studio's own default SDK location, in case it was used before.
if ($env:LOCALAPPDATA) {
    Add-OldDir (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
}

# Strip Android/SDK-related entries from the User PATH.
$pattern = '(?i)\\android(\\|$)|\\android sdk(\\|$)|\\cmdline-tools(\\|$)|' +
           '\\platform-tools(\\|$)|\\build-tools(\\|$)|\\emulator(\\|$)|\\ndk(\\|$)'

$p = Get-Var 'Path' 'User'
if ($p) {
    $kept = @($p -split ';' | Where-Object { $_ -and ($_ -notmatch $pattern) })
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
}

foreach ($dir in $oldDirs) {
    Write-Host "       Removing old Android setup: $dir"
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($oldDirs.Count -eq 0) {
    Write-Host "       No old/wrong Android environment found."
}

Write-Host "       Old Android environment variables and PATH entries cleared."
