//
//  AppDistribution.swift
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

/// Where the app and its Wine libraries are published.
///
/// Everything is served from the GitHub Releases of a single repository.
/// Change `repository` to point a build at another fork.
public enum AppDistribution {
    /// GitHub repository, as `owner/name`, that hosts the releases.
    public static let repository = "criptore/reantry"

    /// Release tag holding the Wine libraries.
    ///
    /// This release is updated independently from app releases and must contain
    /// `Libraries.tar.gz` and `WhiskyWineVersion.plist` (see `docs/Releasing.md`).
    public static let librariesTag = "libraries"

    public static let repositoryURL = URL(string: "https://github.com/\(repository)")

    public static let releasesURL = URL(string: "https://github.com/\(repository)/releases")

    /// Archive extracted into the application support folder on first launch.
    public static let librariesURL = URL(
        string: "https://github.com/\(repository)/releases/download/\(librariesTag)/Libraries.tar.gz"
    )

    /// Version of the latest published libraries, used to offer updates.
    public static let librariesVersionURL = URL(
        string: "https://github.com/\(repository)/releases/download/\(librariesTag)/WhiskyWineVersion.plist"
    )

    /// Version of the upstream Wine Staging build used when `librariesURL` is not available.
    /// Gcenx only keeps recent releases, so this must point to a tag that still exists.
    public static let fallbackWineVersion = (major: 11, minor: 18)

    /// Upstream Wine Staging build used when `librariesURL` is not available.
    public static let fallbackLibrariesURL = URL(
        string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/"
            + "\(fallbackWineVersion.major).\(fallbackWineVersion.minor)/"
            + "wine-staging-\(fallbackWineVersion.major).\(fallbackWineVersion.minor)-osx64.tar.xz"
    )
}
