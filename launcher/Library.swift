// SPDX-License-Identifier: LGPL-2.1-or-later
// What Cuvee.app shows, read from disk: the bottles, their settings (cuvee.conf) and the games of Steam bottles.
import AppKit
import Foundation

let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Cuvee")
let cli = support.appending(path: "runtime/cuvee")
let bottlesDir = support.appending(path: "Bottles")
let logFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Cuvee.log")
private let hiddenApps: Set<String> = ["228980"]   // Steamworks Common Redistributables

/// The launchers `cuvee add` knows, with the bottle each one gets (must match `launcher()` in the cuvee script).
struct LauncherKind: Identifiable, Hashable {
    let id: String
    let bottle: String

    static let all = [
        LauncherKind(id: "steam", bottle: "Steam"),
        LauncherKind(id: "epic", bottle: "Epic Games"),
        LauncherKind(id: "ea", bottle: "EA app"),
        LauncherKind(id: "battlenet", bottle: "Battle.net"),
        LauncherKind(id: "ubisoft", bottle: "Ubisoft Connect"),
    ]
}

enum Graphics: String, CaseIterable, Identifiable {
    case vulkan, opengl, dxmt
    var id: String { rawValue }
    var label: String {
        switch self {
        case .vulkan: "Vulkan (MoltenVK)"
        case .opengl: "OpenGL"
        case .dxmt: "Metal (DXMT)"
        }
    }
}

enum TileAction: Equatable {
    case open(bottle: String)
    case game(bottle: String, appid: String)
}

struct Tile: Identifiable, Equatable {
    let id: String
    let name: String
    let art: URL?
    let action: TileAction
    let image: NSImage?     // decoded once here: views re-render on every hover change
    let process: String?    // in the command line of the game once it runs: `steamapps\common\<installdir>\`

    init(id: String, name: String, art: URL?, action: TileAction, process: String? = nil) {
        self.id = id
        self.name = name
        self.art = art
        self.action = action
        self.image = art.flatMap(NSImage.init(contentsOf:))
        self.process = process
    }

    static func == (a: Tile, b: Tile) -> Bool { a.id == b.id && a.name == b.name && a.art == b.art }
}

struct Bottle: Identifiable, Equatable {
    let name: String
    let launcher: String?
    let graphics: Graphics
    let metalFX: Bool
    let tiles: [Tile]
    var id: String { name }
    var opener: Tile? { tiles.first { if case .open = $0.action { true } else { false } } }
    var games: [Tile] { tiles.filter { if case .game = $0.action { true } else { false } } }
}

enum Library {
    static func bottles() -> [Bottle] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: bottlesDir, includingPropertiesForKeys: nil)) ?? []
        return dirs
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "drive_c").path) }
            .map(bottle)
            .sorted { order($0) < order($1) }
    }

    // Steam first, then the other launchers in catalog order, then plain bottles by name.
    private static func order(_ b: Bottle) -> String {
        let index = LauncherKind.all.firstIndex { $0.id == b.launcher } ?? LauncherKind.all.count
        return String(format: "%02d", index) + b.name.lowercased()
    }

    private static func bottle(_ dir: URL) -> Bottle {
        let name = dir.lastPathComponent
        let conf = settings(dir)
        let steamDir = dir.appending(path: "drive_c/Program Files (x86)/Steam")
        let hasSteam = FileManager.default.fileExists(atPath: steamDir.appending(path: "steam.exe").path)
        let launcher = conf["launcher"] ?? (hasSteam ? "steam" : nil)
        var tiles: [Tile] = []
        if let launcher {
            let art = launcher == "steam" ? steamDir.appending(path: "public/steam_tray.ico") : nil
            tiles.append(Tile(id: "\(name)/open", name: launcher == "steam" ? "Steam" : name, art: art, action: .open(bottle: name)))
        }
        if hasSteam { tiles += games(bottle: name, steamDir: steamDir) }
        return Bottle(name: name, launcher: launcher, graphics: Graphics(rawValue: conf["graphics"] ?? "") ?? .vulkan,
                      metalFX: conf["metalfx"] == "on", tiles: tiles)
    }

    private static func settings(_ dir: URL) -> [String: String] {
        guard let text = try? String(contentsOf: dir.appending(path: "cuvee.conf"), encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
        return values
    }

    private static func games(bottle: String, steamDir: URL) -> [Tile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: steamDir.appending(path: "steamapps"),
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { manifest($0, bottle: bottle, steamDir: steamDir) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func manifest(_ url: URL, bottle: String, steamDir: URL) -> Tile? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let id = text.firstMatch(of: #/(?i)"appid"\s+"(\d+)"/#)?.1,
              let name = text.firstMatch(of: #/"name"\s+"([^"]+)"/#)?.1,
              !hiddenApps.contains(String(id)) else { return nil }
        let dir = text.firstMatch(of: #/"installdir"\s+"([^"]+)"/#)?.1
        return Tile(id: "\(bottle)/\(id)", name: String(name), art: art(String(id), steamDir: steamDir),
                    action: .game(bottle: bottle, appid: String(id)), process: dir.map { "steamapps\\common\\\($0)\\" })
    }

    /// Does a wineserver serve this bottle? Same test as `running()` in the cuvee script (a stat, cheap to poll).
    static func isOpen(_ bottle: String) -> Bool {
        var info = stat()
        guard stat(bottlesDir.appending(path: bottle).path, &info) == 0 else { return false }
        let dev = String(UInt32(bitPattern: info.st_dev), radix: 16), ino = String(info.st_ino, radix: 16)
        return FileManager.default.fileExists(atPath: "/private/tmp/.wine-\(getuid())/server-\(dev)-\(ino)/socket")
    }

    /// Is a process with `marker` in its command line running? Wine shows a program's Windows path there.
    static func isRunning(_ marker: String) -> Bool {
        let ps = Process()
        let out = Pipe()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-axo", "comm="]
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return false }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return text.localizedCaseInsensitiveContains(marker)
    }

    // Steam caches artwork per appid, sometimes inside hashed sub-folders: prefer the portrait capsule.
    private static func art(_ id: String, steamDir: URL) -> URL? {
        let dir = steamDir.appending(path: "appcache/librarycache/\(id)")
        let found = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for wanted in ["library_600x900.jpg", "library_capsule.jpg", "library_header.jpg", "header.jpg"] {
            if let hit = found.first(where: { $0.lastPathComponent == wanted }) { return hit }
        }
        return nil
    }
}

/// Runs the installed `cuvee` CLI, output appended to ~/Library/Logs/Cuvee.log.
enum CLI {
    static func run(_ args: [String], onExit: @escaping @Sendable (Int32) -> Void) throws {
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logFile)
        log.seekToEndOfFile()
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = [cli.path] + args
        process.environment = ProcessInfo.processInfo.environment.merging(["CUVEE_NO_SETUP": "1"]) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { onExit($0.terminationStatus) }
        try process.run()
    }

    static func args(for action: TileAction) -> [String] {
        switch action {
        case .open(let bottle): ["open", bottle]
        case .game(let bottle, let appid): ["game", bottle, appid]
        }
    }
}
