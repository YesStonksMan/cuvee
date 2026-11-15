// SPDX-License-Identifier: LGPL-2.1-or-later
// Sheet of Cuvee.app: naming a new empty bottle.
import SwiftUI

/// A sheet's editable fields. @State is a macro in this SDK, and its plugin ships only with Xcode.
final class Draft<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

struct NewBottleSheet: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var name = Draft("")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Nouvelle bouteille", "New bottle")).font(.title2.bold())
            Text(tr("Une bouteille vide est un Windows 10 à part, pour installer un programme à la main.",
                    "An empty bottle is a separate Windows 10, to install a program by hand."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(tr("Nom", "Name"), text: $name.value).textFieldStyle(.roundedBorder).onSubmit(create)
            if let problem { Text(problem).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button(tr("Annuler", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("Créer", "Create"), action: create).keyboardShortcut(.defaultAction).disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var trimmed: String { name.value.trimmingCharacters(in: .whitespaces) }

    /// Why "Create" is off, once something is typed (same rules as `bottle()` in the cuvee script).
    private var problem: String? {
        if trimmed.isEmpty { return nil }
        if trimmed.contains("/") || trimmed.hasPrefix(".") || trimmed.hasPrefix("-") {
            return tr("Le nom ne peut pas contenir « / » ni commencer par « . » ou « - ».",
                      "The name cannot contain “/” or start with “.” or “-”.")
        }
        // the Mac's disk ignores case: "steam" is the folder of "Steam"
        if model.bottles.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return tr("Une bouteille porte déjà ce nom.", "A bottle already has this name.")
        }
        return nil
    }

    private var isValid: Bool { !trimmed.isEmpty && problem == nil }

    private func create() {
        guard isValid else { return }
        model.create(trimmed)
        dismiss()
    }
}
