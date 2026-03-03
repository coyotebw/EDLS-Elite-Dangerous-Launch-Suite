# EDLaunchSuite

A Windows-based launcher utility for **Elite: Dangerous** that starts the game and all your companion tools in one click — and automatically shuts them down when you're done.

---

## Features

- One-click launch of Elite: Dangerous via Steam plus up to N companion apps
- Configurable delay between each app launch
- Real-time status indicators showing which apps are running
- Timestamped activity log (UI + file)
- Automatically closes companion apps when Elite: Dangerous exits
- Manual **[ SHUTDOWN ]** button to kill companion apps at any time
- Elapsed session timer
- Auto-start mode — launches everything when EDLaunchSuite itself opens
- Settings dialog to add, remove, enable/disable apps and adjust options
- Settings and logs persist in `%LOCALAPPDATA%\EDLaunchSuite\`

---

## Requirements

| Requirement | Details |
|---|---|
| OS | Windows (64-bit) |
| PowerShell | 5.1 or later |
| .NET Framework | 3.0+ (WPF) |
| Steam | Must be installed; Elite: Dangerous owned and installed |
| Elite: Dangerous Steam App ID | 359320 (default) |

---

## Installation

### Download (recommended)

Download the latest `EliteLaunchSuite.exe` from the [Releases page](https://github.com/coyotebw/EDLaunchSuite/releases). No installation needed — just run the `.exe` and a default `settings.json` is created automatically on first launch. Open **[ SETTINGS ]** to adjust companion app paths if any are installed in non-standard locations.

### Building from source (manual compilation)

1. **Clone** the repository, then open PowerShell in the repo root.

2. **Run the one-time setup script** to configure git and build the `.exe`:

   ```powershell
   .\Setup.ps1
   ```

   This script sets `git core.hooksPath` to `.githooks/` so the post-merge hook is active,
   then offers to run `Build.ps1` immediately to produce `EliteLaunchSuite.exe`.

3. **Run** `EliteLaunchSuite.exe`. On first launch, a default `settings.json` is created automatically.

4. Open **[ SETTINGS ]** to adjust companion app paths if any are installed in non-standard locations.

#### Rebuilding manually

To rebuild the `.exe` at any time:

```powershell
.\Build.ps1
```

This requires PowerShell 5.1+ and will automatically install the
[ps2exe](https://github.com/MScholtes/PS2EXE) module on first run if it isn't already present.

#### Automatic rebuild on pull

After running `Setup.ps1` once, every `git pull` — including pulls via **GitHub Desktop** —
automatically recompiles the `.exe` via the `.githooks/post-merge` hook. No manual build step needed.

> **Note**: The compiled `.exe` is excluded from version control via `.gitignore`.
> Each developer builds locally from source.

---

## Configuration

Settings are stored at:

```
%LOCALAPPDATA%\EDLaunchSuite\settings.json
```

| Field | Type | Description |
|---|---|---|
| `CmdrName` | string | Your commander name, shown in the title bar |
| `LaunchDelaySeconds` | integer | Seconds to wait between launching each companion app |
| `EliteAppId` | integer | Steam App ID for Elite: Dangerous (default: `359320`) |
| `AutoStart` | boolean | Automatically trigger the launch sequence on startup |
| `Apps` | array | List of companion app entries (see below) |

### App entry fields

```json
{
  "Name":    "EDMarketConnector",
  "Process": "EDMarketConnector",
  "Path":    "%ProgramFiles(x86)%\\EDMarketConnector\\EDMarketConnector.exe",
  "Enabled": true
}
```

- `Name` — display name shown in the UI
- `Process` — process name used to detect if the app is already running
- `Path` — full path to the executable; supports `%ENVIRONMENT_VARIABLE%` expansion
- `Enabled` — set to `false` to skip this app without removing it

---

## Default Companion Apps

| Name | Default Process | Default Path |
|---|---|---|
| EDMarketConnector | `EDMarketConnector` | `%ProgramFiles(x86)%\EDMarketConnector\EDMarketConnector.exe` |
| SrvSurvey | `SrvSurvey` | auto-detected via `%LOCALAPPDATA%\Apps\2.0` |
| OdysseyMaterials | `Elite Dangerous Odyssey Materials Helper` | `%LOCALAPPDATA%\Elite Dangerous Odyssey Materials Helper Launcher\...` |
| EDCoPilot | `EDCoPilot` | `C:\EDCoPilot\EDCoPilot.exe` |
| EDHM_UI | `EDHM-UI-V3` | `%LOCALAPPDATA%\EDHM-UI-V3\EDHM-UI-V3.exe` |
| opentrack | `opentrack` | `%ProgramFiles(x86)%\opentrack\opentrack.exe` |

If an app is installed elsewhere, update its path in the **[ SETTINGS ]** dialog.

---

## Usage

| Control | Action |
|---|---|
| **[ LAUNCH ]** | Verifies paths, starts Steam if needed, launches Elite: Dangerous, then launches enabled companion apps with the configured delay |
| **[ SHUTDOWN ]** | Force-closes all companion apps (does not close Elite: Dangerous) |
| **[ AUTO-START ]** | Toggle: when active (highlighted), the launch sequence fires automatically each time EDLaunchSuite opens |
| **[ SETTINGS ]** | Opens the configuration dialog |

---

## File Locations

| File | Path |
|---|---|
| Settings | `%LOCALAPPDATA%\EDLaunchSuite\settings.json` |
| Log | `%LOCALAPPDATA%\EDLaunchSuite\launcher.log` |

---

## Notes

- If a companion app is installed in a non-standard location, update its path in **[ SETTINGS ]**. A missing path will be logged and skipped — it will not cause a crash.
- The launcher is compiled to an `.exe` via **ps2exe** (see `Build.ps1`). No external GUI tool is required.
