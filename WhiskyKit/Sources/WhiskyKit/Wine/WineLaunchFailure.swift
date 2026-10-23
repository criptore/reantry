//
//  WineLaunchFailure.swift
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

import AppKit

/// A `wine` process that stopped abnormally soon after it was launched, which usually means the program or Wine
/// itself could not start.
public struct WineLaunchFailure: Sendable {
    /// Exits after this many seconds are a program quitting or crashing during play, not a failed launch
    static let launchWindow: TimeInterval = 10

    public let programName: String
    /// The signal number when `crashed`, the exit status otherwise
    public let status: Int32
    public let crashed: Bool
    public let logURL: URL
    /// The bottle was never initialized, or Wine crashed on a bad memory access: Wine itself likely can't run
    public let wineCouldNotStart: Bool

    /// Returns `nil` for a normal exit, a stop asked by the user, or an exit long after the launch.
    init?(process: Process, programName: String, bottle: Bottle, logURL: URL, launchDate: Date) {
        let crashed = process.terminationReason == .uncaughtSignal
        let status = process.terminationStatus
        guard crashed || status != 0 else { return nil }
        guard !crashed || (status != SIGTERM && status != SIGKILL) else { return nil }
        guard Date.now.timeIntervalSince(launchDate) < Self.launchWindow else { return nil }

        self.programName = programName
        self.status = status
        self.crashed = crashed
        self.logURL = logURL
        self.wineCouldNotStart = (crashed && status == SIGSEGV) || Wine.registryBuildNumber(bottle: bottle) == 0
    }

    @MainActor public func showAlert() {
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "alert.wineStopped.message"), programName)
        let detail: String.LocalizationValue = crashed ? "alert.wineStopped.signal" : "alert.wineStopped.exit"
        var info = String(format: String(localized: detail), status)
        if wineCouldNotStart {
            info += "\n\n" + String(format: String(localized: "alert.wineStopped.hint"), Wine.macOSVersion)
        }
        alert.informativeText = info
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.addButton(withTitle: String(localized: "button.showLog"))

        guard alert.runModal() == .alertSecondButtonReturn else { return }
        // Logs open in Console by default
        if !NSWorkspace.shared.open(logURL) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        }
    }
}
