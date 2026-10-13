#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NutNotes Single-Source Version Manager
Usage:
    python tools/set_version.py [new_version]

Examples:
    python tools/set_version.py 0.3.0-beta
    python tools/set_version.py             # Syncs all files with version in VERSION file
"""

import os
import re
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT_DIR / "VERSION"
NUTNOTES_LUA = ROOT_DIR / "NutNotes.lua"
STATE_LUA = ROOT_DIR / "modules" / "state.lua"
INSTALLER_ISS = ROOT_DIR / "Setup" / "NutNotes_Installer.iss"

def get_current_version() -> str:
    if VERSION_FILE.exists():
        v = VERSION_FILE.read_text(encoding="utf-8").strip()
        if v:
            return v
    if NUTNOTES_LUA.exists():
        content = NUTNOTES_LUA.read_text(encoding="utf-8")
        m = re.search(r"@version\s+([^\r\n]+)", content)
        if m:
            return m.group(1).strip()
    return "0.3.0-beta"

def sync_all(new_version: str):
    new_version = new_version.strip()
    print(f"[*] Setting NutNotes project version to: {new_version}")

    # 1. Update VERSION file
    VERSION_FILE.write_text(new_version + "\n", encoding="utf-8")
    print(f"  + Updated {VERSION_FILE.name}")

    # 2. Update NutNotes.lua (@version)
    if NUTNOTES_LUA.exists():
        content = NUTNOTES_LUA.read_text(encoding="utf-8")
        updated = re.sub(r"(@version\s+)[^\r\n]+", rf"\g<1>{new_version}", content)
        NUTNOTES_LUA.write_text(updated, encoding="utf-8")
        print(f"  + Updated {NUTNOTES_LUA.name} (@version)")

    # 3. Update modules/state.lua (version = "...")
    if STATE_LUA.exists():
        content = STATE_LUA.read_text(encoding="utf-8")
        if re.search(r'version\s*=\s*"[^"]*"', content):
            updated = re.sub(r'version\s*=\s*"[^"]*"', f'version = "{new_version}"', content)
        else:
            # Insert after the opening "local state = {"
            updated = re.sub(r'(local state = \{)', rf'\1\n  version = "{new_version}",', content)
        STATE_LUA.write_text(updated, encoding="utf-8")
        print(f"  + Updated modules/state.lua (version)")

    # 4. Update Setup/NutNotes_Installer.iss (#define MyAppVersion "...")
    if INSTALLER_ISS.exists():
        content = INSTALLER_ISS.read_text(encoding="utf-8-sig")
        updated = re.sub(r'#define\s+MyAppVersion\s+"[^"]+"', f'#define MyAppVersion "{new_version}"', content)
        INSTALLER_ISS.write_text(updated, encoding="utf-8-sig")
        print(f"  + Updated Setup/NutNotes_Installer.iss (#define MyAppVersion)")

    print(f"[OK] All project files successfully synchronized to version {new_version}!\n")

def main():
    if len(sys.argv) > 1:
        target_version = sys.argv[1].strip()
    else:
        target_version = get_current_version()
    sync_all(target_version)

if __name__ == "__main__":
    main()
