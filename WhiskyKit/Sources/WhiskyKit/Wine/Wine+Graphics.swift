//
//  Wine+Graphics.swift
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
    /// URL to the installed `DXVK` folder
    static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
    /// URL to Wine's own Direct3D DLLs, saved before D3DMetal replaced them in the Wine libraries
    static let wineD3DFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "WineD3D")

    public static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// Copy Wine's own Direct3D DLLs into the bottle when D3DMetal replaced them in the Wine libraries
    public static func enableWineD3D(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.wineD3DFolder.appending(path: "x64")
        )
    }

    /// `WINEDLLOVERRIDES` value loading the DLLs of the given graphics backend that were copied into the bottle.
    ///
    /// D3DMetal is built into the Wine libraries and needs no override. Without an override, Wine loads its builtin
    /// DLLs before the ones in `system32`, so DLLs left in the bottle by another backend are ignored.
    static func graphicsDLLOverrides(for backend: GraphicsBackend) -> String? {
        let native: [String]
        switch backend {
        case .d3dMetal:
            native = []
        case .dxvk:
            native = ["dxgi", "d3d9", "d3d10core", "d3d11"]
        case .wineD3D:
            let dlls = (try? FileManager.default.contentsOfDirectory(
                at: wineD3DFolder.appending(path: "x64"), includingPropertiesForKeys: nil
            )) ?? []
            native = dlls.filter { $0.pathExtension == "dll" }.map { $0.deletingPathExtension().lastPathComponent }
        }

        guard !native.isEmpty else { return nil }
        return native.sorted().joined(separator: ",") + "=n,b"
    }
}
