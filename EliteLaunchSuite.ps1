# ==========================================================
# |||||||| Elite: Dangerous Launch Suite          ||||||||||
# |||||||| by CMDR Coyote Bongwater (and Claude)  ||||||||||
# ==========================================================

$script:AppVersion = '0.9.0'

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
            Path    = ''
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
            Process = 'EDHM-UI-V3'
            Path    = '%LOCALAPPDATA%\EDHM-UI-V3\EDHM-UI-V3.exe'
            Enabled = $true
        },
        [ordered]@{
            Name    = 'opentrack'
            Process = 'opentrack'
            Path    = '%ProgramFiles(x86)%\opentrack\opentrack.exe'
            Enabled = $true
        }
    )
    $Defaults = [ordered]@{
        CmdrName           = "Epstein Didn't Kill Himself"
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

    $script:CmdrName          = if ($J.CmdrName)                    { $J.CmdrName }               else { $Defaults.CmdrName }
    $script:EliteAppId        = if ($null -ne $J.EliteAppId)        { [int]$J.EliteAppId }        else { $Defaults.EliteAppId }
    $script:AutoStart         = if ($null -ne $J.AutoStart)         { [bool]$J.AutoStart }        else { $false }
    $script:ShowInactiveCards = if ($null -ne $J.ShowInactiveCards) { [bool]$J.ShowInactiveCards } else { $true }
    $script:AutoClose         = if ($null -ne $J.AutoClose)         { [bool]$J.AutoClose }        else { $false }

    # AllApps: every entry with a Name + Process (used for status card display regardless of Enabled)
    $script:AllApps = @()
    foreach ($E in $J.Apps) {
        if (-not $E.Name -or -not $E.Process) { continue }
        $script:AllApps += @{ Name = $E.Name; Process = $E.Process; Enabled = [bool]$E.Enabled }
    }

    # Apps: enabled-only subset used for launching
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
        ForEach-Object { $_.ToCharArray() -join '' }) -join ' '
    "[CMDR] $Spaced"
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
            -Uri 'https://api.github.com/repos/coyotebw/EDLS-Elite-Dangerous-Launch-Suite/releases/latest' `
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
        $ErrMsg = $_.ToString()
        if ($ErrMsg -match '404|Not Found') {
            UiLog 'Version check: no releases published yet.' -Lvl Dim
        } elseif ($_ -is [System.Net.WebException] -or $ErrMsg -match 'connect|network|timeout|resolve|unable to') {
            UiLog 'Version check skipped (network unavailable).' -Lvl Dim
        } else {
            UiLog "Version check failed: $ErrMsg" -Lvl Dim
        }
    }
}

# ── Main window XAML ──────────────────────────────────────
[xml]$Xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="EDLS | Elite: Dangerous Launch Suite"
    Background="#080808"
    FontFamily="Agency FB"
    Width="1295" Height="1070" MinWidth="648" MinHeight="535"
    ResizeMode="CanResizeWithGrip"
    WindowStartupLocation="CenterScreen">

  <Window.Resources>
    <!-- Diagonal/parallelogram button style.
         LayoutTransform skews the whole button; ContentPresenter counter-skews
         so text stays upright.  Height=52 * tan(12deg) ~ 11 px, so buttons use
         Margin="0,0,-11,0" to make adjacent parallelogram edges share one line. -->
    <Style x:Key="DiagBtn" TargetType="Button">
      <Setter Property="LayoutTransform">
        <Setter.Value><SkewTransform AngleX="12"/></Setter.Value>
      </Setter>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="Bg"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center">
                <ContentPresenter.LayoutTransform>
                  <SkewTransform AngleX="-12"/>
                </ContentPresenter.LayoutTransform>
              </ContentPresenter>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bg" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Viewbox Stretch="Uniform">
  <Grid Width="1253" Height="1034" Margin="10,8,10,8">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header card -->
    <Border Grid.Row="0" Name="TitleBarCard" Background="Transparent" BorderBrush="#1C1C22" BorderThickness="1"
            Margin="0,0,0,3" Padding="24,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
        <Image Name="OutpostImage" Width="88" Height="88" Margin="0,0,16,0" VerticalAlignment="Center"/>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Name="TitleLabel"
                     Text=" ELITE: DANGEROUS · LAUNCH SUITE "
                     Foreground="#FFB700" FontSize="38"
                     VerticalAlignment="Center" FontWeight="Bold"/>
          <TextBlock Name="CmdrLabel"
                     Foreground="#C8860A" FontSize="15"
                     HorizontalAlignment="Center"
                     Margin="0,1,0,0"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <!-- Status card -->
    <Border Grid.Row="1" Background="Transparent" BorderBrush="#1C1C22" BorderThickness="1"
            Margin="0,0,0,3">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#CC111114" BorderBrush="#1C1C22" BorderThickness="0,0,0,1" Padding="18,9">
          <TextBlock Name="StatusLabel" Text="S T A T U S" Foreground="#8888A0" FontSize="11"/>
        </Border>
        <Border Grid.Row="1" Padding="14,8">
          <WrapPanel Name="StatusPanel" Orientation="Horizontal"/>
        </Border>
      </Grid>
    </Border>

    <!-- Log card -->
    <Border Grid.Row="2" Background="Transparent" BorderBrush="#1C1C22" BorderThickness="1"
            Margin="0,0,0,3">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#CC111114" BorderBrush="#1C1C22" BorderThickness="0,0,0,1" Padding="18,9">
          <TextBlock Name="TerminalLabel" Text="T E R M I N A L" Foreground="#8888A0" FontSize="11"/>
        </Border>
        <RichTextBox Name="LogBox" Grid.Row="1"
                     IsReadOnly="True"
                     Background="Transparent"
                     BorderThickness="0"
                     Padding="18,10"
                     FontSize="16"
                     VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Disabled">
          <FlowDocument PageWidth="5000"/>
        </RichTextBox>
      </Grid>
    </Border>

    <!-- Button bar card -->
    <Border Grid.Row="3" Background="#CC111114" BorderBrush="#1C1C22" BorderThickness="1"
            Padding="18,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <!-- Left: author credit + version + issue link -->
        <StackPanel Grid.Column="0" VerticalAlignment="Center" TextElement.FontFamily="Consolas">
          <TextBlock Foreground="#484850" FontSize="11" FontStyle="Italic"
                     Text="by CMDR Coyote Bongwater and (mostly) Claude"/>
          <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
            <TextBlock Name="VersionLabel" Foreground="#3A3A45" FontSize="12"/>
            <TextBlock Foreground="#3A3A45" FontSize="12" Margin="10,0,0,0">
              <Hyperlink Name="ReportIssueLink" Foreground="#3A3A45">report issue</Hyperlink>
            </TextBlock>
          </StackPanel>
        </StackPanel>
        <!-- Right: diagonal buttons — Margin 0,0,-11,0 closes the parallelogram gap -->
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button Name="ShutdownBtn"
                  Content="SHUTDOWN" Style="{StaticResource DiagBtn}"
                  Width="190" Height="52" Margin="0,0,-11,0"
                  Background="#CC111114" Foreground="#666670"
                  BorderBrush="#2A2A35" BorderThickness="1"
                  FontSize="17" Cursor="Hand"/>
          <Button Name="AutoStartBtn"
                  Content="AUTO START" Style="{StaticResource DiagBtn}"
                  Width="190" Height="52" Margin="0,0,-11,0"
                  Background="#CC111114" Foreground="#666670"
                  BorderBrush="#2A2A35" BorderThickness="1"
                  FontSize="17" Cursor="Hand"/>
          <Button Name="SettingsBtn"
                  Content="SETTINGS" Style="{StaticResource DiagBtn}"
                  Width="180" Height="52" Margin="0,0,-11,0"
                  Background="#CC111114" Foreground="#666670"
                  BorderBrush="#2A2A35" BorderThickness="1"
                  FontSize="17" Cursor="Hand"/>
          <Button Name="LaunchBtn"
                  Content="LAUNCH" Style="{StaticResource DiagBtn}"
                  Width="220" Height="52"
                  Background="#CC140F00" Foreground="#FFB700"
                  BorderBrush="#C8860A" BorderThickness="2"
                  FontSize="24" FontWeight="Bold" Cursor="Hand"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
  </Viewbox>
</Window>
'@

# ── Load window ───────────────────────────────────────────
$Window          = [System.Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($Xaml))
$CmdrLabel       = $Window.FindName('CmdrLabel')
$VersionLabel    = $Window.FindName('VersionLabel')
$ReportIssueLink = $Window.FindName('ReportIssueLink')
$StatusPanel     = $Window.FindName('StatusPanel')
$LogBox          = $Window.FindName('LogBox')
$LaunchBtn       = $Window.FindName('LaunchBtn')
$SettingsBtn     = $Window.FindName('SettingsBtn')
$AutoStartBtn    = $Window.FindName('AutoStartBtn')
$ShutdownBtn     = $Window.FindName('ShutdownBtn')
$TitleBarCard    = $Window.FindName('TitleBarCard')
$LogDocument     = $LogBox.Document
$Dispatcher      = $Window.Dispatcher

# ── Aspect-ratio enforcement (WM_SIZING hook) ────────────
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32Sizing {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    public const int WM_SIZING    = 0x0214;
    public const int WMSZ_TOP     = 3;
    public const int WMSZ_TOPLEFT = 4;
    public const int WMSZ_TOPRIGHT= 5;

    public static void Enforce(IntPtr lParam, int edge, double ratio) {
        RECT r = (RECT)Marshal.PtrToStructure(lParam, typeof(RECT));
        int w = r.Right  - r.Left;
        int h = r.Bottom - r.Top;
        switch (edge) {
            case WMSZ_TOP:
                r.Right = r.Left + (int)Math.Round(h * ratio); break;
            case WMSZ_TOPLEFT:
            case WMSZ_TOPRIGHT:
                r.Top = r.Bottom - (int)Math.Round(w / ratio); break;
            default:
                r.Bottom = r.Top + (int)Math.Round(w / ratio); break;
        }
        Marshal.StructureToPtr(r, lParam, false);
    }
}
"@

$script:WinAspect = 1295.0 / 1070.0

$Window.Add_SourceInitialized({
    $src = [System.Windows.Interop.HwndSource]::FromHwnd(
        [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle)
    $src.AddHook([System.Windows.Interop.HwndSourceHook]{
        param($hwnd, $msg, $wParam, $lParam, [ref]$handled)
        if ($msg -eq [Win32Sizing]::WM_SIZING) {
            [Win32Sizing]::Enforce($lParam, $wParam.ToInt32(), $script:WinAspect)
            $handled = $true
        }
        return [IntPtr]::Zero
    })
})

$ReportIssueLink.NavigateUri = [System.Uri]::new('https://github.com/coyotebw/EDLaunchSuite/issues')
$ReportIssueLink.Add_RequestNavigate({
    param($s, $e); Start-Process $e.Uri.AbsoluteUri; $e.Handled = $true
})

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

# ── Resolve app directory (reliable in both .ps1 and ps2exe .exe) ────────────
$_appDir = if ($PSScriptRoot) { $PSScriptRoot } else {
    [System.IO.Path]::GetDirectoryName(
        [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

# ── Asset loader helper ───────────────────────────────────
function Load-ImageBrush([string]$RelPath, [string]$Stretch) {
    $full = Join-Path $_appDir $RelPath
    if (-not (Test-Path $full)) {
        Add-Content -Path $script:LogFile -Value "[assets] not found: $full" -EA SilentlyContinue
        return $null
    }
    try {
        $uri   = [System.Uri]::new($full, [System.UriKind]::Absolute)
        $bmp   = [System.Windows.Media.Imaging.BitmapImage]::new($uri)
        $brush = [System.Windows.Media.ImageBrush]::new($bmp)
        $brush.Stretch = [System.Windows.Media.Stretch]$Stretch
        return $brush
    } catch {
        Add-Content -Path $script:LogFile -Value "[assets] failed to load ${RelPath}: $_" -EA SilentlyContinue
        return $null
    }
}

# ── Window background ─────────────────────────────────────
$_b = Load-ImageBrush 'assets\window-bg.png' 'UniformToFill'
if ($_b) { $Window.Background = $_b }

# ── Title bar background ───────────────────────────────────
$_b = Load-ImageBrush 'assets\title-bar.png' 'Fill'
if ($_b) { $TitleBarCard.Background = $_b }

# ── Outpost icon in title bar ──────────────────────────────
$OutpostImage    = $Window.FindName('OutpostImage')
$_outpostPath = Join-Path $_appDir 'assets\outpost.png'
if (Test-Path $_outpostPath) {
    $OutpostImage.Source = [System.Windows.Media.Imaging.BitmapImage]::new(
        [System.Uri]::new($_outpostPath, [System.UriKind]::Absolute)
    )
}

# ── Window icon ───────────────────────────────────────────
$_iconFull = Join-Path $_appDir 'assets\icon.ico'
if (Test-Path $_iconFull) {
    try {
        $Window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new(
            [System.Uri]::new($_iconFull, [System.UriKind]::Absolute))
    } catch {
        Add-Content -Path $script:LogFile -Value "[assets] failed to load icon: $_" -EA SilentlyContinue
    }
}

# ── Button hover effects ──────────────────────────────────
$LaunchBtn.Add_MouseEnter({
    try {
        if ($LaunchBtn.IsEnabled) {
            $LaunchBtn.Background  = Brush '#CC221A00'
            $LaunchBtn.BorderBrush = Brush '#FFB700'
        }
    } catch {}
})
$LaunchBtn.Add_MouseLeave({
    try {
        if ($LaunchBtn.IsEnabled) {
            $LaunchBtn.Background  = Brush '#CC140F00'
            $LaunchBtn.BorderBrush = Brush '#C8860A'
        }
    } catch {}
})
$ShutdownBtn.Add_MouseEnter({
    try {
        $ShutdownBtn.Foreground  = Brush '#DD3333'
        $ShutdownBtn.BorderBrush = Brush '#551111'
    } catch {}
})
$ShutdownBtn.Add_MouseLeave({
    try {
        $ShutdownBtn.Foreground  = Brush '#666670'
        $ShutdownBtn.BorderBrush = Brush '#2A2A35'
    } catch {}
})

# ── Status row management ─────────────────────────────────
$script:StatusRows = @{}

function New-StatusRow { param([string]$Key, [string]$Label, [bool]$IsInactive = $false)
    $isElite = ($Key -eq 'Elite')

    # Outer card — double-wide for Elite so the timer + PID have room on the right
    $Card = [System.Windows.Controls.Border]::new()
    $Card.Width           = if ($isElite) { 532 } else { 264 }
    $Card.Height          = 88
    $Card.Background      = Brush '#CC111114'
    $Card.BorderBrush     = Brush '#1C1C22'
    $Card.BorderThickness = [System.Windows.Thickness]::new(1)
    $Card.Margin          = [System.Windows.Thickness]::new(0,0,4,4)
    $Card.Padding         = [System.Windows.Thickness]::new(14,10,14,10)

    # Inner grid — 3 rows for all cards; Elite adds a right column for timer+PID
    $InnerGrid = [System.Windows.Controls.Grid]::new()
    foreach ($h in @('Auto', 'Star', 'Auto')) {
        $rd = [System.Windows.Controls.RowDefinition]::new()
        $rd.Height = if ($h -eq 'Star') {
            [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        } else { [System.Windows.GridLength]::Auto }
        $InnerGrid.RowDefinitions.Add($rd)
    }
    if ($isElite) {
        # Col 0 (*): label + status text  |  Col 1 (Auto): timer (top) + PID (bottom)
        $cd0 = [System.Windows.Controls.ColumnDefinition]::new()
        $cd0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $cd1 = [System.Windows.Controls.ColumnDefinition]::new()
        $cd1.Width = [System.Windows.GridLength]::Auto
        $InnerGrid.ColumnDefinitions.Add($cd0)
        $InnerGrid.ColumnDefinitions.Add($cd1)
    }

    # Row 0, Col 0: small dot indicator + app name label
    $LabelRow = [System.Windows.Controls.StackPanel]::new()
    $LabelRow.Orientation = 'Horizontal'
    [System.Windows.Controls.Grid]::SetRow($LabelRow, 0)
    [System.Windows.Controls.Grid]::SetColumn($LabelRow, 0)

    $Dot = [System.Windows.Shapes.Rectangle]::new()
    $Dot.Width = 8; $Dot.Height = 8
    $Dot.VerticalAlignment = 'Center'
    $Dot.Margin = [System.Windows.Thickness]::new(0,0,6,0)
    $Dot.Fill   = Brush '#1E1E28'
    $LabelRow.Children.Add($Dot) | Out-Null

    $LabelTB = [System.Windows.Controls.TextBlock]::new()
    $LabelTB.Text       = $Label.ToUpper()
    $LabelTB.FontSize   = 10
    $LabelTB.Foreground = Brush '#8888A0'
    $LabelTB.VerticalAlignment = 'Center'
    $LabelRow.Children.Add($LabelTB) | Out-Null

    $InnerGrid.Children.Add($LabelRow) | Out-Null

    # Row 0 right side: INACTIVE badge for disabled apps
    if ($IsInactive) {
        $InactiveTB = [System.Windows.Controls.TextBlock]::new()
        $InactiveTB.Text              = 'INACTIVE'
        $InactiveTB.FontSize          = 8
        $InactiveTB.Foreground        = Brush '#484850'
        $InactiveTB.VerticalAlignment = 'Center'
        $InactiveTB.HorizontalAlignment = 'Right'
        [System.Windows.Controls.Grid]::SetRow($InactiveTB, 0)
        # Elite has Col 1; non-Elite single-column cell is full-width so right-align works
        if ($isElite) { [System.Windows.Controls.Grid]::SetColumn($InactiveTB, 1) }
        $InnerGrid.Children.Add($InactiveTB) | Out-Null
    }

    # Row 1, Col 0: main status text
    $StateTB = [System.Windows.Controls.TextBlock]::new()
    $StateTB.Text       = '—'
    $StateTB.FontSize   = if ($isElite) { 28 } else { 20 }
    $StateTB.FontWeight = if ($isElite) { [System.Windows.FontWeights]::Bold } `
                                        else { [System.Windows.FontWeights]::Normal }
    $StateTB.Foreground        = Brush '#3A3A45'
    $StateTB.VerticalAlignment = 'Bottom'
    $StateTB.Margin            = [System.Windows.Thickness]::new(0,4,0,2)
    [System.Windows.Controls.Grid]::SetRow($StateTB, 1)
    [System.Windows.Controls.Grid]::SetColumn($StateTB, 0)
    if ($isElite) { [System.Windows.Controls.Grid]::SetRowSpan($StateTB, 2) }
    $InnerGrid.Children.Add($StateTB) | Out-Null

    # Timer TextBlock (Elite: Col 1 Row 1 top-right; non-Elite: not added to grid)
    $TimerTB = [System.Windows.Controls.TextBlock]::new()
    $TimerTB.Text       = ''
    $TimerTB.FontSize   = 11
    $TimerTB.Foreground = Brush '#484850'

    # PID TextBlock
    $PidTB = [System.Windows.Controls.TextBlock]::new()
    $PidTB.Text       = ''
    $PidTB.FontSize   = 10
    $PidTB.Foreground = Brush '#484850'

    if ($isElite) {
        # Timer: Col 1, Row 1 — sits atop the PID on the right side of the Elite card
        $TimerTB.HorizontalAlignment = 'Right'
        $TimerTB.VerticalAlignment   = 'Bottom'
        [System.Windows.Controls.Grid]::SetRow($TimerTB, 1)
        [System.Windows.Controls.Grid]::SetColumn($TimerTB, 1)
        $InnerGrid.Children.Add($TimerTB) | Out-Null

        # PID: Col 1, Row 2 — below timer
        $PidTB.HorizontalAlignment = 'Right'
        $PidTB.VerticalAlignment   = 'Top'
        [System.Windows.Controls.Grid]::SetRow($PidTB, 2)
        [System.Windows.Controls.Grid]::SetColumn($PidTB, 1)
        $InnerGrid.Children.Add($PidTB) | Out-Null
    } else {
        # PID: Row 1 — bottom-aligned with status text, right side
        $PidTB.HorizontalAlignment = 'Right'
        $PidTB.VerticalAlignment   = 'Bottom'
        [System.Windows.Controls.Grid]::SetRow($PidTB, 1)
        $InnerGrid.Children.Add($PidTB) | Out-Null
        # TimerTB kept in row map for UiStatus ClearTimer compat but not shown
    }

    $Card.Child = $InnerGrid
    $StatusPanel.Children.Add($Card) | Out-Null
    $script:StatusRows[$Key] = @{ Dot = $Dot; StateTB = $StateTB; TimerTB = $TimerTB; PidTB = $PidTB }
}

function Rebuild-StatusRows {
    $StatusPanel.Children.Clear()
    $script:StatusRows.Clear()
    New-StatusRow -Key 'Steam' -Label 'Steam'
    New-StatusRow -Key 'Elite' -Label 'Elite: Dangerous'
    $EnabledNames = @($script:Apps | ForEach-Object { $_.Name })
    $AppsToShow   = if ($script:ShowInactiveCards) { $script:AllApps } else { $script:Apps }
    foreach ($App in $AppsToShow) {
        New-StatusRow -Key $App.Name -Label $App.Name -IsInactive ($App.Name -notin $EnabledNames)
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
#   $Dispatcher, $LogFile, $EliteAppId,
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
                              [string]$Color = '#C8860A', [bool]$ClearTimer = $false,
                              [bool]$ClearPid = $false)
        $row = $StatusRows[$Key]; if (-not $row) { return }
        $c = $Color; $s = $State; $ct = $ClearTimer; $cp = $ClearPid
        $Dispatcher.Invoke([Action]{
            $row.Dot.Fill           = RsBrush $c
            $row.StateTB.Text       = $s
            $row.StateTB.Foreground = RsBrush $c
            if ($ct) { $row.TimerTB.Text = '' }
            if ($cp -and $row.PidTB) { $row.PidTB.Text = '' }
        })
    }

    function UiPid { param([string]$Key, [int]$ProcId)
        $row = $StatusRows[$Key]; if (-not $row -or -not $row.PidTB) { return }
        $p = $ProcId
        $Dispatcher.Invoke([Action]{ $row.PidTB.Text = "PID $p" })
    }

    function Fail { param($M)
        UiLog $M -Lvl Error
        Add-Content -Path $LogFile `
            -Value "=== Session ended $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" `
            -EA SilentlyContinue
        $Dispatcher.Invoke([Action]{
            $LaunchBtn.IsEnabled = $true
            $LaunchBtn.Content   = 'LAUNCH'
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
    $SteamProc = Get-Process -Name steam -EA SilentlyContinue | Select-Object -First 1
    if ($SteamProc) { UiPid 'Steam' $SteamProc.Id }

    # ── Launch Elite ───────────────────────────────────────
    UiStatus 'Elite' 'Waiting…' '#C8860A'
    UiLog 'Opening Elite: Dangerous via Steam...'
    Start-Process "steam://run/$EliteAppId"
    UiLog 'Waiting for EliteDangerous64.exe...'

    $EP = $null
    do {
        Start-Sleep -Seconds 2
        $EP = Get-Process -Name EliteDangerous64 -EA SilentlyContinue |
              Select-Object -First 1
    } until ($EP)

    UiStatus 'Elite' 'Running' '#FFB700'
    UiLog "Elite: Dangerous online. (PID: $($EP.Id))" -Lvl Success
    UiPid 'Elite' $EP.Id

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
                UiPid $App.Name $ExistingProc.Id
                continue
            }
            try {
                UiLog "Launching $($App.Name)..."
                UiStatus $App.Name 'Launching…' '#C8860A'
                $P = Start-Process $App.Path -PassThru -EA Stop
                $Launched += @{ Name = $App.Name; Process = $App.Process; PID = $P.Id }
                UiStatus $App.Name 'Online' '#44CC44'
                UiPid $App.Name $P.Id
                UiLog "$($App.Name) online. (PID: $($P.Id))" -Lvl Success
            } catch {
                UiLog "Failed to launch $($App.Name): $_" -Lvl Warning
                UiStatus $App.Name 'Failed' '#CC4444'
            }
        }
        UiLog 'All systems nominal.' -Lvl Success

        # ── Monitor ────────────────────────────────────────────
        UiLog 'Monitoring Elite: Dangerous...' -Lvl Dim
        $NotedOffline = @{}
        while (Get-Process -Id $EP.Id -EA SilentlyContinue) {
            Start-Sleep -Seconds 2
            foreach ($LA in $Launched) {
                if ($NotedOffline[$LA.Name]) { continue }
                $Still = $null
                if ($LA.PID) { $Still = Get-Process -Id $LA.PID -EA SilentlyContinue }
                if (-not $Still) { $Still = Get-Process -Name $LA.Process -EA SilentlyContinue }
                if (-not $Still) {
                    UiStatus $LA.Name 'Offline' '#484850' -ClearPid $true
                    $NotedOffline[$LA.Name] = $true
                }
            }
        }

        # ── Shutdown ───────────────────────────────────────────
        UiStatus 'Elite' 'Offline' '#484850' -ClearTimer $true -ClearPid $true
        UiLog 'Elite: Dangerous offline.'
        UiLog 'Closing third-party tools...'

        foreach ($LA in $Launched) {
            $Running = $null
            if ($LA.PID) { $Running = Get-Process -Id $LA.PID -EA SilentlyContinue }
            if (-not $Running) { $Running = Get-Process -Name $LA.Process -EA SilentlyContinue }
            if ($Running) {
                UiLog "Stopping $($LA.Name)..."
                $Running | Stop-Process -Force -EA SilentlyContinue
                UiStatus $LA.Name 'Closed' '#484850' -ClearPid $true
            }
        }

        UiLog 'Farewell, CMDR. o7' -Lvl Success
        Add-Content -Path $LogFile `
            -Value "=== Session ended $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" `
            -EA SilentlyContinue

        if ($AutoClose) {
            UiLog 'Closing launcher in 5 seconds...' -Lvl Dim
            Start-Sleep -Seconds 5
            $Dispatcher.Invoke([Action]{ $Window.Close() })
        }

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
                $LaunchBtn.Content   = 'LAUNCH'
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
    $LaunchBtn.Content   = 'RUNNING'
    Write-UILog 'Launch sequence initiated.' -Level Success

    $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($Pair in @(
        @('Dispatcher',         $Dispatcher),
        @('LogFile',            $script:LogFile),
        @('EliteAppId',         $script:EliteAppId),
        @('Apps',               $script:Apps),
        @('StatusRows',         $script:StatusRows),
        @('LogDocument',        $LogDocument),
        @('LogBox',             $LogBox),
        @('LaunchBtn',          $LaunchBtn),
        @('ElapsedTimer',       $ElapsedTimer),
        @('SharedState',        $SharedState),
        @('AutoClose',          $script:AutoClose),
        @('Window',             $Window)
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

# ── Auto-start button toggle ──────────────────────────────
$AutoStartBtn.Add_Click({
    try {
        $script:AutoStart = -not $script:AutoStart
        if ($script:AutoStart) {
            $AutoStartBtn.Foreground  = Brush '#FFB700'
            $AutoStartBtn.Background  = Brush '#CC140F00'
            $AutoStartBtn.BorderBrush = Brush '#C8860A'
        } else {
            $AutoStartBtn.Foreground  = Brush '#666670'
            $AutoStartBtn.Background  = Brush '#CC111114'
            $AutoStartBtn.BorderBrush = Brush '#2A2A35'
        }
        Save-AutoStart $script:AutoStart
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
                    $row.Dot.Fill           = Brush '#484850'
                    $row.StateTB.Text       = 'Closed'
                    $row.StateTB.Foreground = Brush '#484850'
                    if ($row.PidTB) { $row.PidTB.Text = '' }
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
    Background="#080808" FontFamily="Consolas"
    Width="640" Height="520"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterOwner">

  <Border Background="#111114" BorderBrush="#1C1C22" BorderThickness="1"
          CornerRadius="6" Margin="12">
    <Grid Margin="16">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Section label -->
      <TextBlock Grid.Row="0" Text="S E T T I N G S" Foreground="#484850" FontSize="11"
                 Margin="2,0,0,14"/>

      <!-- Scalar settings -->
      <Grid Grid.Row="1" Margin="0,0,0,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="160"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="CMDR NAME"
                   Foreground="#666670" FontSize="11" VerticalAlignment="Center" Margin="0,4"/>
        <TextBox Grid.Row="0" Grid.Column="1" Name="CmdrBox"
                 FontSize="11" Background="#0C0C0F" Foreground="#FFB700"
                 BorderBrush="#252530" CaretBrush="#FFB700" Padding="6,4" Margin="0,4"/>

        <CheckBox Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Name="ChkShowInactive"
                  Content="Show status cards for inactive programs"
                  Foreground="#C8860A" FontSize="11" Margin="0,8,0,2"/>

        <CheckBox Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2" Name="ChkAutoClose"
                  Content="Close launcher automatically after shutdown sequence (5s delay)"
                  Foreground="#C8860A" FontSize="11" Margin="0,2,0,2"/>

      </Grid>

      <!-- Apps grid -->
      <DataGrid Grid.Row="2" Name="AppsGrid"
                Background="#0C0C0F" Foreground="#C8860A" FontSize="11"
                BorderBrush="#252530" BorderThickness="1"
                GridLinesVisibility="None" HeadersVisibility="Column"
                AutoGenerateColumns="False"
                CanUserAddRows="False" CanUserDeleteRows="False"
                RowBackground="#0C0C0F" AlternatingRowBackground="#111114"
                SelectionMode="Single">
        <DataGrid.ColumnHeaderStyle>
          <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#111114"/>
            <Setter Property="Foreground" Value="#666670"/>
            <Setter Property="Padding"    Value="6,4"/>
            <Setter Property="FontSize"   Value="10"/>
          </Style>
        </DataGrid.ColumnHeaderStyle>
        <DataGrid.Columns>
          <DataGridCheckBoxColumn Header="ON"      Binding="{Binding Enabled}" Width="36"/>
          <DataGridTextColumn    Header="NAME"    Binding="{Binding Name}"    Width="130"/>
          <DataGridTextColumn    Header="PROCESS" Binding="{Binding Process}" Width="180"/>
          <DataGridTextColumn    Header="PATH"    Binding="{Binding Path}"    Width="*"/>
        </DataGrid.Columns>
      </DataGrid>

      <!-- Buttons -->
      <Grid Grid.Row="3" Margin="0,12,0,0">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
          <Button Name="AddAppBtn" Content="+ ADD" Width="72" Height="30" Margin="0,0,6,0"
                  Background="#111114" Foreground="#C8860A"
                  BorderBrush="#252530" BorderThickness="1" Cursor="Hand"/>
          <Button Name="RemoveAppBtn" Content="- REMOVE" Width="84" Height="30"
                  Background="#111114" Foreground="#666670"
                  BorderBrush="#252530" BorderThickness="1" Cursor="Hand"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button Name="SaveBtn" Content="SAVE" Width="80" Height="30" Margin="0,0,8,0"
                  Background="#140F00" Foreground="#FFB700"
                  BorderBrush="#C8860A" BorderThickness="1" Cursor="Hand"/>
          <Button Name="CancelBtn" Content="CANCEL" Width="80" Height="30"
                  Background="#111114" Foreground="#666670"
                  BorderBrush="#252530" BorderThickness="1" Cursor="Hand"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

    $Dlg      = [System.Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($SX))
    $Dlg.Owner= $Window

    $CmdrBox         = $Dlg.FindName('CmdrBox')
    $ChkShowInactive = $Dlg.FindName('ChkShowInactive')
    $ChkAutoClose    = $Dlg.FindName('ChkAutoClose')
    $AppsGrid        = $Dlg.FindName('AppsGrid')
    $AddAppBtn    = $Dlg.FindName('AddAppBtn')
    $RemoveAppBtn = $Dlg.FindName('RemoveAppBtn')
    $SaveBtn      = $Dlg.FindName('SaveBtn')
    $CancelBtn    = $Dlg.FindName('CancelBtn')

    $CmdrBox.Text                = $script:CmdrName
    $ChkShowInactive.IsChecked   = $script:ShowInactiveCards
    $ChkAutoClose.IsChecked      = $script:AutoClose

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
                CmdrName          = $CmdrBox.Text
                EliteAppId        = $script:EliteAppId
                AutoStart         = $script:AutoStart
                ShowInactiveCards = [bool]$ChkShowInactive.IsChecked
                AutoClose         = [bool]$ChkAutoClose.IsChecked
                Apps              = $NewApps
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

    # Highlight the Settings button while the dialog is open
    $SettingsBtn.Foreground  = Brush '#FFB700'
    $SettingsBtn.Background  = Brush '#CC140F00'
    $SettingsBtn.BorderBrush = Brush '#C8860A'
    $Dlg.Add_Closed({
        $SettingsBtn.Foreground  = Brush '#666670'
        $SettingsBtn.Background  = Brush '#CC111114'
        $SettingsBtn.BorderBrush = Brush '#2A2A35'
    })

    $Dlg.ShowDialog() | Out-Null
})

# ── Initial load & show ───────────────────────────────────
Load-Settings
$CmdrLabel.Text    = Format-CmdrLine $script:CmdrName
$VersionLabel.Text = "v$($script:AppVersion)"
Rebuild-StatusRows

# Restore auto-start button state from settings
if ($script:AutoStart) {
    $AutoStartBtn.Foreground  = Brush '#FFB700'
    $AutoStartBtn.Background  = Brush '#CC140F00'
    $AutoStartBtn.BorderBrush = Brush '#C8860A'
}

# Auto-trigger launch once window is fully rendered
$Window.Add_Loaded({
    if ($script:AutoStart) {
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
