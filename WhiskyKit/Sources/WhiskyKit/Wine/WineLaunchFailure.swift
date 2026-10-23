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

/// A `wine` process that stopped soon after it was launched in a way that very likely means Wine itself failed:
/// a crash, or an error exit in a bottle that was never initialized.
public struct WineLaunchFailure: Sendable {
    /// Exits after this many seconds are a program quitting or crashing during play, not a failed launch
    static let launchWindow: TimeInterval = 10
    /// A crash within this many seconds of the launch is Wine itself not being able to start
    static let earlyCrashWindow: TimeInterval = 3
    /// Signals of a crash. SIGTERM, SIGKILL, SIGINT and SIGHUP ask a process to stop and are left out.
    static let crashSignals: Set<Int32> = [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP]

    public let programName: String
    /// The signal number when `crashed`, the exit status otherwise
    public let status: Int32
    public let crashed: Bool
    public let logURL: URL
    /// Wine crashed in a bottle that was never initialized or right after the launch: Wine itself likely can't run
    public let wineCouldNotStart: Bool

    /// Returns `nil` for a normal exit, a stop asked by the user, an exit long after the launch, or an error exit
    /// in an initialized bottle, since installers and launchers often exit with a non-zero status on purpose.
    init?(process: Process, programName: String, bottle: Bottle, logURL: URL, launchDate: Date) {
        let elapsed = Date.now.timeIntervalSince(launchDate)
        guard elapsed < Self.launchWindow else { return nil }
        let crashed = process.terminationReason == .uncaughtSignal
        let status = process.terminationStatus
        if crashed {
            guard Self.crashSignals.contains(status) else { return nil }
        } else if status == 0 {
            return nil
        }
        let uninitialized = Wine.registryBuildNumber(bottle: bottle) == 0
        guard crashed || uninitialized else { return nil }

        self.programName = programName
        self.status = status
        self.crashed = crashed
        self.logURL = logURL
        self.wineCouldNotStart = crashed && (uninitialized || elapsed < Self.earlyCrashWindow)
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
