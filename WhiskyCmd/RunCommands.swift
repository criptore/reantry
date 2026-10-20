//
//  RunCommands.swift
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

extension Whisky {
    struct Exec: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run wine with the given arguments in a bottle and stream its output.",
            discussion: """
            Everything after `--` is passed to wine, and wine's exit status becomes the exit status of this command.
            Example: WhiskyCmd exec mybottle -- cmd /c ver
            """
        )

        @Argument(help: "Name of the bottle.") var bottleName: String

        @Flag(help: "Once wine exits, also wait for the other processes of the bottle to end (wineserver -w).")
        var wait = false

        @Argument(parsing: .postTerminator, help: "Arguments for wine, after `--`.")
        var wineArgs: [String] = []

        mutating func run() async throws {
            guard !wineArgs.isEmpty else {
                throw ValidationError("Missing the wine arguments, for example: exec \(bottleName) -- winecfg")
            }
            try CLI.requireWine()
            let bottle = try CLI.bottle(named: bottleName)
            try CLI.prepareGraphicsBackend(for: bottle)

            let status = try await CLI.streamWine(args: wineArgs, bottle: bottle)

            if wait {
                try await CLI.waitForWineserver(bottle: bottle)
            }
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a program with Reantry.",
            discussion: """
            Without --wait, the program is started in Terminal. With --wait, it runs attached to this command \
            with the bottle's graphics backend, and the exit status of the program becomes the exit status of \
            this command. Options go before the bottle, everything after the program is passed to it.
            Example: WhiskyCmd run --wait mybottle game.exe -windowed
            """
        )

        @Flag(help: "Run the program in this process instead of Terminal, and wait for it to end.")
        var wait = false

        @Argument var bottleName: String
        @Argument var path: String
        @Argument(parsing: .remaining, help: "Arguments for the program.") var args: [String] = []

        mutating func run() async throws {
            let bottle = try CLI.bottle(named: bottleName)
            let url = URL(fileURLWithPath: path)
            let program = Program(url: url, bottle: bottle)

            guard wait else {
                // Returning before the script ran would end the process and the script with it
                await program.runInTerminalAndWait()
                return
            }

            try CLI.requireWine()
            try CLI.prepareGraphicsBackend(for: bottle)
            let savedArguments = program.settings.arguments.split { $0.isWhitespace }.map(String.init)
            let status = try await CLI.streamWine(
                args: [url.path(percentEncoded: false)] + savedArguments + args,
                bottle: bottle,
                environment: program.generateEnvironment(),
                directory: url.deletingLastPathComponent()
            )
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }

    struct Logs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show the logs folder, or the newest log.",
            discussion: "The logs hold the Wine output, the graphics backend and the WINEDLLOVERRIDES of each run."
        )

        @Flag(help: "Print the path and the content of the newest log.")
        var last = false

        mutating func run() async throws {
            let folder = Wine.logsFolder
            guard last else {
                Console.out(folder.path(percentEncoded: false))
                return
            }

            let keys: [URLResourceKey] = [.contentModificationDateKey]
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys
            )) ?? []
            let newest = files
                .filter { $0.pathExtension == "log" }
                .max { modified($0) < modified($1) }
            guard let newest else {
                throw CLI.fail("No log in \(folder.path(percentEncoded: false)).")
            }

            Console.out(newest.path(percentEncoded: false))
            Console.out("")
            let content = try String(contentsOf: newest, encoding: .utf8)
            Console.out(content, terminator: "")
        }

        private func modified(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? .distantPast
        }
    }
}
