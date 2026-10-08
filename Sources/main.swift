import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: DeckModel!
    var window: NSWindow!
    var item: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Soomfon Raccourcis", isDirectory: true)
        model = DeckModel(directory: directory)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 900, height: 720)
        window.title = "Soomfon Raccourcis"
        window.contentView = NSHostingView(rootView: DeckView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SoomfonConfigurationWindow")
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Soomfon Raccourcis")
        let menu = NSMenu()
        let show = menu.addItem(withTitle: "Configurer les touches", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        let pause = menu.addItem(withTitle: "Activer / désactiver la pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quitter Soomfon Raccourcis", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        item.menu = menu
        let appMenu = NSMenu()
        let root = NSMenuItem(); appMenu.addItem(root); root.submenu = menu.copy() as? NSMenu
        NSApplication.shared.mainMenu = appMenu
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true) }
    @objc func togglePause() { model.paused.toggle() }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func windowWillClose(_ notification: Notification) { model.recording = false }
}

if CommandLine.arguments.contains("--self-test") {
    _ = NSApplication.shared
    try runSelfTests()
} else if CommandLine.arguments.contains("--probe") {
    let usb = USBDeck()
    usb.onStatus = { connected, message in print("USB \(connected ? "OK" : "INFO"): \(message)") }
    usb.onReport = { report in
        if let event = DeckProtocol.event(report) { print("BUTTON \(event.index.map { String($0 + 1) } ?? "release-all") \(event.down ? "down" : "up")") }
    }
    usb.start()
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    usb.stop()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
} else if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--weather-check" {
    let city = CommandLine.arguments[2]
    Task {
        do {
            let places = try await WeatherService.search(city: city)
            guard let place = places.first else { print("FAIL: aucune ville trouvée"); exit(1) }
            let reading = try await WeatherService.current(location: place)
            print("PASS: recherche et météo — \(place.label), \(reading.temperature(fahrenheit: false)), \(reading.condition)")
            CFRunLoopStop(CFRunLoopGetMain())
        } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    CFRunLoopRun()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
