// SPDX-License-Identifier: LGPL-2.1-or-later
// What Cuvee.app shows, read from disk: the bottles, their settings (cuvee.conf) and the games of Steam bottles.
import AppKit
import Foundation

let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Cuvee")
// Release apps carry their own engine. Developer builds keep the existing installed runtime.
let cli = Bundle.main.resourceURL.map { $0.appending(path: "runtime/cuvee") }
    .flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    ?? support.appending(path: "runtime/cuvee")
let hasMoltenVK = FileManager.default.fileExists(atPath: cli.deletingLastPathComponent().appending(path: "dist/lib/libMoltenVK.dylib").path)
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
    static var available: [Graphics] { hasMoltenVK ? allCases : [.dxmt, .opengl] }
    static var fallback: Graphics { hasMoltenVK ? .vulkan : .dxmt }
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

    var bottle: String {
        switch self {
        case .open(let bottle), .game(let bottle, _): bottle
        }
    }
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

/// A Mac folder the bottle sees as a Windows drive (`cuvee drive`), e.g. on an external disk.
struct Drive: Identifiable, Equatable {
    let letter: String   // "D"
    let path: String
    var id: String { letter }
    var reachable: Bool { FileManager.default.fileExists(atPath: path) }   // false: the disk is unplugged
}

struct Bottle: Identifiable, Equatable {
    let name: String
    let launcher: String?
    let graphics: Graphics
    let metalFX: Bool
    let tiles: [Tile]
    let drives: [Drive]
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
        if hasSteam { tiles += games(bottle: dir, steamDir: steamDir) }
        return Bottle(name: name, launcher: launcher, graphics: Graphics(rawValue: conf["graphics"] ?? "") ?? .fallback,
                      metalFX: conf["metalfx"] == "on", tiles: tiles, drives: drives(dir))
    }

    /// Same rule as `drives_cmd` in the cuvee script: a D:-Y: link without Wine's "x::" device link.
    private static func drives(_ dir: URL) -> [Drive] {
        "defghijklmnopqrstuvwxy".compactMap { letter in
            let link = dir.appending(path: "dosdevices/\(letter):").path
            guard let path = try? FileManager.default.destinationOfSymbolicLink(atPath: link),
                  (try? FileManager.default.destinationOfSymbolicLink(atPath: link + ":")) == nil else { return nil }
            return Drive(letter: String(letter).uppercased(), path: path)
        }
    }

    /// A Windows path of the bottle ("D:\\SteamLibrary") as a Mac path, through its dosdevices links.
    private static func unixPath(_ windows: String, bottle dir: URL) -> URL? {
        guard let letter = windows.first?.lowercased(), windows.dropFirst().hasPrefix(":") else { return nil }
        let root = dir.appending(path: "dosdevices/\(letter):").resolvingSymlinksInPath()
        return windows.dropFirst(2).split(separator: "\\").reduce(root) { $0.appending(path: String($1)) }
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

    /// Games of every Steam library folder: Steam's own, plus those added in Steam (an external disk's drive).
    private static func games(bottle dir: URL, steamDir: URL) -> [Tile] {
        let vdf = (try? String(contentsOf: steamDir.appending(path: "steamapps/libraryfolders.vdf"), encoding: .utf8)) ?? ""
        let others = vdf.matches(of: #/"path"\s+"([^"]+)"/#)
            .compactMap { unixPath($0.1.replacingOccurrences(of: "\\\\", with: "\\"), bottle: dir) }
        var seen = Set<String>()
        let libraries = ([steamDir] + others).map { $0.resolvingSymlinksInPath() }.filter { seen.insert($0.path).inserted }
        let files = libraries.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0.appending(path: "steamapps"), includingPropertiesForKeys: nil)) ?? []
        }
        var ids = Set<String>()
        return files
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { manifest($0, bottle: dir.lastPathComponent, steamDir: steamDir) }
            .filter { ids.insert($0.id).inserted }   // one tile per game, even if two libraries list it
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
        guard let dir = serverDir(bottle) else { return false }
        return FileManager.default.fileExists(atPath: "/private/tmp/.wine-\(getuid())/\(dir)/socket")
    }

    /// "server-DEV-INODE": the folder of the wineserver that serves this bottle.
    private static func serverDir(_ bottle: String) -> String? {
        var info = stat()
        guard stat(bottlesDir.appending(path: bottle).path, &info) == 0 else { return nil }
        return "server-\(String(UInt32(bitPattern: info.st_dev), radix: 16))-\(String(info.st_ino, radix: 16))"
    }

    /// Windows programs running in `bottle` that pass `keep`, as Wine names them (a full Windows path, or a bare
    /// "steam.exe" when started by name). The name says nothing of the bottle: every Wine process maps a file of
    /// its own wineserver's folder, so `lsof` tells which bottle each candidate belongs to.
    static func programs(in bottle: String, where keep: (String) -> Bool) -> [String] {
        guard let dir = serverDir(bottle) else { return [] }
        let candidates = output("/bin/ps", ["-axo", "pid=,comm="]).split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, keep(String(parts[1])) else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
        return candidates.filter { output("/usr/sbin/lsof", ["-a", "-p", $0.0, "-d", "txt", "-Fn"]).contains("/\(dir)/") }
            .map(\.1)
    }

    /// A game, not Windows itself nor a launcher's own programs (an unknown helper counts as a game: one more question).
    static func isGame(_ program: String) -> Bool {
        let path = program.lowercased()
        guard path.dropFirst().hasPrefix(":\\"), !path.contains("\\windows\\") else { return false }   // bare names: launchers
        if gameDirs.contains(where: path.contains) { return true }
        return !launcherDirs.contains(where: path.contains)
    }

    // must match where the launchers of `launcher()` in the cuvee script install themselves
    private static let launcherDirs = ["\\steam\\", "\\common files\\", "\\epic games\\launcher\\", "\\epic online services\\",
                                       "\\electronic arts\\ea desktop\\", "\\battle.net\\", "\\ubisoft game launcher\\"]
    private static let gameDirs = ["\\steamapps\\common\\", "\\ubisoft game launcher\\games\\"]

    private static func output(_ tool: String, _ args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: tool)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text
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
    /// `onExit` gets the exit code and, on a failure, what the CLI said when it gave up (its `cuvee: ...` line).
    static func run(_ args: [String], onExit: @escaping @Sendable (Int32, String?) -> Void) throws {
        try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateLog()
        // O_APPEND: several programs write this file at once (Steam for hours, then each command); without it every
        // one kept its own position and wrote over the others
        let fd = open(logFile.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let start = (try? log.seekToEnd()) ?? 0
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = [cli.path] + args
        process.environment = ProcessInfo.processInfo.environment.merging(["CUVEE_NO_SETUP": "1"]) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { onExit($0.terminationStatus, $0.terminationStatus == 0 ? nil : reason(since: start)) }
        try process.run()
    }

    /// The last `cuvee: ...` line the log gained since `start`: why the command stopped ("bottle 'X' is running...").
    private static func reason(since start: UInt64) -> String? {
        guard let file = try? FileHandle(forReadingFrom: logFile) else { return nil }
        defer { try? file.close() }
        let size = (try? file.seekToEnd()) ?? 0
        let from = start <= size ? start : 0   // the log was emptied meanwhile
        try? file.seek(toOffset: max(from, size > 65536 ? size - 65536 : 0))
        let text = String(decoding: (try? file.readToEnd()) ?? Data(), as: UTF8.self)
        return text.split(separator: "\n").last { $0.hasPrefix("cuvee: ") }.map { String($0.dropFirst(7)) }
    }

    /// Steam's output is appended on every launch and nothing ever trimmed it (the log reached 10 GB, 13-11-2026).
    /// Past 20 MB, the log is copied to Cuvee.old.log (replacing the previous one) and emptied in place.
    /// Emptied, not renamed: a Steam still running kept writing to the renamed file, which grew without limit
    /// (276 MB in a day, 14-11-2026); with O_APPEND it goes on in the emptied log.
    // ponytail: checked only at launch, so one very long session can still grow past 20 MB until the next launch.
    static let maxLogBytes = 20 * 1024 * 1024

    static func rotateLog() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: logFile.path))?[.size] as? Int, size > maxLogBytes else { return }
        let old = logFile.deletingLastPathComponent().appending(path: "Cuvee.old.log")
        try? fm.removeItem(at: old)
        try? fm.copyItem(at: logFile, to: old)   // an APFS clone: instant, no extra disk
        truncate(logFile.path, 0)
    }

    static func args(for action: TileAction) -> [String] {
        switch action {
        case .open(let bottle): ["open", bottle]
        case .game(let bottle, let appid): ["game", bottle, appid]
        }
    }
}
