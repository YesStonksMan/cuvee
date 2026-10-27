// SPDX-License-Identifier: LGPL-2.1-or-later
// Cuvee quick-launch window: Steam + every installed Steam game of the "Steam" bottle.
// Each tile calls the installed runtime CLI (`cuvee steam|game`), which goes through Steam like its Play button.
import AppKit
import SwiftUI

private let support = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/Cuvee")
private let cli = support.appending(path: "runtime/cuvee")
private let steamDir = support.appending(path: "Bottles/Steam/drive_c/Program Files (x86)/Steam")
private let logFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Cuvee.log")
private let hiddenApps: Set<String> = ["228980"]   // Steamworks Common Redistributables

private let pink = Color(red: 1, green: 0.416, blue: 0.604)      // #ff6a9a, from the app icon
private let magenta = Color(red: 0.878, green: 0.122, blue: 0.471) // #e01f78
private let violet = Color(red: 0.478, green: 0.102, blue: 0.651)  // #7a1aa6

struct Tile: Identifiable, Equatable {
    let id: String          // "steam" or a Steam appid
    let name: String
    let art: URL?
    let image: NSImage?     // decoded once here: views re-render on every hover change

    init(id: String, name: String, art: URL?) {
        self.id = id
        self.name = name
        self.art = art
        self.image = art.flatMap(NSImage.init(contentsOf:))
    }

    static func == (a: Tile, b: Tile) -> Bool { a.id == b.id && a.name == b.name && a.art == b.art }
}

enum Library {
    static func tiles() -> [Tile] {
        let steam = Tile(id: "steam", name: "Steam", art: steamDir.appending(path: "public/steam_tray.ico"))
        return [steam] + games()
    }

    static func games() -> [Tile] {
        let apps = steamDir.appending(path: "steamapps")
        let files = (try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap(parseManifest)
            .filter { !hiddenApps.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func parseManifest(_ url: URL) -> Tile? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let id = text.firstMatch(of: #/(?i)"appid"\s+"(\d+)"/#)?.1,
              let name = text.firstMatch(of: #/"name"\s+"([^"]+)"/#)?.1 else { return nil }
        return Tile(id: String(id), name: String(name), art: art(for: String(id)))
    }

    // Steam caches artwork per appid, sometimes inside hashed sub-folders: prefer the portrait capsule.
    private static func art(for id: String) -> URL? {
        let dir = steamDir.appending(path: "appcache/librarycache/\(id)")
        let found = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        for wanted in ["library_600x900.jpg", "library_capsule.jpg", "library_header.jpg", "header.jpg"] {
            if let hit = found.first(where: { $0.lastPathComponent == wanted }) { return hit }
        }
        return nil
    }
}

enum Launcher {
    static func launch(_ tile: Tile, onFailure: @escaping @Sendable (Int32) -> Void) throws {
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logFile)
        log.seekToEndOfFile()
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = tile.id == "steam" ? [cli.path, "steam", "Steam"] : [cli.path, "game", "Steam", tile.id]
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { if $0.terminationStatus != 0 { onFailure($0.terminationStatus) } }
        try process.run()
    }
}

struct TileView: View {
    let tile: Tile
    let launching: Bool
    let hovered: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                artwork
                    .frame(width: 150, height: 225)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(LinearGradient(colors: [pink, violet], startPoint: .topLeading,
                                                         endPoint: .bottomTrailing), lineWidth: 2)
                            .opacity(hovered ? 1 : 0)
                    }
                    .overlay { if launching { launchingBadge } }
                    .shadow(color: .black.opacity(hovered ? 0.45 : 0.25), radius: hovered ? 14 : 6, y: hovered ? 8 : 3)
                Text(tile.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
            .scaleEffect(hovered ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.spring(duration: 0.25, bounce: 0.15)) { onHover(over) } }
        .accessibilityLabel("Lancer \(tile.name)")
    }

    @ViewBuilder private var artwork: some View {
        if tile.id == "steam" {
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
                if let image = tile.image {
                    Image(nsImage: image).resizable().interpolation(.high).frame(width: 72, height: 72)
                }
            }
        } else if let image = tile.image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [magenta, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(tile.name.prefix(1)).font(.system(size: 56, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    private var launchingBadge: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Lancement…").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
        }
    }
}

// Plain ObservableObject: SwiftUI's @State/@Observable macros need Xcode's plugins, absent with Command Line Tools.
@MainActor
final class LauncherModel: ObservableObject {
    @Published var tiles = Library.tiles()
    @Published var launching: Set<String> = []
    @Published var hovered: String?
    @Published var failure: String?

    func refresh() {
        let fresh = Library.tiles()
        if fresh != tiles { tiles = fresh }
    }

    func start(_ tile: Tile) {
        guard !launching.contains(tile.id) else { return }
        do {
            let name = tile.name
            try Launcher.launch(tile) { status in
                Task { @MainActor in self.failure = "Lancement de \(name) échoué (code \(status)), voir ~/Library/Logs/Cuvee.log" }
            }
            failure = nil
            launching.insert(tile.id)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))   // Steam takes a few seconds to show the game window
                self.launching.remove(tile.id)
            }
        } catch {
            failure = "Impossible de lancer \(tile.name) : \(error.localizedDescription)"
        }
    }
}

struct QuickLaunchView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Démarrage rapide")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                if model.tiles.count == 1 {
                    Text("Aucun jeu installé dans Steam pour l'instant.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 24, alignment: .top)],
                          alignment: .leading, spacing: 28) {
                    ForEach(model.tiles) { tile in
                        TileView(tile: tile, launching: model.launching.contains(tile.id),
                                 hovered: model.hovered == tile.id,
                                 onHover: { over in model.hovered = over ? tile.id : nil }) { model.start(tile) }
                    }
                }
                if let failure = model.failure {
                    Text(failure).font(.system(size: 12)).foregroundStyle(pink)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.078, green: 0.067, blue: 0.106))   // #14111b
        .frame(minWidth: 560, minHeight: 420)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CuveeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Cuvee", id: "main") {
            QuickLaunchView().preferredColorScheme(.dark)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
    }
}
