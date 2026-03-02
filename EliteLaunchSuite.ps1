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

function Set-ConsoleStyle {
    # Apply Elite Dangerous amber-on-black aesthetic
    try {
        $Host.UI.RawUI.WindowTitle     = "Elite: Dangerous | Launch Suite"
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.UI.RawUI.ForegroundColor = 'DarkYellow'
        if ($Host.UI.RawUI.WindowSize.Width -lt 80) {
            $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(
                80, $Host.UI.RawUI.WindowSize.Height)
        }
        Clear-Host  # fill window with new background color
    } catch { <# non-interactive or restricted host — skip gracefully #> }
}

function Write-Log {
    param (
        $Message,
        [ValidateSet('Info','Success','Warning','Error','Dim')]
        [string]$Level = 'Info'
    )

    $Prefix = switch ($Level) {
        'Warning' { '▲ ' }
        'Error'   { '✖ ' }
        default   { '' }
    }

    $Color = switch ($Level) {
        'Success' { 'Yellow'     }
        'Warning' { 'Yellow'     }
        'Error'   { 'Red'        }
        'Dim'     { 'DarkGray'   }
        default   { 'DarkYellow' }
    }

    $Line = "[$(Get-Date -Format 'HH:mm:ss')] $Prefix$Message"
    Write-Host $Line -ForegroundColor $Color
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $Line -ErrorAction SilentlyContinue
    }
}

function Write-Header {
    $W     = 78  # inner width between ║ borders
    $Blank = ' ' * $W

    function Pad([string]$Text) {
        $P = [Math]::Max(0, $W - $Text.Length)
        return (' ' * [Math]::Floor($P / 2)) + $Text + (' ' * [Math]::Ceiling($P / 2))
    }

    # Spread letters with single spaces; double-space between words — matches header style
    function SpaceOut([string]$Text) {
        ($Text.ToUpper() -split '\s+' | ForEach-Object { $_.ToCharArray() -join ' ' }) -join '  '
    }

    Write-Host "╔$('═' * $W)╗"                                                                     -ForegroundColor DarkYellow
    Write-Host "║$Blank║"                                                                             -ForegroundColor DarkYellow
    Write-Host "║$(Pad '◆  E L I T E  :  D A N G E R O U S  ·  L A U N C H  S U I T E  ◆')║"     -ForegroundColor Yellow
    Write-Host "║$(Pad "C M D R  ·  $(SpaceOut $script:CmdrName)")║"                                 -ForegroundColor DarkYellow
    Write-Host "║$Blank║"                                                                             -ForegroundColor DarkYellow
    Write-Host "╚$('═' * $W)╝"                                                                     -ForegroundColor DarkYellow
    Write-Host ""
}

function Write-Phase {
    param([string]$Label)
    $Fill = [Math]::Max(2, 70 - $Label.Length)
    Write-Host ""
    Write-Host "  ◈  " -ForegroundColor DarkYellow -NoNewline
    Write-Host $Label  -ForegroundColor White       -NoNewline
    Write-Host ('  ' + '─' * $Fill) -ForegroundColor DarkGray
    Write-Host ""
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

    $Spinner   = @('|', '/', '-', '\')
    $Index     = 0
    $StartTime = Get-Date

    Write-Host ""

    while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {

        $Elapsed = (Get-Date) - $StartTime
        $ElapsedText = if ($Elapsed.TotalHours -ge 1) {
            "{0:hh\:mm\:ss}" -f $Elapsed
        } else {
            "{0:mm\:ss}" -f $Elapsed
        }

        $Char = $Spinner[$Index % $Spinner.Count]
        Write-Host -NoNewline "`r  $Message " -ForegroundColor DarkYellow
        Write-Host -NoNewline $Char           -ForegroundColor Yellow
        Write-Host -NoNewline "  [$ElapsedText]" -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 250
        $Index++
    }

    $TotalElapsed = (Get-Date) - $StartTime
    $FinalTime    = "{0:hh\:mm\:ss}" -f $TotalElapsed
    Write-Host "`r  $Message ✔  [$FinalTime]   " -ForegroundColor Yellow
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
        Write-Log $ErrorMessage          -Level Error
        Write-Log "Launcher cannot continue." -Level Error
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
        CmdrName           = "Coyote Bongwater"
        LaunchDelaySeconds = 3
        EliteAppId         = 359320
        Apps               = $DefaultAppList
    }

    # Create settings file with defaults on first run
    if (-not (Test-Path $script:SettingsFile)) {
        $Defaults | ConvertTo-Json -Depth 5 | Set-Content $script:SettingsFile -Encoding UTF8
        Write-Log "Settings file created: $($script:SettingsFile)" -Level Success
        Write-Log "Edit it to customise paths, delays, and which tools to launch." -Level Dim
    }

    # Load and parse settings
    try {
        $Json = Get-Content $script:SettingsFile -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "Could not read settings file — using defaults. ($_)" -Level Warning
        $Json = $Defaults | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }

    # Apply scalar settings (fall back to defaults for missing keys)
    $script:CmdrName           = if ($Json.CmdrName)                     { $Json.CmdrName }                                                     else { $Defaults.CmdrName }
    $script:EliteAppId         = if ($null -ne $Json.EliteAppId)         { [int]$Json.EliteAppId }                                              else { $Defaults.EliteAppId }
    $script:LaunchDelaySeconds = if ($null -ne $Json.LaunchDelaySeconds) { [int]$Json.LaunchDelaySeconds }                                      else { $Defaults.LaunchDelaySeconds }

    # Rebuild $Apps from the JSON array
    $script:Apps = @()
    foreach ($Entry in $Json.Apps) {

        if (-not $Entry.Enabled) { continue }

        if (-not $Entry.Name -or -not $Entry.Process) {
            Write-Log "Skipping malformed entry in settings.json (missing Name or Process)." -Level Warning
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
            Write-Log "$($Entry.Name) has no path in settings and no auto-discovery — will be skipped." -Level Warning
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

Set-ConsoleStyle

#create data directory and open log for this session
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
Add-Content -Path $LogFile -Value "" -ErrorAction SilentlyContinue
Add-Content -Path $LogFile -Value "=== Session started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ErrorAction SilentlyContinue

Write-Phase "PREFLIGHT"

#load settings from %LOCALAPPDATA%\EDLaunchSuite\settings.json
Load-Settings

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
        Write-Log "$($App.Name) not found — will be skipped." -Level Warning
        $App.Path = $null
    }
}

Clear-Host
Write-Header
Write-Phase "LAUNCH SEQUENCE"

Write-Log "Checking for Steam..."
#find & boot steam
if (-not (Is-Process-Running "steam")) {
    Write-Log "Steam offline — launching..."
    Start-Process "steam://open/main"
    Start-Sleep -Seconds 10
}
else {
    Write-Log "Steam online." -Level Success
}

#boot elite, wait up to 60s for it to appear
Write-Log "Opening Elite: Dangerous via Steam..."
Start-Process "steam://run/$EliteAppId"
Write-Log "Waiting for EliteDangerous64.exe...`r`n         (Click PLAY in the Frontier Launcher)`r`n"
$EliteStartTimeout = (Get-Date).AddSeconds(60)

do {
    Start-Sleep -Seconds 2
    $EliteProcess = Get-Process -Name "EliteDangerous64" -ErrorAction SilentlyContinue |
        Select-Object -First 1
} until ($EliteProcess -or ((Get-Date) -gt $EliteStartTimeout))

Assert-OrExit `
    ($EliteProcess) `
    "Elite Dangerous did not start within 60 seconds."

Write-Log "Elite: Dangerous online. (PID: $($EliteProcess.Id))" -Level Success

Write-Phase "LAUNCHING TOOLS"

#launch apps
foreach ($App in $Apps) {

    if (-not $App.Path) {
        continue
    }

    if (Is-Process-Running $App.Process) {
        Write-Log "$($App.Name) already running — skipping." -Level Dim
        continue
    }

    try {
        Write-Log "Launching $($App.Name)..."
        $Proc = Start-Process $App.Path -PassThru -ErrorAction Stop
        $LaunchedProcesses += $App.Process
        Write-Log "$($App.Name) online. (PID: $($Proc.Id))" -Level Success
    } catch {
        Write-Log "Failed to launch $($App.Name): $_" -Level Warning
    }

    Start-Sleep -Seconds $LaunchDelaySeconds
}

Write-Log "All systems nominal." -Level Success

Write-Phase "MONITORING"

#wait for elite to close
WaitSpinner -ProcessId $EliteProcess.Id -Message "Elite: Dangerous"

Write-Phase "SHUTDOWN"

Write-Log "Elite: Dangerous offline."
Write-Log "Closing third-party tools..."

#kill 3rd party apps on close
foreach ($ProcessName in $LaunchedProcesses) {

    $Running = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

    if ($Running) {
        Write-Log "Stopping $ProcessName..."
        $Running | Stop-Process -Force
    }
}

Write-Log "Farewell, CMDR. o7" -Level Success
Add-Content -Path $LogFile -Value "=== Session ended $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
exit 0
