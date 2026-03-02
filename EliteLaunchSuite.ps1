# ==========================================================
# Elite Dangerous Launch Suite   ||||||||||||||||||||||||||
# v1.5 by CMDR Coyote Bongwater  ||||||||||||||||||||||||||
# ==========================================================

#first things first: force 64bit
if (-not [Environment]::Is64BitProcess) {
    Write-Host "Restarting in 64-bit PowerShell..."
    Start-Process "$env:WINDIR\sysnative\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit 0
}

 # ==========================
 # Vars |||||||||||||||||||||
 # ==========================

#window name
$Host.UI.RawUI.WindowTitle = "Elite: Dangerous | One-click launch"

#locate elite thru steam
$EliteAppId = 359320

#pathfinding black magic
$LocalAppData    = $env:LOCALAPPDATA
$ProgramFilesX86 = ${env:ProgramFiles(x86)}

$LaunchDelaySeconds = 3

#array to track & close all apps on game exit
$LaunchedProcesses = @()

#array of 3rd party tools
$Apps = @(
    @{
        Name    = "EDMarketConnector"
        Process = "EDMarketConnector"
        Path    = Join-Path $ProgramFilesX86 "EDMarketConnector\EDMarketConnector.exe"
    },
    @{
        Name    = "SrvSurvey"
        Process = "SrvSurvey"
        Path    = {
            Get-ChildItem `
                -Path (Join-Path $LocalAppData "Apps\2.0") `
                -Filter "SrvSurvey.exe" `
                -Recurse `
                -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        }
    },
    @{
        Name    = "OdysseyMaterialsHelper"
        Process = "Elite Dangerous Odyssey Materials Helper"
        Path    = Join-Path $LocalAppData `
            "Elite Dangerous Odyssey Materials Helper Launcher\program\Elite Dangerous Odyssey Materials Helper.exe"
    },
    @{
        Name    = "EDCoPilot"
        Process = "EDCoPilot"
        Path    = "C:\EDCoPilot\EDCoPilot.exe"
    }
)


 # ===============================
 # Helper Functions ||||||||||||||
 # ===============================

function Write-Log {
    param ($Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message"
}

function Is-Process-Running {
    param ($ProcessName)
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
}

function Resolve-AppPath {
    param ($Path)
    if ($Path -is [scriptblock]) { & $Path }
    else { $Path }
}

#pointless but amusing animation
function WaitSpinner {
    param (
        [int]$ProcessId,
        [string]$Message
    )

    $Spinner = @('|', '/', '-', '\')
    $Index = 0
    $StartTime = Get-Date

    Write-Host ""  # spacer line

    while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {

        $Elapsed = (Get-Date) - $StartTime
        if ($Elapsed.TotalHours -ge 1) {
            $ElapsedText = "{0:hh\:mm\:ss}" -f $Elapsed
        }
        else {
            $ElapsedText = "{0:mm\:ss}" -f $Elapsed
        }
        $Char = $Spinner[$Index % $Spinner.Count]
        Write-Host -NoNewline "`r$Message $Char  [$ElapsedText]"
        Start-Sleep -Milliseconds 250
        $Index++
    }
    $TotalElapsed = (Get-Date) - $StartTime
    $FinalTime = "{0:hh\:mm\:ss}" -f $TotalElapsed
    Write-Host "`r$Message ✔  [$FinalTime]"
}

#error checking
function Test-SteamAvailable {
    try {
        $null = Get-Item "HKCU:\Software\Valve\Steam" -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-Executable {
    param (
        [string]$Path
    )

    return ($Path -and (Test-Path $Path))
}

function Assert-OrExit {
    param (
        [bool]$Condition,
        [string]$ErrorMessage
    )

    if (-not $Condition) {
        Write-Log "ERROR: $ErrorMessage"
        Write-Log "Launcher cannot continue."
        Start-Sleep -Seconds 3
        exit 1
    }
}


 # ===============================
 # MAIN ||||||||||||||||||||||||||
 # ===============================

#error catching
Write-Log "Running preflight checks..."

# Steam must exist
Assert-OrExit `
    (Test-SteamAvailable) `
    "Steam does not appear to be installed."

# Elite Steam App ID sanity check
Assert-OrExit `
    ($EliteAppId -is [int]) `
    "Elite Dangerous Steam App ID is invalid."

# Validate third-party tool paths (non-fatal); resolve scriptblock paths now so we
# don't run them twice (once here, once in the launch loop).
foreach ($App in $Apps) {
    $ResolvedPath = Resolve-AppPath $App.Path
    if (Test-Executable $ResolvedPath) {
        $App.Path = $ResolvedPath
    } else {
        Write-Log "WARNING: $($App.Name) not found — will be skipped."
        $App.Path = $null
    }
}

Clear-Host
Write-Host ""
Write-Log "||                                ||"
Write-Log "||          WELCOME CMDR          ||"
Write-Log "||               o7               ||"
Write-Host ""
Write-Log "Checking for Steam..."
#find & boot steam
if (-not (Is-Process-Running "steam")) {
    Write-Log "Steam not running. Launching Steam..."
    Start-Process "steam://open/main"
    Start-Sleep -Seconds 10
}
else {
    Write-Log "Steam already running."
}

#boot elite, kill process if not detected within 60s
Write-Log "Launching Elite: Dangerous..."
Start-Process "steam://run/$EliteAppId"
Write-Log "Waiting for EliteDangerous64.exe...`r`n (GO CLICK THE BUTTON IN FRONTIER LAUNCHER!)`r`n"
$EliteStartTimeout = (Get-Date).AddSeconds(60)

do {
    Start-Sleep -Seconds 2
    $EliteProcess = Get-Process -Name "EliteDangerous64" -ErrorAction SilentlyContinue |
        Select-Object -First 1
} until ($EliteProcess -or ((Get-Date) -gt $EliteStartTimeout))

Assert-OrExit `
    ($EliteProcess) `
    "Elite Dangerous failed to start."

Write-Log "Elite detected (PID: $($EliteProcess.Id))"


#launch apps
foreach ($App in $Apps) {

    if (-not $App.Path) {
        continue
    }

    if (Is-Process-Running $App.Process) {
        Write-Log "$($App.Name) already running — skipping."
        continue
    }

    try {
        Write-Log "Launching $($App.Name) ($($App.Path))..."
        $Proc = Start-Process $App.Path -PassThru -ErrorAction Stop
        $LaunchedProcesses += $App.Process
        Write-Log "$($App.Name) started (PID: $($Proc.Id))."
    } catch {
        Write-Log "WARNING: Failed to launch $($App.Name): $_"
    }

    Start-Sleep -Seconds $LaunchDelaySeconds
}

Write-Log "All tools launched."

#wait for close
WaitSpinner -ProcessId $EliteProcess.Id -Message "Waiting for Elite: Dangerous to close..."
Write-Log "Elite: Dangerous has exited."
Write-Log "Closing third-party tools..."
#kill 3rd party apps on close
foreach ($ProcessName in $LaunchedProcesses) {

    $Running = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

    if ($Running) {
        Write-Log "Stopping $ProcessName..."
        $Running | Stop-Process -Force
    }
}

Write-Log "Launcher shutting down. Farewell, CMDR. o7"
Start-Sleep -Seconds 3
exit 0
