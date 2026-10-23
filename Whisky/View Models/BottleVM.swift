//
//  BottleVM.swift
//  Whisky
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

import AppKit
import SemanticVersion
import WhiskyKit

// swiftlint:disable:next todo
// TODO: Don't use unchecked!
final class BottleVM: ObservableObject, @unchecked Sendable {
    @MainActor static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []
    /// The Steam setup step of the bottles being created with Steam, by bottle URL
    @Published var steamSetupSteps: [URL: SteamSetupStep] = [:]

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL, setUpSteam: Bool = false) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task.detached {
            var bottleId: Bottle?
            var steamError: String?
            do {
                try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle

                await MainActor.run {
                    self.bottles.append(bottle)
                }

                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)
                if setUpSteam {
                    steamError = await self.installSteam(in: bottle)
                }
                // Add record
                await MainActor.run {
                    self.bottlesList.paths.append(newBottleDir)
                    self.loadBottles()
                }
                if let steamError {
                    await self.showSteamError(steamError)
                }
            } catch {
                print("Failed to create new bottle: \(error)")
                if let bottle = bottleId {
                    await MainActor.run {
                        if let index = self.bottles.firstIndex(of: bottle) {
                            self.bottles.remove(at: index)
                        }
                    }
                }
            }
        }
        return newBottleDir
    }

    /// Installs Steam in a bottle being created, showing the steps in the list of bottles.
    /// Returns the reason of a failure, the bottle being usable anyway.
    private func installSteam(in bottle: Bottle) async -> String? {
        let url = bottle.url
        var failure: String?
        do {
            try await SteamSetup.setUp(bottle: bottle) { step in
                await MainActor.run {
                    self.steamSetupSteps[url] = step
                }
            }
        } catch {
            print("Failed to set up Steam: \(error)")
            failure = error.localizedDescription
        }
        await MainActor.run {
            self.steamSetupSteps[url] = nil
        }
        return failure
    }

    @MainActor
    private func showSteamError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "create.steam.failed")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
