<p align="center"><img src="docs/images/icon.png" width="128"></p>

<div align="center">

  # Reantry

  *Run Windows games and apps on your Apple Silicon Mac.*

  [![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
  [![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-green)](https://support.apple.com/en-us/116943)
  [![License](https://img.shields.io/badge/License-GPL--3.0-orange)](LICENSE)

</div>

Reantry is a native macOS app that runs Windows programs with Wine. You create
"bottles" (separate Windows environments), install programs into them and
launch them from a simple interface, without touching the terminal. It is based
on [Whisky](https://github.com/Whisky-App/Whisky) by Isaac Marovitz and on
[Moonshine](https://github.com/ybmeng/moonshine).

## Features

- **Wine on Apple Silicon.** Reantry downloads and installs Wine for you on
  first launch. Wine runs through Rosetta 2.
- **A graphics backend per bottle.** Choose D3DMetal (Apple's Direct3D to Metal
  layer), DXVK (Direct3D to Vulkan, on Metal through MoltenVK) or WineD3D
  (Wine's own Direct3D) in each bottle's configuration.
- **A Wine runtime per bottle.** Besides the default Wine, extra Wine builds can
  be installed side by side, and each bottle can use its own.
- **Steam support.** The default Wine is built from the CrossOver sources by
  CodeWeavers, which include the macOS and Steam fixes that upstream Wine lacks.
- **A command-line tool.** `ReantryCmd` creates and configures bottles, runs
  programs and shows logs from the terminal.
- **Update checks** for the app (Sparkle) and for the Wine libraries.

## Requirements

- A Mac with Apple Silicon (M1 or later).
- macOS 14 (Sonoma) or later.
- D3DMetal, as shipped in the current Wine libraries, needs macOS 26 or later.
  On older versions, use the DXVK or WineD3D backend.
- Reantry is tested on macOS 27.

## Install

1. Download `Reantry.app.zip` from the
   [latest release](https://github.com/criptore/reantry/releases/latest).
2. Unzip it (double-click in Finder) and drag **Reantry.app** to your
   **Applications** folder.
3. The app is not notarized, so macOS may refuse to open it or say it is
   "damaged". Remove the quarantine flag in Terminal, then open it again:

   ```bash
   xattr -cr /Applications/Reantry.app
   ```

   If macOS still refuses to open it, sign it locally:
   `codesign --force --deep --sign - /Applications/Reantry.app`.

Already using an earlier build named `Whisky.app` or `Moonshine.app`? It keeps
updating itself in place, and Reantry.app uses the same bottles, settings and
Wine libraries, so you can switch at any time.

## Getting started

### First launch

The setup wizard checks that Rosetta 2 is installed (and offers to install it
if needed), then downloads the Wine libraries from the
[`libraries` release](https://github.com/criptore/reantry/releases/tag/libraries)
and installs them. If that release cannot be reached, it installs the Gcenx
build of Wine Staging instead, which works for many programs but not for Steam.
You can open the wizard again at any time from the app menu with **Setup...**.

### Create a bottle

1. Click **Create Bottle**.
2. Give it a name, pick the Windows version (Windows 10 is a good default) and
   click **Create**.
3. In **Bottle Configuration**, choose the **Graphics Backend** for this
   bottle.
4. Click **Run...** and pick a Windows installer or program (usually an
   `.exe`). Installed programs show up under **Installed Programs**.

### Install Steam

1. Click **Create Bottle**, give it a name and turn on **Set up for Steam**.
   Reantry sets Windows 10, D3DMetal and Retina mode, downloads the Steam
   installer, installs Steam and pins it. The bottle shows the progress in the
   sidebar.
2. Start Steam from its pin. On its first start, Steam updates itself and
   then shows the login window.

To install Steam by hand instead, download `SteamSetup.exe` from
[store.steampowered.com](https://store.steampowered.com/about/), click
**Run...** in a Windows 10 bottle and pick it.

Steam asks Windows to start it at login. Reantry removes that entry before
it starts a program, because Wine would otherwise start a hidden Steam in the
background and keep the bottle busy.

If the Steam window stays black, try another graphics backend and keep the
log (**Open Logs Folder** in the File menu, `Cmd+L`) for a bug report.

## Command line

`ReantryCmd` works with the same bottles as the app. It is published as a
separate download on each release and also sits inside the app: choose
**Install Reantry CLI...** in the app menu to make it available as `reantry`
in your terminal.

```bash
reantry wine status                    # is Wine installed, and is there an update?
reantry create test --windows win10    # new bottle
reantry create games --steam           # new bottle with Steam installed
reantry config test --backend dxvk     # d3dmetal, dxvk or wined3d
reantry run --wait test game.exe       # run a program and wait for it
reantry logs --last                    # newest log
```

Run `reantry --help` for every command. To check a build without the GUI, see
[Testing without the GUI](docs/Releasing.md#testing-without-the-gui).

## Build from source

You need Xcode 16 or later. This script installs Homebrew and SwiftLint if
needed, clones the repository, builds the app, copies it to
`/Applications/Reantry.app` and opens it:

```bash
curl -fsSL https://raw.githubusercontent.com/criptore/reantry/main/scripts/build_from_source.sh | bash
```

From a clone, run `./scripts/build_from_source.sh` instead. In Xcode, open
`Whisky.xcodeproj` and build the `Whisky` scheme for the app or the
`WhiskyCmd` scheme for the command-line tool (the projects keep their original
names). `./scripts/build_dmg.sh` builds a `Reantry.dmg`.

Building the Wine libraries, publishing releases and the update feed are
described in [docs/Releasing.md](docs/Releasing.md).

## Known limitations

- **Steam needs the CrossOver-based Wine** (the `crossover` engine of the
  libraries). With the Wine Staging fallback, Steam's window stays black, and
  the Wine of Apple's Game Porting Toolkit is too old for the current Steam
  client.
- **Games with anti-cheat** (kernel-level or not supported by Wine) do not
  work.
- **macOS versions older than 26:** D3DMetal in the current libraries does not
  run there. This is fixed in the next libraries build; until then, use DXVK or
  WineD3D.

Wine logs are written to `~/Library/Logs/com.isaacmarovitz.Whisky/`, one file
per run. Please attach the log when you
[report a problem](https://github.com/criptore/reantry/issues).

## Credits and licence

Reantry is free software under the [GPL-3.0](LICENSE).

It is based on [Whisky](https://github.com/Whisky-App/Whisky) by Isaac
Marovitz and on [Moonshine](https://github.com/ybmeng/moonshine), and builds on:

- [Wine](https://www.winehq.org/) (LGPL 2.1 or later), and the
  [Wine Staging builds](https://github.com/Gcenx/macOS_Wine_builds) by Gcenx.
- The [CrossOver sources](https://media.codeweavers.com/pub/crossover/source/)
  published by CodeWeavers; their Wine part is LGPL 2.1 or later. CrossOver
  itself is a commercial product and is not part of Reantry.
- D3DMetal, from Apple's
  [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/).
  Its licence only allows free distribution, so archives that include it are
  published free of charge. It can also be added from your own copy with
  `scripts/install_gptk.sh`.
- [DXVK](https://github.com/doitsujin/dxvk), through
  [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx.
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by the Khronos Group.
- [Sparkle](https://github.com/sparkle-project/Sparkle) for app updates, and
  [Winetricks](https://github.com/Winetricks/winetricks).
