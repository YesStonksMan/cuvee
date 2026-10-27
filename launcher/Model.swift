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
    @Published var open: Set<String> = []       // bottles whose programs run, polled: Steam can be quit from its own menu
    @Published var stopping: Set<String> = []
    @Published var confirmingStop: Bottle?     // a game of it runs: closing the bottle closes the game
    private var startedHere: Set<String> = []  // quitting Cuvee stops these; bottles started elsewhere are left alone

    static let shared = LauncherModel()          // the app delegate stops the bottles at quit

    /// The bottles this app started that still run, and whether one of their games is open.
    func runningStarted() -> (bottles: [Bottle], gameOpen: Bool) {
        let list = bottles.filter { startedHere.contains($0.name) && Library.isOpen($0.name) }
        return (list, list.flatMap(\.games).compactMap(\.process).contains(where: Library.isRunning))
    }

    /// `cuvee stop` on each bottle, then `done` once all have exited (failed or not).
    func stopAll(_ list: [Bottle], then done: @escaping @Sendable () -> Void) {
        let group = DispatchGroup()
        for bottle in list {
            group.enter()
            do { try CLI.run(["stop", bottle.name]) { _ in group.leave() } } catch { group.leave() }
        }
        group.notify(queue: .main, execute: done)
    }

    private init() {
        Task { [weak self] in
            while let self {
                let fresh = Set(bottles.map(\.name).filter(Library.isOpen))
                // a bottle that was open and now is not was stopped (here or elsewhere): a later start is not ours
                startedHere.subtract(open.subtracting(fresh))
                if fresh != open { open = fresh }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop(_ bottle: Bottle, confirmed: Bool = false) {
        guard !stopping.contains(bottle.name) else { return }
        let markers = bottle.games.compactMap(\.process)
        Task {
            if !confirmed, await Task.detached(operation: { markers.contains(where: Library.isRunning) }).value {
                confirmingStop = bottle
                return
            }
            let what = tr("Arrêt de « \(bottle.name) »", "Stopping “\(bottle.name)”")
            if run(["stop", bottle.name], what: what, then: { _ in
                self.stopping.remove(bottle.name)
                self.open = self.open.filter(Library.isOpen)
            }) { stopping.insert(bottle.name) }
        }
    }

    func refresh() {
        let fresh = Library.bottles()
        if fresh != bottles { bottles = fresh }
        if case .bottle(let name)? = page, bottle(named: name) == nil { page = .library }
    }

    func bottle(named name: String) -> Bottle? { bottles.first { $0.name == name } }
    func bottle(for kind: LauncherKind) -> Bottle? { bottles.first { $0.launcher == kind.id } }
    var plainBottles: [Bottle] { bottles.filter { $0.launcher == nil } }

    var games: [Tile] {
        bottles.flatMap(\.games).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func matches(_ text: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.localizedCaseInsensitiveContains(q)
    }

    func start(_ tile: Tile) {
        guard !launching.contains(tile.id) else { return }
        guard run(CLI.args(for: tile.action), what: tr("Lancement de \(tile.name)", "Launching \(tile.name)"), isLaunch: true)
        else { return }
        startedHere.insert(tile.action.bottle)
        launching.insert(tile.id)
        Task {
            // a launcher shows its window within seconds; a game waits for Steam (~30 s when Steam starts cold),
            // so its badge stays until the game's own process runs, at most 2 minutes
            let deadline = Date().addingTimeInterval(tile.process == nil ? 6 : 120)
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(1))
                if let marker = tile.process, await Task.detached(operation: { Library.isRunning(marker) }).value { break }
            }
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
