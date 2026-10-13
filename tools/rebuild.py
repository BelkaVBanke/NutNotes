#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NutNotes Full Rebuild Pipeline:
  1. Synchronize version in all project files (VERSION, NutNotes.lua, modules/state.lua, Inno Setup)
  2. Build clean release ZIP archive (build/NutNotes_v<ver>.zip)
  3. Compile Inno Setup offline installer (installer/Output/NutNotes_Setup_v<ver>.exe)
"""

import os
import sys
import subprocess
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT_DIR / "VERSION"

def get_current_version() -> str:
    if VERSION_FILE.exists():
        v = VERSION_FILE.read_text(encoding="utf-8").strip()
        if v:
            return v
    return "0.3.0-beta"

def run_command(cmd, desc):
    print("\n" + "=" * 65)
    print(f"[*] {desc}")
    print("=" * 65)
    res = subprocess.run(cmd, cwd=str(ROOT_DIR))
    if res.returncode != 0:
        print(f"\n[ERROR] Ошибка при выполнении: {desc} (код выхода: {res.returncode})")
        sys.exit(res.returncode)

def main():
    print("=" * 65)
    print("               NutNotes - Full Rebuild Pipeline")
    print("=" * 65)

    current_ver = get_current_version()

    # Determine target version
    if len(sys.argv) > 1 and sys.argv[1].strip():
        target_ver = sys.argv[1].strip()
    else:
        print(f"\nТекущая версия проекта: {current_ver}")
        try:
            user_input = input(f"Введите версию для сборки (Enter для '{current_ver}'): ").strip()
        except EOFError:
            user_input = ""
        target_ver = user_input if user_input else current_ver

    print(f"\n[>] Запуск ребилда для версии: {target_ver}\n")

    # Step 1: Set & sync version everywhere
    run_command(
        [sys.executable, str(ROOT_DIR / "tools" / "set_version.py"), target_ver],
        f"[ШАГ 1/3] Синхронизация версий во всех файлах проекта ({target_ver})"
    )

    # Step 2: Build release ZIP
    run_command(
        [sys.executable, str(ROOT_DIR / "tools" / "build_release.py"), target_ver],
        f"[ШАГ 2/3] Сборка релизного ZIP-архива NutNotes_v{target_ver}.zip"
    )

    # Step 3: Build Inno Setup installer
    run_command(
        [sys.executable, str(ROOT_DIR / "installer" / "build.py")],
        f"[ШАГ 3/3] Компиляция установщика NutNotes_Setup_v{target_ver}.exe"
    )

    print("\n" + "=" * 65)
    print("                   РЕБИЛД УСПЕШНО ЗАВЕРШЕН!")
    print("=" * 65)
    print(f" Версия:     {target_ver}")
    print(f" ZIP-архив:  build/NutNotes_v{target_ver}.zip")
    print(f" Установщик: installer/Output/NutNotes_Setup_v{target_ver}.exe")
    print("=" * 65 + "\n")

if __name__ == "__main__":
    main()
