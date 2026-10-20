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
            throw ValidationError("No bottle called \"\(name)\" found.")
        }
        return bottle
    }

    /// Fails with a hint when Wine is not installed.
    static func requireWine() throws {
        guard WhiskyWineInstaller.isWhiskyWineInstalled() else {
            throw ValidationError("Wine is not installed. Run `WhiskyCmd wine install` first.")
        }
    }

    /// Copies the graphics backend files into the bottle, as `Wine.runProgram` does before starting a program.
    static func prepareGraphicsBackend(for bottle: Bottle) throws {
        switch bottle.settings.graphicsBackend {
        case .d3dMetal:
            break
        case .dxvk:
            try Wine.enableDXVK(bottle: bottle)
        case .wineD3D:
            try Wine.enableWineD3D(bottle: bottle)
        }
    }
}
