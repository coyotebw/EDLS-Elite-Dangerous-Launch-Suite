# EDLS - Elite: Dangerous Launch Suite

A launcher utility for **Elite: Dangerous** (Steam/Windows only for now). Starts the game and all your companion tools in one click and automatically shuts them down when you're done. Originally just a 20-line powershell script until I decided it was an excuse to try out claude code. Claude did a pretty solid job, and only broke it several times (meaning his track record is better than mine)

<img width="959" height="799" alt="edls090" src="https://github.com/user-attachments/assets/2bf751f2-5f21-4a66-9d8c-071751328487" />

---

## Features

- One-click launch of Elite: Dangerous via Steam plus up to N companion apps; bypassing Frontier launcher with [Min-Ed-Launcher](https://github.com/rfvgyhn/min-ed-launcher) (see below)
- Real-time status indicators showing which apps are running
- Automatically closes companion apps when Elite: Dangerous exits
- Manual shutdown button to kill companion apps at any time
- Auto-start mode — launches everything when EDLaunchSuite itself opens (off by default)
- Configurable- can add, remove, enable/disable apps and adjust options
- Settings and logs persist in `%LOCALAPPDATA%\EDLaunchSuite\`

---

<img width="961" height="798" alt="edls0902" src="https://github.com/user-attachments/assets/62c61648-9933-4a9a-a593-bad697ad84eb" />


## Requirements

| Requirement | Details |
|---|---|
| OS | Windows (64-bit) |
| PowerShell | 5.1 or later |
| .NET Framework | 3.0+ (WPF) |
| Steam | Must be installed; Elite: Dangerous owned and installed |
| [Min-Ed-Launcher](https://github.com/rfvgyhn/min-ed-launcher) | Required to bypass the Frontier launcher (see below) |

---

## Min-Ed-Launcher Setup (Highly recommended)

The purpose of EDLaunchSuite is, by default, foiled by the Frontier launcher, which forces you to wait for their laggy unoptimized launcher and then click a few extra times so you have to see the store. We can circumvent this with [min-ed-launcher](https://github.com/rfvgyhn/min-ed-launcher) to launch
Elite: Dangerous directly, bypassing the Frontier launcher. Min-ed-launcher in turn requires another program called [legendary](https://github.com/derrod/legendary). Don't be daunted by the instructions! I've written a detailed guide below, and anyway if you don't set this part up it does rather undermine the point of the program. But hey, knock yourself out.

_**NOTE** that this does indeed work for Steam. You'll need to make an epic games account and link your steam to it, but that's all. No installing the epic launcher or anything else._
_Also this guide is a work in progress..._

1. First we will need to install legendary. Download the .exe from [latest release of legendary](https://github.com/derrod/legendary/releases) and put it somewhere that it won't be moved or deleted (i.e. not in downloads). I went with `C:\legendary\legendary.exe`

2. Now we will add legendary to our `%PATH%` Open the start menu and type `env`, then click on "Edit the system environment variables".
	1. In the window that pops up, click "environment variables" on the bottom right.
	2. Under 'System Variables' find the variable called 'Path' and click edit.
	3. Click 'New' at the top right. In the text box that comes up, paste the path to the directory where you saved legendary.exe - so in my case it would be `C:\legendary`
	4. Click 'ok' on all the dialogs to dismiss. Check to see that we did it right by opening command prompt and typing in `legendary`. It should look like the image below:

<img width="671" height="579" alt="cmd" src="https://github.com/user-attachments/assets/2803533c-0776-4be4-a783-febe21d962ab" />


3. Next we'll authenticate through legendary. Open a command prompt anywhere and enter `legendary auth`. You'll be prompted to log in through Epic. If you haven't already, first go to [the Epic Games website](https://www.epicgames.com/id/register/guided) and make an account, then connect your steam to it. Once that's done you can log into Epic. We're now done with legendary for the moment.

4. Download the zip from the [latest release of Min-Ed-Launcher](https://github.com/rfvgyhn/min-ed-launcher/releases). Open your Elite: Dangerous install directory (from Steam library, right click the game > properties > local files > browse local files). From the zip, place MinEdLauncher.exe in your Elite Dangerous install location so that it's in the same folder as EDLaunch.exe. (MinEdLauncher.Bootstrap is for Epic only and may be ignored.)

5. Now we'll change our launch options through Steam. In your library, right click the game, then click properties. In the *launch options* text box, enter cmd /c "MinEdLauncher.exe %command% /autorun /autoquit" and then close the window.

6. See [this very helpful and illustrated section of the min-ed-launcher wiki to configure legendary](https://github.com/rfvgyhn/min-ed-launcher/wiki/Using-Legendary-on-Windows)

7. Test that we've done it all correctly by opening the game thru your Steam library. If it boots straight to the main menu and doesn't give you a blurb about logging in to update the game, you're all set!



---

## Installation

### Download (recommended)

Download and run the latest `EDLS-setup.exe` from the [Releases page](https://github.com/coyotebw/EDLaunchSuite/releases). 

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
- install wizard by [Inno Setup](https://jrsoftware.org/isinfo.php) and assets from [EDassets](https://edassets.org/#/) & Claude
