# Bibliometrix Desktop

An easy way to run [Bibliometrix](https://github.com/massimoaria/bibliometrix) on Windows. Install Bibliometrix Desktop and run — no separate R or Rtools install for end users.

> **Platform note:** The current release targets **Windows x64**. macOS and Linux packaging are planned as separate artifacts later.

## Why this tool?

Bibliometrix is excellent for bibliometric analysis, but installing R, package dependencies, and sometimes Rtools is a hurdle for students. This project ships a portable R runtime with **pre-baked Windows binary packages**, plus a simple launcher.

## Installation (end users)

1. Download `BibliometrixSetup_x.y.z.exe` from [GitHub Releases](https://github.com/ecksteing/bibliometrix-desktop/releases).
2. Run the installer (no administrator rights required; installs under your user profile).
3. Start **Bibliometrix Desktop** from the Start Menu or desktop shortcut. Biblioshiny opens in your browser.

Logs (if something goes wrong) are written to `%LOCALAPPDATA%\Bibliometrix Desktop\launcher.log`.

### If Windows blocks the installer

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

No. The installer includes a portable R runtime and the Bibliometrix stack as Windows binaries. End users do not need Rtools because packages are not compiled on their machine.

#### Do I get the same features as Bibliometrix?

Yes. This wrapper launches official Bibliometrix / Biblioshiny.

#### Is the latest version of Bibliometrix included?

Each desktop release ships with a working Bibliometrix binary baked at build time (so the app works offline). When online, each launch checks **CRAN for a newer Windows binary** of `bibliometrix` and installs it into the user’s library if available. Updates never compile from source and never pull from GitHub, so end users do not need Rtools.

You only need a new desktop installer when the **wrapper / portable R** must change — not for every Bibliometrix CRAN release.

Desktop wrapper updates are separate: the launcher compares `version.txt` on this GitHub repo and notifies users to download a new installer from Releases.

#### Why did you create this tool?

I am a university lecturer. I encourage students to use Bibliometrix for literature analysis and wanted a one-click option. I have also used [Bibliometrix in peer-reviewed literature](https://link.springer.com/article/10.1007/s11301-024-00458-5).

## Building from source (maintainers)

### Prerequisites

- Windows x64
- [Python 3](https://www.python.org/) + `pip install -r requirements-build.txt`
- [Inno Setup 6](https://jrsoftware.org/isinfo.php)
- Portable R under `R-Portable\` (PortableApps-style layout). Use a **current R 4.4/4.5** Windows build so CRAN still publishes recent `bibliometrix` binaries. Older R (e.g. 4.2.0) can only bake older binary package versions.

### One-shot Windows build

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1
```

This will:

1. Bake `bibliometrix` (CRAN binaries) into `R-Portable` via `scripts/bake_packages.R`
2. Compile `run_bibliometrix.exe` with PyInstaller (`--onefile --noconsole`)
3. Compile `installer_config.iss` into `Output\BibliometrixSetup_<version>.exe`

Useful flags:

- `-SkipBake` — skip package baking (only if already baked)
- `-SkipInstaller` — build the launcher exe only

### Manual steps (equivalent)

```powershell
.\R-Portable\App\R-Portable\bin\Rscript.exe .\scripts\bake_packages.R
pip install -r requirements-build.txt
pyinstaller --onefile --noconsole --icon=app_icon.ico run_bibliometrix.py
# Copy dist\run_bibliometrix.exe to the repo root, then compile installer_config.iss in Inno Setup
```

Bump `version.txt` before each release. Publish **only** the setup exe on GitHub Releases (not the whole `R-Portable` tree).

## Licence

This project is distributed under the [GNU GPL v3](LICENSE). Bibliometrix and R retain their own licences; see upstream projects for details.

## Support

- Installer / desktop wrapper: [GitHub Issues](https://github.com/ecksteing/bibliometrix-desktop/issues)
- Bibliometrix itself: contact the Bibliometrix authors / upstream repo

## Acknowledgements

- [Bibliometrix](https://github.com/massimoaria/bibliometrix) by Massimo Aria and colleagues
- R Core Team and CRAN binary package maintainers
