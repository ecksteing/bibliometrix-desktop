# run_bibliometrix.py
import os
import sys
import subprocess
import requests

# Set this to the Raw URL of version.txt in YOUR public GitHub repository
GITHUB_VERSION_URL = "https://raw.githubusercontent.com/YourUsername/YourRepo/main/version.txt"
CURRENT_VERSION = "1.0.0"

def get_base_dir():
    """Finds directory path whether running as .py or compiled .exe"""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

def check_for_wrapper_updates():
    """Checks your GitHub repository for updates to your launcher"""
    try:
        response = requests.get(GITHUB_VERSION_URL, timeout=3)
        if response.status_code == 200:
            latest = response.text.strip()
            if latest != CURRENT_VERSION:
                print(f"Notice: Version {latest} of this launcher is available on GitHub.")
    except Exception:
        pass # Silently continue if user is offline

def start_application():
    base_dir = get_base_dir()
    
    # Locate Rscript.exe within the portable folder structure
    rscript_path = os.path.join(base_dir, "R-Portable", "App", "R-Portable", "bin", "Rscript.exe")
    if not os.path.exists(rscript_path):
        rscript_path = os.path.join(base_dir, "R-Portable", "bin", "Rscript.exe")

    r_script = os.path.join(base_dir, "launch_app.R")

    if not os.path.exists(rscript_path):
        print(f"Error: R-Portable path not found at {rscript_path}")
        input("Press Enter to exit...")
        sys.exit(1)

    # Hide command prompt window on Windows when starting R
    startupinfo = None
    if sys.platform == "win32":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

    subprocess.run([rscript_path, r_script], startupinfo=startupinfo)

if __name__ == "__main__":
    check_for_wrapper_updates()
    start_application()