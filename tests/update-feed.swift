// SPDX-License-Identifier: LGPL-2.1-or-later
import Foundation

@main
struct UpdateFeedTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let digest = "sha256:" + String(repeating: "a", count: 64)
        func release(_ tag: String, draft: Bool = false, preview: Bool = false,
                     url: String? = nil, hash: String? = nil) -> GitHubRelease {
            let name = "Cuvee-\(tag.dropFirst())-macOS-AppleSilicon.pkg"
            return GitHubRelease(tagName: tag, draft: draft, prerelease: preview, assets: [
                ReleaseAsset(name: name,
                             browserDownloadURL: URL(string: url ?? "https://github.com/YesStonksMan/cuvee/releases/download/\(tag)/\(name)")!,
                             digest: hash ?? digest)
            ])
        }
        check(ReleaseVersion("") == nil, "empty version")
        check(ReleaseVersion("broken") == nil, "malformed version")
        check(ReleaseVersion("1.2") == nil, "incomplete version")
        check(ReleaseVersion("1.-2.3") == nil, "negative version")
        check(ReleaseVersion("v1.10.0")! > ReleaseVersion("v1.9.9")!, "numeric, not lexical ordering")
        check(ReleaseVersion("v2.0.0-preview.1") == ReleaseVersion("2.0.0"), "preview core version")
        check(UpdateFeed.newest([], after: "1.0.0") == nil, "empty feed")
        check(UpdateFeed.newest([release("v1.1.0")], after: "1.1.0") == nil, "do not reinstall same version")
        check(UpdateFeed.newest([release("v1.0.0")], after: "1.1.0") == nil, "never downgrade")
        check(UpdateFeed.newest([release("v9.0.0", draft: true)], after: "1.0.0") == nil, "ignore draft")
        check(UpdateFeed.newest([release("v1.2.0"), release("v1.10.0"), release("v1.3.0")], after: "1.1.0")?.version == "v1.10.0", "newest compatible release")
        check(UpdateFeed.newest([release("v1.2.0", preview: true)], after: "1.1.0")?.preview == true, "label preview")
        check(UpdateFeed.newest([release("v1.2.0", url: "https://evil.example/installer.pkg")], after: "1.1.0") == nil, "reject external host")
        check(UpdateFeed.newest([release("v1.2.0", url: "https://github.com/Other/repo/releases/download/v1.2.0/a.pkg")], after: "1.1.0") == nil, "reject other repository")
        check(UpdateFeed.newest([release("v1.2.0", hash: "sha256:bad")], after: "1.1.0") == nil, "reject missing checksum")
        check(UpdateFeed.newest([release("v1.2.0", hash: "sha256:" + String(repeating: "z", count: 64))], after: "1.1.0") == nil, "reject malformed checksum")
        let decoded = try JSONDecoder().decode([GitHubRelease].self, from: Data("""
        [{"tag_name":"v1.2.0","draft":false,"prerelease":false,"assets":[]}]
        """.utf8))
        check(UpdateFeed.newest(decoded, after: "1.1.0") == nil, "source-only release is not an app update")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try Data("abc".utf8).write(to: temp)
        let initialHash = try UpdateIntegrity.sha256(temp)
        check(initialHash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 known vector")
        try Data("changed".utf8).write(to: temp)
        let changedHash = try UpdateIntegrity.sha256(temp)
        check(changedHash != initialHash, "detect cached installer tampering")
        print("PASS: \(checks) update feed checks")
    }
}
