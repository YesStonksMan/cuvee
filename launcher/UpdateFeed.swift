// SPDX-License-Identifier: LGPL-2.1-or-later
// The public GitHub release feed is the only update source. This file is UI-independent for testing.
import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        let core = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard let number = core.split(separator: "-", maxSplits: 1).first else { return nil }
        let pieces = number.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, let a = Int(pieces[0]), let b = Int(pieces[1]), let c = Int(pieces[2]),
              a >= 0, b >= 0, c >= 0 else { return nil }
        major = a; minor = b; patch = c
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct ReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?
    enum CodingKeys: String, CodingKey { case name, digest; case browserDownloadURL = "browser_download_url" }

    var trustedInstaller: Bool {
        guard browserDownloadURL.scheme == "https", browserDownloadURL.host == "github.com",
              browserDownloadURL.user == nil, browserDownloadURL.password == nil,
              browserDownloadURL.port == nil || browserDownloadURL.port == 443,
              browserDownloadURL.path.hasPrefix("/YesStonksMan/cuvee/releases/download/"),
              name.hasPrefix("Cuvee-"), name.hasSuffix("-macOS-AppleSilicon.pkg"),
              browserDownloadURL.lastPathComponent == name,
              let digest, digest.hasPrefix("sha256:"), digest.count == 71 else { return false }
        return digest.dropFirst(7).allSatisfy { "0123456789abcdef".contains($0) }
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAsset]
    enum CodingKeys: String, CodingKey { case draft, prerelease, assets; case tagName = "tag_name" }
}

struct AvailableUpdate {
    let version: String
    let preview: Bool
    let installer: ReleaseAsset
}

enum UpdateFeed {
    static func newest(_ releases: [GitHubRelease], after installed: String) -> AvailableUpdate? {
        guard let current = ReleaseVersion(installed) else { return nil }
        return releases.filter { !$0.draft }.compactMap { release -> (ReleaseVersion, AvailableUpdate)? in
            guard let version = ReleaseVersion(release.tagName), version > current,
                  let installer = release.assets.first(where: \.trustedInstaller) else { return nil }
            return (version, AvailableUpdate(version: release.tagName, preview: release.prerelease, installer: installer))
        }.max(by: { $0.0 < $1.0 })?.1
    }
}
