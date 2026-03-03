# ==========================================================
# Elite Dangerous Launch Suite  — WPF GUI edition ||||||||||
# v0.6.2 by CMDR Coyote Bongwater  ||||||||||||||||||||||||||
# ==========================================================

$script:AppVersion = '0.6.2'

# ── 64-bit bootstrap ──────────────────────────────────────
if (-not [Environment]::Is64BitProcess) {
    Start-Process "$env:WINDIR\sysnative\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-STA -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit 0
}

# ── WPF requires an STA thread ────────────────────────────
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe `
        -ArgumentList "-STA -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit 0
}

# ── Assemblies ────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ── Paths ─────────────────────────────────────────────────
$DataDir             = Join-Path $env:LOCALAPPDATA 'EDLaunchSuite'
$script:LogFile      = Join-Path $DataDir 'launcher.log'
$script:SettingsFile = Join-Path $DataDir 'settings.json'
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
Add-Content -Path $script:LogFile `
    -Value "=== Session started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" `
    -EA SilentlyContinue

# ── Settings functions ─────────────────────────────────────
function Test-SteamAvailable {
    try { $null = Get-Item 'HKCU:\Software\Valve\Steam' -EA Stop; $true }
    catch { $false }
}

function Load-Settings {
    $DefaultApps = @(
        [ordered]@{
            Name    = 'EDMarketConnector'
            Process = 'EDMarketConnector'
            Path    = '%ProgramFiles(x86)%\EDMarketConnector\EDMarketConnector.exe'
            Enabled = $true
        },
        [ordered]@{
            Name    = 'SrvSurvey'
            Process = 'SrvSurvey'
            Path    = $null
            Enabled = $true
        },
        [ordered]@{
            Name    = 'OdysseyMaterials'
            Process = 'Elite Dangerous Odyssey Materials Helper'
            Path    = '%LOCALAPPDATA%\Elite Dangerous Odyssey Materials Helper Launcher\program\Elite Dangerous Odyssey Materials Helper.exe'
            Enabled = $true
        },
        [ordered]@{
            Name    = 'EDCoPilot'
            Process = 'EDCoPilot'
            Path    = 'C:\EDCoPilot\EDCoPilot.exe'
            Enabled = $true
        },
        [ordered]@{
            Name    = 'EDHM_UI'
            Process = 'EDHM_UI'
            Path    = '%ProgramFiles%\EDHM_UI\EDHM_UI.exe'
            Enabled = $true
        },
        [ordered]@{
            Name    = 'opentrack'
            Process = 'opentrack'
            Path    = '%ProgramFiles%\opentrack\opentrack.exe'
            Enabled = $true
        }
    )
    $Defaults = [ordered]@{
        CmdrName           = 'Coyote Bongwater'
        LaunchDelaySeconds = 3
        EliteAppId         = 359320
        Apps               = $DefaultApps
    }

    if (-not (Test-Path $script:SettingsFile)) {
        $Defaults | ConvertTo-Json -Depth 5 |
            Set-Content $script:SettingsFile -Encoding UTF8
    }
    try   { $J = Get-Content $script:SettingsFile -Raw -EA Stop | ConvertFrom-Json -EA Stop }
    catch { $J = $Defaults | ConvertTo-Json -Depth 5 | ConvertFrom-Json }

    # Merge any default apps missing from the existing settings file so that
    # new entries added in a later version automatically appear for existing installs.
    $existingNames = @($J.Apps | ForEach-Object { $_.Name })
    $missing = $DefaultApps | Where-Object { $_.Name -notin $existingNames }
    if ($missing) {
        $allApps = @($J.Apps) + @($missing)
        $J | Add-Member -NotePropertyName Apps -NotePropertyValue $allApps -Force
        try { $J | ConvertTo-Json -Depth 5 | Set-Content $script:SettingsFile -Encoding UTF8 } catch {}
    }

    $script:CmdrName           = if ($J.CmdrName)                     { $J.CmdrName }                else { $Defaults.CmdrName }
    $script:EliteAppId         = if ($null -ne $J.EliteAppId)         { [int]$J.EliteAppId }         else { $Defaults.EliteAppId }
    $script:LaunchDelaySeconds = if ($null -ne $J.LaunchDelaySeconds) { [int]$J.LaunchDelaySeconds } else { $Defaults.LaunchDelaySeconds }
    $script:AutoStart          = if ($null -ne $J.AutoStart)          { [bool]$J.AutoStart }          else { $false }

    $script:Apps = @()
    foreach ($E in $J.Apps) {
        if (-not $E.Enabled -or -not $E.Name -or -not $E.Process) { continue }
        $P = if ($E.Path) {
            [System.Environment]::ExpandEnvironmentVariables($E.Path)
        } elseif ($E.Name -eq 'SrvSurvey') {
            { Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Apps\2.0') `
                -Filter SrvSurvey.exe -Recurse -EA SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName }
        } else { $null }
        $script:Apps += @{ Name = $E.Name; Process = $E.Process; Path = $P }
    }
}

# ── Brush helper ──────────────────────────────────────────
function Brush { param($Hex)
    [System.Windows.Media.SolidColorBrush]`
    [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
}

# ── AutoStart setting persister ───────────────────────────
function Save-AutoStart { param([bool]$Value)
    try {
        $J = Get-Content $script:SettingsFile -Raw -EA Stop |
             ConvertFrom-Json -EA Stop
        $J | Add-Member -NotePropertyName AutoStart -NotePropertyValue $Value -Force
        $J | ConvertTo-Json -Depth 5 |
             Set-Content $script:SettingsFile -Encoding UTF8
    } catch {}
}

# ── CMDR label formatter ──────────────────────────────────
function Format-CmdrLine { param([string]$Name)
    $Spaced = ($Name.ToUpper() -split '\s+' |
        ForEach-Object { $_.ToCharArray() -join ' ' }) -join '  '
    "C M D R  ·  $Spaced"
}


# ── Self-version check scriptblock ────────────────────────
# Injected vars: $Dispatcher, $LogFile, $LogDocument, $LogBox, $AppVersion
$SelfVersionScript = {
    Add-Type -AssemblyName PresentationFramework, PresentationCore
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    function RsBrush { param($H)
        [System.Windows.Media.SolidColorBrush]`
        [System.Windows.Media.ColorConverter]::ConvertFromString($H)
    }

    function UiLog { param($M, [string]$Lvl = 'Info')
        $C = switch ($Lvl) {
            'Success' { '#FFB700' } 'Error'   { '#CC4444' }
            'Warning' { '#C8860A' } 'Dim'     { '#555555' }
            default   { '#C8860A' }
        }
        $L = "[$(Get-Date -Format 'HH:mm:ss')] $M"
        Add-Content -Path $LogFile -Value $L -EA SilentlyContinue
        $d = $LogDocument; $b = $LogBox; $c = $C; $l = $L
        $Dispatcher.Invoke([Action]{
            $p = [System.Windows.Documents.Paragraph]::new()
            $p.Margin = [System.Windows.Thickness]::new(0)
            $r = [System.Windows.Documents.Run]::new($l)
            $r.Foreground = RsBrush $c
            $p.Inlines.Add($r)
            if ($d.Blocks.Count -gt 500) { $d.Blocks.Remove($d.Blocks.FirstBlock) }
            $d.Blocks.Add($p)
            $b.ScrollToEnd()
        })
    }

    try {
        $H = @{ 'User-Agent' = "EDLaunchSuite/$AppVersion" }
        $Release = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/coyotebw/EDLaunchSuite/releases/latest' `
            -Headers $H -EA Stop
        $LatestTag = $Release.tag_name -replace '^[vV]', ''
        $Current   = [Version]$AppVersion
        $Latest    = try { [Version]$LatestTag } catch { $null }
        if ($Latest -and $Latest -gt $Current) {
            UiLog "Update available: EDLaunchSuite v$LatestTag  (running v$AppVersion)" -Lvl Warning
        } else {
            UiLog "EDLaunchSuite v$AppVersion — up to date." -Lvl Dim
        }
    } catch {
        # Network unavailable or repo not found — silently skip.
    }
}

# ── Main window XAML ──────────────────────────────────────
[xml]$Xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Elite: Dangerous | Launch Suite"
    Background="#0D0D0D"
    FontFamily="Consolas"
    Width="1295" Height="1070"
    ResizeMode="CanMinimize"
    WindowStartupLocation="CenterScreen">

  <Grid Margin="21,18,21,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Border Grid.Row="0" BorderBrush="#C8860A" BorderThickness="1,2,1,1"
            Margin="0,0,0,14" Padding="25,18">
      <StackPanel>
        <TextBlock Name="TitleLabel"
                   Text="◆  E L I T E  :  D A N G E R O U S  ·  L A U N C H  S U I T E  ◆"
                   Foreground="#FFB700" FontSize="23"
                   TextAlignment="Center" FontWeight="Bold"/>
        <TextBlock Name="CmdrLabel"
                   Foreground="#C8860A" FontSize="19"
                   TextAlignment="Center" Margin="0,9,0,0"/>
        <TextBlock Name="VersionLabel"
                   Foreground="#3A3A3A" FontSize="13"
                   TextAlignment="Center" Margin="0,5,0,0"/>
      </StackPanel>
    </Border>

    <!-- Status panel -->
    <Border Grid.Row="1" BorderBrush="#1E1E1E" BorderThickness="1"
            Margin="0,0,0,14" Padding="18,14">
      <StackPanel>
        <TextBlock Text="  STATUS" Foreground="#3A3A3A" FontSize="18"
                   Margin="0,0,0,11"/>
        <StackPanel Name="StatusPanel"/>
      </StackPanel>
    </Border>

    <!-- Log pane -->
    <Border Grid.Row="2" BorderBrush="#252525" BorderThickness="1"
            Margin="0,0,0,14">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="  LOG" Foreground="#3A3A3A" FontSize="18"
                   Margin="0,11,0,4" Padding="7,0"/>
        <RichTextBox Name="LogBox" Grid.Row="1"
                     IsReadOnly="True"
                     Background="#0D0D0D"
                     BorderThickness="0"
                     Padding="14,7"
                     FontSize="19"
                     VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Disabled">
          <FlowDocument PageWidth="5000"/>
        </RichTextBox>
      </Grid>
    </Border>

    <!-- Button bar -->
    <Border Grid.Row="3" BorderBrush="#1E1E1E" BorderThickness="0,1,0,0"
            Padding="0,14,0,0">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
        <Button Name="LaunchBtn"
                Content="[ LAUNCH ]"
                Width="228" Height="60" Margin="0,0,14,0"
                Background="#1A1100" Foreground="#FFB700"
                BorderBrush="#C8860A" BorderThickness="1"
                FontFamily="Consolas" FontSize="23" Cursor="Hand"/>
        <CheckBox Name="AutoStartChk"
                  Content="auto-start"
                  Foreground="#3A3A3A"
                  FontFamily="Consolas" FontSize="19"
                  VerticalAlignment="Center"
                  VerticalContentAlignment="Center"
                  Margin="0,0,28,0"
                  Cursor="Hand"/>
        <Button Name="ShutdownBtn"
                Content="[ SHUTDOWN ]"
                Width="210" Height="60" Margin="0,0,25,0"
                Background="#0D0D0D" Foreground="#555555"
                BorderBrush="#2A2A2A" BorderThickness="1"
                FontFamily="Consolas" FontSize="21" Cursor="Hand"/>
        <Button Name="SettingsBtn"
                Content="Settings"
                Width="158" Height="60"
                Background="#0D0D0D" Foreground="#555555"
                BorderBrush="#2A2A2A" BorderThickness="1"
                FontFamily="Consolas" FontSize="19" Cursor="Hand"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

# ── Load window ───────────────────────────────────────────
$Reader       = [System.Xml.XmlNodeReader]::new($Xaml)
$Window       = [System.Windows.Markup.XamlReader]::Load($Reader)
$TitleLabel   = $Window.FindName('TitleLabel')
$CmdrLabel    = $Window.FindName('CmdrLabel')
$VersionLabel = $Window.FindName('VersionLabel')
$StatusPanel  = $Window.FindName('StatusPanel')
$LogBox       = $Window.FindName('LogBox')
$LaunchBtn    = $Window.FindName('LaunchBtn')
$SettingsBtn  = $Window.FindName('SettingsBtn')
$AutoStartChk = $Window.FindName('AutoStartChk')
$ShutdownBtn  = $Window.FindName('ShutdownBtn')
$LogDocument  = $LogBox.Document
$Dispatcher   = $Window.Dispatcher

# ── Dispatcher crash guard ────────────────────────────────
# Without this, any unhandled exception on the UI thread kills the process
# with no log entry. This handler logs the full exception + stack trace so
# the root cause can be identified, then keeps the app alive.
$Dispatcher.Add_UnhandledException({
    param($s, $e)
    $ts = Get-Date -Format 'HH:mm:ss'
    Add-Content -Path $script:LogFile `
        -Value "[$ts] [UNHANDLED] $($e.Exception.GetType().Name): $($e.Exception.Message)" `
        -EA SilentlyContinue
    Add-Content -Path $script:LogFile `
        -Value $e.Exception.StackTrace `
        -EA SilentlyContinue
    $e.Handled = $true
})

# ── Window icon ───────────────────────────────────────────
$_iconPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'icon.ico' } else { '' }
if ($_iconPath -and (Test-Path $_iconPath)) {
    try {
        $Window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new(
            [System.Uri]::new($_iconPath))
    } catch {}
}

# ── Button hover effects ──────────────────────────────────
$LaunchBtn.Add_MouseEnter({
    try {
        if ($LaunchBtn.IsEnabled) {
            $LaunchBtn.Background  = Brush '#2A2000'
            $LaunchBtn.BorderBrush = Brush '#FFB700'
        }
    } catch {}
})
$LaunchBtn.Add_MouseLeave({
    try {
        if ($LaunchBtn.IsEnabled) {
            $LaunchBtn.Background  = Brush '#1A1100'
            $LaunchBtn.BorderBrush = Brush '#C8860A'
        }
    } catch {}
})
$ShutdownBtn.Add_MouseEnter({
    try {
        $ShutdownBtn.Foreground  = Brush '#CC4444'
        $ShutdownBtn.BorderBrush = Brush '#663333'
    } catch {}
})
$ShutdownBtn.Add_MouseLeave({
    try {
        $ShutdownBtn.Foreground  = Brush '#555555'
        $ShutdownBtn.BorderBrush = Brush '#2A2A2A'
    } catch {}
})

# ── Status row management ─────────────────────────────────
$script:StatusRows = @{}

function New-StatusRow { param([string]$Key, [string]$Label)
    $Grid = [System.Windows.Controls.Grid]::new()
    $Grid.Margin = [System.Windows.Thickness]::new(0,4,0,4)

    foreach ($spec in @(25, 333, 0, 140)) {
        $cd = [System.Windows.Controls.ColumnDefinition]::new()
        $cd.Width = if ($spec -eq 0) {
            [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        } else {
            [System.Windows.GridLength]::new($spec)
        }
        $Grid.ColumnDefinitions.Add($cd)
    }

    $Dot = [System.Windows.Shapes.Ellipse]::new()
    $Dot.Width = 14; $Dot.Height = 14; $Dot.VerticalAlignment = 'Center'
    $Dot.Fill = Brush '#2A2A2A'
    [System.Windows.Controls.Grid]::SetColumn($Dot, 0)
    $Grid.Children.Add($Dot) | Out-Null

    $NameTB = [System.Windows.Controls.TextBlock]::new()
    $NameTB.Text = "  $Label"
    $NameTB.FontSize = 19; $NameTB.VerticalAlignment = 'Center'
    $NameTB.Foreground = Brush '#C8860A'
    [System.Windows.Controls.Grid]::SetColumn($NameTB, 1)
    $Grid.Children.Add($NameTB) | Out-Null

    $StateTB = [System.Windows.Controls.TextBlock]::new()
    $StateTB.Text = '—'; $StateTB.FontSize = 19; $StateTB.VerticalAlignment = 'Center'
    $StateTB.Foreground = Brush '#3A3A3A'
    [System.Windows.Controls.Grid]::SetColumn($StateTB, 2)
    $Grid.Children.Add($StateTB) | Out-Null

    $TimerTB = [System.Windows.Controls.TextBlock]::new()
    $TimerTB.Text = ''; $TimerTB.FontSize = 19; $TimerTB.VerticalAlignment = 'Center'
    $TimerTB.HorizontalAlignment = 'Right'; $TimerTB.Foreground = Brush '#555555'
    [System.Windows.Controls.Grid]::SetColumn($TimerTB, 3)
    $Grid.Children.Add($TimerTB) | Out-Null

    $StatusPanel.Children.Add($Grid) | Out-Null
    $script:StatusRows[$Key] = @{ Dot = $Dot; StateTB = $StateTB; TimerTB = $TimerTB }
}

function Rebuild-StatusRows {
    $StatusPanel.Children.Clear()
    $script:StatusRows.Clear()
    New-StatusRow -Key 'Steam' -Label 'Steam'
    New-StatusRow -Key 'Elite' -Label 'Elite: Dangerous'
    foreach ($App in $script:Apps) {
        New-StatusRow -Key $App.Name -Label $App.Name
    }
}

# ── UI log writer (main thread) ───────────────────────────
function Write-UILog { param($Message, [string]$Level = 'Info')
    $Color = switch ($Level) {
        'Success' { '#FFB700' } 'Error'   { '#CC4444' }
        'Warning' { '#C8860A' } 'Dim'     { '#555555' }
        default   { '#C8860A' }
    }
    $Line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Add-Content -Path $script:LogFile -Value $Line -EA SilentlyContinue
    $c = $Color; $l = $Line; $doc = $LogDocument; $box = $LogBox
    $Dispatcher.Invoke([Action]{
        $p = [System.Windows.Documents.Paragraph]::new()
        $p.Margin = [System.Windows.Thickness]::new(0)
        $r = [System.Windows.Documents.Run]::new($l)
        $r.Foreground = [System.Windows.Media.SolidColorBrush]`
            [System.Windows.Media.ColorConverter]::ConvertFromString($c)
        $p.Inlines.Add($r)
        if ($doc.Blocks.Count -gt 500) { $doc.Blocks.Remove($doc.Blocks.FirstBlock) }
        $doc.Blocks.Add($p)
        $box.ScrollToEnd()
    })
}

# ── Shared state (thread-safe) ────────────────────────────
$SharedState = [hashtable]::Synchronized(@{ EliteStartTime = $null })

# ── Elapsed timer (UI thread) ─────────────────────────────
$ElapsedTimer = [System.Windows.Threading.DispatcherTimer]::new()
$ElapsedTimer.Interval = [TimeSpan]::FromSeconds(1)
$ElapsedTimer.Add_Tick({
    try {
        $t = $SharedState['EliteStartTime']
        if ($t) {
            $elapsed = [DateTime]::Now - $t
            $row = $script:StatusRows['Elite']
            if ($row -and $row.TimerTB) {
                $row.TimerTB.Text = '▸ {0:hh\:mm\:ss}' -f $elapsed
            }
        }
    } catch {
        # Swallow: a tick exception must never reach the WPF dispatcher unhandled.
        Add-Content -Path $script:LogFile `
            -Value "[$(Get-Date -Format 'HH:mm:ss')] [WARN] ElapsedTimer tick error: $_" `
            -EA SilentlyContinue
    }
})

# ── Background launch scriptblock ─────────────────────────
# Variables injected via InitialSessionState:
#   $Dispatcher, $LogFile, $EliteAppId, $LaunchDelaySeconds,
#   $Apps, $StatusRows, $LogDocument, $LogBox,
#   $LaunchBtn, $ElapsedTimer, $SharedState
$LaunchScript = {
    Add-Type -AssemblyName PresentationFramework, PresentationCore

    function RsBrush { param($H)
        [System.Windows.Media.SolidColorBrush]`
        [System.Windows.Media.ColorConverter]::ConvertFromString($H)
    }

    function UiLog { param($M, [string]$Lvl = 'Info')
        $C = switch ($Lvl) {
            'Success' { '#FFB700' } 'Error'   { '#CC4444' }
            'Warning' { '#C8860A' } 'Dim'     { '#555555' }
            default   { '#C8860A' }
        }
        $L = "[$(Get-Date -Format 'HH:mm:ss')] $M"
        Add-Content -Path $LogFile -Value $L -EA SilentlyContinue
        $d = $LogDocument; $b = $LogBox; $c = $C; $l = $L
        $Dispatcher.Invoke([Action]{
            $p = [System.Windows.Documents.Paragraph]::new()
            $p.Margin = [System.Windows.Thickness]::new(0)
            $r = [System.Windows.Documents.Run]::new($l)
            $r.Foreground = RsBrush $c
            $p.Inlines.Add($r)
            if ($d.Blocks.Count -gt 500) { $d.Blocks.Remove($d.Blocks.FirstBlock) }
            $d.Blocks.Add($p)
            $b.ScrollToEnd()
        })
    }

    function UiStatus { param([string]$Key, [string]$State,
                              [string]$Color = '#C8860A', [bool]$ClearTimer = $false)
        $row = $StatusRows[$Key]; if (-not $row) { return }
        $c = $Color; $s = $State; $ct = $ClearTimer
        $Dispatcher.Invoke([Action]{
            $row.Dot.Fill         = RsBrush $c
            $row.StateTB.Text     = $s
            $row.StateTB.Foreground = RsBrush $c
            if ($ct) { $row.TimerTB.Text = '' }
        })
    }

    function Fail { param($M)
        UiLog $M -Lvl Error
        Add-Content -Path $LogFile `
            -Value "=== Session ended $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" `
            -EA SilentlyContinue
        $Dispatcher.Invoke([Action]{
            $LaunchBtn.IsEnabled = $true
            $LaunchBtn.Content   = '[ LAUNCH ]'
        })
    }

    # ── Preflight ──────────────────────────────────────────
    UiLog 'Preflight checks...' -Lvl Dim

    try { $null = Get-Item 'HKCU:\Software\Valve\Steam' -EA Stop }
    catch {
        UiStatus 'Steam' 'Not found' '#CC4444'
        Fail 'Steam does not appear to be installed.'
        return
    }

    foreach ($App in $Apps) {
        $R = if ($App.Path -is [scriptblock]) { & $App.Path } else { $App.Path }
        if ($R -and (Test-Path $R)) {
            $App.Path = $R
        } else {
            UiLog "$($App.Name) not found — will be skipped." -Lvl Warning
            UiStatus $App.Name 'Not found' '#CC4444'
            $App.Path = $null
        }
    }

    # ── Steam ──────────────────────────────────────────────
    if (-not (Get-Process -Name steam -EA SilentlyContinue)) {
        UiStatus 'Steam' 'Launching…' '#C8860A'
        UiLog 'Steam offline — launching...'
        Start-Process 'steam://open/main'
        Start-Sleep -Seconds 10
    }
    UiStatus 'Steam' 'Online' '#44CC44'
    UiLog 'Steam online.' -Lvl Success

    # ── Launch Elite ───────────────────────────────────────
    UiStatus 'Elite' 'Waiting…' '#C8860A'
    UiLog 'Opening Elite: Dangerous via Steam...'
    Start-Process "steam://run/$EliteAppId"
    UiLog 'Waiting for EliteDangerous64.exe...  (click PLAY in the Frontier Launcher)'

    $EP = $null
    do {
        Start-Sleep -Seconds 2
        $EP = Get-Process -Name EliteDangerous64 -EA SilentlyContinue |
              Select-Object -First 1
    } until ($EP)

    UiStatus 'Elite' 'Running' '#FFB700'
    UiLog "Elite: Dangerous online. (PID: $($EP.Id))" -Lvl Success

    $SharedState['EliteStartTime'] = [DateTime]::Now
    $Dispatcher.Invoke([Action]{ $ElapsedTimer.Start() })

    try {
        # ── Launch tools ───────────────────────────────────────
        $Launched = @()
        foreach ($App in $Apps) {
            if (-not $App.Path) { continue }
            $ExistingProc = Get-Process -Name $App.Process -EA SilentlyContinue |
                            Select-Object -First 1
            if ($ExistingProc) {
                UiLog "$($App.Name) already running — skipping." -Lvl Dim
                $Launched += @{ Name = $App.Name; Process = $App.Process; PID = $ExistingProc.Id }
                UiStatus $App.Name 'Online' '#44CC44'
                continue
            }
            try {
                UiLog "Launching $($App.Name)..."
                UiStatus $App.Name 'Launching…' '#C8860A'
                $P = Start-Process $App.Path -PassThru -EA Stop
                $Launched += @{ Name = $App.Name; Process = $App.Process; PID = $P.Id }
                UiStatus $App.Name 'Online' '#44CC44'
                UiLog "$($App.Name) online. (PID: $($P.Id))" -Lvl Success
            } catch {
                UiLog "Failed to launch $($App.Name): $_" -Lvl Warning
                UiStatus $App.Name 'Failed' '#CC4444'
            }
            Start-Sleep -Seconds $LaunchDelaySeconds
        }
        UiLog 'All systems nominal.' -Lvl Success

        # ── Monitor ────────────────────────────────────────────
        UiLog 'Monitoring Elite: Dangerous...' -Lvl Dim
        while (Get-Process -Id $EP.Id -EA SilentlyContinue) {
            Start-Sleep -Seconds 2
        }

        # ── Shutdown ───────────────────────────────────────────
        UiStatus 'Elite' 'Offline' '#555555' -ClearTimer $true
        UiLog 'Elite: Dangerous offline.'
        UiLog 'Closing third-party tools...'

        foreach ($LA in $Launched) {
            $Running = $null
            if ($LA.PID) { $Running = Get-Process -Id $LA.PID -EA SilentlyContinue }
            if (-not $Running) { $Running = Get-Process -Name $LA.Process -EA SilentlyContinue }
            if ($Running) {
                UiLog "Stopping $($LA.Name)..."
                $Running | Stop-Process -Force -EA SilentlyContinue
                UiStatus $LA.Name 'Closed' '#555555'
            }
        }

        UiLog 'Farewell, CMDR. o7' -Lvl Success
        Add-Content -Path $LogFile `
            -Value "=== Session ended $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" `
            -EA SilentlyContinue

    } catch {
        $ErrMsg = $_.ToString()
        UiLog "Unexpected error: $ErrMsg" -Lvl Error
        Add-Content -Path $LogFile `
            -Value "=== Session ended with error $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $ErrMsg ===" `
            -EA SilentlyContinue

    } finally {
        # Always stop the timer and re-enable the button — idempotent and safe to
        # call twice on the normal path (stopped timer is a no-op in WPF).
        try {
            $Dispatcher.Invoke([Action]{
                $ElapsedTimer.Stop()
                $LaunchBtn.IsEnabled = $true
                $LaunchBtn.Content   = '[ LAUNCH ]'
            })
        } catch {}
        $SharedState['EliteStartTime'] = $null
    }
}

# ── Launch button ─────────────────────────────────────────
$LaunchBtn.Add_Click({
    Load-Settings
    Rebuild-StatusRows

    $LaunchBtn.IsEnabled = $false
    $LaunchBtn.Content   = '[ RUNNING ]'
    Write-UILog 'Launch sequence initiated.' -Level Success

    $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($Pair in @(
        @('Dispatcher',         $Dispatcher),
        @('LogFile',            $script:LogFile),
        @('EliteAppId',         $script:EliteAppId),
        @('LaunchDelaySeconds', $script:LaunchDelaySeconds),
        @('Apps',               $script:Apps),
        @('StatusRows',         $script:StatusRows),
        @('LogDocument',        $LogDocument),
        @('LogBox',             $LogBox),
        @('LaunchBtn',          $LaunchBtn),
        @('ElapsedTimer',       $ElapsedTimer),
        @('SharedState',        $SharedState)
    )) {
        $ISS.Variables.Add(
            [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
                $Pair[0], $Pair[1], ''))
    }

    # Dispose any previous runspace/pipeline before creating a new one.
    if ($script:LaunchPS) {
        try { $script:LaunchPS.Stop()    } catch {}
        try { $script:LaunchPS.Dispose() } catch {}
        $script:LaunchPS = $null
    }
    if ($script:LaunchRS) {
        try { $script:LaunchRS.Close()   } catch {}
        try { $script:LaunchRS.Dispose() } catch {}
        $script:LaunchRS = $null
    }

    $script:LaunchRS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($ISS)
    $script:LaunchRS.ApartmentState = 'STA'
    $script:LaunchRS.Open()
    $script:LaunchPS = [System.Management.Automation.PowerShell]::Create()
    $script:LaunchPS.Runspace = $script:LaunchRS
    $script:LaunchPS.AddScript($LaunchScript) | Out-Null
    $script:LaunchPS.BeginInvoke() | Out-Null
})

# ── Cleanup on window close ───────────────────────────────
$Window.Add_Closed({
    $ElapsedTimer.Stop()
    if ($script:LaunchPS) {
        try { $script:LaunchPS.Stop()    } catch {}
        try { $script:LaunchPS.Dispose() } catch {}
    }
    if ($script:LaunchRS) {
        try { $script:LaunchRS.Close()   } catch {}
        try { $script:LaunchRS.Dispose() } catch {}
    }
    if ($script:VerCheckPS) {
        try { $script:VerCheckPS.Stop()    } catch {}
        try { $script:VerCheckPS.Dispose() } catch {}
    }
    if ($script:VerCheckRS) {
        try { $script:VerCheckRS.Close()   } catch {}
        try { $script:VerCheckRS.Dispose() } catch {}
    }
})

# ── Auto-start checkbox ───────────────────────────────────
$AutoStartChk.Add_Checked({
    try {
        $AutoStartChk.Foreground = Brush '#FFB700'
        Save-AutoStart $true
    } catch { Write-UILog "Auto-start save error: $_" -Level Warning }
})
$AutoStartChk.Add_Unchecked({
    try {
        $AutoStartChk.Foreground = Brush '#3A3A3A'
        Save-AutoStart $false
    } catch { Write-UILog "Auto-start save error: $_" -Level Warning }
})

# ── Shutdown button ───────────────────────────────────────
$ShutdownBtn.Add_Click({
    try {
        if (-not $script:Apps) { Load-Settings }
        $anyFound = $false
        foreach ($App in $script:Apps) {
            $Running = Get-Process -Name $App.Process -EA SilentlyContinue
            if ($Running) {
                $anyFound = $true
                Write-UILog "Stopping $($App.Name)..." -Level Warning
                $Running | Stop-Process -Force -EA SilentlyContinue
                $row = $script:StatusRows[$App.Name]
                if ($row) {
                    $row.Dot.Fill           = Brush '#555555'
                    $row.StateTB.Text       = 'Closed'
                    $row.StateTB.Foreground = Brush '#555555'
                }
            }
        }
        if ($anyFound) {
            Write-UILog 'Third-party tools shut down.' -Level Success
        } else {
            Write-UILog 'No tools running.' -Level Dim
        }
    } catch {
        Write-UILog "Shutdown error: $_" -Level Error
    }
})

# ── Settings button ───────────────────────────────────────
$SettingsBtn.Add_Click({
    Load-Settings

    [xml]$SX = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Launch Suite — Settings"
    Background="#0D0D0D" FontFamily="Consolas"
    Width="600" Height="440"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterOwner">

  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Scalar settings -->
    <Grid Grid.Row="0" Margin="0,0,0,12">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="160"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <TextBlock Grid.Row="0" Grid.Column="0" Text="CMDR Name"
                 Foreground="#555555" FontSize="11" VerticalAlignment="Center" Margin="0,4"/>
      <TextBox Grid.Row="0" Grid.Column="1" Name="CmdrBox"
               FontSize="11" Background="#1A1A1A" Foreground="#FFB700"
               BorderBrush="#2A2A2A" CaretBrush="#FFB700" Padding="4,3" Margin="0,4"/>

      <TextBlock Grid.Row="1" Grid.Column="0" Text="Steam App ID"
                 Foreground="#555555" FontSize="11" VerticalAlignment="Center" Margin="0,4"/>
      <TextBox Grid.Row="1" Grid.Column="1" Name="AppIdBox"
               FontSize="11" Background="#1A1A1A" Foreground="#FFB700"
               BorderBrush="#2A2A2A" CaretBrush="#FFB700" Padding="4,3" Margin="0,4"/>

      <TextBlock Grid.Row="2" Grid.Column="0" Text="Launch Delay (s)"
                 Foreground="#555555" FontSize="11" VerticalAlignment="Center" Margin="0,4"/>
      <TextBox Grid.Row="2" Grid.Column="1" Name="DelayBox"
               FontSize="11" Background="#1A1A1A" Foreground="#FFB700"
               BorderBrush="#2A2A2A" CaretBrush="#FFB700" Padding="4,3" Margin="0,4"/>
    </Grid>

    <!-- Apps grid -->
    <DataGrid Grid.Row="1" Name="AppsGrid"
              Background="#111111" Foreground="#C8860A" FontSize="11"
              BorderBrush="#2A2A2A" BorderThickness="1"
              GridLinesVisibility="None" HeadersVisibility="Column"
              AutoGenerateColumns="False"
              CanUserAddRows="False" CanUserDeleteRows="False"
              RowBackground="#111111" AlternatingRowBackground="#161616"
              SelectionMode="Single">
      <DataGrid.ColumnHeaderStyle>
        <Style TargetType="DataGridColumnHeader">
          <Setter Property="Background" Value="#1A1A1A"/>
          <Setter Property="Foreground" Value="#555555"/>
          <Setter Property="Padding"    Value="4,4"/>
          <Setter Property="FontSize"   Value="10"/>
        </Style>
      </DataGrid.ColumnHeaderStyle>
      <DataGrid.Columns>
        <DataGridCheckBoxColumn Header="On"      Binding="{Binding Enabled}" Width="36"/>
        <DataGridTextColumn    Header="Name"    Binding="{Binding Name}"    Width="130"/>
        <DataGridTextColumn    Header="Process" Binding="{Binding Process}" Width="180"/>
        <DataGridTextColumn    Header="Path"    Binding="{Binding Path}"    Width="*"/>
      </DataGrid.Columns>
    </DataGrid>

    <!-- Buttons -->
    <Grid Grid.Row="2" Margin="0,12,0,0">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
        <Button Name="AddAppBtn" Content="+ Add" Width="72" Height="30" Margin="0,0,6,0"
                Background="#0D0D0D" Foreground="#C8860A"
                BorderBrush="#2A2A2A" BorderThickness="1" Cursor="Hand"/>
        <Button Name="RemoveAppBtn" Content="- Remove" Width="84" Height="30"
                Background="#0D0D0D" Foreground="#555555"
                BorderBrush="#2A2A2A" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="SaveBtn" Content="Save" Width="80" Height="30" Margin="0,0,8,0"
                Background="#1A1100" Foreground="#FFB700"
                BorderBrush="#C8860A" BorderThickness="1" Cursor="Hand"/>
        <Button Name="CancelBtn" Content="Cancel" Width="80" Height="30"
                Background="#0D0D0D" Foreground="#555555"
                BorderBrush="#2A2A2A" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

    $SR       = [System.Xml.XmlNodeReader]::new($SX)
    $Dlg      = [System.Windows.Markup.XamlReader]::Load($SR)
    $Dlg.Owner= $Window

    $CmdrBox  = $Dlg.FindName('CmdrBox')
    $AppIdBox = $Dlg.FindName('AppIdBox')
    $DelayBox = $Dlg.FindName('DelayBox')
    $AppsGrid = $Dlg.FindName('AppsGrid')
    $AddAppBtn    = $Dlg.FindName('AddAppBtn')
    $RemoveAppBtn = $Dlg.FindName('RemoveAppBtn')
    $SaveBtn      = $Dlg.FindName('SaveBtn')
    $CancelBtn    = $Dlg.FindName('CancelBtn')

    $CmdrBox.Text  = $script:CmdrName
    $AppIdBox.Text = "$($script:EliteAppId)"
    $DelayBox.Text = "$($script:LaunchDelaySeconds)"

    try {
        $RawJson  = Get-Content $script:SettingsFile -Raw -EA Stop |
                    ConvertFrom-Json -EA Stop
        $AppItems = $RawJson.Apps | ForEach-Object {
            [PSCustomObject]@{
                Enabled = [bool]$_.Enabled
                Name    = "$($_.Name)"
                Process = "$($_.Process)"
                Path    = if ($_.Path) { "$($_.Path)" } else { '' }
            }
        }
    } catch { $AppItems = @() }

    $Col = [System.Collections.ObjectModel.ObservableCollection[PSCustomObject]]::new()
    foreach ($Item in $AppItems) { $Col.Add($Item) }
    $AppsGrid.ItemsSource = $Col

    $AddAppBtn.Add_Click({
        $NewItem = [PSCustomObject]@{
            Enabled = $true
            Name    = 'NewApp'
            Process = 'NewApp'
            Path    = ''
        }
        $Col.Add($NewItem)
        $AppsGrid.SelectedItem = $NewItem
        $AppsGrid.ScrollIntoView($NewItem)
    })

    $RemoveAppBtn.Add_Click({
        $Selected = $AppsGrid.SelectedItem
        if ($Selected) { $Col.Remove($Selected) }
    })

    $SaveBtn.Add_Click({
        try {
            $NewApps = @($AppsGrid.ItemsSource | ForEach-Object {
                [ordered]@{
                    Name    = "$($_.Name)"
                    Process = "$($_.Process)"
                    Path    = if ($_.Path) { "$($_.Path)" } else { $null }
                    Enabled = [bool]$_.Enabled
                }
            })
            [ordered]@{
                CmdrName           = $CmdrBox.Text
                LaunchDelaySeconds = [int]$DelayBox.Text
                EliteAppId         = [int]$AppIdBox.Text
                AutoStart          = $script:AutoStart
                Apps               = $NewApps
            } | ConvertTo-Json -Depth 5 |
                Set-Content $script:SettingsFile -Encoding UTF8
            Load-Settings
            Rebuild-StatusRows
            $CmdrLabel.Text = Format-CmdrLine $script:CmdrName
            $Dlg.Close()
        } catch {
            [System.Windows.MessageBox]::Show(
                "Save failed: $_", 'Error', 'OK', 'Error')
        }
    })
    $CancelBtn.Add_Click({ $Dlg.Close() })
    $Dlg.ShowDialog() | Out-Null
})

# ── Initial load & show ───────────────────────────────────
Load-Settings
$CmdrLabel.Text    = Format-CmdrLine $script:CmdrName
$VersionLabel.Text = "v$($script:AppVersion)"
Rebuild-StatusRows

# Restore auto-start checkbox from settings
$AutoStartChk.IsChecked = $script:AutoStart
if ($script:AutoStart) { $AutoStartChk.Foreground = Brush '#FFB700' }

# Auto-trigger launch once window is fully rendered
$Window.Add_Loaded({
    if ($AutoStartChk.IsChecked) {
        $Dispatcher.BeginInvoke([Action]{
            try {
                $LaunchBtn.RaiseEvent(
                    [System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Button]::ClickEvent))
            } catch {
                Add-Content -Path $script:LogFile `
                    -Value "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Auto-start trigger failed: $_" `
                    -EA SilentlyContinue
            }
        })
    }

    # Background self-version check on startup
    $ISS_ver = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($Pair in @(
        @('Dispatcher',  $Dispatcher),
        @('LogFile',     $script:LogFile),
        @('LogDocument', $LogDocument),
        @('LogBox',      $LogBox),
        @('AppVersion',  $script:AppVersion)
    )) {
        $ISS_ver.Variables.Add(
            [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
                $Pair[0], $Pair[1], ''))
    }
    $script:VerCheckRS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($ISS_ver)
    $script:VerCheckRS.Open()
    $script:VerCheckPS = [System.Management.Automation.PowerShell]::Create()
    $script:VerCheckPS.Runspace = $script:VerCheckRS
    $script:VerCheckPS.AddScript($SelfVersionScript) | Out-Null
    $script:VerCheckPS.BeginInvoke() | Out-Null
})

Write-UILog 'Elite: Dangerous Launch Suite ready.' -Level Success
if ($script:AutoStart) {
    Write-UILog 'Auto-start enabled — launching...' -Level Dim
} else {
    Write-UILog 'Click LAUNCH to begin.' -Level Dim
}
$Window.ShowDialog() | Out-Null
