import AppKit

enum TextInsertion {
    static let maximumLength = 20_000
    static func isValid(_ value: String) -> Bool {
        value.count <= maximumLength && !value.contains("\0")
    }
    static func draft(_ value: String) -> String {
        String(value.replacingOccurrences(of: "\0", with: "").prefix(maximumLength))
    }
}

// Keep every representation (including images and rich text). Restore only if
// nobody has copied something else since our temporary plain-text paste.
@MainActor struct PasteboardSnapshot {
    let items: [NSPasteboardItem]
    init?(_ pasteboard: NSPasteboard) {
        var copies: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else { return nil }
            }
            copies.append(copy)
        }
        items = copies
    }
    func restore(_ pasteboard: NSPasteboard, ifUnchangedSince changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

@MainActor final class TextInserter {
    private(set) var isInserting = false
    func insert(_ text: String, pasteboard: NSPasteboard = .general,
                paste: () -> Bool) async throws {
        guard !text.isEmpty, TextInsertion.isValid(text) else {
            throw NSError(domain: "Deck", code: 20, userInfo: [NSLocalizedDescriptionKey: "Écris le texte à insérer (20 000 caractères maximum)."])
        }
        guard !isInserting else {
            throw NSError(domain: "Deck", code: 21, userInfo: [NSLocalizedDescriptionKey: "Une insertion de texte est déjà en cours."])
        }
        try Task.checkCancellation()
        guard let original = PasteboardSnapshot(pasteboard) else {
            throw NSError(domain: "Deck", code: 22, userInfo: [NSLocalizedDescriptionKey: "Le presse-papiers n’a pas pu être conservé. Réessaie après avoir copié un texte."])
        }
        isInserting = true
        defer { isInserting = false }
        pasteboard.clearContents()
        let written = pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount
        guard written, paste() else {
            original.restore(pasteboard, ifUnchangedSince: changeCount)
            throw NSError(domain: "Deck", code: 23, userInfo: [NSLocalizedDescriptionKey: "Ouvre le champ à remplir et vérifie l’autorisation d’accessibilité."])
        }
        // Let the receiving app read the text before restoring the clipboard.
        // This cleanup finishes even if a page switch or sleep cancels the action.
        let cleanup = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            original.restore(pasteboard, ifUnchangedSince: changeCount)
        }
        await cleanup.value
        try Task.checkCancellation()
    }
}
