# Bibliometrix Desktop

An easy way to run [Bibliometrix](https://github.com/massimoaria/bibliometrix) on Windows. ➡️ [Install Bibliometrix Desktop](https://github.com/ecksteing/bibliometrix-desktop/releases) and run. No separate R or Rtools needed.

> **Platform note:** The current release targets **Windows x64**. macOS and Linux packaging are planned for later.

## Why this tool?

Bibliometrix is excellent for bibliometric analysis, but installing R, package dependencies, and Rtools is a hurdle for students. This project ships an all-on-one Bibliometrix. Just install and run.

## Installation (end users)

1. Download the latest release from [GitHub Releases](https://github.com/ecksteing/bibliometrix-desktop/releases).
2. Run the installer (no administrator rights required; installs under your user profile).
3. Start **Bibliometrix Desktop** from the Start Menu or desktop shortcut. Bibliometrix/Biblioshiny opens in your browser.

Logs (if something goes wrong) are written to `%LOCALAPPDATA%\Bibliometrix Desktop\launcher.log`.

### If Windows blocks the installer 🤷‍

Windows SmartScreen (and some browsers or antivirus tools) may warn that the app is from an “unknown publisher.” That is common for new, unsigned open-source installers and does **not** mean the file is malware.

**SmartScreen (“Windows protected your PC”):**

1. Click **More info**.
2. Click **Run anyway**.

**Microsoft Edge / Chrome download warning:**

1. Open the browser’s downloads list.
2. Choose **Keep** / **Keep anyway** (Edge may ask you to confirm under the **…** menu).

Only install builds downloaded from the official [GitHub Releases](https://github.com/ecksteing/bibliometrix-desktop/releases) page for this project. If your organisation’s antivirus still blocks the file, ask IT to allowlist it, or open a [GitHub Issue](https://github.com/ecksteing/bibliometrix-desktop/issues).

## FAQ

#### Do I need to install R, Rtools, or Shiny?

No. The installer includes everything you need to run Bibliometrix/Biblioshiny. 

#### Do I get the same features as Bibliometrix?

Yes. This app launches official Bibliometrix / Biblioshiny.

#### The app is sometimes slow to load?

Yes. This is a powerful application. It may take a short while to open in your Browser,

#### Is the latest version of Bibliometrix included?

Each desktop release ships with a working Bibliometrix version (so the app works offline). When online, the app checks for a newer version of `bibliometrix` at most once per week and installs it into the user’s library if available. 

Desktop wrapper updates are separate: the launcher compares `version.txt` on this GitHub repo and notifies users to download a new installer from Releases.

#### Why did you create this tool?

I am a university lecturer. I encourage students to use Bibliometrix for literature analysis and wanted a one-click option. I have also used [Bibliometrix in peer-reviewed literature](https://link.springer.com/article/10.1007/s11301-024-00458-5).

## Licence

This project is distributed under the [GNU GPL v3](LICENSE). Bibliometrix and R retain their own licences; see upstream projects for details.

## Support

- Installer / desktop wrapper: [GitHub Issues](https://github.com/ecksteing/bibliometrix-desktop/issues)
- Bibliometrix itself: contact the Bibliometrix authors / upstream repo

## Acknowledgements

- [Bibliometrix](https://github.com/massimoaria/bibliometrix) by Massimo Aria and colleagues
- R Core Team and CRAN binary package maintainers

## Building from source (maintainers)
End users can ignore this section.
### Prerequisites

- Windows x64
- [Python 3](https://www.python.org/) + `pip install -r requirements-build.txt`
- [Inno Setup 6+](https://jrsoftware.org/isinfo.php) (per-user or machine-wide install)
- Portable R under `R-Portable\` (PortableApps-style layout). Use a **current R 4.4/4.5** Windows build so CRAN still publishes recent `bibliometrix` binaries. Older R (e.g. 4.2.0) can only bake older binary package versions.

### One-shot Windows build

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1
```

This will:

1. Bake `bibliometrix` (CRAN binaries) into `R-Portable` via `scripts/bake_packages.R`
2. Trim non-runtime docs/tests/Tcl trees via `scripts/trim_r_portable.ps1`
3. Compile the onedir launcher with PyInstaller (`--onedir --noconsole`) and stage `run_bibliometrix.exe` + `_internal\` at the repo root
4. Compile `installer_config.iss` into `Output\BibliometrixSetup_<version>.exe`

Useful flags:

- `-SkipBake` — skip package baking (only if already baked)
- `-SkipInstaller` — build the launcher exe only

### Manual steps (equivalent)

```powershell
.\R-Portable\bin\Rscript.exe .\scripts\bake_packages.R
powershell -ExecutionPolicy Bypass -File .\scripts\trim_r_portable.ps1
pip install -r requirements-build.txt
pyinstaller --onedir --noconsole --icon=app_icon.ico --name run_bibliometrix run_bibliometrix.py
# Copy dist\run_bibliometrix\run_bibliometrix.exe and dist\run_bibliometrix\_internal to the repo root,
# then compile installer_config.iss in Inno Setup
```

Bump `version.txt` before each release. Publish **only** the setup exe on GitHub Releases (not the whole `R-Portable` tree).