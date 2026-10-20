//
//  Wine+Logs.swift
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

extension Wine {
    public static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.whiskyBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        return try makeLogFile().handle
    }

    /// Creates an empty log file named after the current time and opens it for writing.
    static func makeLogFile() throws -> (url: URL, handle: FileHandle) {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return (fileURL, try FileHandle(forWritingTo: fileURL))
    }

    /// Starts `wine <url> <args>` and returns without waiting for it. The output goes straight to a log file,
    /// so the program keeps running after the calling process ended. Returns the URL of that log.
    public static func launchDetached(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> URL {
        let (logURL, fileHandle) = try makeLogFile()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        let binFolder = WhiskyWineInstaller.binFolder(for: bottle.settings.wineRuntime)
        let process = Process()
        process.executableURL = binFolder.appending(path: "wine")
        process.arguments = [url.path(percentEncoded: false)] + args
        process.currentDirectoryURL = url.deletingLastPathComponent()
        process.environment = constructWineEnvironment(for: bottle, environment: environment)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = fileHandle
        process.standardError = fileHandle
        fileHandle.writeInfo(for: process)
        try process.run()
        return logURL
    }
}
