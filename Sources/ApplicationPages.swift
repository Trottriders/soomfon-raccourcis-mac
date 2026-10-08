import AppKit
import UniformTypeIdentifiers

struct ApplicationPage: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var pageID: String
    var id: String { bundleID }
    var isValid: Bool {
        !name.isEmpty && name.count <= 80 && bundleID.count <= 255
            && bundleID.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
            && UUID(uuidString: pageID) != nil
    }
}

struct AutomaticPageState {
    private(set) var automaticPageID: String?
    private(set) var launchInProgress = false
    private var launchedBundleID: String?
    mutating func manuallySelected() { automaticPageID = nil; launchInProgress = false; launchedBundleID = nil }
    mutating func beginLaunch() { launchInProgress = true; launchedBundleID = nil }
    mutating func finishLaunch(pageID: String, bundleID: String?) {
        launchInProgress = false; automaticPageID = pageID == homePageID ? nil : pageID; launchedBundleID = bundleID
    }
    mutating func cancelLaunch() { launchInProgress = false }
    mutating func activated(bundleID: String?, ownBundleID: String?, configuration: DeckConfiguration) -> String? {
        guard let bundleID, bundleID != ownBundleID else { return nil }
        // An explicit page on a launcher takes priority over the app's usual
        // page, including activation notifications arriving after completion.
        guard !launchInProgress else { return nil }
        if let launchedBundleID {
            if bundleID == launchedBundleID { return nil }
            self.launchedBundleID = nil
        }
        if configuration.automaticPagesEnabled ?? true,
           let rule = configuration.applicationPages?.first(where: { $0.bundleID == bundleID }) {
            automaticPageID = rule.pageID
            return rule.pageID
        }
        guard automaticPageID != nil else { return nil }
        automaticPageID = nil
        return homePageID
    }
}

extension DeckPage {
    mutating func addHomeButtons() {
        for index in [13, 14] {
            var key = keys[index]
            if key.title.isEmpty { key.title = "Accueil" }
            key.actionKind = .page; key.targetPageID = homePageID
            key.shortcut = nil; key.macro = nil; key.applicationPath = nil; key.pressMode = nil; key.launchPageID = nil
            keys[index] = key
        }
    }
    var canReserveHomeButtons: Bool {
        keys.suffix(2).allSatisfy {
            ($0.effectiveKind == .shortcut && $0.shortcut == nil)
                || ($0.effectiveKind == .page && $0.targetPageID == homePageID)
        }
    }
}

extension DeckModel {
    var currentApplicationPages: [ApplicationPage] {
        (configuration.applicationPages ?? []).filter { $0.pageID == activePageID }
    }
    var isHomeNavigationKey: Bool { selected >= 13 && configuration.requiresHomeNavigation(on: activePageID) }

    func chooseApplicationPage(createPage: Bool) {
        recording = false; cancelActions()
        let targetPageID = activePageID
        let panel = NSOpenPanel()
        panel.title = createPage ? "Créer une page pour un logiciel" : "Associer cette page à un logiciel"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            error = "Cette application n’a pas d’identifiant utilisable."; return
        }
        guard bundleID != Bundle.main.bundleIdentifier else {
            error = "Choisis l’application à contrôler, comme ton navigateur ou ton éditeur."; return
        }
        if createPage, let existing = configuration.applicationPages?.first(where: { $0.bundleID == bundleID }) {
            switchPage(existing.pageID); return
        }
        guard (configuration.applicationPages ?? []).count < 100
            || configuration.applicationPages?.contains(where: { $0.bundleID == bundleID }) == true else { return }
        let name = String(url.deletingPathExtension().lastPathComponent.prefix(80))
        var page: DeckPage
        if createPage {
            guard (configuration.pages ?? []).count < 50 else { error = "La limite de 50 pages est atteinte."; return }
            page = DeckPage(name: name)
        } else {
            guard targetPageID != homePageID, let existing = configuration.pages?.first(where: { $0.id == targetPageID }) else { return }
            guard existing.canReserveHomeButtons else {
                error = "Les touches 14 et 15 doivent être libres pour revenir à l’accueil. Tu peux aussi créer une nouvelle page pour cette application."; return
            }
            page = existing
        }
        let rule = ApplicationPage(bundleID: bundleID, name: name, pageID: page.id)
        guard rule.isValid else { error = "Cette application n’a pas d’identifiant utilisable."; return }
        page.addHomeButtons()
        if configuration.pages == nil { configuration.pages = [] }
        if let index = configuration.pages!.firstIndex(where: { $0.id == page.id }) { configuration.pages![index] = page }
        else { configuration.pages!.append(page) }
        if configuration.applicationPages == nil { configuration.applicationPages = [] }
        configuration.applicationPages!.removeAll { $0.bundleID == bundleID }
        configuration.applicationPages!.append(rule)
        configuration.automaticPagesEnabled = true
        save(); switchPage(page.id)
    }

    func removeApplicationPage(_ bundleID: String) {
        configuration.applicationPages?.removeAll { $0.bundleID == bundleID }
        save()
    }
}
