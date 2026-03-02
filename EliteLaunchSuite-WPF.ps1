# ==========================================================
# Elite Dangerous Launch Suite  — WPF GUI edition ||||||||||
# v1.0 by CMDR Coyote Bongwater  ||||||||||||||||||||||||||||
# ==========================================================

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

    $script:CmdrName           = if ($J.CmdrName)                     { $J.CmdrName }                else { $Defaults.CmdrName }
    $script:EliteAppId         = if ($null -ne $J.EliteAppId)         { [int]$J.EliteAppId }         else { $Defaults.EliteAppId }
    $script:LaunchDelaySeconds = if ($null -ne $J.LaunchDelaySeconds) { [int]$J.LaunchDelaySeconds } else { $Defaults.LaunchDelaySeconds }

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

# ── CMDR label formatter ──────────────────────────────────
function Format-CmdrLine { param([string]$Name)
    $Spaced = ($Name.ToUpper() -split '\s+' |
        ForEach-Object { $_.ToCharArray() -join ' ' }) -join '  '
    "C M D R  ·  $Spaced"
}

# ── Main window XAML ──────────────────────────────────────
[xml]$Xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Elite: Dangerous | Launch Suite"
    Background="#0D0D0D"
    FontFamily="Consolas"
    Width="740" Height="610"
    ResizeMode="CanMinimize"
    WindowStartupLocation="CenterScreen">

  <Grid Margin="12,10,12,10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Border Grid.Row="0" BorderBrush="#C8860A" BorderThickness="1"
            Margin="0,0,0,8" Padding="14,10">
      <StackPanel>
        <TextBlock Name="TitleLabel"
                   Text="◆  E L I T E  :  D A N G E R O U S  ·  L A U N C H  S U I T E  ◆"
                   Foreground="#FFB700" FontSize="13"
                   TextAlignment="Center" FontWeight="Bold"/>
        <TextBlock Name="CmdrLabel"
                   Foreground="#C8860A" FontSize="11"
                   TextAlignment="Center" Margin="0,5,0,0"/>
      </StackPanel>
    </Border>

    <!-- Status panel -->
    <Border Grid.Row="1" BorderBrush="#1E1E1E" BorderThickness="1"
            Margin="0,0,0,8" Padding="10,8">
      <StackPanel>
        <TextBlock Text="  STATUS" Foreground="#3A3A3A" FontSize="10"
                   Margin="0,0,0,6"/>
        <StackPanel Name="StatusPanel"/>
      </StackPanel>
    </Border>

    <!-- Log pane -->
    <Border Grid.Row="2" BorderBrush="#1E1E1E" BorderThickness="1"
            Margin="0,0,0,8">
      <RichTextBox Name="LogBox"
                   IsReadOnly="True"
                   Background="#0D0D0D"
                   BorderThickness="0"
                   Padding="8,6"
                   FontSize="11"
                   VerticalScrollBarVisibility="Auto"
                   HorizontalScrollBarVisibility="Disabled">
        <FlowDocument PageWidth="3000"/>
      </RichTextBox>
    </Border>

    <!-- Button bar -->
    <StackPanel Grid.Row="3" Orientation="Horizontal"
                HorizontalAlignment="Center" Margin="0,4,0,0">
      <Button Name="LaunchBtn"
              Content="[ LAUNCH ]"
              Width="130" Height="34" Margin="0,0,14,0"
              Background="#1A1100" Foreground="#FFB700"
              BorderBrush="#C8860A" BorderThickness="1"
              FontFamily="Consolas" FontSize="13" Cursor="Hand"/>
      <Button Name="SettingsBtn"
              Content="Settings"
              Width="90" Height="34"
              Background="#0D0D0D" Foreground="#555555"
              BorderBrush="#2A2A2A" BorderThickness="1"
              FontFamily="Consolas" FontSize="11" Cursor="Hand"/>
    </StackPanel>
  </Grid>
</Window>
'@

# ── Load window ───────────────────────────────────────────
$Reader     = [System.Xml.XmlNodeReader]::new($Xaml)
$Window     = [System.Windows.Markup.XamlReader]::Load($Reader)
$TitleLabel = $Window.FindName('TitleLabel')
$CmdrLabel  = $Window.FindName('CmdrLabel')
$StatusPanel= $Window.FindName('StatusPanel')
$LogBox     = $Window.FindName('LogBox')
$LaunchBtn  = $Window.FindName('LaunchBtn')
$SettingsBtn= $Window.FindName('SettingsBtn')
$LogDocument= $LogBox.Document
$Dispatcher = $Window.Dispatcher

# ── Status row management ─────────────────────────────────
$script:StatusRows = @{}

function New-StatusRow { param([string]$Key, [string]$Label)
    $Grid = [System.Windows.Controls.Grid]::new()
    $Grid.Margin = [System.Windows.Thickness]::new(0,2,0,2)

    foreach ($spec in @(14, 190, 0, 80)) {
        $cd = [System.Windows.Controls.ColumnDefinition]::new()
        $cd.Width = if ($spec -eq 0) {
            [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        } else {
            [System.Windows.GridLength]::new($spec)
        }
        $Grid.ColumnDefinitions.Add($cd)
    }

    $Dot = [System.Windows.Shapes.Ellipse]::new()
    $Dot.Width = 8; $Dot.Height = 8; $Dot.VerticalAlignment = 'Center'
    $Dot.Fill = Brush '#2A2A2A'
    [System.Windows.Controls.Grid]::SetColumn($Dot, 0)
    $Grid.Children.Add($Dot) | Out-Null

    $NameTB = [System.Windows.Controls.TextBlock]::new()
    $NameTB.Text = "  $Label"
    $NameTB.FontSize = 11; $NameTB.VerticalAlignment = 'Center'
    $NameTB.Foreground = Brush '#C8860A'
    [System.Windows.Controls.Grid]::SetColumn($NameTB, 1)
    $Grid.Children.Add($NameTB) | Out-Null

    $StateTB = [System.Windows.Controls.TextBlock]::new()
    $StateTB.Text = '—'; $StateTB.FontSize = 11; $StateTB.VerticalAlignment = 'Center'
    $StateTB.Foreground = Brush '#3A3A3A'
    [System.Windows.Controls.Grid]::SetColumn($StateTB, 2)
    $Grid.Children.Add($StateTB) | Out-Null

    $TimerTB = [System.Windows.Controls.TextBlock]::new()
    $TimerTB.Text = ''; $TimerTB.FontSize = 11; $TimerTB.VerticalAlignment = 'Center'
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
    $t = $SharedState['EliteStartTime']
    if ($t) {
        $elapsed = [DateTime]::Now - $t
        $script:StatusRows['Elite'].TimerTB.Text = '▸ {0:hh\:mm\:ss}' -f $elapsed
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
            $p.Inlines.Add($r); $d.Blocks.Add($p); $b.ScrollToEnd()
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
            UiStatus $App.Name 'Not found' '#444444'
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
    UiStatus 'Steam' 'Online' '#FFB700'
    UiLog 'Steam online.' -Lvl Success

    # ── Launch Elite ───────────────────────────────────────
    UiStatus 'Elite' 'Waiting…' '#C8860A'
    UiLog 'Opening Elite: Dangerous via Steam...'
    Start-Process "steam://run/$EliteAppId"
    UiLog 'Waiting for EliteDangerous64.exe...  (click PLAY in the Frontier Launcher)'

    $Timeout = (Get-Date).AddSeconds(60)
    $EP = $null
    do {
        Start-Sleep -Seconds 2
        $EP = Get-Process -Name EliteDangerous64 -EA SilentlyContinue |
              Select-Object -First 1
    } until ($EP -or ((Get-Date) -gt $Timeout))

    if (-not ($null -ne $EP)) {
        UiStatus 'Elite' 'Failed' '#CC4444'
        Fail 'Elite Dangerous did not start within 60 seconds.'
        return
    }

    UiStatus 'Elite' 'Running' '#FFB700'
    UiLog "Elite: Dangerous online. (PID: $($EP.Id))" -Lvl Success

    $SharedState['EliteStartTime'] = [DateTime]::Now
    $Dispatcher.Invoke([Action]{ $ElapsedTimer.Start() })

    # ── Launch tools ───────────────────────────────────────
    $Launched = @()
    foreach ($App in $Apps) {
        if (-not $App.Path) { continue }
        if (Get-Process -Name $App.Process -EA SilentlyContinue) {
            UiLog "$($App.Name) already running — skipping." -Lvl Dim
            UiStatus $App.Name 'Already running' '#555555'
            continue
        }
        try {
            UiLog "Launching $($App.Name)..."
            $P = Start-Process $App.Path -PassThru -EA Stop
            $Launched += $App.Process
            UiStatus $App.Name 'Launched' '#FFB700'
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
    $Dispatcher.Invoke([Action]{ $ElapsedTimer.Stop() })
    $SharedState['EliteStartTime'] = $null
    UiStatus 'Elite' 'Offline' '#555555' -ClearTimer $true
    UiLog 'Elite: Dangerous offline.'
    UiLog 'Closing third-party tools...'

    foreach ($PN in $Launched) {
        $Running = Get-Process -Name $PN -EA SilentlyContinue
        if ($Running) {
            UiLog "Stopping $PN..."
            $Running | Stop-Process -Force
            UiStatus $PN 'Closed' '#555555'
        }
    }

    UiLog 'Farewell, CMDR. o7' -Lvl Success
    Add-Content -Path $LogFile `
        -Value "=== Session ended $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" `
        -EA SilentlyContinue
    $Dispatcher.Invoke([Action]{
        $LaunchBtn.IsEnabled = $true
        $LaunchBtn.Content   = '[ LAUNCH ]'
    })
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

    $RS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($ISS)
    $RS.ApartmentState = 'STA'
    $RS.Open()
    $PS = [System.Management.Automation.PowerShell]::Create()
    $PS.Runspace = $RS
    $PS.AddScript($LaunchScript) | Out-Null
    $PS.BeginInvoke() | Out-Null
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
        <DataGridTextColumn    Header="Name"    Binding="{Binding Name}"    Width="130" IsReadOnly="True"/>
        <DataGridTextColumn    Header="Process" Binding="{Binding Process}" Width="180"/>
        <DataGridTextColumn    Header="Path"    Binding="{Binding Path}"    Width="*"/>
      </DataGrid.Columns>
    </DataGrid>

    <!-- Buttons -->
    <StackPanel Grid.Row="2" Orientation="Horizontal"
                HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button Name="SaveBtn" Content="Save" Width="80" Height="30" Margin="0,0,8,0"
              Background="#1A1100" Foreground="#FFB700"
              BorderBrush="#C8860A" BorderThickness="1" Cursor="Hand"/>
      <Button Name="CancelBtn" Content="Cancel" Width="80" Height="30"
              Background="#0D0D0D" Foreground="#555555"
              BorderBrush="#2A2A2A" BorderThickness="1" Cursor="Hand"/>
    </StackPanel>
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
    $SaveBtn  = $Dlg.FindName('SaveBtn')
    $CancelBtn= $Dlg.FindName('CancelBtn')

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
                Apps               = $NewApps
            } | ConvertTo-Json -Depth 5 |
                Set-Content $script:SettingsFile -Encoding UTF8
            Load-Settings
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
$CmdrLabel.Text = Format-CmdrLine $script:CmdrName
Rebuild-StatusRows
Write-UILog 'Elite: Dangerous Launch Suite ready.' -Level Success
Write-UILog 'Click LAUNCH to begin.' -Level Dim
$Window.ShowDialog() | Out-Null
