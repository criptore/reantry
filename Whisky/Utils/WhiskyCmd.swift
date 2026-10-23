//
//  WhiskyCmd.swift
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

class WhiskyCmd {
    static func install() async {
        let whiskyCmdURL = Bundle.main.url(forResource: "ReantryCmd", withExtension: nil)

        if let whiskyCmdURL = whiskyCmdURL {
            // Escape the path for an AppleScript string literal, then let
            // `quoted form of` quote it for the shell.
            let cmdPath = whiskyCmdURL.path(percentEncoded: false)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            // Older versions installed the CLI as /usr/local/bin/whisky, pointing to the binary
            // that was called WhiskyCmd. Repoint that link only when it is broken.
            let script = """
            set cmdPath to quoted form of "\(cmdPath)"
            set oldLink to "/usr/local/bin/whisky"
            set isBroken to "[ -L " & oldLink & " ] && [ ! -e " & oldLink & " ]"
            set fixOldLink to "if " & isBroken & "; then ln -fs " & cmdPath & " " & oldLink & "; fi"
            set linkCmd to "mkdir -p /usr/local/bin && ln -fs " & cmdPath & " /usr/local/bin/reantry && " & fixOldLink
            do shell script linkCmd with administrator privileges
            """

            var error: NSDictionary?
            // Use AppleScript because somehow in 2023 Apple doesn't have good privileged file ops APIs
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                if let error = error {
                    print(error)
                    if let description = error["NSAppleScriptErrorMessage"] as? String {
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.messageText = String(localized: "alert.message")
                            alert.informativeText = String(localized: "alert.info")
                                + description
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: String(localized: "button.ok"))
                            alert.runModal()
                        }
                    }
                }
            }
        }
    }
}
