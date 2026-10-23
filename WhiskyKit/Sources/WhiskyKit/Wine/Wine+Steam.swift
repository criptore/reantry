//
//  Wine+Steam.swift
//  WhiskyKit
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
import os.log

extension Wine {
    /// The key whose values Windows starts at login, and `wineboot` whenever it runs without `--init`
    private static let runKey = #"HKCU\Software\Microsoft\Windows\CurrentVersion\Run"#

    /// Deletes the "Steam" value of the Run key, which the Steam installer and Steam itself add.
    ///
    /// Wine runs that key from `wineboot` (`wineboot -u` for one). Steam then starts hidden with `-silent`
    /// and keeps the bottle busy, so `wineboot` and the commands that wait for the bottle never return.
    /// Steam still starts normally from its pin.
    public static func removeSteamAutostart(bottle: Bottle) async throws {
        try await runWine(["reg", "delete", runKey, "/v", "Steam", "/f"], bottle: bottle)
    }

    /// Deletes the "Steam" value of the Run key when the registry of the bottle holds it.
    /// The registry file is read directly, so the bottles without the value start no Wine process.
    public static func removeSteamAutostartIfPresent(bottle: Bottle) async {
        guard hasSteamAutostart(bottle: bottle) else { return }
        do {
            try await removeSteamAutostart(bottle: bottle)
        } catch {
            Logger.wineKit.error("Failed to remove the Steam autostart of \(bottle.settings.name): \(error)")
        }
    }

    /// Whether `user.reg` holds the "Steam" value of the Run key. The file lags behind a running wineserver,
    /// which saves the registry from time to time and when it exits.
    static func hasSteamAutostart(bottle: Bottle) -> Bool {
        guard let data = try? Data(contentsOf: bottle.url.appending(path: "user.reg")),
              let registry = String(bytes: data, encoding: .utf8) else { return false }

        var inRunKey = false
        for line in registry.lowercased().split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") {
                inRunKey = line.hasPrefix(#"[software\\microsoft\\windows\\currentversion\\run]"#)
            } else if inRunKey, line.hasPrefix(#""steam"="#) {
                return true
            }
        }
        return false
    }
}
