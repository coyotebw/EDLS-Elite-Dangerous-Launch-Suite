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

#persistent data directory — safe for both .ps1 and compiled .exe contexts
$DataDir      = Join-Path $env:LOCALAPPDATA "EDLaunchSuite"
$LogFile      = Join-Path $DataDir "launcher.log"
$SettingsFile = Join-Path $DataDir "settings.json"

#array to track & close all apps on game exit
$LaunchedProcesses = @()

# $EliteAppId, $LaunchDelaySeconds, and $Apps are populated by Load-Settings below


 # ===============================
 # Helper Functions ||||||||||||||
 # ===============================

function Write-Log {
    param ($Message)
    $Line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $Line
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $Line -ErrorAction SilentlyContinue
    }
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

function Load-Settings {
    # Default app list written to settings.json on first run.
    # Paths use %VARIABLE% syntax so they're readable and portable across accounts.
    $DefaultAppList = @(
        [ordered]@{
            Name    = "EDMarketConnector"
            Process = "EDMarketConnector"
            Path    = '%ProgramFiles(x86)%\EDMarketConnector\EDMarketConnector.exe'
            Enabled = $true
        },
        [ordered]@{
            Name    = "SrvSurvey"
            Process = "SrvSurvey"
            Path    = $null   # null = auto-discover via ClickOnce Apps\2.0 directory
            Enabled = $true
        },
        [ordered]@{
            Name    = "OdysseyMaterialsHelper"
            Process = "Elite Dangerous Odyssey Materials Helper"
            Path    = '%LOCALAPPDATA%\Elite Dangerous Odyssey Materials Helper Launcher\program\Elite Dangerous Odyssey Materials Helper.exe'
            Enabled = $true
        },
        [ordered]@{
            Name    = "EDCoPilot"
            Process = "EDCoPilot"
            Path    = 'C:\EDCoPilot\EDCoPilot.exe'
            Enabled = $true
        }
    )

    $Defaults = [ordered]@{
        LaunchDelaySeconds = 3
        EliteAppId         = 359320
        Apps               = $DefaultAppList
    }

    # Create settings file with defaults on first run
    if (-not (Test-Path $script:SettingsFile)) {
        $Defaults | ConvertTo-Json -Depth 5 | Set-Content $script:SettingsFile -Encoding UTF8
        Write-Log "Settings file created: $($script:SettingsFile)"
        Write-Log "Edit it to customise paths, delays, and which tools to launch."
    }

    # Load and parse settings
    try {
        $Json = Get-Content $script:SettingsFile -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "WARNING: Could not read settings file — using defaults. ($_)"
        $Json = $Defaults | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }

    # Apply scalar settings (fall back to defaults for missing keys)
    $script:EliteAppId         = if ($null -ne $Json.EliteAppId)         { [int]$Json.EliteAppId }         else { $Defaults.EliteAppId }
    $script:LaunchDelaySeconds = if ($null -ne $Json.LaunchDelaySeconds) { [int]$Json.LaunchDelaySeconds } else { $Defaults.LaunchDelaySeconds }

    # Rebuild $Apps from the JSON array
    $script:Apps = @()
    foreach ($Entry in $Json.Apps) {

        if (-not $Entry.Enabled) { continue }

        if (-not $Entry.Name -or -not $Entry.Process) {
            Write-Log "WARNING: Skipping malformed entry in settings.json (missing Name or Process)."
            continue
        }

        $AppPath = if ($Entry.Path) {
            # Expand any %VARIABLE% placeholders in the stored path
            [System.Environment]::ExpandEnvironmentVariables($Entry.Path)
        } elseif ($Entry.Name -eq "SrvSurvey") {
            # Null path for SrvSurvey triggers auto-discovery in its ClickOnce directory
            {
                Get-ChildItem `
                    -Path (Join-Path $env:LOCALAPPDATA "Apps\2.0") `
                    -Filter "SrvSurvey.exe" `
                    -Recurse `
                    -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
            }
        } else {
            Write-Log "WARNING: $($Entry.Name) has no path in settings and no auto-discovery — will be skipped."
            $null
        }

        $script:Apps += @{
            Name    = $Entry.Name
            Process = $Entry.Process
            Path    = $AppPath
        }
    }
}


 # ===============================
 # MAIN ||||||||||||||||||||||||||
 # ===============================

#create data directory and open log for this session
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
Add-Content -Path $LogFile -Value "" -ErrorAction SilentlyContinue
Add-Content -Path $LogFile -Value "=== Session started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ErrorAction SilentlyContinue

#load settings from %LOCALAPPDATA%\EDLaunchSuite\settings.json
Load-Settings

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
Add-Content -Path $LogFile -Value "=== Session ended $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
exit 0
