# Releasing

Everything the app downloads is served from the GitHub Releases of the
repository set in `AppDistribution.repository`
(`WhiskyKit/Sources/WhiskyKit/AppDistribution.swift`). The Sparkle feed is the
`appcast.xml` file at the root of the `main` branch.

| What | Where |
|------|-------|
| Wine libraries | Release tagged `libraries`, assets `Libraries.tar.gz` and `WhiskyWineVersion.plist` |
| App builds | One release per version (`v2.8.0`, ...), asset `Moonshine.zip` (and the DMG) |
| Update feed | `https://raw.githubusercontent.com/criptore/reantry/main/appcast.xml` (`SUFeedURL` in `Whisky/Info.plist`) |

## Wine libraries

`Libraries.tar.gz` is extracted into
`~/Library/Application Support/<bundle id>/` and contains:

```
Libraries/
├── Wine/                    # bin/, lib/, share/ (with gptk, bin/wine and bin/wine-preloader are symlinks)
├── DXVK/                    # x64/ and x32/ DLLs, copied into bottles using the DXVK backend
├── WineD3D/                 # Wine's Direct3D DLLs replaced by D3DMetal, for the WineD3D backend (staging or crossover engine with --gptk only)
├── winetricks
├── verbs.txt
└── WhiskyWineVersion.plist  # version dict: major, minor, patch, preRelease, build
```

`WhiskyWineVersion.plist` is also uploaded next to the archive. The app compares
it with the installed copy at launch and offers to reinstall when the published
version is higher, so it must increase every time the archive changes.

### Engines

`scripts/build_libraries.sh` builds the archive with one of four Wine engines,
selected with `--engine`:

| Engine | Source | Notes |
|--------|--------|-------|
| `gptk` | [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit) 3.0-3 | CrossOver based, D3DMetal included |
| `staging` | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) Wine Staging 11.18 | Upstream Wine, no D3DMetal unless merged with `--gptk` |
| `sikarugir` | [Sikarugir-App/Engines](https://github.com/Sikarugir-App/Engines) `WS12WineSikarugir11.0_1` | Wine 11.0 (unified wow64) with macOS patches and DXMT's `winemetal.dll` |
| `crossover` (default) | Built locally from the [CrossOver sources](https://media.codeweavers.com/pub/crossover/source/) with `scripts/build_crossover_wine.sh`, passed with `--wine-dir` | CrossOver's Wine (macOS and Steam fixes), D3DMetal merged with `--gptk` |

`crossover` is the default: CrossOver's Wine (macOS and Steam fixes) with D3DMetal merged from a mounted Game Porting Toolkit when one is found. `gptk` is the alternative that is CrossOver based and already includes
D3DMetal (`lib/external/D3DMetal.framework`, `libd3dshared.dylib` and the
D3DMetal `d3d11`, `d3d12`, `dxgi`, `d3d10core`, `nvapi64` and `atidxx64`
DLLs). The upstream Gcenx Wine Staging build has neither D3DMetal nor DXVK
support out of the box, and Steam's CEF UI renders as a black window on it.

The Game Porting Toolkit archive ships `wine64` but no `wine`, while the app
always runs `<Libraries/Wine/bin>/wine` (and Winetricks uses `WINE=wine`). The
script therefore creates a relative symlink `bin/wine -> wine64`. Symlinks
survive both `tar -czf` when building and `tar -xf` in `WhiskyWineInstaller`.

When started as `wine`, the loader looks for `wine-preloader`, but the archive
only ships `wine64-preloader`. Without it 32-bit support breaks: new prefixes
get an empty `syswow64` and 32-bit programs fail. The script therefore also
creates the relative symlink `bin/wine-preloader -> wine64-preloader`. Tested on
a Mac: with the link `syswow64` gets 717 files and 32-bit `cmd.exe` runs.

**GPTK 3.0-3 and Steam.** The Wine inside Game Porting Toolkit 3.0-3 reports
`wine-7.7 (Game Porting Toolkit 1.1)`. It is too old for the current 64-bit
Steam client, which crashes on a missing `DeleteFileTransactedW`. Use the
`crossover` engine when Steam is needed: it is the engine tested with Steam,
built from the CrossOver 26.3 sources with the `steamwebhelper` patch and
GnuTLS (see "Building Wine from the CrossOver sources" below), packaged with
D3DMetal through `--gptk`. Steam and the DirectX 11 game SPAM run with it on
macOS 27.

With `gptk` the script skips the MoltenVK replacement (MoltenVK is inside
`lib/GStreamer.framework`) and rejects `--gptk`, since D3DMetal is already
included. There is no `WineD3D` folder either, because the original wined3d
DLLs are not in the archive: the WineD3D backend uses D3DMetal's builtin DLLs
with this engine. DXVK, winetricks and `verbs.txt` are bundled by all engines.

The `sikarugir` archive extracts to `wswine.bundle/{bin,lib,share,version,dxmt_extescape}`.
`bin` has `wine` and `wineserver`, a unified wow64 Wine 11.0 with the macOS
patches and DXMT's `winemetal.dll`. The script moves the whole bundle to
`Libraries/Wine`, so `version` and `dxmt_extescape` stay next to `bin`. No
symlinks are needed and MoltenVK is not replaced. `--gptk` is rejected, and
there is no `WineD3D` folder. The engine version is set with `SIKARUGIR_ENGINE`
(default `WS12WineSikarugir11.0_1`).

The default engine is now `crossover`: it needs a Wine folder built locally with
`scripts/build_crossover_wine.sh`, and merges D3DMetal from a mounted Game Porting Toolkit when one is found.

### Building

| Component | Source | Default |
|-----------|--------|---------|
| Wine (`gptk`) | [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit) | Game Porting Toolkit 3.0-3 |
| Wine (`staging`) | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) | Wine Staging 11.18 |
| Wine (`sikarugir`) | [Sikarugir-App/Engines](https://github.com/Sikarugir-App/Engines) | WS12WineSikarugir11.0_1 |
| Wine (`crossover`) | Folder built by `scripts/build_crossover_wine.sh` | newest CrossOver sources |
| MoltenVK (`staging`, `crossover`) | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) | v1.4.2 |
| DXVK | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | v1.10.3-20230507 (async) |
| winetricks | [Winetricks/winetricks](https://github.com/Winetricks/winetricks) | 20260125 |
| D3DMetal (`staging` and `crossover`) | Apple Game Porting Toolkit (optional) | none |

```bash
# Default: locally built CrossOver Wine with D3DMetal when a Game Porting Toolkit is mounted
./scripts/build_libraries.sh

# Wine Staging without D3DMetal
./scripts/build_libraries.sh --engine staging

# Wine 11.0 with macOS patches and DXMT (Sikarugir)
./scripts/build_libraries.sh --engine sikarugir

# Wine Staging with D3DMetal, from the mounted Game Porting Toolkit DMG
./scripts/build_libraries.sh --engine staging --gptk "/Volumes/Evaluation environment for Windows games 3.0"

# Wine built from the CrossOver sources (see below), with D3DMetal
./scripts/build_libraries.sh --engine crossover --wine-dir build/crossover-wine-26.3.0 \
    --gptk "/Volumes/Evaluation environment for Windows games 3.0"

# Build and upload to the "libraries" release (needs `gh auth login`)
./scripts/build_libraries.sh --publish
```

Versions can be overridden with `GPTK_VERSION`, `SIKARUGIR_ENGINE`, `WINE_VERSION`, `WINE_FLAVOR`
(`staging` or `devel`), `DXVK_VERSION`, `MOLTENVK_VERSION` and
`WINETRICKS_VERSION`. The output is written to `build/`, which is ignored by git.

### Building Wine from the CrossOver sources

CodeWeavers publishes the source of every CrossOver release at
https://media.codeweavers.com/pub/crossover/source/ as
`crossover-sources-<version>.tar.gz`. The archive contains a `wine/` folder,
CrossOver's Wine tree with the macOS and Steam (CEF) fixes that upstream Wine
and the Gcenx builds lack, next to other projects that are not used here.
`scripts/build_crossover_wine.sh` builds that `wine/` folder on a Mac and
produces a self-contained Wine folder for the `crossover` engine.

Why: with Gcenx's upstream Wine Staging 11.18 the 64-bit Steam client starts but
`steamwebhelper`'s login window stays black whatever the Direct3D path (wined3d
on GL or Vulkan, DXVK, software, virtual desktop): CEF never presents into its
window. The Wine of Game Porting Toolkit 3.0-3 (`wine-7.7`) is too old for the
current Steam client, and the Sikarugir engine starts nothing outside its own
wrapper. CrossOver supports Steam on macOS officially.

**Prerequisites**

- An Apple Silicon Mac (Intel works too) on macOS 14 or later, with Rosetta 2
  (`softwareupdate --install-rosetta --agree-to-license`).
- The Xcode Command Line Tools (`xcode-select --install`).
- An x86_64 Homebrew in `/usr/local`, next to the native one in `/opt/homebrew`:
  `arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`.
  Wine's Unix side runs as x86_64 under Rosetta 2, so the libraries it loads
  (FreeType, GnuTLS, SDL2) must be x86_64; the arm64 Homebrew cannot provide
  them. The script installs `bison flex pkgconf gettext freetype gnutls sdl2`
  with it. Without an x86_64 Homebrew, see "Prebuilt libraries (`DEPS_DIR`)"
  below.
- About 15 GB of free disk space in the work folder (`~/crossover-wine-build` by
  default: source archive, extracted tree, llvm-mingw, build objects) plus about
  1.5 GB for the result.
- Time: 30 to 90 minutes, mostly `make`, which runs under Rosetta 2. The
  Homebrew step takes longer when bottles are missing and formulae are built
  from source.

**Recipe.** It follows Gcenx's MacPorts Portfiles
([macports-wine](https://github.com/Gcenx/macports-wine), `emulators/wine-devel`,
`emulators/wine-stable`, `cross/llvm-mingw`) and the configure options listed in
the [macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) README:
wow64 with `--enable-archs=i386,x86_64 --enable-win64`, PE files built with
llvm-mingw (`--with-mingw=llvm-mingw`, which makes configure use
`x86_64-w64-mingw32-clang` and `i686-w64-mingw32-clang` from the toolchain's
`bin/`, placed last in `PATH` so Apple's `clang` builds the Unix side; same
release as the Portfile),
`MACOSX_DEPLOYMENT_TARGET=14.0`, `--disable-tests`, CoreAudio, CUPS, FreeType,
GnuTLS, OpenCL, PCSC, pcap, SDL2 and Vulkan (MoltenVK) on, X11, Wayland,
fontconfig, D-Bus, Kerberos, GStreamer and FFmpeg off, and `make install-lib`.
CrossOver's `winedbg` needs a `distversion.h` that is generated by CodeWeavers'
build system and missing from the archive, so the script writes one.

**Patches.** Every `scripts/patches/crossover/*.patch` (unified diff relative to
the `wine/` folder) is applied to the extracted tree, in sorted order, on every
run: a patch already in the tree is skipped, and the build stops when one
applies neither forward nor in reverse (it was made for another CrossOver
version and must be updated). There is one patch today:
`kernelbase-steamwebhelper-in-process-gpu.patch`. CrossOver adds
`--in-process-gpu` to the main `steamwebhelper.exe` process in its closed
code; the public sources do not, and Steam's CEF window stays black. The patch
makes `CreateProcessInternalW` append `--no-sandbox --in-process-gpu
--disable-gpu` to a `steamwebhelper.exe` command line that has no `--type=`
(the child processes) and no `--in-process-gpu` yet. It was made against
CrossOver 26.3.0.

**GnuTLS is required.** Without the GnuTLS headers configure only prints a
warning and builds `bcrypt`, `crypt32` and `secur32` without GnuTLS: no ECDSA,
the ECC root certificates are left out of the bottle's root store, and TLS fails
in games. The script therefore stops after configure when
`include/config.h` in the build folder has no `SONAME_LIBGNUTLS` or
`SONAME_LIBFREETYPE`, and points at `config.log`. A build folder configured
without them is configured again on the next run (in place, so `make` only
rebuilds what changed). The end of the log shows the GnuTLS and FreeType
libraries that were found.

**Prebuilt libraries (`DEPS_DIR`).** Without an x86_64 Homebrew, set `DEPS_DIR`
to a folder holding the x86_64 dylibs (FreeType, GnuTLS, GMP, SDL2 and their
dependencies) at its top level or in `lib/`. Configure still needs the GnuTLS
and FreeType headers, and finds them in this order:

1. pkg-config, when `DEPS_DIR/lib/pkgconfig` exists (the x86_64 Homebrew's
   pkg-config if there is one, otherwise the native one, limited to that
   folder); `DEPS_DIR/include` and `DEPS_DIR/lib` are added to the search
   paths;
2. `DEPS_DIR/include/gnutls/gnutls.h` and `DEPS_DIR/include/freetype2/ft2build.h`;
3. the native Homebrew (`/opt/homebrew`, or `ARM_BREW_PREFIX`): only the
   `gnutls/` and `freetype2/` header folders are copied into the work folder.
   These headers are the same for arm64 and x86_64 (the generated parts are
   the version numbers and the `iovec` type; FreeType derives type sizes from
   compiler macros). If they are missing, run `brew install gnutls freetype`
   with the native Homebrew.

In cases 2 and 3 the script links `lib<name>.dylib` to the x86_64 library from
`DEPS_DIR` in a private folder and passes `GNUTLS_CFLAGS`/`GNUTLS_LIBS` and
`FREETYPE_CFLAGS`/`FREETYPE_LIBS` to configure. The headers are only used at
build time; Wine opens the bundled x86_64 library with `dlopen()` at run time.
Use headers of the same GnuTLS major version as the library (3.x for
`libgnutls.30.dylib`).

`DEPS_DIR` may contain spaces (for instance a folder under
`~/Library/Application Support`): the paths given to configure go through a
link in the work folder. The only case that stops the build is pkg-config
returning flags inside such a `DEPS_DIR`, since the `.pc` files name their own
prefix. The work folder itself (`--work-dir`) must not contain spaces:
autoconf refuses a source or build folder with one.

Without an x86_64 Homebrew, the build tools come from the native Homebrew
too: Wine needs bison 3.0 or newer and Apple's `/usr/bin/bison` is 2.3. The
script puts `/opt/homebrew/opt/bison/bin` and `/opt/homebrew/opt/flex/bin`
(under `ARM_BREW_PREFIX`) first in `PATH` when they exist, and stops before
the build when `bison --version` is older than 3. So for this mode install,
with the native Homebrew:

```bash
brew install bison flex gnutls freetype
```

The libraries are copied into `lib/` with `@rpath` install names, configure
records `@rpath/<name>` for the libraries Wine opens with `dlopen()`, and every
Unix module gets an `LC_RPATH` to `lib/`. The script then checks with `otool -L`
that binaries only refer to `/usr/lib/`, `/System/` and `@rpath`/`@loader_path`
names (so nothing from Homebrew, MacPorts or `DEPS_DIR`), and runs
`wine --version`, `wineboot --init` in a temporary prefix and `cmd /c ver` (64
and 32-bit) with `DYLD_FALLBACK_LIBRARY_PATH=/usr/lib`, so Homebrew's libraries
cannot be picked up by accident. wine-mono and wine-gecko, in the versions the
tree asks for, are bundled into `share/wine` (skip with `--no-addons`).

**Running it**

```bash
# Newest CrossOver version listed on the CodeWeavers server
./scripts/build_crossover_wine.sh

# A given version
CROSSOVER_VERSION=25.1.1 ./scripts/build_crossover_wine.sh

# Without an x86_64 Homebrew: prebuilt x86_64 libraries, headers and bison/flex from the
# native Homebrew
brew install bison flex gnutls freetype
DEPS_DIR=/path/to/x86_64-libs CROSSOVER_VERSION=26.3.0 ./scripts/build_crossover_wine.sh
```

The log goes to `~/crossover-wine-build/build.log`. When a step fails, the
script prints the failed command; fix the cause and run it again: finished
steps (download, extraction, toolchain, libraries, configure with the same
options) are skipped and `make` continues where it stopped. The Homebrew check
runs every time, and the libraries are bundled again when their source changes
(another `DEPS_DIR`, or switching between `DEPS_DIR` and Homebrew). `--clean`
starts the version over. When the listing cannot be read, the script falls back to
`CROSSOVER_FALLBACK_VERSION` in the script; check that this version still
exists on the server before relying on it. The result is written to
`build/crossover-wine-<version>/` (`bin/wine`, `bin/wineserver`, `lib/`, `share/`).

Then package it, with D3DMetal from the Game Porting Toolkit DMG:

```bash
./scripts/build_libraries.sh --engine crossover --wine-dir build/crossover-wine-<version> \
    --gptk "/Volumes/Evaluation environment for Windows games 3.0"
```

**Testing Steam.** Install the archive with `WhiskyCmd`, then install and
start Steam in a new bottle:

```bash
CLI=./WhiskyCmd   # path to the built WhiskyCmd binary
$CLI wine install --file build/Libraries.tar.gz
$CLI create steam-test --windows win10
curl -fLo SteamSetup.exe https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe
$CLI run --wait steam-test SteamSetup.exe /S
$CLI list         # shows the path of the steam-test bottle
$CLI run steam-test "<bottle path>/drive_c/Program Files (x86)/Steam/steam.exe"
```

Steam updates itself first, then opens the login window. It works when the
login window shows the QR code and the fields instead of a black rectangle. Try
each graphics backend (`$CLI config steam-test --backend d3dmetal|dxvk|wined3d`).
If the window stays black, start Steam with `-cef-disable-gpu` to tell a CEF
GPU problem apart from a presentation problem, and keep the `steamwebhelper`
lines of the log (`$CLI logs --last`).

**Root certificates after a rebuild with GnuTLS.** A new bottle gets the full
root store. An existing bottle created with a build that lacked GnuTLS repairs
itself: Wine's `crypt32` (`dlls/crypt32/rootstore.c`) imports the macOS roots
the first time a process opens the machine `Root` store (any TLS connection or
certificate check does). It adds the Windows roots it ships, then checks each
macOS root it does not have yet and writes the accepted ones to
`HKLM\Software\Microsoft\SystemCertificates\Root\Certificates`, remembering them
under `HKLM\Software\Wine\HostImportedCertificates`. Roots that were rejected
before (the ECC roots, for lack of ECDSA) were neither stored nor remembered,
so they are checked again by the next process. Stop the bottle's processes with
`wineserver -k` so the next start uses the new build. To start from a clean
store anyway (this also drops roots that programs added to the bottle), delete
the key; it is rebuilt the next time a program opens the store:

```bash
WINEPREFIX="<bottle path>" <wine folder>/bin/wine reg delete 'HKLM\Software\Microsoft\SystemCertificates\Root' /f
WINEPREFIX="<bottle path>" <wine folder>/bin/wineserver -k
```

`wineboot -u` is not needed for this: the import does not run at boot but in
whichever process first opens the store.

**Licence.** The Wine part of the CrossOver sources is free software under the
GNU LGPL 2.1 or later, like upstream Wine; the script copies `COPYING.LIB`,
`LICENSE` and `AUTHORS` into `share/doc/wine/` with a `SOURCE.txt` that names
the source archive. When publishing an archive built from it, keep those files
and keep the matching source available (the CodeWeavers URL in `SOURCE.txt`).
Other folders of the source archive have their own licences and are not used.
CrossOver itself (the app, its bottle management and its D3DMetal copy) is
commercial and is not part of this build.

### Version scheme

The version in `WhiskyWineVersion.plist` defaults to the build date as
`YYYY.M.(D*100)` without leading zeros (for example `2026.10.2000` on 20 October).
It is higher than the `11.18.0` that the fallback installs, so installed apps offer
the update, and it increases with every build on a later day. Pass
`--version X.Y.Z` to override it; the script only checks the `X.Y.Z` shape
(numbers only). For another build on the same day, add one to the patch number
(`2026.10.2001`, `2026.10.2002`, ...): the next day's default (`2026.10.2100`)
is still higher.

Until the `libraries` release exists, the setup wizard falls back to the
Gcenx Wine Staging build set in `AppDistribution.fallbackWineVersion` (11.18).

### Before publishing a new archive

Test it on a Mac first: point a local build at it by copying the extracted
`Libraries` folder into `~/Library/Application Support/<bundle id>/`, then
run a DirectX 11 game with each graphics backend.

Known points to check:

- **D3DMetal licence.** Do not ship Apple's D3DMetal in a published
  archive: Apple's Game Porting Toolkit licence is non-commercial and its
  components must not be separated from the toolkit for redistribution.
  Publish with `--engine crossover` (or `staging`) and without `--gptk`;
  each user then provides their own Game Porting Toolkit to enable
  D3DMetal/WineD3D. With `--engine gptk`, D3DMetal is already included in
  that engine's own archive and remains subject to the same restriction.
- **Sikarugir licence.** The README of
  [Sikarugir-App/Engines](https://github.com/Sikarugir-App/Engines) contains
  only a title and states no licence, and the repository declares none. Wine
  itself is LGPL 2.1, but check the licences of the macOS patches and of DXMT
  with the Sikarugir authors before publishing an archive built from it.
- **Steam.** Check that Steam's window renders (no black CEF UI), see
  "Testing Steam" above; the `crossover` engine with D3DMetal is the one
  tested with Steam.
- **OpenGL 3.2+ patch.** The `winemac.so` patch that let SDL3 games create
  OpenGL 3.2+ contexts used a byte offset specific to the Gcenx 11.2 build,
  which Gcenx no longer hosts, so it is no longer applied. Check whether
  SDL3/OpenGL 3.2 games still need it on the current Wine version.

## Sparkle signing key

Updates are signed with an EdDSA key. The public half lives in `SUPublicEDKey`
in `Whisky/Info.plist`; the private half must never be committed.

To set up a new key (only needed if the current one is lost or rotated):

1. Get the Sparkle tools. Either download `Sparkle-2.x.tar.xz` from
   https://github.com/sparkle-project/Sparkle/releases, or use the copy Xcode
   fetched with the package:
   `~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`.
2. Run `./bin/generate_keys`. The private key is stored in your login Keychain
   and the public key is printed.
3. Put the printed public key in `SUPublicEDKey` in `Whisky/Info.plist`.
4. Back up the private key somewhere safe (password manager):
   `./bin/generate_keys -x sparkle_private_key.pem`. On another Mac, import it
   with `./bin/generate_keys -f sparkle_private_key.pem`.

If the private key is lost, users have to download the next version manually.

## Publishing an app update

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
   Sparkle compares `CURRENT_PROJECT_VERSION` (`CFBundleVersion`), so it must
   always increase.
2. Build the app and zip it:
   `ditto -c -k --sequesterRsrc --keepParent Moonshine.app Moonshine.zip`
3. Sign the archive: `./bin/sign_update Moonshine.zip`. It prints
   `sparkle:edSignature="..." length="..."`.
4. Create the GitHub release `vX.Y.Z` and upload `Moonshine.zip`.
5. Add an item to `appcast.xml` and push it to `main`:

```xml
<item>
    <title>X.Y.Z</title>
    <pubDate>Mon, 20 Oct 2026 12:00:00 +0000</pubDate>
    <sparkle:version>44</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <enclosure
        url="https://github.com/criptore/reantry/releases/download/vX.Y.Z/Moonshine.zip"
        type="application/octet-stream"
        sparkle:edSignature="..."
        length="..." />
</item>
```

`generate_appcast` can produce the same item automatically when pointed at a
folder holding the zip:
`./bin/generate_appcast --download-url-prefix https://github.com/criptore/reantry/releases/download/vX.Y.Z/ updates/`

## Testing without the GUI

`WhiskyCmd` (see the Command line section of the README) can create bottles, change their settings and run
Wine, so a build can be checked from a terminal. This script runs `winecfg` once per graphics backend and checks
in the newest log that the backend was applied:

```bash
#!/bin/bash
set -euo pipefail
CLI=./WhiskyCmd   # path to the built WhiskyCmd binary

$CLI wine status
$CLI wine install            # skip when Wine is already installed
$CLI create backend-test --windows win10

for backend in d3dmetal dxvk wined3d; do
    echo "== $backend"
    $CLI config backend-test --backend "$backend"
    $CLI exec backend-test -- winecfg -v win10   # without -v, winecfg opens its window and waits
    log=$($CLI logs --last)
    echo "$log" | grep -i "Graphics Backend: $backend"
    echo "$log" | grep "WINEDLLOVERRIDES" || echo "no WINEDLLOVERRIDES (expected for d3dmetal)"
done

$CLI exec backend-test -- cmd /c ver
$CLI delete backend-test
```

Expect no `WINEDLLOVERRIDES` with `d3dmetal`, a `WINEDLLOVERRIDES` of `d3d10core,d3d11,d3d9,dxgi=n,b` with `dxvk`, and the Direct3D DLLs of the `WineD3D` folder with `wined3d`. `exec` returns wine's exit
status, so a failing command fails the script.
