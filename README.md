<div align="center">

  # Moonshine 🌙
  *Whisky's rebellious offspring — Wine for macOS, uncut*

  [![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
  [![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-green)](https://support.apple.com/en-us/116943)
  [![Wine](https://img.shields.io/badge/Wine-Staging%2011.18-purple)](https://github.com/Gcenx/macOS_Wine_builds)
  [![License](https://img.shields.io/badge/License-GPL--3.0-orange)](LICENSE)

  Fork of [Moonshine](https://github.com/ybmeng/moonshine), itself a fork of [Whisky-App/Whisky](https://github.com/Whisky-App/Whisky) (archived May 2025)
</div>

---

Moonshine is a maintained fork of Whisky, a native SwiftUI wrapper for Wine on macOS. Run Windows games and apps on your Mac with no technical knowledge required — create bottles, configure settings, and launch programs through a clean GUI.

## What's different from Whisky?

- **Wine Staging 11.2** (Feb 2026) — replaces the outdated CrossOver 22.1.1 (2023) bundled with the original
- **Crash logs that actually work** — Wine output is captured in full, including page faults, DLL load failures, and exit codes
- **OpenGL 3.2+ support** — binary patch to Wine's macOS driver fixes context creation for SDL3 and other modern engines
- **macOS 26 tested** — verified on the latest macOS with Apple Silicon

## System Requirements

| Requirement | Minimum |
|------------|---------|
| CPU | Apple Silicon (M1 / M2 / M3 / M4) |
| OS | macOS Sonoma 14.0+ |
| Xcode | 16+ (building from source only) |

## Quick Start

### Method 1: Install from DMG (recommended)

1. Download `Moonshine.dmg` from the [latest release](https://github.com/criptore/reantry/releases/latest)
2. Open the DMG and drag **Moonshine.app** to **Applications**
3. Launch the app — the setup wizard will automatically:
   - Download the Wine libraries from the [`libraries` release](https://github.com/criptore/reantry/releases/tag/libraries)
     (or [Wine Staging 11.18](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18) from Gcenx if that release is not published yet)
   - Extract and install Wine into the correct directory structure
4. Create a bottle and start running Windows programs

No manual Wine installation, no terminal commands, no patching required.

### Method 2: Build from source

One command does everything — clones the repo, installs dependencies, builds the app, and launches it:

```bash
curl -fsSL https://raw.githubusercontent.com/criptore/reantry/main/scripts/build_from_source.sh | bash
```

Or if you've already cloned the repo:

```bash
./scripts/build_from_source.sh
```

The script will:
1. Install Homebrew (if not installed)
2. Install swiftlint via Homebrew
3. Clone the repo (if not already in it)
4. Build the app with `xcodebuild` (Release, ad-hoc signed)
5. Copy `Moonshine.app` to `/Applications`
6. Launch the app

On first launch, the setup wizard downloads and installs Wine — same as Method 1.

### Build a DMG

To create a distributable DMG locally:

```bash
./scripts/build_dmg.sh
```

This builds a Release configuration, stages the app with an Applications symlink, and outputs `Moonshine.dmg` in the project root.

### Homebrew

There is no Homebrew cask for this fork yet. `brew install --cask whisky` installs the original, unmaintained Whisky.

### Publishing releases

See [docs/Releasing.md](docs/Releasing.md) for the Wine libraries release, the Sparkle signing key and the update feed.

### Logs

Wine logs are written to:

```
~/Library/Logs/com.isaacmarovitz.Whisky/*.log
```

Each run creates a timestamped log with full Wine output, including crash details and DLL load diagnostics.

## Command line

`WhiskyCmd` drives the app from the terminal, which allows testing without the GUI. Build the `WhiskyCmd`
scheme in Xcode (the binary is also embedded in the app bundle) and run it from a terminal. Bottles are
shared with the app.

| Command | What it does |
|---------|--------------|
| `WhiskyCmd wine status` | Shows whether Wine is installed, its version, the library folder and whether an update is available |
| `WhiskyCmd wine install [--file <archive>]` | Downloads the Wine libraries (with the Gcenx build as fallback) and installs them, or installs a local archive |
| `WhiskyCmd create <name> [--windows win10]` | Creates a bottle and initializes its prefix |
| `WhiskyCmd list` | Lists the bottles |
| `WhiskyCmd config <bottle> [options]` | Prints the settings of a bottle, or changes them |
| `WhiskyCmd exec <bottle> [--wait] -- <args...>` | Runs `wine <args>` in the bottle, streams the output and returns wine's exit status |
| `WhiskyCmd run [--wait] <bottle> <exe> [args...]` | Runs a program: in Terminal, or with `--wait` attached to the command |
| `WhiskyCmd logs [--last]` | Prints the logs folder, or the path and content of the newest log |
| `WhiskyCmd add`, `remove`, `delete`, `shellenv` | Add, forget or delete a bottle, print `export` statements for a bottle |

`config` takes `--backend d3dmetal|dxvk|wined3d`, `--windows <version>`, `--sync none|esync|msync`,
`--dxvk-async true|false`, `--dxvk-hud full|partial|fps|off`, `--metal-hud true|false`, `--avx true|false`
and `--runtime <name>|default`. The values are saved to the bottle's `Metadata.plist`.

```bash
WhiskyCmd wine install
WhiskyCmd create test --windows win10
WhiskyCmd config test --backend dxvk --dxvk-hud fps
WhiskyCmd exec test -- cmd /c ver
WhiskyCmd logs --last | grep -E "Graphics Backend|WINEDLLOVERRIDES"
```

`exec --wait` also waits for the other processes started in the bottle (`wineserver -w`). Options of
`run` go before the bottle name.

---

## Changelog (from upstream Whisky v2.3.5)

### v2.7.0-fork — DMG distribution with auto-download Wine setup

**Problem:** Setting up Moonshine required 7 manual steps — clone the repo, install swiftlint, build from source, download Wine Staging, extract it into the right directory, apply the OpenGL patch, and finally launch. Users needed developer tools and terminal knowledge just to get started.

**Solution:** One-step install via DMG. On first launch, the app automatically downloads Wine Staging 11.2, sets up the correct directory structure, and applies the OpenGL patch.

#### Changes

| File | Change |
|------|--------|
| `WhiskyWineDownloadView.swift` | Download URL changed to Gcenx Wine Staging 11.2 (`wine-staging-11.2-osx64.tar.xz`) |
| `Tar.swift` | `untar()` flag changed from `-xzf` (gzip) to `-xf` (auto-detect, supports `.tar.xz`) |
| `WhiskyWineInstaller.swift` | After extraction, moves files from `Wine Staging.app/Contents/Resources/wine/` to `Libraries/Wine/` |
| `WhiskyWineInstaller.swift` | Writes `WhiskyWineVersion.plist` (version 11.2.0) so `isWhiskyWineInstalled()` returns true |
| `WhiskyWineInstaller.swift` | Auto-applies OpenGL 3.2+ patch to `winemac.so` after install |
| `BottleView.swift` | File picker `allowedContentTypes` changed to `[.item]` so all files (including `.exe`) are selectable |
| `PinCreationView.swift` | Same file picker fix for pin creation dialog |
| `scripts/build_dmg.sh` | New script: builds Release app, creates DMG with Applications symlink |

---

### v2.4.0-fork — Fix silent crash logging

**Problem:** When a Windows exe crashed under Wine, Whisky showed no output. The log file only contained `msync: up and running.` with zero error detail.

**Root cause:** Whisky launched programs via `wine start /unix <path>`, which spawns a **detached** child process. The parent's stdout/stderr was captured, but the child (the actual game) ran independently — its crash output went nowhere.

#### Changes

**`WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift`**

- **`runProgram()`** — Removed `start /unix` from Wine arguments. Programs now launch directly via `wine <path>`, keeping the process attached so all output is captured.
- **`runWineProcess()`** — Added `directory` parameter to set the working directory to the exe's parent folder.
- **`generateRunCommand()`** — Updated terminal command generation to `cd` into the exe directory and run directly.
- **`constructWineEnvironment()`** — Changed `WINEDEBUG` from `fixme-all` to `fixme-all,err+all,warn+module` to enable error-level messages and module warnings.

**`WhiskyKit/Sources/WhiskyKit/Extensions/Process+Extensions.swift`**

- **Termination handler** — Now drains remaining buffered output from both pipes before closing the log file.
- **`logTermination()`** — Writes termination details (exit code, reason) to the log file. Crash signals labeled as `"uncaught signal (crash)"`.

#### Result

```
wine: Unhandled page fault on read access to 0000000000000084 at address 0000000140D5CA75 (thread 0024)
0024:err:seh:start_debugger Couldn't start debugger L"winedbg --auto 32 164" (2)

Process Mewgenics.exe terminated: status=5, reason=exit
```

---

### v2.5.0-fork — Upgrade Wine from CrossOver 22.1.1 to Wine Staging 11.2

**Problem:** The bundled Wine (based on CrossOver 22.1.1 from 2023) lacked support for modern Windows APIs including WinRT `Windows.Gaming.Input`, causing SDL3-based games to crash with null pointer dereferences.

**Solution:** Upgraded to [Wine Staging 11.2](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.2) (Feb 7, 2026).

#### Changes

| File | Change |
|------|--------|
| `Wine.swift` | `wine64` → `wine` (Wine 11.x unified binary name) |
| `Wine.swift` | Terminal aliases updated from `wine64` to `wine` |
| `Winetricks.swift` | `WINE=wine64` → `WINE=wine` |
| Wine binaries | Replaced with Wine Staging 11.2 from [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) |
| `WhiskyWineVersion.plist` | Version set to 11.2.0 |

After installing new Wine binaries, update your bottle:

```bash
WINEPREFIX="<bottle_path>" wine wineboot --update
```

---

### v2.6.0-fork — Fix OpenGL 3.2 context creation on macOS (binary patch)

**Problem:** Games using OpenGL 3.2+ Core Profile (e.g., SDL3-based games) failed with `"Could not create GL context: Invalid handle"`.

**Root cause:** Wine's macOS display driver (`winemac.so`) rejects `wglCreateContextAttribsARB` calls requesting OpenGL 3.2+ without `WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB`. macOS CGL requires this flag for 3.2+ contexts, but on Windows it's optional — so most programs (including SDL3) don't set it.

**Diagnosis** via `WINEDEBUG="+wgl"`:

```
macdrv_context_create   Attrib 0x2091: 3    (WGL_CONTEXT_MAJOR_VERSION_ARB = 3)
macdrv_context_create   Attrib 0x2092: 2    (WGL_CONTEXT_MINOR_VERSION_ARB = 2)
macdrv_context_create   Attrib 0x9126: 1    (WGL_CONTEXT_PROFILE_MASK_ARB = Core)
warn:wgl:macdrv_context_create OS X only supports forward-compatible 3.2+ contexts
warn:wgl:win32u_context_create Failed to create driver context
```

#### Binary patch to `winemac.so`

**File:** `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/wine/x86_64-unix/winemac.so`

Disassembled with `otool -tV` and located the conditional branch in `macdrv_context_create()`:

```asm
; %al = forward-compat flag check: 0 = present, nonzero = missing
;
000329f9: testb  %al, %al
000329fb: je     0x32a1d          ; jump to normal path ONLY if flag present
000329fd: testb  $0x4, ...        ; (debug channel check)
00032a04: je     0x32e52          ; → SetLastError(ERROR_INVALID_OPERATION) + return NULL
00032a0a: leaq   ..., %rdx       ; "macdrv_context_create"
00032a11: leaq   ..., %rcx       ; "OS X only supports forward-compatible..."
00032a18: jmp    0x32e46          ; → print warning + return NULL
00032a1d: ...                     ; normal context creation continues
```

**Patch:** 1 byte at file offset `0x329fb`:

| Offset | Before | After | Effect |
|--------|--------|-------|--------|
| `0x329fb` | `0x74` (`je` — jump if equal) | `0xeb` (`jmp` — unconditional jump) | Always jump to `0x32a1d` |

The `je` only jumped to normal context creation when the forward-compat flag was present (`al == 0`). Changing it to `jmp` makes it unconditional — `macdrv_context_create` now always creates the CGL context (in forward-compatible mode, which is all macOS supports anyway).

**Apply the patch:**

```bash
# Backup
cp winemac.so winemac.so.bak-fwdcompat

# Patch: change byte at offset 0x329fb from 0x74 (je) to 0xeb (jmp)
printf '\xeb' | dd of=winemac.so bs=1 seek=$((0x329fb)) conv=notrunc

# Verify
xxd -s 0x329fb -l 2 winemac.so
# Should show: eb 20
```

#### Result

SDL3 games requesting OpenGL 3.2 Core Profile now successfully create a GL context. Combined with MoltenVK (Vulkan → Metal) and DXVK (D3D → Vulkan), the full range of rendering backends work under Wine on Apple Silicon.

---

## Architecture

```
Game.exe (Windows x86_64)
    │
    ├── OpenGL 3.2+  ──→  Wine opengl32  ──→  winemac.drv (patched) ──→  macOS CGL  ──→  GPU
    ├── Direct3D 11  ──→  DXVK           ──→  Vulkan  ──→  MoltenVK  ──→  Metal    ──→  GPU
    └── Vulkan       ──→  Wine Vulkan    ────────────────→  MoltenVK  ──→  Metal    ──→  GPU
```

Wine runs as an x86_64 process via Rosetta 2 on Apple Silicon.

## Credits

Moonshine builds on the work of many projects:

- [Whisky](https://github.com/Whisky-App/Whisky) by Isaac Marovitz — the original macOS Wine GUI
- [Wine](https://www.winehq.org/) and [Wine Staging](https://github.com/Gcenx/macOS_Wine_builds) — Windows compatibility layer
- [msync](https://github.com/marzent/wine-msync) by marzent — Wine synchronization primitive
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin — D3D-to-Vulkan translation
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup — Vulkan-to-Metal translation
- [Sparkle](https://github.com/sparkle-project/Sparkle) — macOS update framework
- [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers — Wine for macOS

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.
