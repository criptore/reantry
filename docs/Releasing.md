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
├── Wine/                    # bin/, lib/, share/ (D3DMetal merged into lib/ when built with --gptk)
├── DXVK/                    # x64/ and x32/ DLLs, copied into bottles using the DXVK backend
├── WineD3D/                 # Wine's Direct3D DLLs replaced by D3DMetal, for the WineD3D backend (--gptk only)
├── winetricks
├── verbs.txt
└── WhiskyWineVersion.plist  # version dict: major, minor, patch, preRelease, build
```

`WhiskyWineVersion.plist` is also uploaded next to the archive. The app compares
it with the installed copy at launch and offers to reinstall when the published
version is higher, so it must increase every time the archive changes.

### Building

`scripts/build_libraries.sh` assembles the archive on a Mac from:

| Component | Source | Default |
|-----------|--------|---------|
| Wine | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) | Wine Staging 11.18 |
| MoltenVK | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) | v1.4.2 |
| DXVK | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | v1.10.3-20230507 (async) |
| winetricks | [Winetricks/winetricks](https://github.com/Winetricks/winetricks) | 20260125 |
| D3DMetal | Apple Game Porting Toolkit (optional) | — |

```bash
# Without D3DMetal
./scripts/build_libraries.sh

# With D3DMetal, from the mounted Game Porting Toolkit DMG
./scripts/build_libraries.sh --gptk "/Volumes/Evaluation environment for Windows games 3.0"

# Build and upload to the "libraries" release (needs `gh auth login`)
./scripts/build_libraries.sh --gptk "/Volumes/..." --publish
```

Versions can be overridden with `WINE_VERSION`, `WINE_FLAVOR` (`staging` or
`devel`), `DXVK_VERSION`, `MOLTENVK_VERSION` and `WINETRICKS_VERSION`. The
output is written to `build/`, which is ignored by git.

Until the `libraries` release exists, the setup wizard falls back to the
Gcenx Wine Staging 11.2 build.

### Before publishing a new archive

Test it on a Mac first: point a local build at it by copying the extracted
`Libraries` folder into `~/Library/Application Support/<bundle id>/`, then
run a DirectX 11 game with each graphics backend.

Known points to check:

- **D3DMetal and upstream Wine.** D3DMetal was designed for CrossOver's Wine.
  With the Gcenx upstream builds it may not load. If it does not, either
  build Wine from the CrossOver sources
  (https://www.codeweavers.com/crossover/source) and package it in
  `Libraries/Wine` by hand, or ship without `--gptk` (the D3DMetal backend
  then uses Wine's builtin Direct3D).
- **D3DMetal licence.** Read the licence in the Game Porting Toolkit DMG
  before redistributing its `redist` folder.
- **OpenGL 3.2+ patch.** The installer only patches `winemac.so` for the Gcenx
  11.2 fallback, since the byte offset is specific to that binary. Check
  whether SDL3/OpenGL 3.2 games still need it on the new Wine version.

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
