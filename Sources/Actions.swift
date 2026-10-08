import AppKit

let homePageID = "home"

enum KeyActionKind: String, Codable, CaseIterable, Identifiable {
    case shortcut, text, macro, application, website, screenCapture, page
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shortcut: return "Raccourci clavier"
        case .text: return "Insérer du texte"
        case .macro: return "Macro"
        case .application: return "Ouvrir une application"
        case .website: return "Ouvrir un site Internet"
        case .screenCapture: return "Capture d’écran avec Snapzy"
        case .page: return "Afficher une page"
        }
    }
}
enum ScreenCaptureMode: String, Codable, CaseIterable, Identifiable {
    case area, fullscreen, window
    var id: String { rawValue }
    var title: String {
        switch self { case .area: return "Une zone à sélectionner"; case .fullscreen: return "Tout l’écran"; case .window: return "Une fenêtre à choisir" }
    }
    var url: URL { URL(string: "snapzy://capture/" + (self == .window ? "application" : rawValue))! }
}
enum PressMode: String, Codable, CaseIterable, Identifiable {
    case tap, hold
    var id: String { rawValue }
    var title: String { self == .tap ? "Un appui" : "Maintenu sous le doigt" }
}
enum MacroStepKind: String, Codable { case shortcut, text, wait, application, website }
struct MacroStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: MacroStepKind
    var shortcut: Shortcut? = nil
    var seconds: Double = 0.5
    var applicationPath: String? = nil
    var websiteAddress: String? = nil
    var text: String? = nil
    var isValid: Bool {
        seconds.isFinite && (0...60).contains(seconds) && (shortcut?.isValid ?? true)
            && (applicationPath.map(validApplicationPath) ?? true) && (websiteAddress.map(validWebsiteDraft) ?? true)
            && (text.map(TextInsertion.isValid) ?? true)
    }
    var label: String {
        switch kind {
        case .shortcut: return shortcut?.display ?? "Raccourci à choisir"
        case .text: return "Insérer du texte"
        case .wait: return "Attendre \(String(format: "%.2g", seconds)) s"
        case .website: return websiteAddress.flatMap(websiteURL)?.host ?? "Site à choisir"
        case .application: return applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "Application à choisir"
        }
    }
    var isReady: Bool {
        switch kind {
        case .shortcut: return shortcut != nil
        case .text: return text.map { !$0.isEmpty && TextInsertion.isValid($0) } ?? false
        case .wait: return true
        case .application: return applicationPath != nil
        case .website: return websiteAddress.flatMap(websiteURL) != nil
        }
    }
}
func validWebsiteDraft(_ value: String) -> Bool { value.count <= 4096 && !value.contains("\0") }
func websiteURL(_ value: String) -> URL? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, validWebsiteDraft(text), !text.contains(where: { $0.isWhitespace }) else { return nil }
    let normalized = text.contains("://") ? text : "https://" + text
    guard let url = URL(string: normalized), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
    return url
}
func validApplicationPath(_ path: String) -> Bool {
    path.hasPrefix("/") && path.hasSuffix(".app") && path.count <= 4096 && !path.contains("\0")
}
struct DeckPage: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name = "Nouvelle page"
    var keys = Array(repeating: KeyAssignment(), count: 15)
    var isValid: Bool { UUID(uuidString: id) != nil && !name.isEmpty && name.count <= 80 && keys.count == 15 && keys.allSatisfy(\.isValid) }
}

// Rendering and input use the same active-page selection; page switches never
// retain a shortcut from the previous page.
extension DeckConfiguration {
    var allPages: [DeckPage] { [DeckPage(id: homePageID, name: homeName ?? "Accueil", keys: keys)] + (pages ?? []) }
    func keys(on pageID: String) -> [KeyAssignment] { (pages ?? []).first { $0.id == pageID }?.keys ?? keys }
    mutating func setKeys(_ value: [KeyAssignment], on pageID: String) {
        if let index = pages?.firstIndex(where: { $0.id == pageID }) { pages![index].keys = value }
        else { keys = value }
    }
    func containsPage(_ id: String) -> Bool { id == homePageID || (pages ?? []).contains { $0.id == id } }
    func launchers(for pageID: String) -> [KeyAssignment] {
        allPages.flatMap(\.keys).filter { [.application, .website].contains($0.effectiveKind) && $0.launchPageID == pageID }
    }
    func requiresHomeNavigation(on pageID: String) -> Bool {
        pageID != homePageID && (!(applicationPages ?? []).filter { $0.pageID == pageID }.isEmpty || !launchers(for: pageID).isEmpty)
    }

    mutating func removeReferences(to removed: String) {
        for page in allPages {
            var updated = page.keys
            for index in updated.indices {
                if updated[index].targetPageID == removed { updated[index].targetPageID = homePageID }
                if updated[index].launchPageID == removed { updated[index].launchPageID = nil }
            }
            setKeys(updated, on: page.id)
        }
    }
}

@MainActor final class MacroRunner {
    private var task: Task<Void, Never>?
    private var runID: UUID?
    var isRunning: Bool { runID != nil }
    func cancel() { task?.cancel(); task = nil; runID = nil }
    func start(steps: [MacroStep], perform: @escaping (MacroStep) async throws -> Void, progress: @escaping (Int) -> Void, finished: @escaping (String?) -> Void) {
        cancel()
        guard !steps.isEmpty, steps.count <= 100, steps.allSatisfy({ $0.isValid && $0.isReady }) else {
            finished("La macro contient une étape incomplète ou invalide."); return
        }
        let id = UUID(); runID = id
        task = Task { [weak self] in
            do {
                for (index, step) in steps.enumerated() {
                    try Task.checkCancellation(); progress(index)
                    if step.kind == .wait {
                        try await Task.sleep(nanoseconds: UInt64(step.seconds * 1_000_000_000))
                    } else { try await perform(step) }
                }
                try Task.checkCancellation()
                guard let self, self.runID == id else { return }
                self.task = nil; self.runID = nil; finished(nil)
            } catch {
                guard let self, self.runID == id else { return }
                self.task = nil; self.runID = nil
                if !(error is CancellationError) { finished(error.localizedDescription) }
            }
        }
    }
}
