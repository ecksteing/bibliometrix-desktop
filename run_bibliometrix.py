# run_bibliometrix.py
"""Launch Biblioshiny from the bundled portable R runtime."""

from __future__ import annotations

import os
import sys
import subprocess
import traceback
from datetime import datetime
from pathlib import Path
from urllib.error import URLError, HTTPError
from urllib.request import Request, urlopen

GITHUB_VERSION_URL = (
    "https://raw.githubusercontent.com/ecksteing/bibliometrix-desktop/main/version.txt"
)
RELEASES_URL = "https://github.com/ecksteing/bibliometrix-desktop/releases"
APP_NAME = "Bibliometrix Desktop"


def get_base_dir() -> Path:
    """Directory containing the launcher, whether running as .py or .exe."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def get_log_dir() -> Path:
    if sys.platform == "win32":
        root = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    elif sys.platform == "darwin":
        root = Path.home() / "Library" / "Logs"
    else:
        root = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    log_dir = root / APP_NAME
    log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir


def get_user_lib_dir() -> Path:
    if sys.platform == "win32":
        root = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    elif sys.platform == "darwin":
        root = Path.home() / "Library" / "Application Support"
    else:
        root = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    lib_dir = root / APP_NAME / "R_library"
    lib_dir.mkdir(parents=True, exist_ok=True)
    return lib_dir


def log_path() -> Path:
    return get_log_dir() / "launcher.log"


def log(message: str) -> None:
    line = f"{datetime.now().isoformat(timespec='seconds')} {message}"
    try:
        with log_path().open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def show_message(text: str, title: str = APP_NAME, error: bool = False) -> None:
    """Show a native dialog on Windows; fall back to stderr elsewhere."""
    log(("ERROR: " if error else "INFO: ") + text.replace("\n", " | "))
    if sys.platform == "win32":
        try:
            import ctypes

            flags = 0x10 if error else 0x40  # MB_ICONERROR / MB_ICONINFORMATION
            ctypes.windll.user32.MessageBoxW(0, text, title, flags)
            return
        except Exception:
            pass
    print(text, file=sys.stderr)


def get_local_version(base_dir: Path) -> str:
    version_file = base_dir / "version.txt"
    try:
        return version_file.read_text(encoding="utf-8").strip()
    except OSError:
        return "0.0.0"


def check_for_wrapper_updates(current_version: str) -> None:
    """Notify if a newer desktop wrapper version is published on GitHub."""
    try:
        request = Request(
            GITHUB_VERSION_URL,
            headers={"User-Agent": f"{APP_NAME}/{current_version}"},
        )
        with urlopen(request, timeout=3) as response:
            latest = response.read().decode("utf-8", errors="replace").strip()
        if latest and latest != current_version:
            show_message(
                f"A new version ({latest}) is available.\n"
                f"You are running {current_version}.\n\n"
                f"Download it from:\n{RELEASES_URL}",
                title=f"{APP_NAME} update available",
            )
    except (URLError, HTTPError, TimeoutError, ValueError, OSError):
        # Offline or private/unavailable repo — continue silently.
        log("Update check skipped (offline or unavailable).")


def find_rscript(base_dir: Path) -> Path | None:
    if sys.platform == "win32":
        candidates = [
            base_dir / "R-Portable" / "App" / "R-Portable" / "bin" / "Rscript.exe",
            base_dir / "R-Portable" / "App" / "R-Portable" / "bin" / "x64" / "Rscript.exe",
            base_dir / "R-Portable" / "bin" / "Rscript.exe",
            base_dir / "R-Portable" / "bin" / "x64" / "Rscript.exe",
        ]
    else:
        candidates = [
            base_dir / "R-Portable" / "bin" / "Rscript",
            base_dir / "R-Portable" / "bin" / "R",
        ]
    for path in candidates:
        if path.is_file():
            return path
    return None


def start_application(base_dir: Path) -> int:
    rscript_path = find_rscript(base_dir)
    r_script = base_dir / "launch_app.R"

    if rscript_path is None:
        show_message(
            "Bundled R was not found.\n\n"
            f"Expected under:\n{base_dir / 'R-Portable'}\n\n"
            f"Details were written to:\n{log_path()}",
            error=True,
        )
        return 1

    if not r_script.is_file():
        show_message(
            f"Missing launch script:\n{r_script}\n\n"
            f"Details were written to:\n{log_path()}",
            error=True,
        )
        return 1

    env = os.environ.copy()
    user_lib = str(get_user_lib_dir())
    env["R_LIBS_USER"] = user_lib
    # Prefer the writable user library for updates without needing admin rights.
    existing = env.get("R_LIBS", "")
    env["R_LIBS"] = user_lib if not existing else f"{user_lib}{os.pathsep}{existing}"

    creationflags = 0
    startupinfo = None
    if sys.platform == "win32":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    log(f"Starting: {rscript_path} {r_script}")
    log(f"R_LIBS_USER={user_lib}")

    try:
        with log_path().open("a", encoding="utf-8") as fh:
            fh.write(
                f"\n----- R session {datetime.now().isoformat(timespec='seconds')} -----\n"
            )
            result = subprocess.run(
                [str(rscript_path), "--vanilla", str(r_script)],
                cwd=str(base_dir),
                env=env,
                startupinfo=startupinfo,
                creationflags=creationflags,
                stdout=fh,
                stderr=subprocess.STDOUT,
                text=True,
            )
    except OSError as exc:
        show_message(
            f"Could not start R:\n{exc}\n\nDetails were written to:\n{log_path()}",
            error=True,
        )
        return 1

    if result.returncode != 0:
        # Shiny/httpuv commonly exits non-zero when the user closes the app.
        # If the server bound a port, the launch itself succeeded.
        try:
            log_text = log_path().read_text(encoding="utf-8", errors="replace")
        except OSError:
            log_text = ""
        session_marker = (
            f"----- R session "
        )
        # Only inspect the latest R session chunk when possible.
        latest = log_text.rsplit(session_marker, 1)[-1] if session_marker in log_text else log_text
        started = "Listening on http://" in latest or "Starting Biblioshiny..." in latest
        if started:
            log(
                f"R exited with code {result.returncode} after Biblioshiny started; "
                "treating as a normal shutdown."
            )
            return 0

        show_message(
            "Bibliometrix failed to start.\n\n"
            f"Exit code: {result.returncode}\n"
            f"See the log for details:\n{log_path()}",
            error=True,
        )
        return result.returncode

    log("R session finished successfully.")
    return 0


def main() -> int:
    base_dir = get_base_dir()
    current_version = get_local_version(base_dir)
    log(f"Launcher start version={current_version} base_dir={base_dir}")
    check_for_wrapper_updates(current_version)
    return start_application(base_dir)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        details = traceback.format_exc()
        try:
            log(details)
        except Exception:
            pass
        show_message(
            "An unexpected launcher error occurred.\n\n"
            f"See the log for details:\n{log_path()}",
            error=True,
        )
        sys.exit(1)
