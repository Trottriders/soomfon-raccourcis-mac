import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var keyLabel: String
    var modifiersOnly: Bool? = nil
    var display: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        return (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + (isModifiersOnly ? "" : keyLabel)
    }
    static let allowedFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static func label(_ event: NSEvent) -> String {
        let specials: [UInt16: String] = [36:"↩", 48:"⇥", 49:"Espace", 51:"⌫", 53:"Échap", 117:"⌦", 123:"←", 124:"→", 125:"↓", 126:"↑", 122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6", 98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12"]
        return specials[event.keyCode] ?? KeyboardLayout.character(for: event.keyCode)?.uppercased()
            ?? event.charactersIgnoringModifiers?.uppercased() ?? "Touche \(event.keyCode)"
    }
    var isValid: Bool {
        keyCode <= 126 && (isModifiersOnly || ![54,55,56,57,58,59,60,61,62,63].contains(keyCode))
            && modifiers & ~UInt64(Self.allowedFlags.rawValue) == 0
            && (isModifiersOnly ? modifiers != 0 : !keyLabel.isEmpty) && keyLabel.count <= 40
    }
}

struct KeyAssignment: Codable, Equatable {
    var title = ""
    var showTitle: Bool? = nil
    var shortcut: Shortcut? = nil
    var iconPNG: Data? = nil
    var appearance: IconAppearance? = nil
    var actionKind: KeyActionKind? = nil
    var pressMode: PressMode? = nil
    var macro: [MacroStep]? = nil
    var applicationPath: String? = nil
    var websiteAddress: String? = nil
    var text: String? = nil
    var captureMode: ScreenCaptureMode? = nil
    var effectiveCaptureMode: ScreenCaptureMode { captureMode ?? .area }
    var targetPageID: String? = nil
    var launchPageID: String? = nil
    var effectiveKind: KeyActionKind { actionKind ?? .shortcut }
    var effectivePressMode: PressMode { pressMode ?? .tap }
    var effectiveMacro: [MacroStep] { macro ?? [] }
    var isConfigured: Bool {
        switch effectiveKind {
        case .shortcut: return shortcut != nil
        case .text: return text.map { !$0.isEmpty && TextInsertion.isValid($0) } ?? false
        case .macro: return !effectiveMacro.isEmpty && effectiveMacro.allSatisfy(\.isReady)
        case .application: return applicationPath != nil
        case .website: return websiteAddress.flatMap(websiteURL) != nil
        case .screenCapture: return true
        case .page: return targetPageID != nil
        }
    }
    var actionLabel: String {
        switch effectiveKind {
        case .shortcut: return shortcut?.display ?? "—"
        case .text: return "Texte"
        case .macro: return "Macro"
        case .application: return "Ouvrir"
        case .website: return "Site ↗"
        case .screenCapture: return "Capture"
        case .page: return "Page →"
        }
    }
    var effectiveAppearance: IconAppearance { appearance ?? IconAppearance() }
    // Preserve the display of existing keys: icons alone, titles on text keys.
    var showsTitle: Bool { showTitle ?? (iconPNG == nil) }
    var isValid: Bool {
        title.count <= 80 && effectiveAppearance.isValid && (shortcut?.isValid ?? true)
        && effectiveMacro.count <= 100 && effectiveMacro.allSatisfy(\.isValid)
        && Set(effectiveMacro.map(\.id)).count == effectiveMacro.count
        && (applicationPath.map(validApplicationPath) ?? true)
        && (websiteAddress.map(validWebsiteDraft) ?? true)
        && (text.map(TextInsertion.isValid) ?? true)
        && (targetPageID.map { $0 == homePageID || UUID(uuidString: $0) != nil } ?? true)
        && (launchPageID.map { $0 == homePageID || UUID(uuidString: $0) != nil } ?? true)
        && (iconPNG.map { $0.count <= 512_000 && Array($0.prefix(8)) == [137,80,78,71,13,10,26,10] && IconImage.decode($0) != nil } ?? true)
    }
}

struct DeckConfiguration: Codable, Equatable {
    var version = 7
    var keys = Array(repeating: KeyAssignment(), count: 15)
    var brightness = 75
    var imageRotation = 90
    var dashboard: DashboardConfiguration? = DashboardConfiguration()
    var screensaver: ScreensaverConfiguration? = ScreensaverConfiguration()
    var pages: [DeckPage]? = nil
    var homeName: String? = nil
    var applicationPages: [ApplicationPage]? = nil
    var automaticPagesEnabled: Bool? = nil
    var effectiveScreensaver: ScreensaverConfiguration { screensaver ?? ScreensaverConfiguration() }
    var effectiveDashboard: DashboardConfiguration { dashboard ?? DashboardConfiguration() }
    var isValid: Bool {
        (1...7).contains(version) && keys.count == 15 && (0...100).contains(brightness)
            && [0,90,180,270].contains(imageRotation)
            && (dashboard?.isValid ?? true) && (screensaver?.isValid ?? true)
            && keys.allSatisfy(\.isValid)
            && (pages ?? []).count <= 50 && (pages ?? []).allSatisfy(\.isValid)
            && Set((pages ?? []).map(\.id)).count == (pages ?? []).count
            && (homeName.map { !$0.isEmpty && $0.count <= 80 } ?? true)
            && allPages.flatMap(\.keys).allSatisfy {
                ($0.targetPageID.map(containsPage) ?? true) && ($0.launchPageID.map(containsPage) ?? true)
            }
            && allPages.filter { requiresHomeNavigation(on: $0.id) }.allSatisfy {
                $0.keys.suffix(2).allSatisfy { $0.effectiveKind == .page && $0.targetPageID == homePageID }
            }
            && (applicationPages ?? []).count <= 100
            && Set((applicationPages ?? []).map(\.bundleID)).count == (applicationPages ?? []).count
            && (applicationPages ?? []).allSatisfy { rule in
                rule.isValid && rule.pageID != homePageID && containsPage(rule.pageID)
                && keys(on: rule.pageID).suffix(2).allSatisfy { $0.effectiveKind == .page && $0.targetPageID == homePageID }
            }
    }

    var migrated: DeckConfiguration {
        guard version < 7 else { return self }
        var updated = self
        updated.version = 7
        // Correct the old default without undoing a manual adjustment already
        // made by the user while trying the orientation picker.
        if version == 1 && imageRotation == 270 { updated.imageRotation = 90 }
        if updated.dashboard == nil { updated.dashboard = DashboardConfiguration() }
        if updated.screensaver == nil { updated.screensaver = ScreensaverConfiguration() }
        return updated
    }
}

struct ConfigurationStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("raccourcis.json") }
    var backup: URL { directory.appendingPathComponent("raccourcis.previous.json") }
    func load() throws -> DeckConfiguration {
        guard FileManager.default.fileExists(atPath: file.path) else { return DeckConfiguration() }
        let value = try JSONDecoder().decode(DeckConfiguration.self, from: Data(contentsOf: file))
        guard value.isValid else { throw NSError(domain: "Deck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Le fichier de raccourcis est invalide. Il a été conservé."]) }
        if value != value.migrated { try save(value.migrated) }
        return value.migrated
    }
    func save(_ configuration: DeckConfiguration) throws {
        guard configuration.isValid else { throw NSError(domain: "Deck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Configuration invalide."]) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep a last known valid copy; never replace it with a corrupt file.
        if let old = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(DeckConfiguration.self, from: old), decoded.isValid {
            try old.write(to: backup, options: .atomic)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: file, options: .atomic)
    }
}

struct Preset: Identifiable {
    var id: String { title }
    let title: String
    let code: UInt16
    let flags: NSEvent.ModifierFlags
    let label: String
    var assignment: KeyAssignment {
        let resolved = label.count == 1 && label.first!.isLetter ? KeyboardLayout.code(for: label) ?? code : code
        return KeyAssignment(title: title, shortcut: Shortcut(keyCode: resolved, modifiers: UInt64(flags.rawValue), keyLabel: label))
    }
    static let all: [Preset] = [
        Preset(title: "Copier", code: 8, flags: .command, label: "C"),
        Preset(title: "Coller", code: 9, flags: .command, label: "V"),
        Preset(title: "Couper", code: 7, flags: .command, label: "X"),
        Preset(title: "Annuler", code: 6, flags: .command, label: "Z"),
        Preset(title: "Rétablir", code: 6, flags: [.command,.shift], label: "Z"),
        Preset(title: "Tout sélectionner", code: 0, flags: .command, label: "A"),
        Preset(title: "Enregistrer", code: 1, flags: .command, label: "S"),
        Preset(title: "Rechercher", code: 3, flags: .command, label: "F"),
        Preset(title: "Nouvel onglet", code: 17, flags: .command, label: "T"),
        Preset(title: "Changer d’application", code: 48, flags: .command, label: "⇥"),
        Preset(title: "Capture de zone", code: 21, flags: [.command,.shift], label: "4")
    ]
}

// Resolve preset letters using the active layout (including French AZERTY).
// Persisted shortcuts retain the physical key, exactly as a recorded shortcut.
enum KeyboardLayout {
    static func character(for code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let pointer = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(pointer).assumingMemoryBound(to: UCKeyboardLayout.self)
        var state: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let result = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                    &state, characters.count, &length, &characters)
        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
    static func code(for character: String) -> UInt16? {
        (UInt16(0)...UInt16(50)).first { self.character(for: $0)?.uppercased() == character.uppercased() }
    }
}
