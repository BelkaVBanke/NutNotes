#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NutNotes Setup & Updater Builder Script
Automates:
  1. Icon and asset generation (toolbar icons, .ico)
  2. Downloading official x64 dependencies (ReaImGui, ReaPack, js_ReaScriptAPI)
  3. Locating or bootstrapping Inno Setup (ISCC.exe)
  4. Compiling the self-contained installer: build/v<version>/NutNotes_Setup_v<version>.exe
"""

import os
import sys
import shutil
import hashlib
import subprocess
import urllib.request
import json

INSTALLER_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(INSTALLER_DIR)
ASSETS_DIR = os.path.join(INSTALLER_DIR, "assets")
DEPS_DIR = os.path.join(INSTALLER_DIR, "dependencies")
ISS_FILE = os.path.join(INSTALLER_DIR, "NutNotes_Installer.iss")

# Tested dependencies versions
DEPS = [
    {
        "filename": "reaper_imgui-x64.dll",
        "url": "https://github.com/cfillion/reaimgui/releases/download/v0.10.0.5/reaper_imgui-x64.dll",
        "desc": "ReaImGui 64-bit extension (v0.10+ Unicode/Cyrillic)"
    },
    {
        "filename": "reaper_reapack-x64.dll",
        "url": "https://github.com/cfillion/reapack/releases/download/v1.2.6/reaper_reapack-x64.dll",
        "desc": "ReaPack 64-bit extension"
    },
    {
        "filename": "reaper_js_ReaScriptAPI64.dll",
        "url": "https://github.com/julians83/js_ReaScriptAPI/releases/download/v1.002/reaper_js_ReaScriptAPI64.dll",
        "desc": "js_ReaScriptAPI 64-bit extension"
    }
]

def log(msg):
    print(f"[NutNotes Builder] {msg}")

def get_current_version():
    ver_file = os.path.join(PROJECT_DIR, "VERSION")
    if os.path.exists(ver_file):
        v = open(ver_file, "r", encoding="utf-8").read().strip()
        if v:
            return v
    return "0.3.1-beta"

def get_output_dir():
    ver = get_current_version()
    return os.path.join(PROJECT_DIR, "build", f"v{ver}")

def ensure_assets():
    """Generate colored logo, wizard BMPs, ICO and REAPER toolbar icons"""
    os.makedirs(ASSETS_DIR, exist_ok=True)
    gen_script = os.path.join(PROJECT_DIR, "tools", "generate_installer_assets.py")
    if os.path.exists(gen_script):
        log("Ensuring colored artwork and wizard assets are generated...")
        res = subprocess.run([sys.executable, gen_script], cwd=PROJECT_DIR, capture_output=True, text=True)
        if res.returncode == 0:
            log("Artwork and wizard assets generated successfully.")
        else:
            log(f"Warning: Asset generator returned error: {res.stderr}")
    else:
        log("Asset generator script not found; using existing assets.")

def download_file(url, target_path, desc):
    """Downloads a file with status message"""
    log(f"Downloading {desc} from {url}...")
    req = urllib.request.Request(url, headers={"User-Agent": "NutNotes-Builder/1.0"})
    with urllib.request.urlopen(req) as resp, open(target_path, "wb") as f:
        shutil.copyfileobj(resp, f)
    size_mb = os.path.getsize(target_path) / (1024 * 1024)
    log(f"Saved {os.path.basename(target_path)} ({size_mb:.2f} MB)")

def ensure_dependencies():
    """Ensure all required DLLs are present in installer/dependencies/"""
    os.makedirs(DEPS_DIR, exist_ok=True)
    for dep in DEPS:
        dst = os.path.join(DEPS_DIR, dep["filename"])
        if not os.path.exists(dst) or os.path.getsize(dst) < 1000:
            download_file(dep["url"], dst, dep["desc"])
        else:
            size_mb = os.path.getsize(dst) / (1024 * 1024)
            log(f"Dependency ready: {dep['filename']} ({size_mb:.2f} MB)")

def find_iscc():
    """Locates ISCC.exe in system PATH, standard Program Files, or LocalAppData"""
    which_iscc = shutil.which("iscc.exe") or shutil.which("iscc")
    if which_iscc and os.path.exists(which_iscc):
        return which_iscc

    candidates = [
        os.path.expandvars(r"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"),
        os.path.expandvars(r"%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"),
        os.path.expandvars(r"%ProgramFiles%\Inno Setup 6\ISCC.exe"),
        os.path.expandvars(r"%LOCALAPPDATA%\Programs\Inno Setup 7\ISCC.exe"),
        os.path.expandvars(r"%ProgramFiles(x86)%\Inno Setup 7\ISCC.exe"),
        os.path.expandvars(r"%ProgramFiles%\Inno Setup 7\ISCC.exe"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c

    winget = shutil.which("winget")
    if winget:
        log("Inno Setup not found in standard paths. Attempting automated winget install...")
        try:
            cmd = [winget, "install", "--id", "JRSoftware.InnoSetup", "-e", "--source", "winget",
                   "--accept-source-agreements", "--accept-package-agreements", "--silent"]
            subprocess.run(cmd, check=True)
            for c in candidates:
                if os.path.exists(c):
                    return c
        except Exception as e:
            log(f"Winget install failed: {e}")

    return None

def build_installer(iscc_path):
    """Compiles the installer via Inno Setup Command-Line Compiler"""
    output_dir = get_output_dir()
    os.makedirs(output_dir, exist_ok=True)
    log(f"Compiling installer using {iscc_path}...")
    log(f"Script: {ISS_FILE}")
    log(f"Destination: {output_dir}")

    cmd = [iscc_path, ISS_FILE]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        log(f"ERROR: ISCC compilation failed with exit code {res.returncode}")
        sys.exit(res.returncode)

    # Locate generated output file
    out_files = [os.path.join(output_dir, f) for f in os.listdir(output_dir) if f.endswith(".exe")]
    if out_files:
        latest = max(out_files, key=os.path.getmtime)
        size_mb = os.path.getsize(latest) / (1024 * 1024)
        
        # Calculate SHA256
        h = hashlib.sha256()
        with open(latest, "rb") as f:
            while chunk := f.read(65536):
                h.update(chunk)
        sha256 = h.hexdigest()

        print("\n" + "=" * 65)
        print(" SUCCESS: NutNotes Setup was compiled successfully!")
        print("=" * 65)
        print(f" File:   {latest}")
        print(f" Size:   {size_mb:.2f} MB ({os.path.getsize(latest):,} bytes)")
        print(f" SHA256: {sha256}")
        print("=" * 65 + "\n")
    else:
        log("Warning: Output directory does not contain any .exe files!")

def sync_version():
    """Reads project version and synchronizes all project files using tools/set_version.py"""
    tools_dir = os.path.join(PROJECT_DIR, "tools")
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    try:
        import set_version
        v = set_version.get_current_version()
        set_version.sync_all(v)
        log(f"All files synchronized to version: {v}")
    except Exception as e:
        log(f"Warning: set_version sync encountered an error: {e}")

def main():
    print("\n--- NutNotes Setup Builder ---")
    log("Step 0: Synchronizing version from NutNotes.lua...")
    sync_version()

    log("Step 1: Preparing assets and icons...")
    ensure_assets()

    log("Step 2: Checking embedded dependencies...")
    ensure_dependencies()

    log("Step 3: Checking Inno Setup Compiler...")
    iscc = find_iscc()
    if not iscc:
        log("ERROR: Inno Setup Compiler (ISCC.exe) was not found!")
        log("Please install Inno Setup 6 from https://jrsoftware.org/isdl.php or via 'winget install JRSoftware.InnoSetup'")
        sys.exit(1)

    log(f"Found ISCC: {iscc}")
    log("Step 4: Compiling installer...")
    build_installer(iscc)

if __name__ == "__main__":
    main()
