# run_bibliometrix.py
#
"""Launch Biblioshiny from the bundled portable R runtime."""

from __future__ import annotations

import json
import os
import socket
import sys
import subprocess
import threading
import time
import traceback
import webbrowser
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import URLError, HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

GITHUB_VERSION_URL = (
    "https://raw.githubusercontent.com/ecksteing/bibliometrix-desktop/main/version.txt"
)
RELEASES_URL = "https://github.com/ecksteing/bibliometrix-desktop/releases"
APP_NAME = "Bibliometrix Desktop"
SHINY_HOST = "127.0.0.1"
SHINY_PORT = 3838
LOADING_PORT = 3837
LOG_MAX_BYTES = 2 * 1024 * 1024  # 2 MiB
LOG_BACKUP_COUNT = 2


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


def rotate_logs_if_needed() -> None:
    """Keep launcher.log from growing without bound (size-based rotation)."""
    path = log_path()
    try:
        if not path.is_file() or path.stat().st_size < LOG_MAX_BYTES:
            return
        oldest = path.with_name(f"launcher.log.{LOG_BACKUP_COUNT}")
        if oldest.exists():
            oldest.unlink()
        for i in range(LOG_BACKUP_COUNT - 1, 0, -1):
            src = path.with_name(f"launcher.log.{i}")
            dst = path.with_name(f"launcher.log.{i + 1}")
            if src.exists():
                src.replace(dst)
        path.replace(path.with_name("launcher.log.1"))
    except OSError:
        pass


def log(message: str) -> None:
    line = f"{datetime.now().isoformat(timespec='seconds')} {message}"
    try:
        rotate_logs_if_needed()
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


def ask_yes_no(text: str, title: str = APP_NAME) -> bool:
    """Ask a Yes/No question. Returns True if the user chooses Yes."""
    log(f"PROMPT: {text.replace(chr(10), ' | ')}")
    if sys.platform == "win32":
        try:
            import ctypes

            # MB_YESNO | MB_ICONINFORMATION; IDYES == 6
            result = ctypes.windll.user32.MessageBoxW(0, text, title, 0x04 | 0x40)
            return result == 6
        except Exception:
            pass
    # Non-Windows / dialog failure: print and do not assume Yes.
    print(text, file=sys.stderr)
    return False


def get_local_version(base_dir: Path) -> str:
    version_file = base_dir / "version.txt"
    try:
        return version_file.read_text(encoding="utf-8").strip()
    except OSError:
        return "0.0.0"


def query_wrapper_update(current_version: str) -> dict:
    """Return desktop wrapper update status from GitHub version.txt."""
    try:
        request = Request(
            GITHUB_VERSION_URL,
            headers={"User-Agent": f"{APP_NAME}/{current_version}"},
        )
        with urlopen(request, timeout=5) as response:
            latest = response.read().decode("utf-8", errors="replace").strip()
        if not latest:
            return {"status": "error", "message": "Could not read the latest version."}
        if latest == current_version:
            return {
                "status": "current",
                "current": current_version,
                "latest": latest,
                "message": f"You have the latest desktop installer ({current_version}).",
            }
        return {
            "status": "update",
            "current": current_version,
            "latest": latest,
            "releases_url": RELEASES_URL,
            "message": (
                f"A newer desktop installer ({latest}) is available. "
                f"You are running {current_version}."
            ),
        }
    except (URLError, HTTPError, TimeoutError, ValueError, OSError):
        return {
            "status": "offline",
            "message": "Update check unavailable (offline or GitHub unreachable).",
        }


def check_for_wrapper_updates(current_version: str) -> None:
    """Notify if a newer desktop wrapper version is published on GitHub."""
    result = query_wrapper_update(current_version)
    if result["status"] != "update":
        if result["status"] == "offline":
            log("Update check skipped (offline or unavailable).")
        return

    open_download = ask_yes_no(
        f"{result['message']}\n\nOpen the download page now?",
        title=f"{APP_NAME} update available",
    )
    if open_download:
        log(f"Opening releases page: {RELEASES_URL}")
        webbrowser.open(RELEASES_URL)


def shiny_url(port: int = SHINY_PORT) -> str:
    return f"http://{SHINY_HOST}:{port}"


def port_is_listening(port: int = SHINY_PORT) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex((SHINY_HOST, port)) == 0


def shiny_http_reachable(port: int = SHINY_PORT) -> bool:
    """
    True if something on the Shiny port answers HTTP.
    Uses a raw socket: urllib often fails against httpuv even when the app is up.
    """
    try:
        with socket.create_connection((SHINY_HOST, port), timeout=2.0) as sock:
            sock.settimeout(2.0)
            sock.sendall(
                b"GET / HTTP/1.0\r\n"
                b"Host: 127.0.0.1\r\n"
                b"Connection: close\r\n"
                b"\r\n"
            )
            chunks: list[bytes] = []
            while True:
                try:
                    data = sock.recv(2048)
                except socket.timeout:
                    break
                if not data:
                    break
                chunks.append(data)
                joined = b"".join(chunks)
                if b"HTTP/" in joined or len(joined) >= 32:
                    return True
            return bool(chunks)
    except OSError:
        return False


def process_image_path(pid: int) -> Path | None:
    """Return the executable path for a PID (Windows), or None."""
    if sys.platform != "win32" or pid <= 0:
        return None
    try:
        import ctypes
        from ctypes import wintypes

        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return None
        try:
            buf = ctypes.create_unicode_buffer(32768)
            size = wintypes.DWORD(len(buf))
            query = getattr(kernel32, "QueryFullProcessImageNameW")
            if query(handle, 0, buf, ctypes.byref(size)):
                return Path(buf.value)
        finally:
            kernel32.CloseHandle(handle)
    except Exception:
        return None
    return None


def pids_belong_to_install(pids: set[int], base_dir: Path) -> bool:
    """True if any PID is an executable under this install folder."""
    root = str(base_dir.resolve()).rstrip("\\").lower()
    for pid in pids:
        image = process_image_path(pid)
        if image is None:
            continue
        path = str(image).rstrip("\\").lower()
        if path == root or path.startswith(root + "\\"):
            return True
    return False


def open_shiny_in_browser(port: int = SHINY_PORT) -> None:
    webbrowser.open(shiny_url(port))


def open_loading_page(
    base_dir: Path, shiny_port: int = SHINY_PORT, current_version: str = "0.0.0"
) -> ThreadingHTTPServer | None:
    """
    Serve a small local loading page and open it in the browser while R starts.
    Returns the server so the caller can shut it down later, or None on failure.
    """
    loading_file = base_dir / "loading.html"
    if loading_file.is_file():
        html = loading_file.read_text(encoding="utf-8")
    else:
        html = (
            "<!doctype html><meta charset=utf-8><title>Loading…</title>"
            "<p>Starting Biblioshiny…</p>"
            "<script>setTimeout(function(){location.replace("
            f"'{shiny_url(shiny_port)}'"
            ");},3000);</script>"
        )

    class LoadingHandler(BaseHTTPRequestHandler):
        def _send_json(self, payload: dict, status: int = 200) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802
            path = self.path.split("?", 1)[0]
            if path == "/check-update":
                log("Manual desktop update check requested from loading page.")
                self._send_json(query_wrapper_update(current_version))
                return

            body = html.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    try:
        server = ThreadingHTTPServer((SHINY_HOST, LOADING_PORT), LoadingHandler)
    except OSError as exc:
        log(f"Could not start loading page server on {LOADING_PORT}: {exc}")
        return None

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    target = quote(shiny_url(shiny_port), safe=":/")
    loading_url = f"http://{SHINY_HOST}:{LOADING_PORT}/?target={target}"
    log(f"Opening loading page: {loading_url}")
    webbrowser.open(loading_url)
    return server


def _creationflags_no_window() -> int:
    if sys.platform == "win32":
        return getattr(subprocess, "CREATE_NO_WINDOW", 0)
    return 0


def pids_listening_on_port(port: int = SHINY_PORT) -> set[int]:
    """Return PIDs with a TCP LISTENING socket on port (Windows)."""
    if sys.platform != "win32":
        return set()
    try:
        output = subprocess.check_output(
            ["netstat", "-ano", "-p", "TCP"],
            text=True,
            errors="replace",
            creationflags=_creationflags_no_window(),
        )
    except (OSError, subprocess.CalledProcessError):
        return set()

    suffix = f":{port}"
    pids: set[int] = set()
    for line in output.splitlines():
        if "LISTENING" not in line:
            continue
        parts = line.split()
        # Expect: Proto LocalAddress ForeignAddress State PID
        if len(parts) < 5:
            continue
        local_addr = parts[1]
        # Match 127.0.0.1:3838 or 0.0.0.0:3838, not :38380.
        if not local_addr.endswith(suffix):
            continue
        # Ensure exact port: character before port must be ':' already in suffix.
        try:
            pids.add(int(parts[-1]))
        except ValueError:
            continue
    return pids


def kill_pids(pids: set[int]) -> None:
    for pid in sorted(pids):
        if pid <= 0:
            continue
        log(f"Stopping process PID {pid} holding the Biblioshiny port.")
        try:
            if sys.platform == "win32":
                subprocess.run(
                    ["taskkill", "/PID", str(pid), "/T", "/F"],
                    capture_output=True,
                    text=True,
                    creationflags=_creationflags_no_window(),
                )
            else:
                os.kill(pid, 15)
        except OSError as exc:
            log(f"Could not stop PID {pid}: {exc}")


def prepare_shiny_port(port: int = SHINY_PORT, base_dir: Path | None = None) -> bool:
    """
    If Biblioshiny is already running, reopen the browser and return True
    (caller should exit). Otherwise free a stuck port if needed and return False.
    """
    for attempt in range(3):
        if shiny_http_reachable(port):
            log(f"Biblioshiny already running at {shiny_url(port)}; reopening browser.")
            open_shiny_in_browser(port)
            return True
        if attempt < 2 and port_is_listening(port):
            time.sleep(0.4)

    if not port_is_listening(port):
        return False

    holders = pids_listening_on_port(port)
    if base_dir is not None and pids_belong_to_install(holders, base_dir):
        # httpuv often fails a strict HTTP client while the app is still healthy.
        log(
            f"Port {port} is held by this install; reopening {shiny_url(port)} "
            "instead of restarting R."
        )
        open_shiny_in_browser(port)
        return True

    log(f"Port {port} is in use but Biblioshiny is not responding; freeing it.")
    kill_pids(holders)
    time.sleep(1.0)
    return False


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
    env["BIBDESK_SHINY_HOST"] = SHINY_HOST
    env["BIBDESK_SHINY_PORT"] = str(SHINY_PORT)
    # Browser is opened by the Python loading page; R should not open a second tab.
    env["BIBDESK_LAUNCH_BROWSER"] = "0"

    creationflags = 0
    startupinfo = None
    if sys.platform == "win32":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    log(f"Starting: {rscript_path} {r_script}")
    log(f"R_LIBS_USER={user_lib}")

    loading_server = open_loading_page(base_dir, SHINY_PORT, current_version=get_local_version(base_dir))
    session_started = False
    session_failed_bind = False

    try:
        rotate_logs_if_needed()
        with log_path().open("a", encoding="utf-8") as fh:
            fh.write(
                f"\n----- R session {datetime.now().isoformat(timespec='seconds')} -----\n"
            )
            fh.flush()
            proc = subprocess.Popen(
                [str(rscript_path), "--vanilla", str(r_script)],
                cwd=str(base_dir),
                env=env,
                startupinfo=startupinfo,
                creationflags=creationflags,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )

            def _pump_r_output() -> None:
                nonlocal session_started, session_failed_bind
                assert proc.stdout is not None
                for line in proc.stdout:
                    fh.write(line)
                    fh.flush()
                    if "Listening on http://" in line or "Starting Biblioshiny" in line:
                        session_started = True
                    lower = line.lower()
                    if "address already in use" in lower or "failed to create server" in lower:
                        session_failed_bind = True
                proc.stdout.close()

            pump = threading.Thread(target=_pump_r_output, daemon=True)
            pump.start()
            result = proc.wait()
            pump.join(timeout=5)
    except OSError as exc:
        show_message(
            f"Could not start R:\n{exc}\n\nDetails were written to:\n{log_path()}",
            error=True,
        )
        return 1
    finally:
        if loading_server is not None:
            try:
                loading_server.shutdown()
            except Exception:
                pass

    if result.returncode != 0:
        # Shiny/httpuv commonly exits non-zero when the browser closes or a
        # later launch stops this R process. That is not a failed start.
        if session_started and not session_failed_bind:
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

    # Closing the browser tab does not stop Shiny; reopen or free port 3838.
    if prepare_shiny_port(SHINY_PORT, base_dir=base_dir):
        return 0

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
