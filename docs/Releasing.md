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
`~/Library/Application Support/<bundle id>/` and must contain:

```
Libraries/
├── Wine/                    # bin/, lib/, share/
├── DXVK/                    # x64/ and x32/ DLLs, copied into bottles when DXVK is enabled
├── winetricks
├── verbs.txt
└── WhiskyWineVersion.plist  # version dict: major, minor, patch, preRelease, build
```

`WhiskyWineVersion.plist` is also uploaded next to the archive. The app compares
it with the installed copy at launch and offers to reinstall when the published
version is higher, so bump it every time the archive changes.

Publish or replace the assets with:

```bash
gh release create libraries --title "Wine libraries" --notes "Wine libraries used by the app" || true
gh release upload libraries Libraries.tar.gz WhiskyWineVersion.plist --clobber
```

Until this release exists, the setup wizard falls back to the Gcenx Wine
Staging 11.2 build.

## Sparkle signing key

Updates are signed with an EdDSA key. The public half lives in `SUPublicEDKey`
in `Whisky/Info.plist`; the private half must never be committed.

The key currently in `Info.plist` belongs to the original Whisky project, so no
update can be published until it is replaced:

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
