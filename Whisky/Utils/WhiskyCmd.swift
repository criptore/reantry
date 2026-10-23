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
            let cmdPath = whiskyCmdURL.path(percentEncoded: false)
            // Older versions installed the CLI as /usr/local/bin/whisky, pointing to the binary
            // that was called WhiskyCmd. Repoint that link only when it is broken.
            let shell = "ln -fs '\(cmdPath)' /usr/local/bin/reantry"
                + " && if [ -L /usr/local/bin/whisky ] && [ ! -e /usr/local/bin/whisky ];"
                + " then ln -fs '\(cmdPath)' /usr/local/bin/whisky; fi"
            let script = "do shell script \"\(shell)\" with administrator privileges"

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
