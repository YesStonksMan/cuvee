// SPDX-License-Identifier: LGPL-2.1-or-later
// Cuvee.app speaks French and English: the language follows macOS unless one is picked in Settings.
import Foundation

enum Language: String, CaseIterable, Identifiable {
    case system, fr, en
    var id: String { rawValue }
    static let key = "language"

    static var current: Language { Language(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    static var isFrench: Bool {
        switch current {
        case .fr: true
        case .en: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("fr") ?? false
        }
    }
}

/// The French or English text, by the current language.
func tr(_ fr: String, _ en: String) -> String { Language.isFrench ? fr : en }
