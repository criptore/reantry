//
//  Process+Extensions.swift
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

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeStream(name: name, fileHandle: fileHandle)
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }

    private func makeStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
            continuation.onTermination = { termination in
                switch termination {
                case .finished:
                    break
                case .cancelled:
                    guard self.isRunning else { return }
                    self.terminate()
                @unknown default:
                    break
                }
            }

            continuation.yield(.started(self))

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.message(line))
                guard !line.isEmpty else { return }
                Logger.wineKit.info("\(line, privacy: .public)")
                fileHandle?.write(line: line)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.error(line))
                guard !line.isEmpty else { return }
                Logger.wineKit.warning("\(line, privacy: .public)")
                fileHandle?.write(line: line)
            }

            terminationHandler = { (process: Process) in
                Self.drainPipe(pipe, as: .message, continuation: continuation, fileHandle: fileHandle)
                Self.drainPipe(errorPipe, as: .error, continuation: continuation, fileHandle: fileHandle)
                process.logTermination(name: name, fileHandle: fileHandle)
                try? fileHandle?.close()
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    /// Forwards what the process left in the pipe, without waiting for the end of the pipe.
    ///
    /// Processes started by the process, such as the programs a `wineboot` starts, inherit the pipe and keep it
    /// open after the process ended, so waiting for the end of the pipe would wait for them too. What they write
    /// afterwards is read and dropped, so that they never block on a full pipe or write to a closed one.
    private static func drainPipe(
        _ pipe: Pipe,
        as kind: PipeKind,
        continuation: AsyncStream<ProcessOutput>.Continuation,
        fileHandle: FileHandle?
    ) {
        let reading = pipe.fileHandleForReading
        reading.readabilityHandler = nil
        let remaining = readWithoutWaiting(from: reading.fileDescriptor)
        // Holding the handle keeps the pipe open for them, until they all closed it
        reading.readabilityHandler = { _ in
            if reading.availableData.isEmpty {
                reading.readabilityHandler = nil
            }
        }

        guard let text = String(data: remaining, encoding: .utf8), !text.isEmpty else { return }

        switch kind {
        case .message:
            continuation.yield(.message(text))
            Logger.wineKit.info("\(text, privacy: .public)")
        case .error:
            continuation.yield(.error(text))
            Logger.wineKit.warning("\(text, privacy: .public)")
        }
        fileHandle?.write(line: text)
    }

    private func logTermination(name: String, fileHandle: FileHandle? = nil) {
        let reason: String
        switch terminationReason {
        case .exit:
            reason = "exit"
        case .uncaughtSignal:
            reason = "uncaught signal (crash)"
        @unknown default:
            reason = "unknown"
        }

        let status = terminationStatus
        let message = "\nProcess \(name) terminated: status=\(status), reason=\(reason)\n"

        if status == 0 && terminationReason == .exit {
            Logger.wineKit.info("Terminated \(name) with status '\(status, privacy: .public)'")
        } else {
            let detail = "status=\(status) reason=\(reason)"
            Logger.wineKit.warning("Terminated \(name): \(detail, privacy: .public)")
        }

        fileHandle?.write(line: message)
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}

private enum PipeKind {
    case message
    case error
}

/// Reads the data that is already in a pipe, stopping as soon as reading more would wait.
private func readWithoutWaiting(from fileDescriptor: Int32) -> Data {
    let bufferSize = 16_384
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    var data = Data()
    var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
    // `poll` also reports the end of the pipe as readable, then `read` returns 0
    while poll(&descriptor, 1, 0) > 0 {
        let count = read(fileDescriptor, &buffer, bufferSize)
        guard count > 0 else { break }
        data.append(contentsOf: buffer[0..<count])
    }
    return data
}

extension FileHandle {
    func nextLine() -> String? {
        guard let line = String(data: availableData, encoding: .utf8) else { return nil }
        if !line.isEmpty {
            return line
        } else {
            return nil
        }
    }
}
