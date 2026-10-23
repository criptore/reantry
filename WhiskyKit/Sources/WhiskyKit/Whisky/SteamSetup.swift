//
//  SteamSetup.swift
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

/// The steps of `SteamSetup.setUp`, reported as they start.
public enum SteamSetupStep: Sendable, Hashable, CustomStringConvertible {
    case configuring
    case downloading
    case installing

    public var description: String {
        switch self {
        case .configuring: return "Configuring the bottle for Steam"
        case .downloading: return "Downloading the Steam installer"
        case .installing: return "Installing Steam"
        }
    }
}

public enum SteamSetupError: LocalizedError {
    case downloadFailed(String)
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason):
            return "The Steam installer could not be downloaded: \(reason)"
        case .notInstalled:
            return "The Steam installer ended without installing Steam."
        }
    }
}

/// Prepares a bottle for Steam and installs it.
///
/// The bottle keeps its Wine runtime: the default libraries are built from CrossOver's Wine, which Steam needs.
public enum SteamSetup {
    /// The official Steam installer
    public static let installerAddress = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"

    /// Where the Steam installer puts `steam.exe` in a bottle
    public static func steamExecutable(in bottle: Bottle) -> URL {
        bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "steam.exe")
    }

    /// Sets Windows 10, D3DMetal and the Retina mode, downloads the Steam installer and runs it silently,
    /// waiting for it to end, then pins Steam. Each step is reported to `progress` as it starts.
    /// The bottle stays usable when a step fails.
    public static func setUp(
        bottle: Bottle, progress: @Sendable (SteamSetupStep) async -> Void = { _ in }
    ) async throws {
        await progress(.configuring)
        if bottle.settings.windowsVersion != .win10 {
            try await Wine.changeWinVersion(bottle: bottle, win: .win10)
            bottle.settings.windowsVersion = .win10
        }
        bottle.settings.graphicsBackend = .d3dMetal
        try await Wine.changeRetinaMode(bottle: bottle, retinaMode: true)

        await progress(.downloading)
        let folder = FileManager.default.temporaryDirectory.appending(path: "SteamSetup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let installer = try await downloadInstaller(to: folder)

        await progress(.installing)
        try await Wine.runProgram(at: installer, args: ["/S"], bottle: bottle)
        // The installer asks Windows to start Steam at login, which Wine does in the background
        try await Wine.removeSteamAutostart(bottle: bottle)

        let steam = steamExecutable(in: bottle)
        guard FileManager.default.fileExists(atPath: steam.path(percentEncoded: false)) else {
            throw SteamSetupError.notInstalled
        }
        if !bottle.settings.pins.contains(where: { $0.url == steam }) {
            bottle.settings.pins.append(PinnedProgram(name: "Steam", url: steam))
        }
    }

    /// Downloads the Steam installer into `folder`, which is created, and returns its URL.
    private static func downloadInstaller(to folder: URL) async throws -> URL {
        guard let address = URL(string: installerAddress) else {
            throw SteamSetupError.downloadFailed("invalid address \(installerAddress)")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let result: (URL, URLResponse)
        do {
            result = try await session.download(from: address)
        } catch {
            throw SteamSetupError.downloadFailed(error.localizedDescription)
        }
        guard let response = result.1 as? HTTPURLResponse, response.statusCode == 200 else {
            try? FileManager.default.removeItem(at: result.0)
            let status = (result.1 as? HTTPURLResponse).map { "the status \($0.statusCode)" } ?? "no HTTP status"
            throw SteamSetupError.downloadFailed("the server answered with \(status)")
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let installer = folder.appending(path: "SteamSetup.exe")
        try FileManager.default.moveItem(at: result.0, to: installer)
        return installer
    }
}
