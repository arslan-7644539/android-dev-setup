# Shared console UX helpers (colors, banner, status lines, summary box).
# Dot-sourced by Install.ps1 and tools\Clean-AndroidEnv.ps1.

$script:NoColor = $false

function Set-ConsoleColorMode {
    param([switch]$NoColor)
    $script:NoColor = [bool]$NoColor
}

function Write-Banner {
    param([string]$Title = "ANDROID DEVELOPMENT SETUP")

    if ($script:NoColor) {
        Write-Host "== $Title =="
        return
    }

    $width = 60
    $top = "+" + ("-" * ($width - 2)) + "+"
    $pad = [Math]::Max(0, [int](($width - 2 - $Title.Length) / 2))
    $mid = "|" + (" " * $pad) + $Title + (" " * ($width - 2 - $pad - $Title.Length)) + "|"

    Write-Host ""
    Write-Host $top -ForegroundColor Cyan
    Write-Host $mid -ForegroundColor Cyan
    Write-Host $top -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    if ($script:NoColor) {
        Write-Host "== $Text =="
    } else {
        Write-Host "== $Text ==" -ForegroundColor Cyan
    }
}

function Write-Ok {
    param([string]$Text)
    if ($script:NoColor) {
        Write-Host "  [ OK ] $Text"
    } else {
        Write-Host "  [ OK ] " -ForegroundColor Green -NoNewline
        Write-Host $Text
    }
}

function Write-Fail {
    param([string]$Text)
    if ($script:NoColor) {
        Write-Host "  [FAIL] $Text"
    } else {
        Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
        Write-Host $Text
    }
}

function Write-Warn {
    param([string]$Text)
    if ($script:NoColor) {
        Write-Host "  [WARN] $Text"
    } else {
        Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline
        Write-Host $Text
    }
}

function Write-Info {
    param([string]$Text)
    if ($script:NoColor) {
        Write-Host "        $Text"
    } else {
        Write-Host "        $Text" -ForegroundColor DarkGray
    }
}

function Write-DryRun {
    param([string]$Text)
    if ($script:NoColor) {
        Write-Host "  [DRY-RUN] $Text"
    } else {
        Write-Host "  [DRY-RUN] " -ForegroundColor Magenta -NoNewline
        Write-Host $Text
    }
}

function Write-DownloadProgress {
    param(
        [int]$Percent,
        [double]$DoneMB,
        [double]$TotalMB,
        [double]$SpeedMBs,
        [string]$Label = "Downloading"
    )

    $barWidth = 30
    $filled = [Math]::Max(0, [Math]::Min($barWidth, [int][Math]::Floor($barWidth * $Percent / 100)))
    $bar = ("#" * $filled) + ("-" * ($barWidth - $filled))
    $stats = "{0,3}% ({1:N1}/{2:N1} MB, {3:N1} MB/s)   " -f $Percent, $DoneMB, $TotalMB, $SpeedMBs

    if ($script:NoColor) {
        Write-Host -NoNewline ("`r  {0}: [{1}] {2}" -f $Label, $bar, $stats)
    } else {
        Write-Host -NoNewline "`r  "
        Write-Host -NoNewline "$Label " -ForegroundColor DarkGray
        Write-Host -NoNewline "[$bar] " -ForegroundColor Cyan
        Write-Host -NoNewline $stats -ForegroundColor Green
    }
}

function Write-Summary {
    param(
        [hashtable]$Fields,
        [string]$Title = "SETUP COMPLETE",
        [System.TimeSpan]$Elapsed
    )

    $width = 60
    $top = "+" + ("-" * ($width - 2)) + "+"
    $color = if ($script:NoColor) { $null } else { "Green" }

    Write-Host ""
    if ($color) { Write-Host $top -ForegroundColor $color } else { Write-Host $top }
    $pad = [Math]::Max(0, [int](($width - 2 - $Title.Length) / 2))
    $mid = "|" + (" " * $pad) + $Title + (" " * ($width - 2 - $pad - $Title.Length)) + "|"
    if ($color) { Write-Host $mid -ForegroundColor $color } else { Write-Host $mid }
    if ($color) { Write-Host $top -ForegroundColor $color } else { Write-Host $top }
    Write-Host ""

    foreach ($key in $Fields.Keys) {
        $line = "  {0,-14}: {1}" -f $key, $Fields[$key]
        Write-Host $line
    }

    if ($Elapsed) {
        Write-Host ""
        Write-Info ("Completed in {0:N1}s" -f $Elapsed.TotalSeconds)
    }
    Write-Host ""
}
