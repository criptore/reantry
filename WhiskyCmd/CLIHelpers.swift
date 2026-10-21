//
//  CLIHelpers.swift
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
import ArgumentParser

/// Unbuffered output, so that streamed Wine output and progress lines show up right away, even through a pipe.
enum Console {
    static func out(_ text: String, terminator: String = "\n") {
        write(text + terminator, to: .standardOutput)
    }

    static func err(_ text: String, terminator: String = "\n") {
        write(text + terminator, to: .standardError)
    }

    private static func write(_ text: String, to handle: FileHandle) {
        guard let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }
}

/// Direct3D implementations as spelled on the command line.
enum BackendOption: String, CaseIterable, ExpressibleByArgument {
    case d3dmetal
    case dxvk
    case wined3d

    var backend: GraphicsBackend {
        switch self {
        case .d3dmetal: return .d3dMetal
        case .dxvk: return .dxvk
        case .wined3d: return .wineD3D
        }
    }

    init(_ backend: GraphicsBackend) {
        switch backend {
        case .d3dMetal: self = .d3dmetal
        case .dxvk: self = .dxvk
        case .wineD3D: self = .wined3d
        }
    }
}

/// DXVK HUD modes as spelled on the command line.
enum HUDOption: String, CaseIterable, ExpressibleByArgument {
    case full
    case partial
    case fps
    case off

    var hud: DXVKHUD {
        switch self {
        case .full: return .full
        case .partial: return .partial
        case .fps: return .fps
        case .off: return .off
        }
    }

    init(_ hud: DXVKHUD) {
        switch hud {
        case .full: self = .full
        case .partial: self = .partial
        case .fps: self = .fps
        case .off: self = .off
        }
    }
}

enum CLI {
    /// Reports a runtime failure on stderr. Throw the result to exit with status 1, without the usage text
    /// that `ValidationError` prints.
    static func fail(_ message: String) -> ExitCode {
        Console.err("Error: \(message)")
        return .failure
    }

    /// The real path of a URL, with the home directory shortened to `~`.
    static func displayPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = NSHomeDirectory()
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Parses a Windows version such as `win10`. `winxp` is accepted for `winxp64`.
    static func windowsVersion(_ name: String) throws -> WinVersion {
        let lowered = name.lowercased()
        if let version = WinVersion(rawValue: lowered == "winxp" ? "winxp64" : lowered) {
            return version
        }
        let valid = WinVersion.allCases.map { $0.rawValue }.joined(separator: ", ")
        throw ValidationError("Unknown Windows version \"\(name)\". Valid values: \(valid).")
    }

    /// Finds a bottle by its name.
    static func bottle(named name: String) throws -> Bottle {
        var bottlesList = BottleData()
        guard let bottle = bottlesList.loadBottles().first(where: { $0.settings.name == name }) else {
            throw fail("No bottle called \"\(name)\" found.")
        }
        return bottle
    }

    /// Fails with a hint when Wine is not installed.
    static func requireWine() throws {
        guard WhiskyWineInstaller.isWhiskyWineInstalled() else {
            throw fail("Wine is not installed. Run `WhiskyCmd wine install` first.")
        }
    }

    /// Copies the graphics backend files into the bottle, as `Wine.runProgram` does before starting a program.
    /// The DXVK DLLs left by a previous backend are replaced with Wine's own.
    static func prepareGraphicsBackend(for bottle: Bottle) throws {
        switch bottle.settings.graphicsBackend {
        case .d3dMetal:
            try Wine.disableDXVK(bottle: bottle)
        case .dxvk:
            try Wine.enableDXVK(bottle: bottle)
        case .wineD3D:
            try Wine.disableDXVK(bottle: bottle)
            try Wine.enableWineD3D(bottle: bottle)
        }
    }

    /// The given environment, plus the variables of this command's own environment that must reach wine.
    /// Wine only gets the environment it is given, so a `WINEDEBUG` set by the caller would otherwise be
    /// replaced by the default one.
    static func wineEnvironment(_ environment: [String: String] = [:]) -> [String: String] {
        var result = environment
        if let debug = ProcessInfo.processInfo.environment["WINEDEBUG"] {
            result["WINEDEBUG"] = debug
        }
        return result
    }

    /// Runs wine in the bottle, streaming its output, and returns its exit status.
    /// A crash is reported as 128 plus the signal, like a shell does.
    static func streamWine(
        args: [String], bottle: Bottle, environment: [String: String] = [:], directory: URL? = nil
    ) async throws -> Int32 {
        var status: Int32 = 0
        for await output in try Wine.runWineProcess(
            args: args, bottle: bottle, environment: wineEnvironment(environment), directory: directory
        ) {
            switch output {
            case .started:
                break
            case .message(let text):
                Console.out(text, terminator: "")
            case .error(let text):
                Console.err(text, terminator: "")
            case .terminated(let process):
                let signalled = process.terminationReason == .uncaughtSignal
                status = signalled ? 128 + process.terminationStatus : process.terminationStatus
            }
        }
        return status
    }

    /// Waits for every process of the bottle to end (`wineserver -w`).
    static func waitForWineserver(bottle: Bottle) async throws {
        try await runWineserver(wineserverURL(for: bottle), args: ["-w"], bottle: bottle)
    }
}

extension CLI {
    /// The `wineserver` of the bottle's runtime.
    static func wineserverURL(for bottle: Bottle) -> URL {
        WhiskyWineInstaller.binFolder(for: bottle.settings.wineRuntime).appending(path: "wineserver")
    }

    /// Stops the wineserver running on the bottle when it comes from another runtime than the bottle's.
    ///
    /// Wine processes use the wineserver already running on their prefix. After a runtime change, the one started
    /// by the previous runtime would fail them with a protocol mismatch, or serve them with the previous runtime.
    /// Its own `wineserver -k` stops it, after it saved the registry.
    static func stopForeignWineserver(for bottle: Bottle) async throws {
        guard let running = runningWineserver(prefix: bottle.url) else { return }
        let expected = wineserverURL(for: bottle)
        let runningPath = running.resolvingSymlinksInPath().path(percentEncoded: false)
        guard runningPath != expected.resolvingSymlinksInPath().path(percentEncoded: false) else { return }

        Console.err("Stopping the wineserver of another runtime on this bottle: \(displayPath(running))")
        let exists = FileManager.default.isExecutableFile(atPath: running.path(percentEncoded: false))
        // `wineserver -k` signals the owner of the lock, so any runtime's can stop it
        try await runWineserver(exists ? running : expected, args: ["-k"], bottle: bottle)
    }

    /// The executable of the wineserver running on the given prefix, if any.
    ///
    /// A wineserver locks the file `lock` of its folder, `/tmp/.wine-<uid>/server-<device>-<inode>` for the device
    /// and the inode of the prefix in hexadecimal, as long as it runs. The owner of that lock is the wineserver.
    private static func runningWineserver(prefix: URL) -> URL? {
        var info = stat()
        guard stat(prefix.path(percentEncoded: false), &info) == 0 else { return nil }
        // Wine formats the device as an unsigned 64-bit number, sign extended like a C cast
        let device = String(UInt64(bitPattern: Int64(info.st_dev)), radix: 16)
        let inode = String(info.st_ino, radix: 16)
        let lock = "/tmp/.wine-\(getuid())/server-\(device)-\(inode)/lock"

        let descriptor = open(lock, O_RDWR)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var request = flock()
        request.l_type = Int16(F_WRLCK)
        request.l_whence = Int16(SEEK_SET)
        guard fcntl(descriptor, F_GETLK, &request) == 0, request.l_type != Int16(F_UNLCK) else { return nil }
        return executable(of: request.l_pid)
    }

    /// The executable of a process, as reported by `ps`. Only an absolute path is trusted.
    private static func executable(of pid: pid_t) -> URL? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "comm=", "-p", String(pid)]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Runs `wineserver` on the bottle and waits for it to end.
    /// `Wine.runWineserverProcess` would start a log of its own, which would hide wine's log from `logs --last`.
    private static func runWineserver(_ executable: URL, args: [String], bottle: Bottle) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = ["WINEPREFIX": bottle.url.path(percentEncoded: false)]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
