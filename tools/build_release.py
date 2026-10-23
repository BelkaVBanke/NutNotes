#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NutNotes Cross-Platform Release Package Builder
Creates a clean, portable cross-platform ZIP archive for REAPER (Windows, macOS, Linux):
  Scripts/
    NutNotes/
      NutNotes.lua
      README.md
      LICENSE
      modules/
      assets/
      test_samples/
  INSTALL_CROSSPLATFORM.txt

Target output:
  build/v<version>/NutNotes_v<version>.zip

Usage:
    python tools/build_release.py [version]
Example:
    python tools/build_release.py 0.3.1-beta
"""

import os
import re
import sys
import shutil
import zipfile
from pathlib import Path

def detect_version(root_dir: Path) -> str:
    ver_file = root_dir / "VERSION"
    if ver_file.exists():
        v = ver_file.read_text(encoding="utf-8").strip()
        if v:
            return v
    lua_file = root_dir / "NutNotes.lua"
    if lua_file.exists():
        content = lua_file.read_text(encoding="utf-8")
        m = re.search(r"@version\s+([^\r\n]+)", content)
        if m:
            return m.group(1).strip()
    return "0.3.1-beta"

def create_install_instructions(version: str) -> str:
    return f"""=====================================================================
NutNotes v{version} - Cross-Platform Installation Guide (Windows / macOS / Linux)
=====================================================================

1. COPY SCRIPT TO REAPER:
   - Open Cockos REAPER.
   - In the top menu, click:
       Options -> Show REAPER resource path in explorer/finder...
   - Open the "Scripts" folder.
   - Copy or extract the "NutNotes" folder from this archive into "Scripts/".
     (Final path should be: <REAPER Resource Path>/Scripts/NutNotes/NutNotes.lua)

2. INSTALL REQUIRED EXTENSIONS VIA REAPACK (macOS / Linux / Windows):
   NutNotes requires ReaImGui and js_ReaScriptAPI for UI rendering and window docking.
   If not already installed:
   - In REAPER, click: Extensions -> ReaPack -> Browse packages...
   - Search for and install:
       1) "ReaImGui: ReaScript binding for Dear ImGui"
       2) "js_ReaScriptAPI: API functions for ReaScripts"
   - Click "Apply" in the bottom-right corner, then restart REAPER.

3. LOAD ACTION IN REAPER:
   - In REAPER, press '?' or open: Actions -> Show action list...
   - Click "New action..." -> "Load ReaScript..."
   - Select: Scripts/NutNotes/NutNotes.lua
   - NutNotes is now ready! You can run it, assign a shortcut, or add a toolbar button.

=====================================================================
GitHub Repository & Updates: https://github.com/BelkaVBanke/NutNotes
=====================================================================
"""

def main():
    root_dir = Path(__file__).resolve().parent.parent
    version = sys.argv[1] if len(sys.argv) > 1 else detect_version(root_dir)

    build_dir = root_dir / "build"
    version_dir = build_dir / f"v{version}"
    stage_dir = build_dir / "release_stage"
    zip_path = version_dir / f"NutNotes_v{version}.zip"

    print(f"[*] Building NutNotes cross-platform release archive: v{version} ...")

    # 1. Ensure target build/v<version> folder exists
    version_dir.mkdir(parents=True, exist_ok=True)

    # 2. Clean previous staging directory
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    stage_dir.mkdir(parents=True, exist_ok=True)

    # 3. Target directories inside archive
    scripts_dir = stage_dir / "Scripts"
    nutnotes_dir = scripts_dir / "NutNotes"
    nutnotes_dir.mkdir(parents=True, exist_ok=True)

    # 4. Copy Core NutNotes script files
    core_files = ["NutNotes.lua", "README.md", "LICENSE"]
    for file_name in core_files:
        src = root_dir / file_name
        if src.exists():
            shutil.copy2(src, nutnotes_dir / file_name)
            print(f"  + Scripts/NutNotes: {file_name}")

    # 5. Copy Core NutNotes directories
    ignore_patterns = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store", "Thumbs.db")
    for dir_name in ["modules", "assets"]:
        src = root_dir / dir_name
        if src.exists():
            shutil.copytree(src, nutnotes_dir / dir_name, ignore=ignore_patterns)
            print(f"  + Scripts/NutNotes/{dir_name}/")

    # 6. Copy test_samples into Scripts/NutNotes/test_samples
    samples_src = root_dir / "test_samples"
    if samples_src.exists():
        shutil.copytree(samples_src, nutnotes_dir / "test_samples", ignore=ignore_patterns)
        print(f"  + Scripts/NutNotes/test_samples/")

    # 7. Add cross-platform installation instructions
    install_txt = stage_dir / "INSTALL_CROSSPLATFORM.txt"
    install_txt.write_text(create_install_instructions(version), encoding="utf-8")
    print("  + INSTALL_CROSSPLATFORM.txt")

    # 8. Package directly into ZIP archive
    print(f"\n[*] Packaging to {zip_path.name} in build/v{version}/ ...")
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
        for file in stage_dir.rglob("*"):
            if file.is_file():
                arcname = file.relative_to(stage_dir)
                zipf.write(file, arcname)

    # 9. Clean up staging directory
    shutil.rmtree(stage_dir)

    size_kb = zip_path.stat().st_size / 1024
    print(f"[OK] Cross-platform archive created: {zip_path} ({size_kb:.1f} KB)\n")

if __name__ == "__main__":
    main()
