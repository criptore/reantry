//
//  BottleCommands.swift
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

/// Enhanced sync modes as spelled on the command line.
enum SyncOption: String, CaseIterable, ExpressibleByArgument {
    case none
    case esync
    case msync

    var sync: EnhancedSync {
        switch self {
        case .none: return EnhancedSync.none
        case .esync: return .esync
        case .msync: return .msync
        }
    }
}

/// Retina mode as spelled on the command line.
enum RetinaOption: String, CaseIterable, ExpressibleByArgument {
    case enabled = "on"
    case disabled = "off"
}

private struct PrefixNotCreated: Error, CustomStringConvertible {
    let description = "Wine did not initialize the prefix (no system.reg in the bottle)."
}

extension Whisky {
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new bottle.")

        @Argument var name: String

        @Option(help: "Windows version of the bottle: winxp64, win7, win8, win81, win10 or win11.")
        var windows: String = "win10"

        @Flag(help: """
        Set the bottle up for Steam: Windows 10 (whatever --windows says), D3DMetal and Retina mode, \
        then download and install Steam, and pin it.
        """)
        var steam = false

        mutating func run() async throws {
            let winVersion: WinVersion = try steam ? .win10 : CLI.windowsVersion(windows)
            try CLI.requireWine()

            var bottlesList = BottleData()
            guard !bottlesList.loadBottles().contains(where: { $0.settings.name == name }) else {
                throw CLI.fail("A bottle called \"\(name)\" already exists.")
            }

            let bottleURL = BottleData.defaultBottleDir.appending(path: UUID().uuidString)
            do {
                try FileManager.default.createDirectory(atPath: bottleURL.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = name
                // Initializes the prefix and sets its Windows version, like the app does
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)
                // Wine can fail without reporting an error, only the prefix proves that it worked
                let systemReg = bottleURL.appending(path: "system.reg")
                guard FileManager.default.fileExists(atPath: systemReg.path(percentEncoded: false)) else {
                    throw PrefixNotCreated()
                }
                bottlesList.paths.append(bottleURL)
            } catch {
                try? FileManager.default.removeItem(at: bottleURL)
                throw CLI.fail("Failed to create the bottle: \(error)")
            }
            Console.out("Created new bottle \"\(name)\" at \(bottleURL.path(percentEncoded: false)).")
            if steam {
                try await installSteam(in: Bottle(bottleUrl: bottleURL))
            }
        }

        /// Sets the new bottle up for Steam. The bottle is kept when this fails.
        private func installSteam(in bottle: Bottle) async throws {
            do {
                try await SteamSetup.setUp(bottle: bottle) { step in
                    Console.out("\(step)...")
                }
            } catch {
                throw CLI.fail("The bottle was created, but setting up Steam failed: \(error.localizedDescription)")
            }
            let steamPath = SteamSetup.steamExecutable(in: bottle).path(percentEncoded: false)
            Console.out("Steam is installed and pinned. Run it with: "
                        + "reantry run \(shellQuoted(bottle.settings.name)) \(shellQuoted(steamPath))")
        }

        /// Quotes `text` for a POSIX shell: single quotes, each single quote inside written as '\''.
        private func shellQuoted(_ text: String) -> String {
            "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        }
    }

    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show or change the settings of a bottle.",
            discussion: "Without options, prints the settings. Changes are saved to the bottle's Metadata.plist."
        )

        @Argument(help: "Name of the bottle.") var bottleName: String

        @Option(help: "Graphics backend: d3dmetal, dxvk or wined3d.")
        var backend: BackendOption?

        @Option(help: "Windows version: winxp64, win7, win8, win81, win10 or win11.")
        var windows: String?

        @Option(help: "Enhanced sync: none, esync or msync.")
        var sync: SyncOption?

        @Option(help: "Compile DXVK shaders asynchronously: true or false.")
        var dxvkAsync: Bool?

        @Option(help: "DXVK HUD: full, partial, fps or off.")
        var dxvkHud: HUDOption?

        @Option(help: "Show the Metal HUD: true or false.")
        var metalHud: Bool?

        @Option(help: "Advertise AVX to Rosetta: true or false.")
        var avx: Bool?

        @Option(help: "Name of an installed Wine runtime, or \"default\".")
        var runtime: String?

        @Option(help: "Retina mode, rendering at the full resolution of the screen: on or off.")
        var retina: RetinaOption?

        mutating func run() async throws {
            let bottle = try CLI.bottle(named: bottleName)

            let winVersion = try windows.map { try CLI.windowsVersion($0) }
            // The outer optional tells whether --runtime was given, the inner one is `nil` for the default runtime
            let runtimeName: String?? = try runtime.map { try resolveRuntime($0) }

            // Everything that can fail is checked before the first change, so nothing is applied halfway
            if winVersion != nil || retina != nil {
                try CLI.requireWine()
                try await CLI.stopForeignWineserver(for: bottle)
            }

            // The changes that run Wine, and can still fail on their own, go first
            if let winVersion {
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                bottle.settings.windowsVersion = winVersion
            }
            if let retina {
                try await Wine.changeRetinaMode(bottle: bottle, retinaMode: retina == .enabled)
            }
            applySimpleSettings(to: bottle)
            if let runtimeName {
                // The wineserver of the previous runtime may still run on the bottle, and would serve the next
                // Wine processes. It is stopped first, so that the new runtime is saved only once it is gone.
                try await CLI.stopForeignWineserver(for: bottle, runtime: runtimeName)
                bottle.settings.wineRuntime = runtimeName
            }
            if backend != nil {
                // Swaps the DLLs of the previous backend right away, instead of at the next launch
                try CLI.prepareGraphicsBackend(for: bottle)
            }

            printSettings(of: bottle)
        }

        /// The settings that only need to be saved to the bottle.
        private func applySimpleSettings(to bottle: Bottle) {
            if let backend { bottle.settings.graphicsBackend = backend.backend }
            if let sync { bottle.settings.enhancedSync = sync.sync }
            if let dxvkAsync { bottle.settings.dxvkAsync = dxvkAsync }
            if let dxvkHud { bottle.settings.dxvkHud = dxvkHud.hud }
            if let metalHud { bottle.settings.metalHud = metalHud }
            if let avx { bottle.settings.avxEnabled = avx }
        }

        /// A runtime name to store, `nil` standing for the default runtime.
        private func resolveRuntime(_ value: String) throws -> String? {
            if value.lowercased() == "default" { return nil }
            let installed = WhiskyWineInstaller.installedRuntimes()
            guard installed.contains(value) else {
                let available = installed.isEmpty ? "none" : installed.joined(separator: ", ")
                throw CLI.fail("Runtime \"\(value)\" is not installed. Installed runtimes: \(available).")
            }
            return value
        }

        private func printSettings(of bottle: Bottle) {
            let settings = bottle.settings
            Console.out("Name: \(settings.name)")
            Console.out("Path: \(bottle.url.path(percentEncoded: false))")
            Console.out("Graphics backend: \(BackendOption(settings.graphicsBackend).rawValue)")
            Console.out("Windows version: \(settings.windowsVersion.rawValue) (\(settings.windowsVersion.pretty()))")
            Console.out("Enhanced sync: \(settings.enhancedSync)")
            Console.out("DXVK async: \(settings.dxvkAsync)")
            Console.out("DXVK HUD: \(HUDOption(settings.dxvkHud).rawValue)")
            Console.out("Metal HUD: \(settings.metalHud)")
            Console.out("AVX: \(settings.avxEnabled)")
            Console.out("Wine runtime: \(settings.wineRuntime ?? "default")")
            Console.out("Retina mode: \(retinaMode(of: bottle) ? "on" : "off")")
        }

        /// The retina mode just set, or else the one saved in the bottle's `user.reg`. Reading the file directly
        /// needs no Wine process, unlike `Wine.retinaMode`, which also writes the value when it is missing.
        /// Wine leaves the retina mode off when the value is missing.
        private func retinaMode(of bottle: Bottle) -> Bool {
            if let retina { return retina == .enabled }
            guard let data = try? Data(contentsOf: bottle.url.appending(path: "user.reg")),
                  let registry = String(bytes: data, encoding: .utf8) else { return false }

            var inMacDriverKey = false
            for line in registry.lowercased().split(whereSeparator: \.isNewline) {
                if line.hasPrefix("[") {
                    inMacDriverKey = line.hasPrefix(#"[software\\wine\\mac driver]"#)
                } else if inMacDriverKey, line.hasPrefix(#""retinamode"="#) {
                    return line.hasPrefix(#""retinamode"="y""#)
                }
            }
            return false
        }
    }
}
