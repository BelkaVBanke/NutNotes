#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NutNotes Release Package Builder
Creates a drag-and-drop ready release ZIP archive for REAPER:
  UserPlugins/
    reaper_imgui-x64.dll
    reaper_reapack-x64.dll
  Scripts/
    ReaTeam Extensions/API/
      gfx2imgui.lua
      imgui.lua
      imgui.py
      ReaImGui_Demo.lua
    NutNotes/
      NutNotes.lua
      README.md
      modules/
      assets/
      test_samples/

Usage:
    python tools/build_release.py [version]
Example:
    python tools/build_release.py 0.3.0
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
    return "0.3.0-beta"

def main():
    root_dir = Path(__file__).resolve().parent.parent
    version = sys.argv[1] if len(sys.argv) > 1 else detect_version(root_dir)

    build_dir = root_dir / "build"
    dist_name = f"NutNotes_v{version}"
    stage_dir = build_dir / "release_stage"
    zip_path = build_dir / f"{dist_name}.zip"

    print(f"[*] Building NutNotes release archive: {dist_name} ...")

    # 1. Clean previous staging directory
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    stage_dir.mkdir(parents=True, exist_ok=True)

    # Target directories inside archive
    user_plugins_dir = stage_dir / "UserPlugins"
    scripts_dir = stage_dir / "Scripts"
    reateam_dir = scripts_dir / "ReaTeam Extensions" / "API"
    nutnotes_dir = scripts_dir / "NutNotes"

    user_plugins_dir.mkdir(parents=True, exist_ok=True)
    reateam_dir.mkdir(parents=True, exist_ok=True)
    nutnotes_dir.mkdir(parents=True, exist_ok=True)

    # 2. Copy UserPlugins dependencies (DLLs)
    deps_dir = root_dir / "installer" / "dependencies"
    dll_files = ["reaper_imgui-x64.dll", "reaper_reapack-x64.dll"]
    for dll in dll_files:
        src = deps_dir / dll
        if src.exists():
            shutil.copy2(src, user_plugins_dir / dll)
            print(f"  + UserPlugins: {dll}")
        else:
            print(f"  ! Warning: dependency missing: {src}")

    # 3. Copy ReaTeam Extensions API
    reateam_src = deps_dir / "ReaTeam Extensions" / "API"
    if reateam_src.exists():
        for item in reateam_src.iterdir():
            if item.is_file():
                shutil.copy2(item, reateam_dir / item.name)
                print(f"  + Scripts/ReaTeam Extensions/API: {item.name}")
    else:
        print(f"  ! Warning: ReaTeam Extensions API folder missing: {reateam_src}")

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

    # 7. Package directly into ZIP archive
    print(f"\n[*] Packaging to {zip_path.name} ...")
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
        for file in stage_dir.rglob("*"):
            if file.is_file():
                arcname = file.relative_to(stage_dir)
                zipf.write(file, arcname)

    # 8. Clean up staging directory
    shutil.rmtree(stage_dir)

    size_mb = zip_path.stat().st_size / (1024 * 1024)
    print(f"[OK] Release archive created successfully: {zip_path} ({size_mb:.2f} MB)\n")

if __name__ == "__main__":
    main()
