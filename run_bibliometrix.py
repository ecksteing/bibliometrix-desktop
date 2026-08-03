# run_bibliometrix.py
import os
import sys
import subprocess
import requests

# The Raw URL from GitHub
GITHUB_VERSION_URL = "https://raw.githubusercontent.com/ecksteing/bibliometrix-installer/refs/heads/main/version.txt"

def get_base_dir():
    """Finds directory path whether running as .py or compiled .exe"""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

def get_local_version(base_dir):
    """Autofills current version by reading the local version.txt file"""
    version_file = os.path.join(base_dir, "version.txt")
    try:
        with open(version_file, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return "1.0.0"  # Fallback if version.txt is missing

def check_for_wrapper_updates(current_version):
    """Checks your GitHub repository for updates to your launcher"""
    try:
        response = requests.get(GITHUB_VERSION_URL, timeout=3)
        if response.status_code == 200:
            latest = response.text.strip()
            if latest != current_version:
                print(f"Notice: A new version ({latest}) is available!")
                print(f"You are currently running version {current_version}.")
    except Exception:
        pass # Silently continue if the user is offline

def start_application(base_dir):
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
    base_dir = get_base_dir()
    current_version = get_local_version(base_dir)
    
    check_for_wrapper_updates(current_version)
    start_application(base_dir)