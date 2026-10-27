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

    private var isValid: Bool {
        !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".."
            && !model.bottles.contains { $0.name == trimmed }
    }

    private func create() {
        guard isValid else { return }
        model.create(trimmed)
        dismiss()
    }
}
