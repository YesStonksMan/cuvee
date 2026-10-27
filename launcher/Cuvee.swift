// SPDX-License-Identifier: LGPL-2.1-or-later
// Cuvee window: a sidebar (search, all games, launchers to start or install, bottles, bug reporting) and the selected
// page. Every action calls the installed runtime CLI.
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
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
            .scaleEffect(hovered ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.spring(duration: 0.25, bounce: 0)) { onHover(over) } }
        .help(tile.name)
        .accessibilityLabel(tr("Lancer \(tile.name)", "Launch \(tile.name)"))
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
                Text(tr("Lancement…", "Launching…")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
        }
    }
}

struct Sidebar: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        List(selection: $model.page) {
            Section(tr("Bibliothèque", "Library")) {
                Label(tr("Tous les jeux", "All games"), systemImage: "square.grid.2x2").tag(Page.library)
            }
            Section(tr("Lanceurs", "Launchers")) {
                ForEach(LauncherKind.all.filter { model.matches($0.bottle) }) { kind in
                    if let bottle = model.bottle(for: kind) {
                        installedRow(kind, bottle).tag(Page.bottle(bottle.name))
                    } else {
                        missingRow(kind)
                    }
                }
            }
            Section {
                ForEach(model.plainBottles.filter { model.matches($0.name) }) { bottle in
                    Label(bottle.name, systemImage: "shippingbox").tag(Page.bottle(bottle.name))
                }
            } header: {
                HStack {
                    Text(tr("Bouteilles", "Bottles"))
                    Spacer()
                    Button { model.creating = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help(tr("Nouvelle bouteille vide", "New empty bottle"))
                        .accessibilityLabel(tr("Nouvelle bouteille vide", "New empty bottle"))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            List(selection: $model.page) {
                Label(tr("Signaler un bug", "Report a bug"), systemImage: "ladybug").tag(Page.bug)
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .frame(height: 44)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
    }

    private func installedRow(_ kind: LauncherKind, _ bottle: Bottle) -> some View {
        HStack {
            Label(kind.bottle, systemImage: "gamecontroller")
            Spacer()
            if let opener = bottle.tiles.first(where: { if case .open = $0.action { true } else { false } }) {
                if model.launching.contains(opener.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.start(opener) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless)
                        .help(tr("Démarrer \(kind.bottle)", "Start \(kind.bottle)"))
                        .accessibilityLabel(tr("Démarrer \(kind.bottle)", "Start \(kind.bottle)"))
                }
            }
        }
    }

    private func missingRow(_ kind: LauncherKind) -> some View {
        HStack {
            Label(kind.bottle, systemImage: "gamecontroller").foregroundStyle(.secondary)
            Spacer()
            if model.installing.contains(kind.id) {
                ProgressView().controlSize(.small).help(tr("Installation…", "Installing…"))
            } else {
                Button(tr("Installer", "Install")) { model.install(kind) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(tr("Installer \(kind.bottle) depuis le site de son éditeur", "Install \(kind.bottle) from its publisher's site"))
            }
        }
    }
}

struct RootView: View {
    @StateObject private var model = LauncherModel()
    @AppStorage(Language.key) private var language = Language.system.rawValue   // re-renders every text on change

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom) { if let failure = model.failure { failureBar(failure) } }
        }
        .searchable(text: $model.query, placement: .sidebar, prompt: tr("Rechercher", "Search"))
        .id(language)
        .frame(minWidth: 900, minHeight: 620)
        .sheet(isPresented: $model.creating) { NewBottleSheet(model: model) }
        .confirmationDialog(tr("Mettre « \(model.removing?.name ?? "") » à la Corbeille ?",
                               "Move “\(model.removing?.name ?? "")” to the Trash?"),
                            isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } }),
                            presenting: model.removing) { bottle in
            Button(tr("Mettre à la Corbeille", "Move to Trash"), role: .destructive) { model.remove(bottle) }
        } message: { _ in
            Text(tr("La bouteille et ce qui y est installé partent à la Corbeille. Tu peux l'en ressortir tant qu'elle n'est pas vidée.",
                    "The bottle and everything installed in it go to the Trash. You can take it back until the Trash is emptied."))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.page {
        case .bottle(let name)?:
            if let bottle = model.bottle(named: name) { BottlePage(bottle: bottle, model: model) } else { LibraryPage(model: model) }
        case .bug?: BugPage()
        default: LibraryPage(model: model)
        }
    }

    private func failureBar(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(pink)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            Button { model.failure = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(tr("Fermer", "Dismiss"))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}

struct SettingsView: View {
    @AppStorage(Language.key) private var language = Language.system.rawValue

    var body: some View {
        Form {
            Picker(tr("Langue", "Language"), selection: $language) {
                Text(tr("Celle du Mac", "Same as the Mac")).tag(Language.system.rawValue)
                Text("Français").tag(Language.fr.rawValue)
                Text("English").tag(Language.en.rawValue)
            }
        }
        .padding(24)
        .frame(width: 380)
        .id(language)
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
            RootView().preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 880)   // a bottle page (games, settings, recommendation) fits without scrolling
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) {
                Button(tr("Signaler un bug…", "Report a bug…")) { BugReport.open() }
            }
        }
        Settings {
            SettingsView().preferredColorScheme(.dark)
        }
    }
}
