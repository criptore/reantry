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

            let forwarder = OutputForwarder(
                pipes: [
                    (handle: pipe.fileHandleForReading, kind: .message),
                    (handle: errorPipe.fileHandleForReading, kind: .error)
                ],
                continuation: continuation, fileHandle: fileHandle
            )
            forwarder.start()

            terminationHandler = { (process: Process) in
                forwarder.processTerminated(process, name: name)
            }
        }
    }

    fileprivate func logTermination(name: String, fileHandle: FileHandle? = nil) {
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

private enum PipeKind: Hashable {
    case message
    case error
}

/// Forwards the output of a process to its stream and to its log file.
///
/// The stream finishes when the process exits, with everything the process wrote. Processes started by the
/// process, such as the programs a `wineboot` or a `start.exe` starts, inherit the pipes and can keep them open
/// long after, so their output keeps going to the log file, which is closed only at the end of both pipes.
///
/// All the reads happen on one serial queue and never wait, so the termination handler and the readability
/// handlers never race for the last bytes of a pipe.
private final class OutputForwarder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "WhiskyKit.OutputForwarder")
    private let pipes: [(handle: FileHandle, kind: PipeKind)]
    private let continuation: AsyncStream<ProcessOutput>.Continuation
    private let fileHandle: FileHandle?
    // Only used on `queue`
    private var openPipes: Set<PipeKind>
    private var finished = false
    private var logClosed = false

    init(
        pipes: [(handle: FileHandle, kind: PipeKind)],
        continuation: AsyncStream<ProcessOutput>.Continuation,
        fileHandle: FileHandle?
    ) {
        self.pipes = pipes
        self.continuation = continuation
        self.fileHandle = fileHandle
        self.openPipes = Set(pipes.map { $0.kind })
    }

    func start() {
        for pipe in pipes {
            let kind = pipe.kind
            pipe.handle.readabilityHandler = { handle in
                self.queue.sync {
                    self.forward(from: handle, as: kind)
                }
            }
        }
    }

    func processTerminated(_ process: Process, name: String) {
        queue.sync {
            // The process exited, so all it wrote is already in the pipes
            for pipe in pipes {
                forward(from: pipe.handle, as: pipe.kind)
            }
            process.logTermination(name: name, fileHandle: logClosed ? nil : fileHandle)
            continuation.yield(.terminated(process))
            continuation.finish()
            finished = true
            closeLogIfDone()
        }
    }

    /// Must run on `queue`.
    private func forward(from handle: FileHandle, as kind: PipeKind) {
        guard openPipes.contains(kind) else { return }
        let result = readWithoutWaiting(from: handle.fileDescriptor)
        emit(result.data, as: kind)

        if result.reachedEnd {
            handle.readabilityHandler = nil
            openPipes.remove(kind)
            closeLogIfDone()
        }
    }

    /// Must run on `queue`.
    private func emit(_ data: Data, as kind: PipeKind) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

        switch kind {
        case .message:
            if !finished { continuation.yield(.message(text)) }
            Logger.wineKit.info("\(text, privacy: .public)")
        case .error:
            if !finished { continuation.yield(.error(text)) }
            Logger.wineKit.warning("\(text, privacy: .public)")
        }

        if !logClosed {
            fileHandle?.write(line: text)
        }
    }

    /// Must run on `queue`.
    private func closeLogIfDone() {
        guard finished, openPipes.isEmpty, !logClosed else { return }
        logClosed = true
        try? fileHandle?.close()
    }
}

private struct PipeRead {
    var data = Data()
    var reachedEnd = false
}

/// Reads the data that is already in a pipe, stopping as soon as reading more would wait.
///
/// One call reads at most a few megabytes, so that a program writing without pause cannot keep it reading;
/// what is left stays in the pipe and makes it readable again.
private func readWithoutWaiting(from fileDescriptor: Int32) -> PipeRead {
    let bufferSize = 16_384
    let maxBytes = 4 * 1_024 * 1_024
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    var result = PipeRead()
    var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)

    while result.data.count < maxBytes {
        let ready = poll(&descriptor, 1, 0)
        if ready < 0 && errno == EINTR { continue }
        // `poll` also reports the end of the pipe as readable, then `read` returns 0
        guard ready > 0 else { break }

        let count = read(fileDescriptor, &buffer, bufferSize)
        if count < 0 {
            let error = errno
            if error == EINTR { continue }
            if error == EAGAIN || error == EWOULDBLOCK { break }
        }
        guard count > 0 else {
            // The end of the pipe, or an error after which nothing more can be read
            result.reachedEnd = true
            break
        }
        result.data.append(contentsOf: buffer[0..<count])
    }
    return result
}
