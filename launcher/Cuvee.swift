// SPDX-License-Identifier: LGPL-2.1-or-later
// Cuvee window: one section per bottle (its launcher, plus the games of Steam bottles), "+" to add a launcher
// or an empty bottle, and per-bottle settings and removal. Every action calls the installed runtime CLI.
import AppKit
import SwiftUI

private let pink = Color(red: 1, green: 0.416, blue: 0.604)      // #ff6a9a, from the app icon
private let magenta = Color(red: 0.878, green: 0.122, blue: 0.471) // #e01f78
private let violet = Color(red: 0.478, green: 0.102, blue: 0.651)  // #7a1aa6

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
        if case .open = tile.action, let image = tile.image {
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 72, height: 72)
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

// Plain ObservableObject: SwiftUI's @Observable macro needs Xcode's plugins, absent with Command Line Tools.
@MainActor
final class LauncherModel: ObservableObject {
    @Published var bottles = Library.bottles()
    @Published var installing: Set<String> = []
    @Published var launching: Set<String> = []
    @Published var hovered: String?
    @Published var failure: String?
    @Published var adding = false
    @Published var editing: Bottle?
    @Published var removing: Bottle?

    func refresh() {
        let fresh = Library.bottles()
        if fresh != bottles { bottles = fresh }
    }

    func installed(_ kind: LauncherKind) -> Bool { bottles.contains { $0.launcher == kind.id } }

    func start(_ tile: Tile) {
        guard !launching.contains(tile.id) else { return }
        guard run(CLI.args(for: tile.action), what: "Lancement de \(tile.name)") else { return }
        launching.insert(tile.id)
        Task {
            try? await Task.sleep(for: .seconds(6))   // a launcher takes a few seconds to show its window
            launching.remove(tile.id)
        }
    }

    func install(_ kind: LauncherKind) {
        if run(["add", kind.id], what: "Installation de \(kind.bottle)", then: { _ in self.installing.remove(kind.id) }) {
            installing.insert(kind.id)
        }
    }

    func create(_ name: String) { run(["create", name], what: "Création de « \(name) »") }

    func remove(_ bottle: Bottle) { run(["remove", bottle.name], what: "Suppression de « \(bottle.name) »") }

    func save(_ bottle: Bottle, graphics: Graphics, metalFX: Bool) {
        let what = "Réglages de « \(bottle.name) »"
        run(["set", bottle.name, "graphics", graphics.rawValue], what: what, refreshing: false) { ok in
            if ok { self.run(["set", bottle.name, "metalfx", metalFX ? "on" : "off"], what: what) } else { self.refresh() }
        }
    }

    /// Runs the CLI; on exit reports a failure, refreshes the bottles (unless told not to), then calls `then(succeeded)`.
    @discardableResult
    private func run(_ args: [String], what: String, refreshing: Bool = true,
                     then: @escaping @MainActor (Bool) -> Void = { _ in }) -> Bool {
        do {
            try CLI.run(args) { status in
                Task { @MainActor in
                    if status != 0 { self.failure = "\(what) : échec (code \(status)), voir ~/Library/Logs/Cuvee.log" }
                    if refreshing { self.refresh() }
                    then(status == 0)
                }
            }
            failure = nil
            return true
        } catch {
            failure = "\(what) : \(error.localizedDescription)"
            return false
        }
    }
}

struct BottleSection: View {
    let bottle: Bottle
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(bottle.name).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text(bottle.graphics.label + (bottle.metalFX ? " · MetalFX" : ""))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { model.editing = bottle } label: { Image(systemName: "gearshape") }
                    .help("Réglages")
                Button { model.removing = bottle } label: { Image(systemName: "trash") }
                    .help("Mettre à la Corbeille")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.75))
            if bottle.tiles.isEmpty {
                Text("Bouteille vide.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 24, alignment: .top)],
                          alignment: .leading, spacing: 28) {
                    ForEach(bottle.tiles) { tile in
                        TileView(tile: tile, launching: model.launching.contains(tile.id),
                                 hovered: model.hovered == tile.id,
                                 onHover: { over in model.hovered = over ? tile.id : nil }) { model.start(tile) }
                    }
                }
            }
        }
    }
}

struct QuickLaunchView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack {
                    Text("Cuvee").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Button { model.adding = true } label: { Image(systemName: "plus").font(.system(size: 15, weight: .semibold)) }
                        .buttonStyle(.borderless).foregroundStyle(.white.opacity(0.85))
                        .help("Ajouter un lanceur ou une bouteille")
                }
                if model.bottles.isEmpty {
                    Text("Aucune bouteille. Clique sur + pour installer un lanceur.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                ForEach(model.bottles) { BottleSection(bottle: $0, model: model) }
                if let failure = model.failure {
                    Text(failure).font(.system(size: 12)).foregroundStyle(pink)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.078, green: 0.067, blue: 0.106))   // #14111b
        .frame(minWidth: 560, minHeight: 420)
        .sheet(isPresented: $model.adding) { AddSheet(model: model) }
        .sheet(item: $model.editing) { SettingsSheet(bottle: $0, model: model) }
        .confirmationDialog("Mettre « \(model.removing?.name ?? "") » à la Corbeille ?",
                            isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } }),
                            presenting: model.removing) { bottle in
            Button("Mettre à la Corbeille", role: .destructive) { model.remove(bottle) }
        } message: { _ in
            Text("La bouteille et ce qui y est installé partent à la Corbeille. Tu peux l'en ressortir tant qu'elle n'est pas vidée.")
        }
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
