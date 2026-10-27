// SPDX-License-Identifier: LGPL-2.1-or-later
// State of Cuvee.app: the bottles on disk, what is selected, searched, launching or installing.
import Foundation

enum Page: Hashable {
    case library
    case bottle(String)
    case bug
}

// Plain ObservableObject: SwiftUI's @Observable macro needs Xcode's plugins, absent with Command Line Tools.
@MainActor
final class LauncherModel: ObservableObject {
    @Published var bottles = Library.bottles()
    // `open Cuvee.app --args -page NAME` opens on that bottle (handy for screenshots)
    @Published var page: Page? = UserDefaults.standard.string(forKey: "page").map(Page.bottle) ?? .library
    @Published var query = ""
    @Published var installing: Set<String> = []
    @Published var launching: Set<String> = []
    @Published var hovered: String?
    @Published var failure: String?
    @Published var creating = false
    @Published var removing: Bottle?

    func refresh() {
        let fresh = Library.bottles()
        if fresh != bottles { bottles = fresh }
        if case .bottle(let name)? = page, bottle(named: name) == nil { page = .library }
    }

    func bottle(named name: String) -> Bottle? { bottles.first { $0.name == name } }
    func bottle(for kind: LauncherKind) -> Bottle? { bottles.first { $0.launcher == kind.id } }
    var plainBottles: [Bottle] { bottles.filter { $0.launcher == nil } }

    var games: [Tile] {
        bottles.flatMap(\.tiles).filter { if case .game = $0.action { true } else { false } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func matches(_ text: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.localizedCaseInsensitiveContains(q)
    }

    func start(_ tile: Tile) {
        guard !launching.contains(tile.id) else { return }
        guard run(CLI.args(for: tile.action), what: tr("Lancement de \(tile.name)", "Launching \(tile.name)"), isLaunch: true)
        else { return }
        launching.insert(tile.id)
        Task {
            try? await Task.sleep(for: .seconds(6))   // a launcher takes a few seconds to show its window
            launching.remove(tile.id)
        }
    }

    func install(_ kind: LauncherKind) {
        let what = tr("Installation de \(kind.bottle)", "Installing \(kind.bottle)")
        if run(["add", kind.id], what: what, then: { _ in self.installing.remove(kind.id) }) {
            installing.insert(kind.id)
        }
    }

    func create(_ name: String) {
        run(["create", name], what: tr("Création de « \(name) »", "Creating “\(name)”"), then: { ok in
            if ok { self.page = .bottle(name) }
        })
    }

    func remove(_ bottle: Bottle) {
        run(["remove", bottle.name], what: tr("Suppression de « \(bottle.name) »", "Removing “\(bottle.name)”"))
    }

    /// Shows the new settings at once, then writes them; a failed write reloads what is on disk.
    func save(_ bottle: Bottle, graphics: Graphics, metalFX: Bool) {
        let updated = Bottle(name: bottle.name, launcher: bottle.launcher, graphics: graphics, metalFX: metalFX, tiles: bottle.tiles)
        bottles = bottles.map { $0.name == bottle.name ? updated : $0 }
        let what = tr("Réglages de « \(bottle.name) »", "Settings of “\(bottle.name)”")
        run(["set", bottle.name, "graphics", graphics.rawValue], what: what, refreshing: false) { ok in
            if ok { self.run(["set", bottle.name, "metalfx", metalFX ? "on" : "off"], what: what) } else { self.refresh() }
        }
    }

    /// Runs the CLI; on exit reports a failure, refreshes the bottles (unless told not to), then calls `then(succeeded)`.
    @discardableResult
    private func run(_ args: [String], what: String, refreshing: Bool = true, isLaunch: Bool = false,
                     then: @escaping @MainActor (Bool) -> Void = { _ in }) -> Bool {
        let started = Date()
        do {
            try CLI.run(args) { status in
                Task { @MainActor in
                    // a launcher's own exit code arrives when it quits, maybe hours later: only an early exit is a failed launch
                    let failed = status != 0 && (!isLaunch || Date().timeIntervalSince(started) < 15)
                    if failed {
                        self.failure = tr("\(what) : échec (code \(status)), voir ~/Library/Logs/Cuvee.log",
                                          "\(what) failed (code \(status)), see ~/Library/Logs/Cuvee.log")
                    }
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
