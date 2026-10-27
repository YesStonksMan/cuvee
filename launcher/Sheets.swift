// SPDX-License-Identifier: LGPL-2.1-or-later
// Sheets of Cuvee.app: adding a launcher or an empty bottle, and a bottle's graphics settings.
import SwiftUI

/// A sheet's editable fields. @State is a macro in this SDK, and its plugin ships only with Xcode.
final class Draft<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

struct AddSheet: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var name = Draft("")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ajouter").font(.system(size: 18, weight: .bold))
            Text("Chaque lanceur va dans sa propre bouteille et s'installe depuis le site de son éditeur.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(LauncherKind.all) { kind in
                HStack {
                    Text(kind.bottle).font(.system(size: 13, weight: .medium))
                    Spacer()
                    if model.installed(kind) {
                        Text("Installé").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else if model.installing.contains(kind.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Installer") { model.install(kind) }
                    }
                }
            }
            Divider()
            HStack {
                TextField("Bouteille vide", text: $name.value).textFieldStyle(.roundedBorder)
                Button("Créer") { model.create(name.value.trimmingCharacters(in: .whitespaces)); name.value = "" }
                    .disabled(!isValid(name.value))
            }
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".."
            && !model.bottles.contains { $0.name == trimmed }
    }
}

struct SettingsSheet: View {
    let bottle: Bottle
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var graphics: Draft<Graphics>
    @StateObject private var metalFX: Draft<Bool>

    init(bottle: Bottle, model: LauncherModel) {
        self.bottle = bottle
        self.model = model
        _graphics = StateObject(wrappedValue: Draft(bottle.graphics))
        _metalFX = StateObject(wrappedValue: Draft(bottle.metalFX))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Réglages de « \(bottle.name) »").font(.system(size: 18, weight: .bold))
            Picker("Moteur graphique", selection: $graphics.value) {
                ForEach(Graphics.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Mise à l'échelle MetalFX", isOn: $metalFX.value)
                .disabled(graphics.value != .dxmt)
            Text(note).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    model.save(bottle, graphics: graphics.value, metalFX: graphics.value == .dxmt && metalFX.value)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var note: String {
        switch graphics.value {
        case .vulkan: "Par défaut. Direct3D 10/11 passe par Vulkan, traduit en Metal par MoltenVK."
        case .opengl: "Pour un jeu qui s'affiche mal avec Vulkan."
        case .dxmt: "Direct3D 10/11 traduit directement en Metal. MetalFX agrandit l'image (le jeu calcule moins de pixels). "
            + "L'option DLSS des jeux DirectX 11 passe aussi par MetalFX. Le FSR se règle dans le jeu."
        }
    }
}
