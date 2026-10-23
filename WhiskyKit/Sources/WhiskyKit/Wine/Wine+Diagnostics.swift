//
//  Wine+Diagnostics.swift
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
    /// The version of macOS, such as `15.1.0`
    public static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// The Windows build number in the bottle registry, read from `system.reg` without starting Wine.
    /// Returns 0 when the bottle was never initialized, `nil` when the registry can't be read.
    public static func registryBuildNumber(bottle: Bottle) -> Int? {
        let url = bottle.url.appending(path: "system.reg")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return 0 }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let start = text.range(of: "\"CurrentBuildNumber\"=\"")?.upperBound else { return 0 }
        return Int(text[start...].prefix { $0.isNumber }) ?? 0
    }

    /// A plain text report about the app, the Mac and optionally a bottle, to paste in a bug report.
    /// It holds no environment variable and no program argument, the home folder is replaced with `~`
    /// and the user name in Wine profile paths with `<user>`.
    public static func diagnosticReport(bottle: Bottle? = nil) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let rosetta = Rosetta2.isRosettaInstalled
            || FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
        let wine = WhiskyWineInstaller.whiskyWineVersion().map { "\($0.major).\($0.minor).\($0.patch)" }

        var lines = [
            "Reantry \(version) (\(build))",
            "macOS \(macOSVersion)",
            "Chip: \(chipName ?? "unknown")",
            "Rosetta installed: \(rosetta ? "yes" : "no")",
            "Wine libraries: \(wine ?? "not installed")"
        ]
        if let bottle {
            let settings = bottle.settings
            let buildNumber = registryBuildNumber(bottle: bottle).map { String($0) }
            lines += [
                "",
                "Bottle: \(settings.name)",
                "Windows version: \(settings.windowsVersion.pretty()) (build \(buildNumber ?? "unknown"))",
                "Graphics backend: \(settings.graphicsBackend.rawValue)",
                "Wine runtime: \(settings.wineRuntime ?? "default")"
            ]
        }
        if let log = newestLog(for: bottle) {
            lines += ["", "Last lines of \(log.lastPathComponent):", logTail(of: log, lineCount: 40)]
        }
        return hidingHomeFolder(in: lines.joined(separator: "\n"))
    }

    private static var chipName: String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// The most recent log, or with a bottle, the most recent one written for that bottle
    private static func newestLog(for bottle: Bottle?) -> URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: logsFolder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let logs = urls.filter { $0.pathExtension == "log" }.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
        }
        guard let bottle else { return logs.first }

        // The header of each log names the bottle it was written for
        let marker = Data("Bottle URL: \(bottle.url.path)\n".utf8)
        return logs.prefix(50).first { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 16_384)) ?? Data()
            return head.range(of: marker) != nil
        }
    }

    /// The last lines of a log, without the program arguments and the lines of the environment dump
    private static func logTail(of url: URL, lineCount: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        let data = (try? handle.readToEnd()) ?? Data()

        // The start of the data can cut a character in two
        let text = (0..<4).lazy.compactMap { String(data: data.dropFirst($0), encoding: .utf8) }.first ?? ""
        let lines = text.components(separatedBy: .newlines).filter { line in
            !line.hasPrefix("Arguments: ") && !(line.hasPrefix("    ") && line.contains(" = ") && line.hasSuffix(";"))
        }
        return lines.suffix(lineCount).joined(separator: "\n")
    }

    private static func hidingHomeFolder(in text: String) -> String {
        let userName = NSUserName()
        var result = hidingWineProfileName(userName, in: text)
        let homes = Set([NSHomeDirectory(), NSHomeDirectoryForUser(userName) ?? ""])
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
        for home in homes {
            result = result.replacingOccurrences(of: home, with: "~")
            // Wine writes the same folder as a Windows path, such as `Z:\Users\name`
            result = result.replacingOccurrences(of: home.replacingOccurrences(of: "/", with: "\\"), with: "~")
        }
        return result
    }

    /// Wine profiles are named after the short user name, such as `C:\users\name` or `drive_c/users/name`
    private static func hidingWineProfileName(_ userName: String, in text: String) -> String {
        let name = NSRegularExpression.escapedPattern(for: userName)
        guard !name.isEmpty, let regex = try? NSRegularExpression(
            pattern: #"((?:c:|drive_c)[\\/]users[\\/])"# + name + #"(?![\w.-])"#, options: .caseInsensitive
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1<user>")
    }
}
