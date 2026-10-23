//
//  ProgramShortcut.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import WhiskyKit

class ProgramShortcut {
    /// Where the command line tool lies in the app bundle.
    private static let cmdPathInBundle = "Contents/Resources/ReantryCmd"

    /// Asks where to save a shortcut of the program, `~/Applications` by default, then creates it there.
    @MainActor
    static func chooseLocation(for program: Program) {
        let panel = NSSavePanel()
        if let applications = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
            panel.directoryURL = applications
        }
        panel.message = String(localized: "shortcut.panel.message")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = true
        panel.nameFieldStringValue = defaultName(of: program) + ".app"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let name = url.deletingPathExtension().lastPathComponent
            Task(priority: .userInitiated) {
                await createShortcut(program, app: url, name: name)
            }
        }
    }

    /// The name of the program's pin, or else its file name without the extension.
    private static func defaultName(of program: Program) -> String {
        if let pin = program.bottle.settings.pins.first(where: { $0.url == program.url }), !pin.name.isEmpty {
            return pin.name
        }
        return program.url.deletingPathExtension().lastPathComponent
    }

    /// Creates an app bundle that launches the program with the command line tool of Reantry, which reads the
    /// settings of the bottle and of the program at each launch.
    static func createShortcut(_ program: Program, app: URL, name: String) async {
        let contents = app.appending(path: "Contents")
        let macos = contents.appending(path: "MacOS")
        do {
            // The save panel already asked whether to replace it, the trash keeps it recoverable
            if FileManager.default.fileExists(atPath: app.path(percentEncoded: false)) {
                try FileManager.default.trashItem(at: app, resultingItemURL: nil)
            }
            try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

            let scriptUrl = macos.appending(path: "launch")
            try launchScript(for: program).write(to: scriptUrl, atomically: false, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: scriptUrl.path(percentEncoded: false))

            // Set the category for Game Mode
            let info: [String: Any] = [
                "CFBundleExecutable": "launch",
                "CFBundleIdentifier": "\(bundleIdentifier).shortcut.\(UUID().uuidString)",
                "CFBundleName": name,
                "CFBundlePackageType": "APPL",
                "CFBundleSupportedPlatforms": ["MacOSX"],
                "LSMinimumSystemVersion": "14.0",
                "LSApplicationCategoryType": "public.app-category.games"
            ]
            let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try infoData.write(to: contents.appending(path: "Info.plist"))

            if let icon = await icon(of: program) {
                NSWorkspace.shared.setIcon(icon,
                                           forFile: app.path(percentEncoded: false),
                                           options: NSWorkspace.IconCreationOptions())
            }
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            print(error)
        }
    }

    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.isaacmarovitz.Whisky"
    }

    /// A script that runs the program with `reantry run`, the `ReantryCmd` binary of the app. The tool is looked
    /// up by the bundle identifier of Reantry when the app moved since the shortcut was made, skipping the copies
    /// in the Trash or on other volumes. When the tool fails, an alert explains it, then Reantry opens.
    private static func launchScript(for program: Program) -> String {
        let cmdURL = Bundle.main.url(forResource: "ReantryCmd", withExtension: nil)
            ?? Bundle.main.bundleURL.appending(path: cmdPathInBundle)
        let query = "kMDItemCFBundleIdentifier == '\(bundleIdentifier)'"
        let bottlePath = quoted(program.bottle.url.path(percentEncoded: false))
        let programPath = quoted(program.url.path(percentEncoded: false))
        let alert = "display alert \(appleScriptString(String(localized: "shortcut.error.title")))"
            + " message \(appleScriptString(String(localized: "shortcut.error.message")))"

        return """
        #!/bin/bash
        CMD=\(quoted(cmdURL.path(percentEncoded: false)))
        if [ ! -x "$CMD" ]; then
            APP=""
            USER_APP=""
            OTHER_APP=""
            while IFS= read -r FOUND; do
                case "$FOUND" in
                    "$HOME"/.Trash/*|/Volumes/*) ;;
                    /Applications/*) APP="$FOUND"; break ;;
                    "$HOME"/Applications/*) [ -z "$USER_APP" ] && USER_APP="$FOUND" ;;
                    *) [ -z "$OTHER_APP" ] && OTHER_APP="$FOUND" ;;
                esac
            done < <(/usr/bin/mdfind \(quoted(query)))
            APP="${APP:-${USER_APP:-$OTHER_APP}}"
            CMD="$APP/\(cmdPathInBundle)"
        fi
        if [ -x "$CMD" ]; then
            if "$CMD" run --wait \(bottlePath) \(programPath); then
                exit 0
            fi
            /usr/bin/osascript -e \(quoted(alert))
        fi
        exec /usr/bin/open -b \(quoted(bundleIdentifier))

        """
    }

    /// Quotes a string for AppleScript.
    private static func appleScriptString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// Quotes a string for the shell.
    private static func quoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The icon of the executable, or else its Quick Look thumbnail.
    private static func icon(of program: Program) async -> NSImage? {
        if let icon = program.peFile?.bestIcon() {
            return icon
        }
        let request = QLThumbnailGenerator.Request(fileAt: program.url,
                                                   size: CGSize(width: 512, height: 512),
                                                   scale: 2.0,
                                                   representationTypes: .thumbnail)
        let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return thumbnail?.nsImage
    }
}
