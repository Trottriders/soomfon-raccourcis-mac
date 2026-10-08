import AppKit
import SwiftUI
import ApplicationServices
import ImageIO
import UniformTypeIdentifiers

@MainActor final class DashboardState: ObservableObject {
    @Published var previews: [Data] = []
    @Published var weatherStatus = "Choisis la ville de la météo."
    @Published var weather: WeatherReading? = nil
    @Published var activeAppName = ""
    @Published var clockText = ""
}

@MainActor final class DeckModel: ObservableObject {
    @Published var configuration = DeckConfiguration()
    @Published var activePageID = homePageID
    private var automaticPageState = AutomaticPageState()
    @Published var keyPreviews: [NSImage] = []
    @Published var macroProgress: String? = nil
    private let keyboard = HeldKeyboard()
    private let macroRunner = MacroRunner()
    private let textInserter = TextInserter()
    private var textTask: Task<Void, Never>?
    private var textID: UUID?
    private var launchTask: Task<Void, Never>?
    private var launchID: UUID?
    private var heldTokens: [Int: UUID] = [:]
    private var recordingStepID: UUID?
    let screensaverClock = ScreensaverClock()
    var currentKeys: [KeyAssignment] {
        get { configuration.keys(on: activePageID) }
        set { configuration.setKeys(newValue, on: activePageID) }
    }
    var selectedKey: KeyAssignment { currentKeys[selected] }
    var pageName: String { configuration.allPages.first { $0.id == activePageID }?.name ?? "Accueil" }
    @Published var selected = 0
    @Published var connected = false
    @Published var status = "Recherche du boîtier…"
    @Published var trusted = AXIsProcessTrusted()
    @Published var paused = false { didSet { if paused { cancelActions() } } }
    @Published var testMode = false { didSet { if testMode { cancelActions() } } }
    @Published var recording = false { didSet { if recording { cancelActions() } } }
    @Published var pressed: Int? = nil
    @Published var activity = "Appuie sur une touche du boîtier pour la vérifier."
    @Published var error: String? = nil
    // Message de démarrage qui doit rester visible (réglages restaurés ou illisibles) ;
    // contrairement à `error`, il n'est pas effacé par le prochain affichage sur le boîtier.
    @Published var notice: String? = nil
    let dashboardState = DashboardState()
    var dashboardPreviews: [Data] { get { dashboardState.previews } set { dashboardState.previews = newValue } }
    @Published var cityQuery = ""
    @Published var cityResults: [WeatherLocation] = []
    @Published var searchingCity = false
    var weatherStatus: String { get { dashboardState.weatherStatus } set { dashboardState.weatherStatus = newValue } }
    @Published var citySearchError: String? = nil
    var weather: WeatherReading? { get { dashboardState.weather } set { dashboardState.weather = newValue } }
    var activeAppName: String { get { dashboardState.activeAppName } set { dashboardState.activeAppName = newValue } }
    var clockText: String { get { dashboardState.clockText } set { dashboardState.clockText = newValue } }
    @Published var screensaverActive = false
        private var idle = IdleState(lastInteraction: Date())
    private var lastIdleTick: Int?
    private var cachedIdleImages: [(Int, Data)] = []
    let usb = USBDeck()
    let store: ConfigurationStore
    private var down = Set<Int>()
    private var eventMonitor: Any?
    private var mouseMonitors: [Any] = []
    private var trustTimer: Timer?
    private var renderTask: DispatchWorkItem?
    private(set) var hasLoadError = false
    private var saveTask: DispatchWorkItem?
    private var savePending = false
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var screensWakeObserver: NSObjectProtocol?
    private var screensSleepObserver: NSObjectProtocol?
    private var powerState = DeckPowerState(screensSleeping: CGDisplayIsAsleep(CGMainDisplayID()) != 0)
    private var sleeping: Bool { powerState.sleeping }
    private var dashboardTimer: Timer?
    private var idleTimer: Timer?
    private var previewAnimationStart = Date()
    private var appObserver: NSObjectProtocol?
    private var lastDashboardImages: [Int: Data] = [:]
    private var weatherTask: Task<Void, Never>?
    private var cityTask: Task<Void, Never>?
    private var weatherLocation: WeatherLocation?
    private var weatherNextAttempt = Date.distantPast

    init(directory: URL) {
        store = ConfigurationStore(directory: directory)
        do {
            let loaded = try store.loadRecovering()
            configuration = loaded.configuration
            notice = loaded.notice
        } catch { notice = error.localizedDescription; hasLoadError = true; paused = true }
        usb.onStatus = { [weak self] connected, status in
            if self?.connected != connected { self?.connected = connected }; if self?.status != status { self?.status = status }
            if !connected { self?.cancelActions(); self?.down.removeAll(); self?.pressed = nil; self?.lastDashboardImages = [:]; self?.idle = IdleState(lastInteraction: Date()); self?.screensaverActive = false; self?.lastIdleTick = nil }
        }
        usb.onReady = { [weak self] in
            guard let self else { return }
            self.cancelActions(); self.down.removeAll(); self.pressed = nil
            self.idle = IdleState(lastInteraction: Date()); self.screensaverActive = false; self.lastIdleTick = nil
            self.lastDashboardImages = [:]
            self.activity = self.sleeping ? "Boîtier en veille — écrans du Mac éteints." : "Boîtier prêt — appuie sur une touche pour la vérifier."
            self.renderAll(reinitialize: true)
        }
        usb.onReport = { [weak self] report in self?.receive(report) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording else { return event }
            if event.keyCode == 53 { self.recording = false; return nil }
            let shortcut = Shortcut(keyCode: event.keyCode,
                                    modifiers: UInt64(event.modifierFlags.intersection(Shortcut.allowedFlags).rawValue),
                                    keyLabel: Shortcut.label(event))
            guard shortcut.isValid else { return nil }
            if let id = self.recordingStepID, let index = self.currentKeys[self.selected].macro?.firstIndex(where: { $0.id == id }) {
                self.currentKeys[self.selected].macro![index].shortcut = shortcut
            } else { self.currentKeys[self.selected].shortcut = shortcut }
            self.recordingStepID = nil
            self.recording = false
            self.save()
            return nil
        }
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { mouseMonitors.append(local) }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }; let trusted = AXIsProcessTrusted()
                if self.trusted != trusted { self.trusted = trusted; if !trusted { self.cancelActions() } }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePower(.systemWake)
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handlePower(.systemSleep) }
        }
        screensSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handlePower(.screensSleep) }
        }
        screensWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handlePower(.screensWake) }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier { self?.cancelActions() }
                self?.activateApplicationPage()
                self?.updateDashboard()
            }
        }
        dashboardTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDashboard(); self?.refreshWeather() }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIdle() }
        }
        refreshScreensaverApps()
        updateKeyPreviews()
        updateDashboard()
        usb.setDisplaySleeping(sleeping)
        usb.start()
    }

    func select(_ index: Int) { recording = false; recordingStepID = nil; selected = index }

    private func handlePower(_ event: DeckPowerEvent) {
        let wasSleeping = sleeping
        powerState.apply(event)
        usb.setDisplaySleeping(sleeping)
        if sleeping {
            cancelActions(); down.removeAll(); pressed = nil; recording = false
            renderTask?.cancel()
            idle = IdleState(lastInteraction: Date()); screensaverActive = false; lastIdleTick = nil
            activity = "Boîtier en veille — écrans du Mac éteints."
        }
        switch event {
        case .systemSleep: usb.suspend()
        case .systemWake: usb.resume()
        default: break
        }
        if wasSleeping && !sleeping {
            idle = IdleState(lastInteraction: Date()); screensaverActive = false; lastIdleTick = nil
            down.removeAll(); pressed = nil; lastDashboardImages = [:]
            activity = "Écrans rallumés — les raccourcis sont prêts."
            renderAll(reinitialize: true)
        }
    }

    func reconnectDeck() {
        cancelActions(); down.removeAll(); pressed = nil
        activity = "Réparation de la connexion au boîtier…"
        usb.reconnect()
    }

    func save() {
        guard !hasLoadError else { return }
        saveTask?.cancel(); saveTask = nil; savePending = false
        do { try store.save(configuration); error = nil; updateKeyPreviews(); scheduleRender(); refreshWeather() }
        catch { self.error = "Enregistrement impossible : \(error.localizedDescription)" }
    }

    // Pour la saisie de texte : l'aperçu suit chaque frappe, mais le fichier n'est écrit
    // qu'une demi-seconde après la dernière, au lieu d'être réécrit à chaque lettre.
    func saveSoon() {
        guard !hasLoadError else { return }
        updateKeyPreviews(); scheduleRender()
        savePending = true
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.save() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    // À appeler avant de fermer la fenêtre ou de quitter : écrit tout de suite une saisie en attente.
    func flushPendingSave() { if savePending { save() } }

    func preset(_ preset: Preset) {
        cancelActions(); recording = false
        currentKeys[selected].shortcut = preset.assignment.shortcut
        if currentKeys[selected].title.isEmpty { currentKeys[selected].title = preset.title }
        save()
    }

    func clear() {
        guard !isHomeNavigationKey else { return }
        cancelActions(); recording = false; currentKeys[selected] = KeyAssignment(); save()
    }

    func chooseIcon() {
        recording = false
        let target = selected
        let panel = NSOpenPanel()
        panel.title = "Choisir l’icône de la touche \(target + 1)"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let icon = try IconImage.load(url)
            currentKeys[target].iconPNG = icon
            save()
        } catch { self.error = error.localizedDescription }
    }

    func removeIcon() { currentKeys[selected].iconPNG = nil; save() }

    func changeDashboard(deferSave: Bool = false, _ change: (inout DashboardConfiguration) -> Void) {
        var settings = configuration.effectiveDashboard
        change(&settings)
        configuration.dashboard = settings
        if deferSave { saveSoon() } else { save() }
        updateDashboard()
    }

    func chooseDashboardIcon(_ index: Int) {
        recording = false
        let panel = NSOpenPanel(); panel.title = "Choisir une image pour la bande de droite"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try IconImage.load(url)
            changeDashboard { $0.slots[index].iconPNG = data }
        } catch { self.error = error.localizedDescription }
    }

    func changeAppearance(_ index: Int, _ change: (inout IconAppearance) -> Void) {
        var appearance = currentKeys[index].effectiveAppearance
        change(&appearance); currentKeys[index].appearance = appearance; saveSoon()
    }

    func changeScreensaver(_ change: (inout ScreensaverConfiguration) -> Void) {
        var settings = configuration.effectiveScreensaver
        change(&settings); configuration.screensaver = settings
        _ = idle.press(now: Date()); screensaverActive = false; lastIdleTick = nil
        previewAnimationStart = Date()
        save()
    }

    func chooseWallpaper() {
        let panel = NSOpenPanel(); panel.title = "Choisir le fond d’écran de veille"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let png = try IconImage.load(url)
            changeScreensaver { $0.wallpaperPNG = png }
        } catch { self.error = error.localizedDescription }
    }

    func refreshScreensaverApps() {
        var seen = Set<String>()
        screensaverClock.apps = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return ScreensaverAppIcon(name: app.localizedName ?? "Application", icon: app.icon)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func previewScreensaver(animation: Bool = false) {
        guard connected, !sleeping, configuration.effectiveScreensaver.enabled else { return }
        let settings = configuration.effectiveScreensaver
        idle.lastInteraction = Date().addingTimeInterval(-Double(settings.delay + (animation && settings.usesAnimation ? settings.effectiveClockDuration : 0)))
        refreshScreensaverApps()
        idle.active = true; screensaverActive = true; lastIdleTick = nil
        screensaverClock.elapsed = idleElapsed(at: Date()); screensaverClock.date = Date()
        renderAll()
    }

    func leaveScreensaver() {
        _ = idle.press(now: Date()); screensaverActive = false; lastIdleTick = nil
        renderAll()
    }

    private func mouseMoved() {
        guard !sleeping else { return }
        if idle.mouseMoved(now: Date(), settings: configuration.effectiveScreensaver) {
            screensaverActive = false; lastIdleTick = nil
            activity = "Veille terminée — souris déplacée."
            renderAll()
        }
    }

    private func idleImages() -> [(Int, Data)]? {
        let now = Date()
        let elapsed = idleElapsed(at: now)
        let tick = configuration.effectiveScreensaver.imageTick(at: now, elapsed: elapsed)
        if tick == lastIdleTick && cachedIdleImages.count == 15 { return cachedIdleImages }
        guard let tiles = ScreensaverImage.tiles(settings: configuration.effectiveScreensaver, date: now,
                                                clock: configuration.effectiveDashboard, rotation: configuration.imageRotation,
                                                elapsed: elapsed, apps: screensaverClock.apps) else { return nil }
        cachedIdleImages = tiles.enumerated().map { ($0.offset, $0.element) }; lastIdleTick = tick
        return cachedIdleImages
    }

    private func updateIdle() {
        guard !sleeping else { return }
        let now = Date()
        let settings = configuration.effectiveScreensaver
        let elapsed = idle.active ? idleElapsed(at: now) : max(0, now.timeIntervalSince(previewAnimationStart))
        let tick = settings.imageTick(at: now, elapsed: elapsed)
        if settings.imageTick(at: screensaverClock.date, elapsed: screensaverClock.elapsed) != tick {
            screensaverClock.elapsed = elapsed; screensaverClock.date = now
        }
        guard connected else { return }
        if !down.isEmpty || keyboard.isHolding || macroRunner.isRunning || textInserter.isInserting { idle.lastInteraction = now; return }
        if idle.tick(now: now, settings: settings) {
            if idle.active {
                refreshScreensaverApps()
                screensaverClock.elapsed = idleElapsed(at: now); screensaverClock.date = now
            }
            screensaverActive = idle.active; renderAll()
        } else if idle.active && lastIdleTick != tick {
            let previous = Dictionary(uniqueKeysWithValues: cachedIdleImages)
            guard let images = idleImages() else { return }
            let changed = images.filter { previous[$0.0] != $0.1 }
            if !changed.isEmpty { usb.display(images: changed, brightness: configuration.brightness) }
        }
    }

    private func idleElapsed(at date: Date) -> Double {
        max(0, date.timeIntervalSince(idle.lastInteraction) - Double(configuration.effectiveScreensaver.delay))
    }

    func searchCity() {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 && query.count <= 200 else { citySearchError = "Saisis au moins deux caractères."; return }
        cityTask?.cancel(); searchingCity = true; citySearchError = nil; cityResults = []
        cityTask = Task { [weak self] in
            do {
                let places = try await WeatherService.search(city: query)
                guard !Task.isCancelled, let self else { return }
                self.cityResults = places; self.searchingCity = false
                if places.isEmpty { self.citySearchError = "Aucune ville trouvée." }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.searchingCity = false; self.citySearchError = "Recherche indisponible : \(error.localizedDescription)"
            }
        }
    }

    func selectWeatherLocation(_ location: WeatherLocation) {
        guard location.isValid else { return }
        cityResults = []; cityQuery = location.name
        changeDashboard { $0.location = location }
        refreshWeather(force: true)
    }

    func refreshWeather(force: Bool = false) {
        let settings = configuration.effectiveDashboard
        guard settings.slots.contains(where: { $0.kind == .weather }), let location = settings.location else {
            weatherTask?.cancel(); weatherTask = nil
            if weather != nil { weather = nil }
            weatherLocation = nil
            let message = settings.location == nil ? "Choisis la ville de la météo." : "Météo désactivée."
            if weatherStatus != message { weatherStatus = message }
            return
        }
        guard connected, !sleeping else { return }
        if weatherLocation != location {
            weatherTask?.cancel(); weatherTask = nil; weather = nil
            weatherLocation = location; weatherNextAttempt = .distantPast
        }
        if force { weatherTask?.cancel(); weatherTask = nil; weatherNextAttempt = .distantPast }
        guard weatherTask == nil, Date() >= weatherNextAttempt else { return }
        weatherStatus = "Actualisation de la météo…"
        weatherTask = Task { [weak self] in
            do {
                let reading = try await WeatherService.current(location: location)
                guard !Task.isCancelled, let self, self.configuration.effectiveDashboard.location == location else { return }
                self.weather = reading
                self.weatherStatus = "\(location.name) · \(reading.condition) · \(reading.temperature(fahrenheit: settings.weatherFahrenheit))"
                self.weatherNextAttempt = Date().addingTimeInterval(15 * 60)
                self.weatherTask = nil; self.updateDashboard()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.weatherStatus = "Météo indisponible — nouvel essai dans une minute."
                self.weatherNextAttempt = Date().addingTimeInterval(60)
                self.weatherTask = nil; self.updateDashboard()
            }
        }
    }

    private func dashboardImages() -> [(Int, Data)] {
        let settings = configuration.effectiveDashboard
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Application"
        if activeAppName != appName { activeAppName = appName }
        let date = Date()
        let currentClock = DashboardImage.clockStrings(date, settings: settings).0
        if clockText != currentClock { clockText = currentClock }
        var images: [(Int, Data)] = []
        var previews: [Data] = []
        for (index, slot) in settings.slots.enumerated() {
            if let image = DashboardImage.jpeg(slot: slot, settings: settings, date: date, appName: activeAppName, appIcon: app?.icon, weather: weather, weatherMessage: weatherStatus, rotation: configuration.imageRotation) {
                images.append((index + 15, image))
            }
            if let preview = DashboardImage.jpeg(slot: slot, settings: settings, date: date, appName: activeAppName, appIcon: app?.icon, weather: weather, weatherMessage: weatherStatus, rotation: 0) { previews.append(preview) }
        }
        if previews != dashboardPreviews { dashboardPreviews = previews }
        return images
    }

    func updateDashboard() {
        guard !sleeping else { return }
        let images = dashboardImages()
        guard connected, images.count == 3 else { return }
        let changed = images.filter { lastDashboardImages[$0.0] != $0.1 }
        guard !changed.isEmpty else { return }
        for (index, data) in changed { lastDashboardImages[index] = data }
        usb.display(images: changed, brightness: configuration.brightness)
    }

    func composeShortcut(step: UUID?, keyCode: Int? = nil, modifier: NSEvent.ModifierFlags? = nil, enabled: Bool = false) {
        recording = false
        let old: Shortcut?
        if let id = step {
            guard let value = selectedKey.effectiveMacro.first(where: { $0.id == id }), value.kind == .shortcut else { return }
            old = value.shortcut
        } else { old = selectedKey.shortcut }
        var flags = NSEvent.ModifierFlags(rawValue: UInt(old?.modifiers ?? 0))
        if let modifier {
            if enabled { flags.insert(modifier) } else { flags.remove(modifier) }
        }
        let selectedCode = keyCode ?? (old == nil || old!.isModifiersOnly ? -1 : Int(old!.keyCode))
        let code: UInt16? = (0...126).contains(selectedCode) ? UInt16(selectedCode) : nil
        let label = code.flatMap { code in ShortcutKeyChoice.all.first { $0.code == code }?.label } ?? old?.keyLabel ?? ""
        let shortcut = Shortcut.composed(code: code, label: label, modifiers: UInt64(flags.rawValue))
        if let id = step { updateMacroStep(id) { $0.shortcut = shortcut } }
        else { updateSelected { $0.shortcut = shortcut } }
    }

    func isRecording(step: UUID?) -> Bool { recording && recordingStepID == step }

    func beginRecording(step: UUID? = nil) {
        recordingStepID = step
        recording = true
    }

    func updateSelected(deferSave: Bool = false, _ change: (inout KeyAssignment) -> Void) {
        cancelActions()
        var key = selectedKey; change(&key); currentKeys[selected] = key
        if deferSave { saveSoon() } else { save() }
    }

    func changeAction(_ kind: KeyActionKind) {
        recording = false; recordingStepID = nil
        updateSelected { $0.actionKind = kind }
    }

    private var canSendKeyboard: Bool {
        connected && !paused && !testMode && !recording && !sleeping && AXIsProcessTrusted()
            && NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    func cancelActions() {
        keyboard.releaseAll(); heldTokens.removeAll(); macroRunner.cancel()
        textTask?.cancel(); textTask = nil; textID = nil
        launchTask?.cancel(); launchTask = nil; launchID = nil; automaticPageState.cancelLaunch()
        if macroProgress != nil { macroProgress = nil }
    }

    private var cachedKeys: [KeyAssignment] = []
    func updateKeyPreviews() {
        let keys = currentKeys
        guard keys != cachedKeys || keyPreviews.count != 15 else { return }
        cachedKeys = keys
        keyPreviews = keys.enumerated().map { index, key in
            KeyImage.jpeg(key: key, index: index, rotation: 0).flatMap(NSImage.init(data:)) ?? NSImage(size: NSSize(width: 95, height: 95))
        }
    }

    func switchPage(_ id: String, automatic: Bool = false) {
        guard configuration.containsPage(id) else { return }
        if !automatic { automaticPageState.manuallySelected() }
        cancelActions(); recording = false; recordingStepID = nil
        activePageID = id; selected = 0
        _ = idle.press(now: Date()); screensaverActive = false; lastIdleTick = nil
        updateKeyPreviews(); renderAll()
        activity = "Page : \(pageName)"
    }

    func renamePage(_ name: String) {
        let value = String(name.prefix(80))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if activePageID == homePageID { configuration.homeName = value }
        else if let index = configuration.pages?.firstIndex(where: { $0.id == activePageID }) { configuration.pages![index].name = value }
        saveSoon()
    }

    func addPage() {
        guard (configuration.pages ?? []).count < 50 else { return }
        var page = DeckPage(name: "Page \((configuration.pages ?? []).count + 2)")
        page.addHomeButtons()
        if configuration.pages == nil { configuration.pages = [] }
        configuration.pages!.append(page); save(); switchPage(page.id)
    }

    func duplicatePage() {
        guard (configuration.pages ?? []).count < 50 else { return }
        let page = DeckPage(name: String((pageName + " copie").prefix(80)), keys: currentKeys)
        if configuration.pages == nil { configuration.pages = [] }
        configuration.pages!.append(page); save(); switchPage(page.id)
    }

    func createLaunchPage(named name: String, sourcePageID: String, keyIndex: Int) {
        guard configuration.containsPage(sourcePageID), (0..<15).contains(keyIndex) else { return }
        guard (configuration.pages ?? []).count < 50 else {
            error = "La limite de 50 pages est atteinte."; return
        }
        var sourceKeys = configuration.keys(on: sourcePageID)
        guard [.application, .website].contains(sourceKeys[keyIndex].effectiveKind) else { return }
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { return }
        cancelActions(); recording = false
        var page = DeckPage(name: title); page.addHomeButtons()
        if configuration.pages == nil { configuration.pages = [] }
        configuration.pages!.append(page)
        sourceKeys[keyIndex].launchPageID = page.id
        configuration.setKeys(sourceKeys, on: sourcePageID)
        save()
    }

    func setLaunchPage(_ id: String?) {
        guard let id else { updateSelected { $0.launchPageID = nil }; return }
        guard configuration.containsPage(id) else { return }
        if id != homePageID, var page = configuration.pages?.first(where: { $0.id == id }) {
            guard page.canReserveHomeButtons else {
                error = "Les touches 14 et 15 de cette page doivent être libres pour revenir à l’accueil. Choisis une autre page ou crée-en une nouvelle."; return
            }
            page.addHomeButtons(); configuration.setKeys(page.keys, on: id)
        }
        updateSelected { $0.launchPageID = id }
    }

    func deletePage() {
        guard activePageID != homePageID else { return }
        let removed = activePageID; cancelActions()
        configuration.pages?.removeAll { $0.id == removed }
        configuration.applicationPages?.removeAll { $0.pageID == removed }
        configuration.removeReferences(to: removed)
        switchPage(homePageID); save()
    }

    func activateApplicationPage() {
        guard let pageID = automaticPageState.activated(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                                       ownBundleID: Bundle.main.bundleIdentifier, configuration: configuration) else { return }
        if activePageID != pageID { switchPage(pageID, automatic: true) }
    }

    func setAutomaticPagesEnabled(_ enabled: Bool) {
        configuration.automaticPagesEnabled = enabled; save()
        activateApplicationPage()
    }

    func addMacroStep(_ kind: MacroStepKind) {
        guard selectedKey.effectiveMacro.count < 100 else { return }
        updateSelected { key in
            if key.macro == nil { key.macro = [] }
            key.macro!.append(MacroStep(kind: kind))
        }
    }

    func updateMacroStep(_ id: UUID, deferSave: Bool = false, _ change: (inout MacroStep) -> Void) {
        guard let index = selectedKey.macro?.firstIndex(where: { $0.id == id }) else { return }
        updateSelected(deferSave: deferSave) { change(&$0.macro![index]) }
    }

    func moveMacroStep(_ id: UUID, offset: Int) {
        guard let index = selectedKey.macro?.firstIndex(where: { $0.id == id }), selectedKey.effectiveMacro.indices.contains(index + offset) else { return }
        recording = false
        updateSelected { $0.macro!.swapAt(index, index + offset) }
    }

    func removeMacroStep(_ id: UUID) {
        recording = false; updateSelected { $0.macro?.removeAll { $0.id == id } }
    }

    func chooseApplication(step: UUID? = nil) {
        recording = false
        let page = activePageID, index = selected
        let panel = NSOpenPanel(); panel.title = "Choisir une application"
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, validApplicationPath(url.path), activePageID == page, selected == index else { return }
        if let step {
            updateMacroStep(step) { $0.applicationPath = url.path }
        } else {
            updateSelected { key in
                key.applicationPath = url.path
                if key.title.isEmpty { key.title = url.deletingPathExtension().lastPathComponent }
                if key.iconPNG == nil, let image = NSWorkspace.shared.icon(forFile: url.path).cgImage(forProposedRect: nil, context: nil, hints: nil), let data = IconImage.encode(image, type: "public.png"), data.count <= 512_000 {
                    key.iconPNG = data
                }
            }
        }
    }

    private func openApplication(_ path: String) async throws -> NSRunningApplication {
        guard validApplicationPath(path), FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "Deck", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cette application est introuvable. Choisis-la à nouveau."])
        }
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: NSError(domain: "Deck", code: 11, userInfo: [NSLocalizedDescriptionKey: "Impossible d’ouvrir cette application."])) }
            }
        }
    }

    private func openWebsiteApplication(_ address: String?) async throws -> NSRunningApplication {
        guard let address, let url = websiteURL(address) else {
            throw NSError(domain: "Deck", code: 13, userInfo: [NSLocalizedDescriptionKey: "Saisis une adresse de site valide, en http ou https."])
        }
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: NSError(domain: "Deck", code: 14, userInfo: [NSLocalizedDescriptionKey: "Impossible d’ouvrir ce site dans le navigateur."])) }
            }
        }
    }

    private func launch(_ key: KeyAssignment) {
        guard key.isConfigured else { activity += " — choisis une application ou un site"; return }
        cancelActions()
        let id = UUID(); launchID = id
        if key.launchPageID != nil { automaticPageState.beginLaunch() }
        launchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let app: NSRunningApplication
                if key.effectiveKind == .application, let path = key.applicationPath { app = try await self.openApplication(path) }
                else { app = try await self.openWebsiteApplication(key.websiteAddress) }
                try Task.checkCancellation()
                guard self.launchID == id, self.connected, !self.paused, !self.testMode, !self.recording, !self.sleeping else { return }
                self.launchTask = nil; self.launchID = nil
                if let pageID = key.launchPageID, self.configuration.containsPage(pageID) {
                    self.automaticPageState.finishLaunch(pageID: pageID, bundleID: app.bundleIdentifier)
                    self.switchPage(pageID, automatic: true)
                }
            } catch {
                guard self.launchID == id else { return }
                self.launchTask = nil; self.launchID = nil; self.automaticPageState.cancelLaunch()
                if !(error is CancellationError) { self.error = error.localizedDescription }
                self.activateApplicationPage()
            }
        }
    }

    private func runMacro(_ steps: [MacroStep]) {
        guard !steps.isEmpty, steps.allSatisfy(\.isReady) else { error = "Complète chaque étape de la macro avant de la lancer."; return }
        cancelActions()
        macroProgress = "Macro en cours…"
        macroRunner.start(steps: steps, perform: { [weak self] step in
            guard let self, self.connected, !self.paused, !self.testMode, !self.recording, !self.sleeping else { throw CancellationError() }
            if step.kind == .shortcut {
                guard self.canSendKeyboard, let shortcut = step.shortcut, self.keyboard.tap(shortcut) else {
                    throw NSError(domain: "Deck", code: 12, userInfo: [NSLocalizedDescriptionKey: "Macro arrêtée : ouvre l’application à contrôler et vérifie l’autorisation d’accessibilité."])
                }
            } else if step.kind == .text { try await self.insertText(step.text ?? "") }
            else if step.kind == .application, let path = step.applicationPath { _ = try await self.openApplication(path) }
            else if step.kind == .website { try self.openWebsite(step.websiteAddress) }
        }, progress: { [weak self] index in
            self?.macroProgress = "Macro · étape \(index + 1)/\(steps.count) : \(steps[index].label)"
        }, finished: { [weak self] message in
            self?.macroProgress = nil
            if let message { self?.error = message } else { self?.activity = "Macro terminée." }
        })
    }

    private func insertText(_ text: String) async throws {
        guard canSendKeyboard, !keyboard.isHolding else {
            throw NSError(domain: "Deck", code: 24, userInfo: [NSLocalizedDescriptionKey: "Ouvre le champ à remplir, relâche les autres touches du boîtier et vérifie l’autorisation d’accessibilité."])
        }
        // Post an isolated Command-V; held shortcuts must not add other modifiers.
        let paste = Shortcut(keyCode: 9, modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue), keyLabel: "V")
        guard let events = ShortcutEmitter.events(for: paste) else {
            throw NSError(domain: "Deck", code: 25, userInfo: [NSLocalizedDescriptionKey: "Le Mac n’a pas pu créer les événements clavier."])
        }
        try await textInserter.insert(text) { [weak self] in
            guard let self, self.canSendKeyboard, !self.keyboard.isHolding else { return false }
            for event in events { event.post(tap: .cghidEventTap) }
            return true
        }
    }

    private func runText(_ text: String?) {
        guard let text, !text.isEmpty else { activity += " — écris le texte à insérer"; return }
        guard canSendKeyboard else {
            activity += AXIsProcessTrusted() ? " — ouvre le champ à remplir dans ton logiciel" : " — autorisation d’accessibilité nécessaire"
            return
        }
        guard !textInserter.isInserting else { activity += " — insertion en cours"; return }
        cancelActions()
        let id = UUID(); textID = id
        textTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.insertText(text)
                guard self.textID == id else { return }
                self.textID = nil; self.textTask = nil
                self.activity = "Texte inséré."
            } catch {
                guard self.textID == id else { return }
                self.textID = nil; self.textTask = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    private func openWebsite(_ address: String?) throws {
        guard let address, let url = websiteURL(address), NSWorkspace.shared.open(url) else {
            throw NSError(domain: "Deck", code: 13, userInfo: [NSLocalizedDescriptionKey: "Saisis une adresse de site valide, en http ou https."])
        }
    }

    func captureScreen(_ mode: ScreenCaptureMode) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.trongduong.snapzy") != nil,
              NSWorkspace.shared.open(mode.url) else {
            error = "Ouvre Snapzy et active son intégration dans ses réglages avancés pour lancer une capture."; return
        }
        activity = "Snapzy · \(mode.title)"
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func receive(_ report: [UInt8]) {
        guard !sleeping else { return }
        guard let event = DeckProtocol.event(report) else { return }
        guard let index = event.index else {
            down.removeAll(); pressed = nil; keyboard.releaseAll(); heldTokens.removeAll(); return
        }
        if !event.down {
            down.remove(index); if pressed == index { pressed = nil }
            if let token = heldTokens.removeValue(forKey: index) { keyboard.end(token) }
            return
        }
        guard down.insert(index).inserted else { return }
        pressed = index
        if idle.press(now: Date()) {
            screensaverActive = false; lastIdleTick = nil
            activity = "Veille terminée — les raccourcis sont prêts."
            renderAll(); return
        }
        let key = currentKeys[index]
        activity = "\(key.title.isEmpty ? "Touche \(index + 1)" : key.title) · \(key.actionLabel)"
        guard !paused, !testMode, !recording, !sleeping else { return }
        switch key.effectiveKind {
        case .page:
            if let id = key.targetPageID { switchPage(id) }
            else { activity += " — choisis une page" }
        case .application, .website:
            launch(key)
        case .screenCapture:
            captureScreen(key.effectiveCaptureMode)
        case .macro:
            runMacro(key.effectiveMacro)
        case .text:
            runText(key.text)
        case .shortcut:
            guard let shortcut = key.shortcut else { return }
            guard !textInserter.isInserting else { activity += " — attends la fin de l’insertion du texte"; return }
            guard canSendKeyboard else {
                activity += AXIsProcessTrusted() ? " — ouvre l’application à contrôler" : " — autorisation d’accessibilité nécessaire"
                return
            }
            if key.effectivePressMode == .hold {
                let token = UUID()
                if keyboard.begin(shortcut, token: token) { heldTokens[index] = token; activity += " — maintenu" }
                else { error = "Le Mac n’a pas pu créer les événements clavier." }
            } else if !keyboard.tap(shortcut) { error = "Le Mac n’a pas pu créer les événements clavier." }
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.renderAll() }
        renderTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    func renderAll(reinitialize: Bool = false) {
        guard connected, !sleeping else { return }
        var images: [(Int, Data)] = []
        lastIdleTick = nil
        if idle.active {
            guard let tiles = idleImages() else { error = "Impossible de dessiner la veille."; return }
            images = tiles
        } else {
        for (index, key) in currentKeys.enumerated() {
            guard let data = KeyImage.jpeg(key: key, index: index, rotation: configuration.imageRotation) else {
                error = "Impossible de dessiner la touche \(index + 1)."; return
            }
            images.append((index, data))
        }
        }
        error = nil
        let dashboard = dashboardImages()
        guard dashboard.count == 3 else { error = "Impossible de dessiner la bande de droite."; return }
        images += dashboard
        for (index, data) in dashboard { lastDashboardImages[index] = data }
        usb.display(images: images, brightness: configuration.brightness, reinitialize: reinitialize)
        refreshWeather()
    }

    func exportConfiguration() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Soomfon-raccourcis.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }

    func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let value = try JSONDecoder().decode(DeckConfiguration.self, from: Data(contentsOf: url)).migrated
            guard value.isValid else { throw NSError(domain: "Deck", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ce fichier ne contient pas 15 raccourcis valides."]) }
            if hasLoadError, FileManager.default.fileExists(atPath: store.file.path) {
                let preserved = store.directory.appendingPathComponent("raccourcis.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try FileManager.default.copyItem(at: store.file, to: preserved)
            }
            try store.save(value)
            saveTask?.cancel(); saveTask = nil; savePending = false
            // Un chargement raté avait mis l'application en pause : l'import la répare, on la relance.
            let wasBlocked = hasLoadError
            cancelActions(); configuration = value; activePageID = homePageID; updateKeyPreviews(); idle = IdleState(lastInteraction: Date()); screensaverActive = false; lastIdleTick = nil; hasLoadError = false; error = nil; notice = nil; recording = false
            if wasBlocked { paused = false }
            scheduleRender()
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        flushPendingSave()
        cancelActions()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }; mouseMonitors.removeAll()
        trustTimer?.invalidate(); dashboardTimer?.invalidate(); idleTimer?.invalidate(); renderTask?.cancel()
        weatherTask?.cancel(); cityTask?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let screensWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(screensWakeObserver) }
        if let screensSleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(screensSleepObserver) }
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        usb.stop()
    }
}

enum IconImage {
    static func load(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0, size <= 50_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let png = encode(thumbnail, type: "public.png"), png.count <= 512_000 else {
            throw NSError(domain: "Deck", code: 4, userInfo: [NSLocalizedDescriptionKey: "Image illisible. Choisis un fichier PNG, JPEG, HEIC, TIFF, GIF ou BMP de moins de 50 Mo."])
        }
        return png
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary)
    }

    static func encode(_ image: CGImage, type: String) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

enum KeyImage {
    static func jpeg(key: KeyAssignment, index: Int, rotation: Int) -> Data? {
        let size = 95
        guard let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                 bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let context = NSGraphicsContext(cgContext: cg, flipped: false)
        // Opaque background is filled before rotation, including edge pixels and
        // the transparent parts of an imported icon.
        cg.setFillColor(key.isConfigured ? key.effectiveAppearance.background : DeckColor().cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if !key.isConfigured {
            guard let image = cg.makeImage() else { return nil }
            return IconImage.encode(image, type: "public.jpeg")
        }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let transform = NSAffineTransform()
        transform.translateX(by: 47.5, yBy: 47.5)
        transform.rotate(byDegrees: CGFloat(rotation))
        transform.translateX(by: -47.5, yBy: -47.5)
        transform.concat()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        if let data = key.iconPNG {
            guard let icon = IconImage.decode(data) else { NSGraphicsContext.restoreGraphicsState(); return nil }
            let area = CGRect(x: 0, y: key.showsTitle ? 26 : 0, width: size, height: key.showsTitle ? 69 : size)
            let scale = min(area.width / CGFloat(icon.width), area.height / CGFloat(icon.height)) * key.effectiveAppearance.scale
            let width = CGFloat(icon.width) * scale, height = CGFloat(icon.height) * scale
            cg.saveGState(); cg.clip(to: area)
            cg.interpolationQuality = .high
            cg.draw(icon, in: CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height))
            cg.restoreGState()
        } else {
            let shortcut = key.effectiveKind == .shortcut ? (key.shortcut?.display ?? "\(index + 1)") : key.actionLabel
            let fontSize: CGFloat = shortcut.count > 6 ? 15 : 24
            (shortcut as NSString).draw(in: NSRect(x: 3, y: key.showsTitle ? 36 : 32, width: 89, height: 32), withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.39, green: 0.88, blue: 0.74, alpha: 1), .paragraphStyle: paragraph])
        }
        if key.showsTitle {
            let title = key.title.isEmpty ? (key.effectiveKind == .shortcut && key.shortcut == nil ? "À configurer" : key.effectiveKind.title) : key.title
            (title as NSString).draw(in: NSRect(x: 4, y: key.iconPNG == nil ? 12 : 5, width: 87, height: 17), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = cg.makeImage() else { return nil }
        return IconImage.encode(image, type: "public.jpeg")
    }
}
