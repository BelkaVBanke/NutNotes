# Third-Party Software Notices and Information

This project (NutNotes) bundles or distributes binary and source components created by third parties as dependencies.
This document contains copyright notices and licensing details for those third-party components.

---

## 1. ReaImGui (reaper_imgui-x64.dll & ReaTeam Extensions API)

* **Component / Binary:** `reaper_imgui-x64.dll` & ReaTeam Extensions API files (`gfx2imgui.lua`, `imgui.lua`, `imgui.py`, `ReaImGui_Demo.lua`)
* **Project Name:** ReaImGui: ReaScript binding for Dear ImGui
* **Author / Copyright Holder:** Christian Fillion (cfillion) and ReaImGui contributors
* **Target Version:** `v0.10.0.5`
* **Upstream Source Code:** [https://github.com/cfillion/reaimgui/tree/v0.10.0.5](https://github.com/cfillion/reaimgui/tree/v0.10.0.5)
* **Licenses:**
  * GNU Lesser General Public License v3.0 (LGPL-3.0-or-later) / GNU General Public License v3.0 (GPL-3.0-or-later)
  * Included third-party components within ReaImGui:
    * Dear ImGui (Omar Cornut) — MIT License
    * FreeType — The FreeType Project License / GPL-2.0
    * md4c (Martin Mitáš) — MIT License
    * libjpeg-turbo — IJG / Modified BSD / zlib License
    * libpng — PNG Reference Library License version 2
    * zlib (Jean-loup Gailly and Mark Adler) — zlib License
* **License Texts:** Available in [`licenses/LICENSE-reaimgui-GPL3.txt`](licenses/LICENSE-reaimgui-GPL3.txt) and [`licenses/LICENSE-reaimgui-LGPL3.txt`](licenses/LICENSE-reaimgui-LGPL3.txt).
* **Distribution Notice:** Unmodified 64-bit binaries and API files are bundled in the offline Windows installer (`NutNotes_Setup_vX.X.X.exe`) and the full release archive (`NutNotes_vX.X.X.zip`).

---

## 2. ReaPack (reaper_reapack-x64.dll)

* **Component / Binary:** `reaper_reapack-x64.dll`
* **Project Name:** ReaPack: Package manager for REAPER
* **Author / Copyright Holder:** Christian Fillion (cfillion) and ReaPack contributors
* **Target Version:** `v1.2.6`
* **Upstream Source Code:** [https://github.com/cfillion/reapack/tree/v1.2.6](https://github.com/cfillion/reapack/tree/v1.2.6)
* **License:** GNU General Public License v3.0 (GPL-3.0-or-later)
* **License Text:** Available in [`licenses/LICENSE-reapack-GPL3.txt`](licenses/LICENSE-reapack-GPL3.txt).
* **Distribution Notice:** Unmodified 64-bit binary is bundled in the offline Windows installer (`NutNotes_Setup_vX.X.X.exe`) and the full release archive (`NutNotes_vX.X.X.zip`).

---

## Verification of Binaries (SHA-256 Checksums)

The bundled Windows 64-bit binaries are byte-for-byte identical to the official upstream releases published by the original author:

| Binary File | Target Version | Official SHA-256 Checksum |
| :--- | :--- | :--- |
| `reaper_imgui-x64.dll` | v0.10.0.5 | `800b216e0937bf5bb6b08ba2767b7b974a746b3fc3b54943b4d3011da0a68f2a` |
| `reaper_reapack-x64.dll` | v1.2.6 | `820ac691f9444d7c49c69413ac3dc264cde5204b4dd9a07d13ad9fefaa1243df` |

Both files have been verified against the official release hashes.

---

## Source Code Availability & Compliance

In compliance with GNU General Public License (GPL v3) and GNU Lesser General Public License (LGPL v3):
* Both `reaper_imgui-x64.dll` and `reaper_reapack-x64.dll` distributed in the installer and full archive are **unmodified official release binaries**.
* Complete corresponding source code is freely and publicly available at the respective version tags:
  * ReaPack v1.2.6: [https://github.com/cfillion/reapack/tree/v1.2.6](https://github.com/cfillion/reapack/tree/v1.2.6)
  * ReaImGui v0.10.0.5: [https://github.com/cfillion/reaimgui/tree/v0.10.0.5](https://github.com/cfillion/reaimgui/tree/v0.10.0.5)
* Should you require an offline copy of the exact matching source code archive corresponding to these versions, you may obtain it directly from the upstream repositories above or contact the maintainer of this repository.
