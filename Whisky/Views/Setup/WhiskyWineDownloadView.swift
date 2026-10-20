//
//  WhiskyWineDownloadView.swift
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

import SwiftUI
import WhiskyKit
import os.log

struct WhiskyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack {
                    ProgressView(value: fractionProgress, total: 1)
                    HStack {
                        HStack {
                            Text(String(format: String(localized: "setup.whiskywine.progress"),
                                        formatBytes(bytes: completedBytes),
                                        formatBytes(bytes: totalBytes)))
                            + Text(String(" "))
                            + (shouldShowEstimate() ?
                               Text(String(format: String(localized: "setup.whiskywine.eta"),
                                           formatRemainingTime(remainingBytes: totalBytes - completedBytes)))
                               : Text(String()))
                            Spacer()
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task {
                let urls = [AppDistribution.librariesURL, AppDistribution.fallbackLibrariesURL]
                startDownload(from: urls.compactMap { $0 })
            }
        }
    }

    /// Downloads the first URL that answers, moving on to the next one when the server reports an error.
    func startDownload(from urls: [URL]) {
        guard let url = urls.first else { return }
        let fallbacks = Array(urls.dropFirst())

        downloadTask = URLSession(configuration: .ephemeral).downloadTask(with: url) { downloadedURL, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            // URLSession deletes the downloaded file as soon as this handler returns, so keep it here
            let localURL = statusCode == 200 || fallbacks.isEmpty
                ? downloadedURL.flatMap(Self.keepDownloadedFile)
                : nil
            Task.detached {
                await MainActor.run {
                    if let localURL = localURL {
                        tarLocation = localURL
                        proceed()
                    } else {
                        startDownload(from: fallbacks)
                    }
                }
            }
        }
        observation = downloadTask?.observe(\.countOfBytesReceived) { task, _ in
            Task {
                await MainActor.run {
                    let currentTime = Date()
                    let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                    if completedBytes > 0 {
                        downloadSpeed = Double(completedBytes) / elapsedTime
                    }
                    // The server may not send a size, which leaves the expected count at -1
                    totalBytes = max(task.countOfBytesExpectedToReceive, 0)
                    completedBytes = task.countOfBytesReceived
                    fractionProgress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
                }
            }
        }
        startTime = Date()
        downloadTask?.resume()
    }

    /// Moves a file that URLSession is about to delete to a location owned by the app.
    nonisolated private static func keepDownloadedFile(_ downloadedURL: URL) -> URL? {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(downloadedURL.pathExtension)
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: destination)
            return destination
        } catch {
            Logger.wineKit.error("Failed to keep downloaded WhiskyWine archive: \(error)")
            return nil
        }
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0 && totalBytes > 0
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        if shouldShowEstimate() {
            return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
        } else {
            return ""
        }
    }

    func proceed() {
        path.append(.whiskyWineInstall)
    }
}
