import AppKit

struct ShortcutModifierChoice: Identifiable {
    var id: UInt64 { UInt64(flag.rawValue) }
    let title: String
    let flag: NSEvent.ModifierFlags
    static let all = [
        ShortcutModifierChoice(title: "Ctrl ⌃", flag: .control),
        ShortcutModifierChoice(title: "Option ⌥", flag: .option),
        ShortcutModifierChoice(title: "Majuscule ⇧", flag: .shift),
        ShortcutModifierChoice(title: "Commande ⌘", flag: .command)
    ]
}
struct ShortcutKeyChoice: Identifiable {
    let code: UInt16
    let label: String
    var id: Int { Int(code) }
    static var characters: [ShortcutKeyChoice] {
        (UInt16(0)...UInt16(50)).compactMap { code in
            guard ![36,48,49].contains(code), let value = KeyboardLayout.character(for: code), value.count == 1,
                  value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespaces.contains($0) }) else { return nil }
            return ShortcutKeyChoice(code: code, label: value.uppercased())
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    static let specials: [ShortcutKeyChoice] = [
        .init(code: 49, label: "Espace"), .init(code: 36, label: "↩ Entrée"),
        .init(code: 48, label: "⇥ Tabulation"), .init(code: 53, label: "Échap"),
        .init(code: 51, label: "⌫ Retour arrière"), .init(code: 117, label: "⌦ Supprimer"),
        .init(code: 123, label: "←"), .init(code: 124, label: "→"),
        .init(code: 125, label: "↓"), .init(code: 126, label: "↑"),
        .init(code: 115, label: "Début"), .init(code: 119, label: "Fin"),
        .init(code: 116, label: "Page précédente"), .init(code: 121, label: "Page suivante"),
        .init(code: 122, label: "F1"), .init(code: 120, label: "F2"),
        .init(code: 99, label: "F3"), .init(code: 118, label: "F4"),
        .init(code: 96, label: "F5"), .init(code: 97, label: "F6"),
        .init(code: 98, label: "F7"), .init(code: 100, label: "F8"),
        .init(code: 101, label: "F9"), .init(code: 109, label: "F10"),
        .init(code: 103, label: "F11"), .init(code: 111, label: "F12")
    ]
    static var all: [ShortcutKeyChoice] { characters + specials }
}
extension Shortcut {
    var isModifiersOnly: Bool { modifiersOnly ?? false }
    static func composed(code: UInt16?, label: String, modifiers: UInt64) -> Shortcut? {
        let flags = modifiers & UInt64(allowedFlags.rawValue)
        guard code != nil || flags != 0 else { return nil }
        let shortcut = Shortcut(keyCode: code ?? 0, modifiers: flags, keyLabel: code == nil ? "" : label, modifiersOnly: code == nil)
        return shortcut.isValid ? shortcut : nil
    }
}
