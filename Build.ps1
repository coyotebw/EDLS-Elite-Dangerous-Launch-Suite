#Requires -Version 5.1
<#
.SYNOPSIS
    Compiles EliteLaunchSuite.ps1 to EliteLaunchSuite.exe using ps2exe.
.DESCRIPTION
    Extracts the version from the source script header, ensures the ps2exe
    module is available, and runs the compilation with the correct flags.
    Run this script from the repository root: .\Build.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Transcript (captures all output to build.log) ─────────────────────────────
$BuildLog = Join-Path $PSScriptRoot 'build.log'
Start-Transcript -Path $BuildLog -Append -Force
Write-Host "Build log: $BuildLog"

$exitCode = 0

try {

    # ── Resolve repo root (the folder containing this script) ─────────────────
    $RepoRoot  = $PSScriptRoot
    $SourcePs1 = Join-Path $RepoRoot 'EliteLaunchSuite.ps1'
    $OutputExe = Join-Path $RepoRoot 'EliteLaunchSuite.exe'
    $IconFile  = Join-Path $RepoRoot 'assets\icon.ico'

    # ── Check the output EXE isn't locked by a running process ────────────────
    if (Test-Path $OutputExe) {
        try {
            $stream = [System.IO.File]::Open($OutputExe,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            $stream.Close()
        } catch {
            throw "EliteLaunchSuite.exe is locked by another process (is it still running?). Close it and try again."
        }
    }

    # ── Extract version from $script:AppVersion = 'x.y.z' ────────────────────
    $HeaderLine = (Get-Content $SourcePs1 -TotalCount 10) |
                  Where-Object { $_ -match "AppVersion\s*=\s*'(\d+\.\d+(?:\.\d+)?)'" } |
                  Select-Object -First 1

    if ($HeaderLine -and $HeaderLine -match "AppVersion\s*=\s*'(\d+\.\d+(?:\.\d+)?)'") {
        $VersionRaw = $Matches[1]
    } else {
        $VersionRaw = $null
    }

    # Pad to 4 parts (ps2exe -version wants W.X.Y.Z)
    if ($VersionRaw) {
        $Parts = $VersionRaw.Split('.')
        while ($Parts.Count -lt 4) { $Parts += '0' }
        $BuildVersion = $Parts -join '.'
    } else {
        Write-Warning "Could not extract version from script header; defaulting to 1.0.0.0"
        $BuildVersion = '1.0.0.0'
    }

    Write-Host ""
    Write-Host "=== EDLaunchSuite Build ===" -ForegroundColor Cyan
    Write-Host "Source : $SourcePs1"
    Write-Host "Output : $OutputExe"
    Write-Host "Version: $BuildVersion"
    Write-Host ""

    # ── Ensure ps2exe module is available ─────────────────────────────────────
    if (-not (Get-Module -ListAvailable -Name ps2exe)) {
        Write-Host "ps2exe module not found. Installing..." -ForegroundColor Yellow
        Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "ps2exe installed." -ForegroundColor Green
    } else {
        Write-Host "ps2exe module found." -ForegroundColor Green
    }

    Import-Module ps2exe -Force
    Write-Host "ps2exe version: $((Get-Module ps2exe).Version)"

    # ── Compile ────────────────────────────────────────────────────────────────
    Write-Host "Compiling..." -ForegroundColor Cyan

    try {
        $ps2exeErrors = @()
        Invoke-ps2exe `
            -inputFile   $SourcePs1 `
            -outputFile  $OutputExe `
            -iconFile    $IconFile `
            -noConsole `
            -title       "Elite Launch Suite" `
            -description "Elite Dangerous Launcher" `
            -company     "coyotebw" `
            -version     $BuildVersion `
            -ErrorVariable ps2exeErrors

        if ($ps2exeErrors.Count -gt 0) {
            foreach ($err in $ps2exeErrors) {
                Write-Host "  ps2exe error: $err" -ForegroundColor Red
            }
            throw "ps2exe reported $($ps2exeErrors.Count) error(s)."
        }

        if (Test-Path $OutputExe) {
            $SizeKB = [math]::Round((Get-Item $OutputExe).Length / 1KB, 1)
            Write-Host ""
            Write-Host "BUILD SUCCEEDED  ->  $OutputExe  ($SizeKB KB)" -ForegroundColor Green
            Write-Host ""
        } else {
            throw "Output file was not created."
        }
    } catch {
        Write-Host ""
        Write-Host "BUILD FAILED: $_" -ForegroundColor Red
        Write-Host ""
        $exitCode = 1
    }

} finally {
    Write-Host "Full log written to: $BuildLog"
    Stop-Transcript
    # Keep terminal open when run interactively so the output can be read
    if ($Host.Name -eq 'ConsoleHost') { Read-Host "`nPress Enter to close" }
}

exit $exitCode
