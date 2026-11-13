// SPDX-License-Identifier: LGPL-2.1-or-later
import AppKit
import CoreServices
import SwiftUI

@MainActor
final class Updater: ObservableObject {
    enum Phase {
        case idle, checking, current, available(AvailableUpdate), downloading(AvailableUpdate), ready(AvailableUpdate, URL), failed(String)
    }
    @Published private(set) var phase = Phase.idle
    static let shared = Updater()
    static let automaticKey = "automaticallyCheckUpdates"
    let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private var lastCheck = Date.distantPast
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    func check(automatic: Bool = false) {
        switch phase { case .checking, .downloading, .ready: return; default: break }
        if automatic {
            guard UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true,
                  Date().timeIntervalSince(lastCheck) > 24 * 60 * 60 else { return }
        }
        phase = .checking
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/YesStonksMan/cuvee/releases?per_page=20")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Cuvee/\(installed)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure.feed }
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                if let update = UpdateFeed.newest(releases, after: installed) { phase = .available(update) }
                else { phase = .current }
                lastCheck = Date()
            } catch {
                phase = automatic ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func download(_ update: AvailableUpdate) {
        guard case .available = phase, update.installer.trustedInstaller else { return }
        phase = .downloading(update)
        Task {
            do {
                let (temp, response) = try await session.download(from: update.installer.browserDownloadURL)
                defer { try? FileManager.default.removeItem(at: temp) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure.download }
                let expected = String(update.installer.digest!.dropFirst(7))
                let actual = try await Task.detached { try UpdateIntegrity.sha256(temp) }.value
                guard actual == expected else { throw UpdateFailure.checksum }
                let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
                    .appending(path: "io.github.yesstonksman.cuvee/Updates")
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                var target = cache.appending(path: update.installer.name)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.moveItem(at: temp, to: target)
                // Preserve the normal Gatekeeper decision for an Internet-downloaded installer.
                var values = URLResourceValues()
                values.quarantineProperties = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload,
                                               kLSQuarantineDataURLKey as String: update.installer.browserDownloadURL.absoluteString]
                try target.setResourceValues(values)
                phase = .ready(update, target)
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    func install(_ update: AvailableUpdate, package: URL) {
        guard !Library.bottles().contains(where: { Library.isOpen($0.name) }) else {
            let alert = NSAlert()
            alert.messageText = tr("Ferme les jeux et les lanceurs avant la mise à jour", "Close games and launchers before updating")
            alert.informativeText = tr("L'installateur est prêt. Ferme-les, puis relance l'installation ici.",
                                      "The installer is ready. Close them, then install it here.")
            alert.runModal()
            return
        }
        phase = .checking
        Task {
            do {
                // A cached file can change between download and a later click on Install.
                let hash = try await Task.detached { try UpdateIntegrity.sha256(package) }.value
                guard hash == String(update.installer.digest!.dropFirst(7)) else { throw UpdateFailure.checksum }
                guard NSWorkspace.shared.open(package) else { throw UpdateFailure.download }
                NSApp.terminate(nil)
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

}

private enum UpdateFailure: LocalizedError {
    case feed, download, checksum
    var errorDescription: String? {
        switch self {
        case .feed: tr("GitHub est indisponible. Réessaie plus tard.", "GitHub is unavailable. Try again later.")
        case .download: tr("Le téléchargement a échoué. Réessaie.", "The download failed. Try again.")
        case .checksum: tr("Fichier non conforme à l'empreinte publiée par GitHub. Installation annulée.",
                           "The file does not match GitHub's published checksum. Installation cancelled.")
        }
    }
}

struct UpdateView: View {
    @ObservedObject private var updater = Updater.shared
    @AppStorage(Updater.automaticKey) private var automatic = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Mises à jour", "Updates")).font(.headline)
            Text(tr("Version installée : \(updater.installed)", "Installed version: \(updater.installed)"))
                .foregroundStyle(.secondary)
            switch updater.phase {
            case .idle: EmptyView()
            case .checking: ProgressView(tr("Recherche…", "Checking…"))
            case .current: Text(tr("Cuvee est à jour.", "Cuvee is up to date."))
            case .available(let update):
                Text(tr("\(update.version) disponible", "\(update.version) is available"))
                if update.preview { Text(tr("Préversion sans notarisation Apple.", "Preview without Apple notarization.")).foregroundStyle(.secondary) }
                Button(tr("Télécharger la mise à jour", "Download update")) { updater.download(update) }
            case .downloading: ProgressView(tr("Téléchargement et vérification…", "Downloading and verifying…"))
            case .ready(let update, let package):
                Text(tr("Mise à jour prête. Tes jeux et sauvegardes sont conservés.", "Update ready. Your games and saves are preserved."))
                Button(tr("Installer et quitter Cuvee", "Install and quit Cuvee")) { updater.install(update, package: package) }
            case .failed(let message): Text(message).foregroundStyle(.red).textSelection(.enabled)
            }
            Button(tr("Rechercher les mises à jour", "Check for updates")) { updater.check() }
            Toggle(tr("Rechercher automatiquement", "Check automatically"), isOn: $automatic)
            Text(tr("Les mises à jour sont proposées ici ; l'installateur macOS demande ton accord avant de les appliquer.",
                    "Updates appear here; macOS Installer asks for your approval before applying them."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct UpdateCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(tr("Rechercher les mises à jour…", "Check for updates…")) {
                openWindow(id: "updates")
                Updater.shared.check()
            }
        }
    }
}
