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
import WhiskyKit
import SemanticVersion
import ArgumentParser

extension Whisky {
    struct WineCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "wine",
            abstract: "Manage the Wine libraries.",
            subcommands: [Status.self, Install.self]
        )

        struct Status: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
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

        struct Install: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Download and install the Wine libraries.",
                discussion: "Without --file, the archive is downloaded the same way the app does it during its setup."
            )

            @Option(name: .long, help: "Install from this local archive instead of downloading one.")
            var file: String?

            mutating func run() async throws {
                let archive: URL
                if let file {
                    let source = URL(fileURLWithPath: file)
                    guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
                        throw ValidationError("No file at \"\(file)\".")
                    }
                    // WhiskyWineInstaller.install deletes the archive it installs, so give it a copy
                    archive = try LibrariesDownload.stagingURL(for: source.lastPathComponent)
                    try FileManager.default.copyItem(at: source, to: archive)
                } else {
                    archive = try await LibrariesDownload.download()
                }

                Console.out("Installing...")
                WhiskyWineInstaller.install(from: archive)

                guard let version = WhiskyWineInstaller.whiskyWineVersion() else {
                    throw ValidationError("The installation failed, see the messages above.")
                }
                Console.out("Installed Wine \(version).")
            }
        }
    }
}

/// Reports the progress of a download on stdout.
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        Task.detached {
            let interactive = isatty(STDOUT_FILENO) != 0
            let interval: Duration = interactive ? .milliseconds(500) : .seconds(5)
            while task.state == .running || task.state == .suspended {
                let received = task.countOfBytesReceived
                let expected = task.countOfBytesExpectedToReceive
                var line = "  \(Self.format(received))"
                if expected > 0 {
                    line += " / \(Self.format(expected)) (\(Int(Double(received) / Double(expected) * 100))%)"
                }
                Console.out(interactive ? "\r" + line : line, terminator: interactive ? "" : "\n")
                try? await Task.sleep(for: interval)
            }
            if interactive { Console.out("") }
        }
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Downloads the Wine libraries from the release, falling back to the upstream build, like the app's setup.
enum LibrariesDownload {
    /// A fresh path in the temporary folder, with the given file name.
    static func stagingURL(for fileName: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: fileName)
    }

    static func download() async throws -> URL {
        let urls = [AppDistribution.librariesURL, AppDistribution.fallbackLibrariesURL].compactMap { $0 }
        var lastError = "no download URL"

        for (index, url) in urls.enumerated() {
            Console.out("Downloading \(url.absoluteString)")
            do {
                let (downloaded, response) = try await URLSession(configuration: .ephemeral)
                    .download(from: url, delegate: DownloadProgressDelegate())
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 200 {
                    let destination = try stagingURL(for: url.lastPathComponent)
                    try FileManager.default.moveItem(at: downloaded, to: destination)
                    return destination
                }
                lastError = "HTTP \(statusCode)"
            } catch {
                lastError = "\(error)"
            }
            if index < urls.count - 1 {
                Console.out("Download failed (\(lastError)), trying the next source.")
            }
        }
        throw ValidationError("Could not download the Wine libraries: \(lastError).")
    }
}
