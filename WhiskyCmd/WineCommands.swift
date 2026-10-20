//
//  WineCommands.swift
//  WhiskyCmd
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
import os
import WhiskyKit
import SemanticVersion
import ArgumentParser

extension Whisky {
    struct WineCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "wine",
            abstract: "Manage the Wine libraries.",
            subcommands: [WineStatus.self, WineInstall.self]
        )
    }

    struct WineStatus: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show whether Wine is installed, its version and whether an update is available."
        )

        mutating func run() async throws {
            Console.out("Library folder: \(WhiskyWineInstaller.libraryFolder.path(percentEncoded: false))")

            guard let version = WhiskyWineInstaller.whiskyWineVersion() else {
                Console.out("Installed: no")
                return
            }
            Console.out("Installed: yes")
            Console.out("Version: \(version)")

            let runtimes = WhiskyWineInstaller.installedRuntimes()
            Console.out("Extra runtimes: \(runtimes.isEmpty ? "none" : runtimes.joined(separator: ", "))")

            let (updateAvailable, remoteVersion) = await WhiskyWineInstaller.shouldUpdateWhiskyWine()
            if updateAvailable {
                Console.out("Update available: yes (\(remoteVersion))")
            } else {
                Console.out("Update available: no")
            }
        }
    }

    struct WineInstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Download and install the Wine libraries.",
            discussion: "Without --file, the archive is downloaded the same way the app does it during its setup."
        )

        @Option(name: .long, help: "Install from this local archive instead of downloading one.")
        var file: String?

        mutating func run() async throws {
            // The archive lives in a temporary folder of its own, which goes away when the command ends
            var stagingFolder: URL?
            defer {
                if let stagingFolder { try? FileManager.default.removeItem(at: stagingFolder) }
            }

            let archive: URL
            if let file {
                let source = URL(fileURLWithPath: file)
                guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
                    throw CLI.fail("No file at \"\(file)\".")
                }
                // WhiskyWineInstaller.install deletes the archive it installs, so give it a copy
                archive = try LibrariesDownload.stagingURL(for: source.lastPathComponent)
                stagingFolder = archive.deletingLastPathComponent()
                try FileManager.default.copyItem(at: source, to: archive)
            } else {
                archive = try await LibrariesDownload.download()
                stagingFolder = archive.deletingLastPathComponent()
            }

            Console.out("Installing...")
            WhiskyWineInstaller.install(from: archive)

            guard let version = WhiskyWineInstaller.whiskyWineVersion() else {
                throw CLI.fail("The installation failed, see the messages above.")
            }
            Console.out("Installed Wine \(version).")
        }
    }
}

/// Remembers the download task, so that its progress can be read from elsewhere.
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let current = OSAllocatedUnfairLock<URLSessionTask?>(initialState: nil)

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        current.withLock { $0 = task }
    }

    func progressLine() -> String? {
        guard let task = current.withLock({ $0 }) else { return nil }
        let received = task.countOfBytesReceived
        let expected = task.countOfBytesExpectedToReceive
        var line = "  \(Self.format(received))"
        if expected > 0 {
            line += " / \(Self.format(expected)) (\(Int(Double(received) / Double(expected) * 100))%)"
        }
        return line
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Downloads the Wine libraries from the release, falling back to the upstream build, like the app's setup.
enum LibrariesDownload {
    /// A fresh path in a new temporary folder, with the given file name. The caller removes the folder.
    static func stagingURL(for fileName: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: fileName)
    }

    /// Downloads the archive into a temporary folder and returns its location.
    static func download() async throws -> URL {
        let urls = [AppDistribution.librariesURL, AppDistribution.fallbackLibrariesURL].compactMap { $0 }
        var lastError = "no download URL"

        for (index, url) in urls.enumerated() {
            Console.out("Downloading \(url.absoluteString)")
            do {
                let (downloaded, response) = try await fetch(url)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 200 {
                    let destination = try stagingURL(for: url.lastPathComponent)
                    try FileManager.default.moveItem(at: downloaded, to: destination)
                    return destination
                }
                try? FileManager.default.removeItem(at: downloaded)
                lastError = "HTTP \(statusCode)"
            } catch {
                lastError = "\(error)"
            }
            if index < urls.count - 1 {
                Console.out("Download failed (\(lastError)), trying the next source.")
            }
        }
        throw CLI.fail("Could not download the Wine libraries: \(lastError).")
    }

    /// Downloads a file while printing its progress. The progress is finished once this returns.
    private static func fetch(_ url: URL) async throws -> (URL, URLResponse) {
        let delegate = DownloadProgressDelegate()
        let interactive = isatty(STDOUT_FILENO) != 0
        let interval: Duration = interactive ? .milliseconds(500) : .seconds(5)
        let reporter = Task {
            while !Task.isCancelled {
                if let line = delegate.progressLine() {
                    Console.out(interactive ? "\r" + line : line, terminator: interactive ? "" : "\n")
                }
                try? await Task.sleep(for: interval)
            }
            if interactive { Console.out("") }
        }

        do {
            let result = try await URLSession(configuration: .ephemeral).download(from: url, delegate: delegate)
            reporter.cancel()
            await reporter.value
            return result
        } catch {
            reporter.cancel()
            await reporter.value
            throw error
        }
    }
}
