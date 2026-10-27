// SPDX-License-Identifier: LGPL-2.1-or-later
// Detail pages of Cuvee.app: every installed game, one bottle (start, games, settings), and bug reporting.
import AppKit
import SwiftUI

struct TileGrid: View {
    let tiles: [Tile]
    @ObservedObject var model: LauncherModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 24, alignment: .top)],
                  alignment: .leading, spacing: 28) {
            ForEach(tiles) { tile in
                TileView(tile: tile, launching: model.launching.contains(tile.id), hovered: model.hovered == tile.id,
                         onHover: { over in model.hovered = over ? tile.id : nil }) { model.start(tile) }
            }
        }
    }
}

struct LibraryPage: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        let shown = model.games.filter { model.matches($0.name) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.games.isEmpty {
                    Text(tr("Aucun jeu installé pour l'instant. Installe un lanceur dans la barre de gauche, puis tes jeux depuis ce lanceur.",
                            "No games installed yet. Install a launcher from the sidebar, then your games from that launcher."))
                        .foregroundStyle(.secondary).frame(maxWidth: 420, alignment: .leading)
                } else if shown.isEmpty {
                    Text(tr("Aucun jeu ne correspond à « \(model.query) ».", "No game matches “\(model.query)”."))
                        .foregroundStyle(.secondary)
                } else {
                    TileGrid(tiles: shown, model: model)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .navigationTitle(tr("Tous les jeux", "All games"))
    }
}

struct BottlePage: View {
    let bottle: Bottle
    @ObservedObject var model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                if !bottle.games.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(tr("Jeux", "Games")).font(.title3.weight(.semibold))
                        TileGrid(tiles: bottle.games.filter { model.matches($0.name) }, model: model)
                    }
                }
                settings
                Button(role: .destructive) { model.removing = bottle } label: {
                    Label(tr("Mettre à la Corbeille…", "Move to Trash…"), systemImage: "trash")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .navigationTitle(bottle.name)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.name).font(.largeTitle.bold())
                Text(bottle.launcher == nil ? tr("Bouteille vide", "Empty bottle") : tr("Lanceur de jeux", "Game launcher"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let opener = bottle.opener {
                let launching = model.launching.contains(opener.id), stopping = model.stopping.contains(bottle.name)
                let open = model.open.contains(bottle.name) && !launching
                Button { open ? model.stop(bottle) : model.start(opener) } label: {
                    Label(launching ? tr("Lancement…", "Launching…") : stopping ? tr("Arrêt…", "Stopping…")
                          : open ? tr("Arrêter", "Stop") : tr("Démarrer", "Start"),
                          systemImage: open || stopping ? "stop.fill" : "play.fill")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .tint(open || stopping ? .red : .accentColor)
                .controlSize(.large)
                .disabled(launching || stopping)
                .keyboardShortcut(open ? nil : .defaultAction)   // Return must never close a running launcher
            }
        }
    }

    private var settings: some View {
        let graphics = Binding(get: { bottle.graphics },
                               set: { model.save(bottle, graphics: $0, metalFX: $0 == .dxmt && bottle.metalFX) })
        let metalFX = Binding(get: { bottle.metalFX }, set: { model.save(bottle, graphics: bottle.graphics, metalFX: $0) })
        return VStack(alignment: .leading, spacing: 14) {
            Text(tr("Réglages", "Settings")).font(.title3.weight(.semibold))
            Form {
                Picker(tr("Moteur graphique", "Graphics engine"), selection: graphics) {
                    ForEach(Graphics.allCases) { Text($0.label).tag($0) }
                }
                Toggle(tr("Mise à l'échelle MetalFX", "MetalFX upscaling"), isOn: metalFX).disabled(bottle.graphics != .dxmt)
            }
            .frame(maxWidth: 460, alignment: .leading)
            Text(note).font(.callout).foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let chip = Device.chip, let rec = Device.recommended {
                recommendation(chip: chip, graphics: rec.graphics, metalFX: rec.metalFX)
            }
        }
    }

    private func recommendation(chip: String, graphics: Graphics, metalFX: Bool) -> some View {
        let applied = bottle.graphics == graphics && bottle.metalFX == metalFX
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cpu").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Recommandé pour \(chip)", "Recommended for \(chip)")).font(.headline)
                Text("\(graphics.label) · MetalFX \(metalFX ? tr("activé", "on") : tr("désactivé", "off"))")
                Text(Device.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(applied ? tr("Appliqué", "Applied") : tr("Appliquer", "Apply")) {
                model.save(bottle, graphics: graphics, metalFX: metalFX)
            }
            .disabled(applied)
        }
        .padding(16)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var note: String {
        let base: String = switch bottle.graphics {
        case .vulkan: tr("Par défaut : Direct3D 10/11 passe par Vulkan, traduit en Metal par MoltenVK.",
                         "Default: Direct3D 10/11 goes through Vulkan, turned into Metal by MoltenVK.")
        case .opengl: tr("Pour un jeu qui s'affiche mal avec Vulkan.", "For a game that looks wrong with Vulkan.")
        case .dxmt: tr("Direct3D 10/11 traduit directement en Metal. L'option DLSS d'un jeu DirectX 11 passe par MetalFX ; le FSR se règle dans le jeu.",
                       "Direct3D 10/11 turned straight into Metal. A DirectX 11 game's DLSS option uses MetalFX; FSR is set in the game.")
        }
        return base + " " + tr("Pris en compte au prochain lancement.", "Applies from the next launch.")
    }
}

enum BugReport {
    static let issues = "https://github.com/YesStonksMan/cuvee/issues/new"

    /// A new GitHub issue with a template and the Mac's model, nothing else: the user reads it before sending.
    static func open() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let system = "Cuvee \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(Device.chip ?? "Intel")"
        let body = tr("""
            **Ce qui se passe**


            **Ce que tu attendais**


            **Pour le reproduire** (lanceur, jeu, moteur graphique)


            ---
            \(system)
            """, """
            **What happens**


            **What you expected**


            **Steps to reproduce** (launcher, game, graphics engine)


            ---
            \(system)
            """)
        var url = URLComponents(string: issues)!
        url.queryItems = [URLQueryItem(name: "body", value: body)]
        if let link = url.url { NSWorkspace.shared.open(link) }
    }

    static func revealLog() {
        if FileManager.default.fileExists(atPath: logFile.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logFile])
        } else {
            NSWorkspace.shared.open(logFile.deletingLastPathComponent())
        }
    }
}

struct BugPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "ladybug").font(.system(size: 40)).foregroundStyle(.tint)
                Text(tr("Signaler un bug", "Report a bug")).font(.largeTitle.bold())
                Text(tr("Un lanceur ou un jeu ne marche pas ? Ouvre un signalement sur GitHub : un modèle s'ouvre dans ton navigateur, avec la version de Cuvee, de macOS et ta puce déjà remplies. Rien n'est envoyé tant que tu ne cliques pas sur « Submit ».",
                        "A launcher or game does not work? Open a report on GitHub: a template opens in your browser with the Cuvee and macOS versions and your chip filled in. Nothing is sent until you click “Submit”."))
                    .foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Text(tr("Le journal aide beaucoup : glisse-le dans le signalement. Relis-le avant, il contient les noms de tes dossiers.",
                        "The log helps a lot: drag it into the report. Read it first, it contains your folder names."))
                    .foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { BugReport.open() } label: {
                        Label(tr("Signaler sur GitHub", "Report on GitHub"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Button { BugReport.revealLog() } label: {
                        Label(tr("Afficher le journal", "Show the log"), systemImage: "doc.text.magnifyingglass")
                    }
                    .controlSize(.large)
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .navigationTitle(tr("Signaler un bug", "Report a bug"))
    }
}
