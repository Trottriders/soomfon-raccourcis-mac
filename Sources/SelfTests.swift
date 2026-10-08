import Foundation
import AppKit

func runSelfTests() throws {
    func check(_ value: @autoclosure () -> Bool, _ name: String) {
        guard value() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    }
    check(DeckProtocol.address(for: 0) == 13, "top left address")
    check(DeckProtocol.address(for: 4) == 1, "top right address")
    check(DeckProtocol.address(for: 10) == 15, "bottom left address")
    check(DeckProtocol.address(for: 14) == 3, "bottom right address")
    for index in 0..<15 { check(DeckProtocol.index(for: DeckProtocol.address(for: index)) == index, "mapping roundtrip \(index)") }
    check(DeckProtocol.index(for: 0) == nil && DeckProtocol.index(for: 16) == nil, "ignore dashboard and invalid addresses")
    var report: [UInt8] = [65,67,75,0,0,0,0,0,0,13,1]
    check(DeckProtocol.event(report)?.index == 0 && DeckProtocol.event(report)?.down == true, "button down")
    report[10] = 0
    check(DeckProtocol.event(report)?.down == false, "button up")
    report[9] = 0
    check(DeckProtocol.event(report)?.index == nil, "release all")
    check(DeckProtocol.event([]) == nil, "short report")
    report[0] = 0
    check(DeckProtocol.event(report) == nil, "reject non ACK")
    report[0] = 65; report[9] = 18
    check(DeckProtocol.event(report) == nil, "ignore dashboard input")
    let jpeg = Data((0..<2050).map { UInt8($0 % 256) })
    let packets = DeckProtocol.imagePackets(jpeg, index: 0)
    check(packets.count == 4 && packets.allSatisfy { $0.count == 1024 }, "native report sizes")
    check(Array(packets[0].prefix(14)) == [67,82,84,0,0,66,65,84,0,0,8,2,13,0], "BAT length and address without report ID")
    check(Array(packets[1].prefix(1024)) == Array(jpeg.prefix(1024)), "JPEG first chunk")
    check(packets[3][0] == 0 && packets[3][1] == 1 && packets[3][2] == 0, "last chunk padding")
    let clear = DeckProtocol.clearScreenPackets
    check(clear.count == 2 && clear.allSatisfy { $0.count == 1024 }, "clear and commit packets")
    check(Array(clear[0].prefix(12)) == [67,82,84,0,0,67,76,69,0,0,0,255], "clear all slots including dashboard")
    check(Array(clear[1].prefix(8)) == [67,82,84,0,0,83,84,80], "commit cleared screen before images")
    let sleepPackets = DeckProtocol.sleepPackets
    check(sleepPackets.count == 5 && sleepPackets.allSatisfy { $0.count == 1024 }, "sleep uses native report sizes")
    check(Array(sleepPackets[1].prefix(12)) == [67,82,84,0,0,76,73,71,0,0,0,0] && Array(sleepPackets[2..<4]) == clear,
          "screen sleep turns backlight off and clears all eighteen display slots")
    check(Array(sleepPackets[4].prefix(8)) == [67,82,84,0,0,72,65,78] && sleepPackets.last == DeckProtocol.command("HAN"),
          "hardware sleep follows the clear commit and is the final command")
    var power = DeckPowerState()
    power.apply(.screensSleep)
    check(power.sleeping && !power.systemSleeping, "display-only sleep blacks the deck immediately")
    power.apply(.screensSleep)
    power.apply(.systemSleep)
    power.apply(.systemWake)
    check(power.sleeping && !power.systemSleeping, "system wake keeps deck black until displays wake")
    power.apply(.screensWake)
    check(!power.sleeping, "display wake restores deck after system wake")
    power.apply(.systemSleep)
    power.apply(.screensSleep)
    power.apply(.screensWake)
    check(power.sleeping && power.systemSleeping, "early display wake cannot resume a sleeping Mac")
    power.apply(.systemWake)
    check(!power.sleeping, "reverse wake notification order also restores deck")
    check(DeckPowerState(screensSleeping: true).sleeping, "launch while displays are asleep stays black")
    var retry = DeckRetryState()
    check(retry.canAttempt(at: 100), "USB recovery starts immediately")
    retry.failed(at: 100)
    check(!retry.canAttempt(at: 100.99) && retry.canAttempt(at: 101), "USB failure waits before retrying")
    retry.failed(at: 101)
    check(!retry.canAttempt(at: 102.99) && retry.canAttempt(at: 103), "repeated USB failure increases retry delay")
    for _ in 0..<20 { retry.failed(at: 200) }
    check(retry.nextAttempt == 230 && retry.failures == 6, "USB retry delay is capped without busy looping")
    retry.succeeded()
    check(retry.failures == 0 && retry.canAttempt(at: 200), "USB recovery resets retry delay")
    let copy = Preset.all[0].assignment
    check(copy.shortcut?.display == "⌘C" && copy.shortcut!.isValid, "shortcut modifier encoding")
    check(!Shortcut(keyCode: 55, modifiers: 0, keyLabel: "⌘").isValid, "modifier alone invalid")
    guard let events = ShortcutEmitter.events(for: copy.shortcut!) else { check(false, "create keyboard events"); return }
    check(events.count == 4 && events[1].type == .keyDown && events[2].type == .keyUp, "paired keyboard events")
    check(events[1].flags.contains(.maskCommand) && events.last!.flags.isEmpty, "release Command after shortcut")
    let combination = Shortcut(keyCode: 8, modifiers: UInt64(Shortcut.allowedFlags.rawValue), keyLabel: "C")
    guard let multi = ShortcutEmitter.events(for: combination) else { check(false, "all modifiers"); return }
    check(multi.count == 10 && multi.last!.flags.isEmpty, "release all four modifiers")
    if let code = KeyboardLayout.code(for: "A") {
        check(KeyboardLayout.character(for: code)?.uppercased() == "A", "active layout letter resolution")
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("soomfon-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let store = ConfigurationStore(directory: temporary)
    var config = DeckConfiguration()
    config.keys[3] = copy
    try store.save(config)
    let loaded = try store.load()
    check(loaded == config, "save/load roundtrip")
    config.keys[3] = KeyAssignment()
    try store.save(config)
    let backup = try JSONDecoder().decode(DeckConfiguration.self, from: Data(contentsOf: store.backup))
    check(backup.keys[3] == copy, "previous valid backup")
    try Data("broken".utf8).write(to: store.file)
    do { _ = try store.load(); check(false, "corrupt file rejected") } catch { }
    check((try? String(contentsOf: store.file, encoding: .utf8)) == "broken", "corrupt file preserved")
    // Fichier principal abîmé mais sauvegarde valide : reprise automatique, ancien fichier gardé à part.
    let recoveryStore = ConfigurationStore(directory: temporary.appendingPathComponent("recovery"))
    var recoverable = DeckConfiguration(); recoverable.keys[2] = copy
    try recoveryStore.save(recoverable)
    recoverable.keys[2] = KeyAssignment(); recoverable.keys[5] = copy
    try recoveryStore.save(recoverable)
    try Data("broken".utf8).write(to: recoveryStore.file)
    let recovery = try recoveryStore.loadRecovering()
    check(recovery.configuration.keys[2] == copy && recovery.notice != nil, "damaged settings fall back to the previous backup with a notice")
    let keptAside = try FileManager.default.contentsOfDirectory(atPath: recoveryStore.directory.path).filter { $0.hasPrefix("raccourcis.corrupt-") }
    check(keptAside.count == 1 && (try? String(contentsOf: recoveryStore.directory.appendingPathComponent(keptAside[0]), encoding: .utf8)) == "broken",
          "damaged settings file is kept aside and never deleted")
    check((try? recoveryStore.load())?.keys[2] == copy, "restored settings are written back as a valid file")
    let healthy = try recoveryStore.loadRecovering()
    check(healthy.notice == nil && healthy.configuration == recovery.configuration, "a healthy settings file loads without any notice")
    let lonelyStore = ConfigurationStore(directory: temporary.appendingPathComponent("lonely"))
    try FileManager.default.createDirectory(at: lonelyStore.directory, withIntermediateDirectories: true)
    try Data("broken".utf8).write(to: lonelyStore.file)
    do { _ = try lonelyStore.loadRecovering(); check(false, "damaged settings without backup rejected") } catch { }
    check((try? String(contentsOf: lonelyStore.file, encoding: .utf8)) == "broken", "damaged settings without backup are left untouched")
    var invalid = config; invalid.keys.removeLast()
    check(!invalid.isValid, "reject missing assignments")
    invalid = config; invalid.brightness = 101
    check(!invalid.isValid, "brightness bounds")
    guard let image = KeyImage.jpeg(key: copy, index: 3, rotation: 270), let decoded = NSBitmapImageRep(data: image) else { check(false, "JPEG decode"); return }
    check(decoded.pixelsWide == 95 && decoded.pixelsHigh == 95, "button image dimensions")
    for index in 0..<15 {
        for rotation in [0,90,180,270] {
            check(KeyImage.jpeg(key: KeyAssignment(), index: index, rotation: rotation) != nil, "render blank key \(index), rotation \(rotation)")
        }
    }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let iconFile = temporary.appendingPathComponent("icon.png")
    guard let context = CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 600 * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { check(false, "icon context"); return }
    context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
    guard let cg = context.makeImage(), let png = IconImage.encode(cg, type: "public.png") else { check(false, "PNG fixture"); return }
    try png.write(to: iconFile)
    let normalized = try IconImage.load(iconFile)
    guard let icon = IconImage.decode(normalized) else { check(false, "decode normalized icon"); return }
    check(icon.width == 256 && icon.height == 128, "icon normalized without distorting aspect ratio")
    config.keys[3] = copy; config.keys[3].iconPNG = normalized
    try store.save(config)
    try FileManager.default.removeItem(at: iconFile)
    let withIcon = try store.load()
    check(withIcon.keys[3].iconPNG == normalized, "embedded icon survives original file removal and JSON roundtrip")
    check(KeyImage.jpeg(key: withIcon.keys[3], index: 3, rotation: 90) != nil, "custom icon renders to device JPEG")
    var badIcon = config; badIcon.keys[3].iconPNG = Data("not PNG".utf8)
    check(!badIcon.isValid, "reject corrupt imported icon")
    var legacy = DeckConfiguration(); legacy.version = 1; legacy.imageRotation = 270; legacy.keys[0] = copy
    try store.save(legacy)
    let migrated = try store.load()
    check(migrated.version == 7 && migrated.imageRotation == 90 && migrated.keys[0] == copy, "migration fixes upside down display and preserves shortcuts")
    legacy.imageRotation = 90
    check(legacy.migrated.imageRotation == 90, "preserve manual orientation fix")
    for index in 15..<18 {
        check(DeckProtocol.address(for: index) == UInt8(index + 1), "dashboard address \(index)")
        check(DeckProtocol.imagePackets(jpeg, index: index)[0][12] == UInt8(index + 1), "dashboard image BAT address")
    }
    let settings = DashboardConfiguration()
    check(settings.slots.map(\.kind) == [.clock,.activeApp,.weather], "requested default dashboard order")
    let strings = DashboardImage.clockStrings(Date(timeIntervalSince1970: 0), settings: settings, timeZone: TimeZone(secondsFromGMT: 0)!)
    check(strings.0 == "00:00" && !strings.1.isEmpty, "clock respects specified time zone")
    var clockSettings = settings; clockSettings.clockSeconds = true; clockSettings.clockDate = false
    let seconds = DashboardImage.clockStrings(Date(timeIntervalSince1970: 1), settings: clockSettings, timeZone: TimeZone(secondsFromGMT: 0)!)
    check(seconds.0 == "00:00:01" && seconds.1.isEmpty, "clock configurable seconds and date")
    let currentJSON = Data("{\"current\":{\"temperature_2m\":12.5,\"weather_code\":61,\"is_day\":1,\"time\":1791374400}}".utf8)
    let reading = try WeatherService.decode(currentJSON)
    check(reading.celsius == 12.5 && reading.condition == "Pluie" && reading.symbol == "cloud.rain.fill", "weather decode and WMO condition")
    check(WeatherReading(celsius: 0, code: 0, isDay: false, observedAt: Date(), fetchedAt: Date()).temperature(fahrenheit: true) == "32°", "Fahrenheit conversion")
    let location = WeatherLocation(id: 1, name: "Saint-Étienne", latitude: 45.44, longitude: 4.39, admin1: "Auvergne-Rhône-Alpes", country: "France")
    let url = WeatherService.searchURL(city: "Saint-Étienne")
    check(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Saint-Étienne", "accented city encoded safely")
    check(WeatherService.forecastURL(location: location).host == "api.open-meteo.com", "forecast endpoint")
    do { _ = try WeatherService.decode(Data("{\"current\":{}}".utf8)); check(false, "reject incomplete forecast") } catch { }
    for kind in DashboardKind.allCases {
        let slot = DashboardSlot(kind: kind, iconPNG: normalized)
        guard let data = DashboardImage.jpeg(slot: slot, settings: settings, date: Date(), appName: "Application", appIcon: NSImage(data: normalized), weather: reading, weatherMessage: "", rotation: 90), let bitmap = NSBitmapImageRep(data: data) else { check(false, "dashboard render \(kind)"); return }
        check(bitmap.pixelsWide == 82 && bitmap.pixelsHigh == 82, "dashboard 82 by 82 \(kind)")
    }
    var previous = config; previous.version = 2; previous.dashboard = nil
    try store.save(previous)
    let upgraded = try store.load()
    check(upgraded.version == 7 && upgraded.dashboard?.slots.count == 3 && upgraded.keys == previous.keys, "v2 migration preserves shortcuts and icons")
    var invalidDashboard = upgraded; invalidDashboard.dashboard!.slots.removeLast()
    check(!invalidDashboard.isValid, "reject missing dashboard slots")
    var customDashboard = upgraded; customDashboard.dashboard!.slots[0].kind = .image
    customDashboard.dashboard!.slots[0].iconPNG = normalized; customDashboard.dashboard!.location = location
    try store.save(customDashboard)
    let restoredDashboard = try store.load()
    check(restoredDashboard == customDashboard, "dashboard choices and city persist")
    // Optional fields keep existing v3 JSON readable, without losing icons/city.
    var v3 = customDashboard; v3.version = 3; v3.screensaver = nil
    let oldData = try JSONEncoder().encode(v3)
    var oldObject = try JSONSerialization.jsonObject(with: oldData) as! [String: Any]
    oldObject.removeValue(forKey: "screensaver")
    let missingFields = try JSONDecoder().decode(DeckConfiguration.self, from: JSONSerialization.data(withJSONObject: oldObject)).migrated
    check(missingFields.version == 7 && missingFields.keys == v3.keys && missingFields.dashboard == v3.dashboard && missingFields.effectiveScreensaver.enabled, "v3 migration preserves city and icons")
    var appearance = IconAppearance(); appearance.scale = 0.5
    var styled = copy; styled.iconPNG = normalized; styled.appearance = appearance
    guard let reduced = KeyImage.jpeg(key: styled, index: 0, rotation: 0), let reducedBitmap = NSBitmapImageRep(data: reduced),
          let black = reducedBitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB),
          let center = reducedBitmap.colorAt(x: 35, y: 47)?.usingColorSpace(.deviceRGB) else { check(false, "styled image"); return }
    check(black.redComponent < 0.03 && black.greenComponent < 0.03 && black.blueComponent < 0.03, "transparent matte is pure black")
    check(center.redComponent > 0.5, "smaller icon remains centered")
    appearance.transparent = false; appearance.color = DeckColor(red: 0, green: 0.7, blue: 0); styled.appearance = appearance
    guard let colored = KeyImage.jpeg(key: styled, index: 0, rotation: 0), let coloredBitmap = NSBitmapImageRep(data: colored),
          let green = coloredBitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB) else { check(false, "colored matte"); return }
    check(green.greenComponent > 0.6 && green.redComponent < 0.1, "chosen background color renders")
    var invalidAppearance = config; invalidAppearance.keys[0].appearance = IconAppearance(scale: 3)
    check(!invalidAppearance.isValid, "reject invalid zoom")
    config.keys[0] = styled; config.screensaver = ScreensaverConfiguration(enabled: true, delay: 90, kind: .repeatedClock, showDate: false, wallpaperPNG: normalized)
    try store.save(config)
    let styledRoundtrip = try store.load()
    check(styledRoundtrip == config, "appearance and idle wallpaper persist")
    check(ScreensaverImage.clockCharacters(Date(timeIntervalSince1970: 45240), timeZone: TimeZone(secondsFromGMT: 0)!) == ["1", "2", ":", "3", "4"], "one entire clock digit per middle-row button")
    let start = Date(timeIntervalSince1970: 1000)
    var idle = IdleState(lastInteraction: start)
    let idleSettings = ScreensaverConfiguration()
    check(!idle.tick(now: start.addingTimeInterval(59), settings: idleSettings) && !idle.active, "idle not active before delay")
    check(idle.tick(now: start.addingTimeInterval(60), settings: idleSettings) && idle.active, "idle activates at configured delay")
    check(idle.press(now: start.addingTimeInterval(70)) && !idle.active, "first waking press consumed")
    check(!idle.press(now: start.addingTimeInterval(71)), "next press allowed")
    check(!idle.tick(now: start.addingTimeInterval(130), settings: idleSettings), "button restarts idle deadline")
    check(idle.tick(now: start.addingTimeInterval(131), settings: idleSettings), "idle restarts after inactivity")
    var disabled = idleSettings; disabled.enabled = false
    check(idle.tick(now: start.addingTimeInterval(200), settings: disabled) && !idle.active, "disabling restores assigned keys")
    var mouseIdle = IdleState(lastInteraction: start, active: true)
    check(mouseIdle.mouseMoved(now: start.addingTimeInterval(100), settings: idleSettings) && !mouseIdle.active, "mouse movement wakes idle without consuming a deck key")
    check(!mouseIdle.tick(now: start.addingTimeInterval(159), settings: idleSettings), "mouse movement restarts inactivity deadline")
    check(mouseIdle.tick(now: start.addingTimeInterval(160), settings: idleSettings), "idle resumes after mouse inactivity")
    var ignoreMouse = idleSettings; ignoreMouse.wakeOnMouseMovement = false
    check(!mouseIdle.mouseMoved(now: start.addingTimeInterval(170), settings: ignoreMouse) && mouseIdle.active, "mouse wake can be disabled")
    config.screensaver = ignoreMouse; try store.save(config)
    check((try? store.load())?.effectiveScreensaver.wakesOnMouseMovement == false, "mouse wake option persists")
    check(ScreensaverImage.cropRect(index: 0).origin == CGPoint(x: 0, y: 0) && ScreensaverImage.cropRect(index: 14).origin == CGPoint(x: 380, y: 190), "mosaic crop order follows physical grid")
    // Colored top and bottom strips prove CGImage crop coordinates, not just dimensions.
    let mosaic = CGContext(data: nil, width: 475, height: 285, bitsPerComponent: 8, bytesPerRow: 1900, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    mosaic.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); mosaic.fill(CGRect(x: 0, y: 190, width: 475, height: 95))
    mosaic.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); mosaic.fill(CGRect(x: 0, y: 0, width: 475, height: 95))
    let fixture = mosaic.makeImage()!
    let top = NSBitmapImageRep(cgImage: fixture.cropping(to: ScreensaverImage.cropRect(index: 0))!).colorAt(x: 30, y: 30)!.usingColorSpace(.deviceRGB)!
    let bottom = NSBitmapImageRep(cgImage: fixture.cropping(to: ScreensaverImage.cropRect(index: 14))!).colorAt(x: 30, y: 30)!.usingColorSpace(.deviceRGB)!
    check(top.redComponent > 0.9 && bottom.blueComponent > 0.9, "mosaic top and bottom are correctly oriented")
    for kind in ScreensaverKind.allCases {
        var settings = idleSettings; settings.kind = kind; settings.wallpaperPNG = normalized
        for rotation in [0,90,180,270] {
            guard let tiles = ScreensaverImage.tiles(settings: settings, date: start, clock: clockSettings, rotation: rotation) else { check(false, "screensaver tiles"); return }
            check(tiles.count == 15 && tiles.allSatisfy { NSBitmapImageRep(data: $0)?.pixelsWide == 95 }, "15 idle tiles for \(kind), rotation \(rotation)")
        }
    }
    let digitCanvas = ScreensaverImage.canvas(settings: ScreensaverConfiguration(), date: Date(timeIntervalSince1970: 45240), clock: DashboardConfiguration())!
    for index in 5...9 {
        let tile = NSBitmapImageRep(cgImage: digitCanvas.cropping(to: ScreensaverImage.cropRect(index: index))!)
        var lit = 0
        for y in 0..<95 { for x in 0..<95 {
            if (tile.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0) > 0.5 { lit += 1 }
        } }
        check(lit > 100, "whole clock glyph visible on button \(index + 1)")
    }
    let secondDate = Date(timeIntervalSince1970: 45296) // 12:34:56 UTC
    check(ScreensaverImage.secondsCharacters(secondDate, timeZone: TimeZone(secondsFromGMT: 0)!) == ["5", "6"], "seconds split into tens and units")
    check(ScreensaverImage.secondsCharacters(Date(timeIntervalSince1970: 45300), timeZone: TimeZone(secondsFromGMT: 0)!) == ["0", "0"], "seconds wrap at minute boundary")
    var withSeconds = ScreensaverConfiguration()
    withSeconds.showDate = false
    var withoutSeconds = withSeconds; withoutSeconds.showSeconds = false
    let secondsTiles = ScreensaverImage.tiles(settings: withSeconds, date: secondDate, clock: settings, rotation: 0)!
    let hiddenTiles = ScreensaverImage.tiles(settings: withoutSeconds, date: secondDate, clock: settings, rotation: 0)!
    check(secondsTiles.indices.filter { secondsTiles[$0] != hiddenTiles[$0] } == [13,14], "seconds occupy only the two bottom-right buttons")
    let nextSecond = ScreensaverImage.tiles(settings: withSeconds, date: secondDate.addingTimeInterval(1), clock: settings, rotation: 0)!
    check(secondsTiles.indices.filter { secondsTiles[$0] != nextSecond[$0] } == [14], "only changed seconds digit needs USB upload")
    let nextHidden = ScreensaverImage.tiles(settings: withoutSeconds, date: secondDate.addingTimeInterval(1), clock: settings, rotation: 0)!
    check(nextHidden == hiddenTiles, "hidden seconds do not alter the display")
    check(withSeconds.imageTick(at: secondDate) != withSeconds.imageTick(at: secondDate.addingTimeInterval(1)), "seconds refresh every second")
    check(withoutSeconds.imageTick(at: secondDate) == withoutSeconds.imageTick(at: secondDate.addingTimeInterval(1)), "disabled seconds retain minute refresh")
    let legacyScreensaver = try JSONDecoder().decode(ScreensaverConfiguration.self, from: Data("{\"enabled\":true,\"delay\":60,\"kind\":\"largeClock\",\"showDate\":true}".utf8))
    check(legacyScreensaver.showsSeconds && legacyScreensaver.isValid, "old settings load without new seconds field")
    config.screensaver = withoutSeconds
    try store.save(config)
    let savedSeconds = try store.load()
    check(savedSeconds.effectiveScreensaver.showSeconds == false, "seconds option remains off after reopening")
    let holdID = UUID(), secondHoldID = UUID()
    let emptyKeyboard = HeldKeyboardState()
    let firstHold = HeldKeyboardState(holds: [holdID: copy.shortcut!])
    let pressing = emptyKeyboard.transition(to: firstHold)
    check(pressing.count == 2 && pressing[0].modifier && pressing[1].down && pressing[1].code == copy.shortcut!.keyCode, "hold emits modifiers and key down without immediate key up")
    let releasing = firstHold.transition(to: emptyKeyboard)
    check(releasing.count == 2 && !releasing[0].down && releasing[1].flags.isEmpty, "finger release emits key up and releases modifier")
    var twoHolds = firstHold
    let paste = Preset.all[1].assignment.shortcut!
    twoHolds.holds[secondHoldID] = paste
    check(firstHold.transition(to: twoHolds).count == 1, "shared Command modifier pressed once")
    let remaining = HeldKeyboardState(holds: [secondHoldID: paste])
    let partialRelease = twoHolds.transition(to: remaining)
    check(partialRelease.count == 1 && !partialRelease[0].down && partialRelease[0].flags.contains(.maskCommand), "releasing one held shortcut preserves other modifier")
    let finalRelease = remaining.transition(to: emptyKeyboard)
    check(finalRelease.last?.flags.isEmpty == true, "disconnect pause or quit can release all synthetic modifiers")
    var duplicateHold = firstHold; duplicateHold.holds[secondHoldID] = copy.shortcut!
    check(firstHold.transition(to: duplicateHold).isEmpty && duplicateHold.transition(to: firstHold).isEmpty, "shared held key released only after last finger")
    var actionConfig = DeckConfiguration()
    actionConfig.keys[0] = styled; actionConfig.keys[0].pressMode = .hold
    var page = DeckPage(name: "Applications")
    page.keys[0] = KeyAssignment(title: "Accueil", actionKind: .page, targetPageID: homePageID)
    page.keys[1] = KeyAssignment(title: "Safari", actionKind: .application, applicationPath: "/Applications/Safari.app")
    let steps = [MacroStep(kind: .shortcut, shortcut: copy.shortcut), MacroStep(kind: .wait, seconds: 0.05), MacroStep(kind: .shortcut, shortcut: paste)]
    page.keys[2] = KeyAssignment(title: "Copier puis coller", actionKind: .macro, macro: steps)
    actionConfig.pages = [page]
    actionConfig.keys[14] = KeyAssignment(title: "Applications", actionKind: .page, targetPageID: page.id)
    check(actionConfig.isValid && actionConfig.keys(on: page.id) == page.keys, "page actions and active-page assignments")
    try store.save(actionConfig)
    let restoredActions = try store.load()
    check(restoredActions == actionConfig && restoredActions.keys[0].effectivePressMode == .hold, "pages macros applications and held mode persist")
    var brokenAction = actionConfig; brokenAction.keys[14].targetPageID = UUID().uuidString
    check(!brokenAction.isValid, "reject a page link that has no target")
    brokenAction = actionConfig; brokenAction.pages![0].keys[2].macro![1].seconds = .infinity
    check(!brokenAction.isValid, "reject invalid macro delay")
    brokenAction = actionConfig; brokenAction.pages!.append(page)
    check(!brokenAction.isValid, "reject duplicate page identifiers")
    var v4 = actionConfig; v4.version = 4; v4.pages = nil; v4.keys[14] = KeyAssignment()
    try store.save(v4)
    let migratedActions = try store.load()
    check(migratedActions.version == 7 && migratedActions.keys == v4.keys, "v4 migration preserves existing icons shortcuts and zoom")
    let legacyKey = try JSONDecoder().decode(KeyAssignment.self, from: Data("{\"title\":\"Ancienne touche\"}".utf8))
    check(legacyKey.effectiveKind == .shortcut && legacyKey.effectivePressMode == .tap, "legacy keys keep single-press behavior")
    let insertedText = "Bonjour, ça va ? 👨‍👩‍👧‍👦\nDeuxième ligne\t  avec espaces."
    let textKey = KeyAssignment(title: "Mon texte", actionKind: .text, text: insertedText)
    check(textKey.isValid && textKey.isConfigured && textKey.actionLabel == "Texte", "plain text action accepts accents emoji newlines tabs and spacing")
    check(!KeyAssignment(actionKind: .text).isConfigured && !KeyAssignment(actionKind: .text, text: "").isConfigured, "empty text key stays unconfigured")
    check(!TextInsertion.isValid("abc\0def") && !TextInsertion.isValid(String(repeating: "a", count: 20_001)), "text imports reject nulls and excessive length")
    check(TextInsertion.draft("ab\0cd") == "abcd" && TextInsertion.draft(String(repeating: "🙂", count: 20_001)).count == 20_000, "draft limits preserve whole Unicode characters")
    let textStep = MacroStep(kind: .text, text: insertedText)
    check(textStep.isValid && textStep.isReady && !MacroStep(kind: .text).isReady, "text macro step requires content")
    actionConfig.keys[4] = textKey
    actionConfig.pages![0].keys[3] = KeyAssignment(actionKind: .macro, macro: [textStep, MacroStep(kind: .wait, seconds: 0.1)])
    try store.save(actionConfig)
    check((try? store.load()) == actionConfig && legacyKey.text == nil, "text keys and text macros roundtrip without changing legacy behavior")
    MainActor.assumeIsolated {
        let board = NSPasteboard(name: NSPasteboard.Name("soomfon-text-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let oldText = "Presse-papiers précédent"
        let rich = Data("{\\rtf1 previous}".utf8)
        func prepareClipboard() {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString(oldText, forType: .string); item.setData(rich, forType: .rtf)
            board.writeObjects([item])
        }
        let inserter = TextInserter()
        var complete = false, failed = false, pasted = false, hidden = false
        func waitForCompletion() {
            let deadline = Date().addingTimeInterval(2)
            while !complete && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(complete, "text insertion completes without blocking main loop")
        }
        prepareClipboard()
        Task { @MainActor in
            do { try await inserter.insert(insertedText, pasteboard: board) {
                pasted = board.string(forType: .string) == insertedText && board.data(forType: .rtf) == nil
                hidden = board.types?.contains(TextInsertion.transientType) == true && board.types?.contains(TextInsertion.concealedType) == true
                return true
            } } catch { failed = true }
            complete = true
        }
        waitForCompletion()
        check(pasted && !failed && !inserter.isInserting && board.string(forType: .string) == oldText && board.data(forType: .rtf) == rich,
              "paste receives exact plain text then restores original text and rich representations")
        check(hidden && board.types?.contains(TextInsertion.concealedType) != true,
              "temporary paste is marked transient and concealed for clipboard managers, and the marks are gone after restore")
        complete = false
        Task { @MainActor in
            do { try await inserter.insert(insertedText, pasteboard: board) {
                board.clearContents(); board.setString("Copié pendant l’insertion", forType: .string); return true
            } } catch { failed = true }
            complete = true
        }
        waitForCompletion()
        check(!failed && board.string(forType: .string) == "Copié pendant l’insertion", "new clipboard content copied during insertion is never overwritten")
        prepareClipboard(); complete = false; failed = false
        Task { @MainActor in
            do { try await inserter.insert(insertedText, pasteboard: board) { false } }
            catch { failed = true }
            complete = true
        }
        waitForCompletion()
        check(failed && board.string(forType: .string) == oldText && board.data(forType: .rtf) == rich && !inserter.isInserting,
              "failed paste rolls clipboard back and clears busy state")
        complete = false; failed = false; pasted = false
        let insertion = Task { @MainActor in
            do { try await inserter.insert(insertedText, pasteboard: board) { pasted = true; return true } }
            catch is CancellationError { failed = true }
            catch { check(false, "unexpected cancellation error") }
            complete = true
        }
        while !pasted { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        insertion.cancel(); waitForCompletion()
        check(failed && board.string(forType: .string) == oldText && board.data(forType: .rtf) == rich && !inserter.isInserting,
              "cancellation still waits for clipboard cleanup and reports cancellation")
    }
    MainActor.assumeIsolated {
        let runner = MacroRunner()
        var performed: [UInt16] = []; var completed = false; var message: String?
        let started = Date()
        runner.start(steps: steps, perform: { step in if let code = step.shortcut?.keyCode { performed.append(code) } }, progress: { _ in }, finished: { value in completed = true; message = value })
        let deadline = Date().addingTimeInterval(2)
        while !completed && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(completed && message == nil && performed == [copy.shortcut!.keyCode,paste.keyCode] && Date().timeIntervalSince(started) >= 0.05, "macro executes in order with asynchronous delay")
        performed = []; completed = false
        runner.start(steps: [MacroStep(kind: .wait, seconds: 0.2), MacroStep(kind: .shortcut, shortcut: paste)], perform: { step in if let code = step.shortcut?.keyCode { performed.append(code) } }, progress: { _ in }, finished: { _ in completed = true })
        RunLoop.main.run(until: Date().addingTimeInterval(0.03)); runner.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        check(performed.isEmpty && !completed && !runner.isRunning, "cancelled macro never executes later steps")
    }
    let ctrlOnly = Shortcut.composed(code: nil, label: "", modifiers: UInt64(NSEvent.ModifierFlags.control.rawValue))!
    check(ctrlOnly.isValid && ctrlOnly.isModifiersOnly && ctrlOnly.display == "⌃", "Ctrl can be chosen on its own")
    check(Shortcut.composed(code: nil, label: "", modifiers: 0) == nil, "empty composition clears shortcut")
    let chosenFlags = UInt64(NSEvent.ModifierFlags([.control,.option,.command]).rawValue)
    let composed = Shortcut.composed(code: copy.shortcut!.keyCode, label: "C", modifiers: chosenFlags)!
    check(composed.display == "⌃⌥⌘C" && composed.isValid, "Ctrl Option and Command combine on a key")
    let onlyState = HeldKeyboardState(holds: [UUID(): ctrlOnly])
    let ctrlDown = emptyKeyboard.transition(to: onlyState), ctrlUp = onlyState.transition(to: emptyKeyboard)
    check(ctrlDown.count == 1 && ctrlDown[0].modifier && ctrlDown[0].down && ctrlDown[0].code == 59, "modifier-only hold sends no phantom letter")
    check(ctrlUp.count == 1 && !ctrlUp[0].down && ctrlUp[0].flags.isEmpty, "modifier-only release clears Ctrl")
    let ctrlTap = ShortcutEmitter.events(for: ctrlOnly)!
    check(ctrlTap.count == 2 && ctrlTap.allSatisfy { $0.type == .flagsChanged } && ctrlTap.last!.flags.isEmpty, "modifier-only single press is paired")
    let originalShortcut = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(copy.shortcut!))
    check(!originalShortcut.isModifiersOnly && originalShortcut == copy.shortcut!, "normal shortcuts remain compatible")
    config.keys[1] = KeyAssignment(shortcut: ctrlOnly, pressMode: .hold)
    try store.save(config)
    let ctrlSaved = try store.load()
    check(ctrlSaved.keys[1].shortcut == ctrlOnly && ctrlSaved.keys[1].effectivePressMode == .hold, "modifier choices and held mode persist")

    check(copy.showsTitle && !styled.showsTitle, "legacy text and icon appearance retained")
    var titledIcon = styled; titledIcon.showTitle = true
    var hiddenTitle = copy; hiddenTitle.showTitle = false
    func hasWhiteCaption(_ key: KeyAssignment) -> Bool {
        guard let data = KeyImage.jpeg(key: key, index: 0, rotation: 0), let bitmap = NSBitmapImageRep(data: data) else { return false }
        for y in 69..<94 {
            for x in 4..<91 {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent > 0.65 && color.greenComponent > 0.65 && color.blueComponent > 0.65 { return true }
            }
        }
        return false
    }
    check(hasWhiteCaption(titledIcon) && !hasWhiteCaption(styled), "icon caption appears only when enabled")
    check(hasWhiteCaption(copy) && !hasWhiteCaption(hiddenTitle), "text key caption hides independently of its shortcut")
    check(hiddenTitle.title == copy.title && hiddenTitle.shortcut == copy.shortcut, "hiding caption preserves name and action")

    var profilePage = DeckPage(name: "Éditeur")
    profilePage.keys[0] = titledIcon
    profilePage.addHomeButtons()
    let profile = ApplicationPage(bundleID: "com.example.editor", name: "Éditeur", pageID: profilePage.id)
    var profilesConfig = config; profilesConfig.pages = [profilePage]; profilesConfig.applicationPages = [profile]
    check(profilesConfig.isValid, "application page includes two reserved home buttons")
    var auto = AutomaticPageState()
    check(auto.activated(bundleID: profile.bundleID, ownBundleID: "fr.local.soomfon-raccourcis", configuration: profilesConfig) == profilePage.id, "foreground app chooses its associated page")
    check(auto.activated(bundleID: "fr.local.soomfon-raccourcis", ownBundleID: "fr.local.soomfon-raccourcis", configuration: profilesConfig) == nil && auto.automaticPageID == profilePage.id, "opening configuration does not switch application page")
    auto.manuallySelected()
    check(auto.activated(bundleID: "com.example.other", ownBundleID: nil, configuration: profilesConfig) == nil, "manual home or page selection remains usable")
    _ = auto.activated(bundleID: profile.bundleID, ownBundleID: nil, configuration: profilesConfig)
    check(auto.activated(bundleID: "com.example.other", ownBundleID: nil, configuration: profilesConfig) == homePageID, "leaving automatic app returns to home")
    profilesConfig.automaticPagesEnabled = false
    check(auto.activated(bundleID: profile.bundleID, ownBundleID: nil, configuration: profilesConfig) == nil, "automatic pages can be disabled")
    var invalidProfiles = profilesConfig; invalidProfiles.applicationPages!.append(profile)
    check(!invalidProfiles.isValid, "duplicate application association rejected")
    invalidProfiles = profilesConfig; invalidProfiles.pages![0].keys[14] = copy
    check(!invalidProfiles.isValid && !invalidProfiles.pages![0].canReserveHomeButtons, "home navigation cannot replace a configured action silently")
    try store.save(profilesConfig)
    let savedProfiles = try store.load()
    check(savedProfiles == profilesConfig, "application pages and caption choices survive reopening")
    var v6 = profilesConfig; v6.version = 6; v6.applicationPages = nil
    check(v6.migrated.version == 7 && v6.migrated.keys == v6.keys && v6.migrated.pages == v6.pages, "v6 migration preserves configured keys and pages")
    var slot = DashboardSlot(kind: .activeApp)
    check(slot.caption(fallback: "Safari") == "Safari", "existing dashboard app title retained")
    slot.showTitle = false
    check(slot.caption(fallback: "Safari") == nil, "dashboard title can be hidden")
    slot.showTitle = true; slot.title = "Navigation"
    check(slot.caption(fallback: "Safari") == "Navigation", "dashboard title can be customized")
    profilesConfig.dashboard!.slots[1] = slot
    var animation = ScreensaverConfiguration(); animation.pacmanEnabled = true
    animation.clockDuration = 10; animation.pacmanDuration = 20
    check(animation.pacmanTime(elapsed: 9.9) == nil && animation.pacmanTime(elapsed: 10) == 0,
          "idle clock switches to Pac-Man after configured duration")
    check(animation.pacmanTime(elapsed: 29.9) != nil && animation.pacmanTime(elapsed: 30) == nil,
          "animation returns to clock and repeats")
    check(PacmanScreensaver.remainingApplications(time: 0, duration: 20).count == 14
          && PacmanScreensaver.remainingApplications(time: 19.9, duration: 20).isEmpty,
          "Pac-Man eats every application along its route")
    check(Set(PacmanScreensaver.route) == Set(0..<15), "animation visits all fifteen keys")
    let appIcons = [ScreensaverAppIcon(name: "Copier", icon: NSImage(cgImage: icon, size: NSSize(width: icon.width, height: icon.height)))]
    let gameStart = ScreensaverImage.tiles(settings: animation, date: secondDate, clock: settings, rotation: 90, elapsed: 10, apps: appIcons)!
    let gameLater = ScreensaverImage.tiles(settings: animation, date: secondDate, clock: settings, rotation: 90, elapsed: 12, apps: appIcons)!
    check(gameStart.count == 15 && gameStart != gameLater, "animated frames render and move on the device")
    check(animation.imageTick(at: secondDate, elapsed: 10) != animation.imageTick(at: secondDate.addingTimeInterval(0.5), elapsed: 10.5), "animation frames advance during movement")
    profilesConfig.screensaver = animation
    try store.save(profilesConfig)
    let savedAnimation = try store.load()
    check(savedAnimation == profilesConfig, "dashboard captions and animated idle durations persist")
    check(websiteURL("wikipedia.org")?.absoluteString == "https://wikipedia.org", "website address gains HTTPS")
    check(websiteURL(" https://example.com/a?q=bonjour#haut ")?.host == "example.com", "website keeps path query and anchor")
    for invalidAddress in ["", "https://", "javascript://alert(1)", "file:///tmp/file", "https://user:password@example.com", "https://exa mple.com"] {
        check(websiteURL(invalidAddress) == nil, "reject unsupported website address")
    }
    var site = KeyAssignment(); site.actionKind = .website; site.websiteAddress = "wikipedia.org"
    profilesConfig.pages![0].keys[2] = site
    var matrix = ScreensaverConfiguration(); matrix.kind = .matrix
    matrix.pacmanEnabled = true
    check(!matrix.usesAnimation && matrix.animationTime(elapsed: 35) == nil, "direct Matrix selection stays Matrix")
    let matrixStart = ScreensaverImage.tiles(settings: matrix, date: secondDate, clock: settings, rotation: 90, elapsed: 0)!
    let matrixLater = ScreensaverImage.tiles(settings: matrix, date: secondDate, clock: settings, rotation: 90, elapsed: 0.5)!
    check(matrixStart.count == 15 && matrixStart != matrixLater, "Matrix moves across fifteen device tiles")
    let overnightRain = ScreensaverImage.tiles(settings: matrix, date: secondDate, clock: settings, rotation: 90, elapsed: 36_000)!
    let overnightNext = ScreensaverImage.tiles(settings: matrix, date: secondDate.addingTimeInterval(0.5), clock: settings, rotation: 90, elapsed: 36_000.5)!
    check(overnightRain.count == 15 && overnightRain != overnightNext, "Matrix still produces moving frames after ten hours elapsed")
    matrix.kind = .largeClock; matrix.animation = .matrix; matrix.clockDuration = 10; matrix.pacmanDuration = 20
    check(matrix.animationTime(elapsed: 9) == nil && matrix.animationTime(elapsed: 10) == 0 && matrix.animationTime(elapsed: 30) == nil,
          "Matrix alternates with clock and respects durations")
    check(!matrix.usesPacman, "Matrix overrides legacy Pac-Man choice")
    profilesConfig.screensaver = matrix
    try store.save(profilesConfig)
    check((try? store.load()) == profilesConfig, "website actions and Matrix selection survive save and reload")
    check((0..<5).allSatisfy { MatrixScreensaver.clockOpacity(time: 0, column: $0) == 0 }, "Matrix starts with rain only")
    check(MatrixScreensaver.clockOpacity(time: 5, column: 0) == 1 && MatrixScreensaver.clockOpacity(time: 5, column: 4) == 0, "Matrix clock appears one character at a time")
    check((0..<5).allSatisfy { MatrixScreensaver.clockOpacity(time: 10, column: $0) == 1 }, "Matrix clock stays readable")
    check(MatrixScreensaver.clockOpacity(time: 14, column: 0) < 1 && MatrixScreensaver.clockOpacity(time: 14, column: 4) == 1, "Matrix clock disappears progressively")
    check((0..<5).allSatisfy { MatrixScreensaver.clockOpacity(time: 18, column: $0) == 0 }, "Matrix returns to rain only")
    check(MatrixScreensaver.clockOpacity(time: 25, column: 0) == MatrixScreensaver.clockOpacity(time: 5, column: 0), "Matrix clock repeats")
    for character in Array("0123456789:").map({ String($0) }) {
        let fragments = MatrixScreensaver.clockFragments(character: character)
        check(!fragments.isEmpty && fragments.allSatisfy { $0.rect.width <= 6 && $0.rect.height <= 7 }, "digit mask has small fragments: \(character)")
    }
    let forming = MatrixScreensaver.fragmentMotion(time: 4.45, column: 0, gridX: 6, gridY: 4)
    let landing = MatrixScreensaver.fragmentMotion(time: 4.8, column: 0, gridX: 6, gridY: 4)
    check(forming.moving && forming.offset.y > landing.offset.y && landing.offset.y > 0 && forming.codeOpacity > landing.codeOpacity,
          "Matrix symbols descend and settle into digit fragments")
    let assembled = MatrixScreensaver.fragmentMotion(time: 10, column: 4, gridX: 6, gridY: 4)
    check(!assembled.moving && assembled.offset == .zero && assembled.opacity == 1 && assembled.codeOpacity == 0, "assembled clock holds still for reading")
    let detached = MatrixScreensaver.fragmentMotion(time: 13.8, column: 0, gridX: 6, gridY: 4)
    let fallen = MatrixScreensaver.fragmentMotion(time: 14.2, column: 0, gridX: 6, gridY: 4)
    check(detached.moving && detached.offset.y < 0 && fallen.offset.y < detached.offset.y && fallen.codeOpacity > detached.codeOpacity,
          "clock breaks into falling pieces that return to Matrix code")
    check(MatrixScreensaver.fragmentMotion(time: 14.2, column: 0, gridX: 6, gridY: 4, speed: 3).offset.y
          < MatrixScreensaver.fragmentMotion(time: 14.2, column: 0, gridX: 6, gridY: 4, speed: 0.25).offset.y, "falling fragments follow Matrix speed")
    check(abs(MatrixScreensaver.fragmentMotion(time: 24.45, column: 0, gridX: 6, gridY: 4).offset.y - forming.offset.y) < 0.00001,
          "fragment construction repeats after twenty seconds")
    for column in 0..<5 {
        for fragment in MatrixScreensaver.clockFragments(character: "8") {
            check(MatrixScreensaver.fragmentMotion(time: 3.9, column: column, gridX: fragment.gridX, gridY: fragment.gridY).opacity == 0
                  && MatrixScreensaver.fragmentMotion(time: 18, column: column, gridX: fragment.gridX, gridY: fragment.gridY).opacity == 0,
                  "clock pieces are absent before construction and after destruction")
        }
    }
    let formationClock = MatrixScreensaver.canvas(time: 4.8, date: secondDate, showClock: true)!
    let formationRain = MatrixScreensaver.canvas(time: 4.8, date: secondDate, showClock: false)!
    let destructionClock = MatrixScreensaver.canvas(time: 14.2, date: secondDate, showClock: true)!
    let destructionRain = MatrixScreensaver.canvas(time: 14.2, date: secondDate, showClock: false)!
    let topRow = CGRect(x: 0, y: 0, width: 475, height: 95), bottomRow = CGRect(x: 0, y: 190, width: 475, height: 95)
    check(IconImage.encode(formationClock.cropping(to: topRow)!, type: "public.png") != IconImage.encode(formationRain.cropping(to: topRow)!, type: "public.png"),
          "construction arrives through the upper device keys")
    check(IconImage.encode(destructionClock.cropping(to: bottomRow)!, type: "public.png") != IconImage.encode(destructionRain.cropping(to: bottomRow)!, type: "public.png"),
          "destroyed digit pieces visibly fall into the bottom device keys")
    check(IconImage.encode(MatrixScreensaver.canvas(time: 18, date: secondDate, showClock: true)!, type: "public.png")
          == IconImage.encode(MatrixScreensaver.canvas(time: 18, date: secondDate, showClock: false)!, type: "public.png"), "no clock fragments remain after destruction")
    let plainRain = MatrixScreensaver.canvas(time: 10, date: secondDate, showClock: false)!
    let timedRain = MatrixScreensaver.canvas(time: 10, date: secondDate, showClock: true)!
    check(IconImage.encode(plainRain, type: "public.png") != IconImage.encode(timedRain, type: "public.png"), "Matrix clock toggle changes displayed image")
    matrix.matrixClockEnabled = false; profilesConfig.screensaver = matrix
    try store.save(profilesConfig)
    check((try? store.load())?.effectiveScreensaver.showsMatrixClock == false, "Matrix clock toggle persists")
    var paced = ScreensaverConfiguration(); paced.kind = .matrix
    for fps in [4, 8, 12] {
        paced.animationFPS = fps
        check(paced.imageTick(at: secondDate, elapsed: 10) != paced.imageTick(at: secondDate.addingTimeInterval(1 / Double(fps)), elapsed: 10), "requested animation cadence advances")
    }
    paced.matrixSpeed = 0.25; paced.animationFPS = 12
    check(paced.isValid, "Matrix speed and fluidity accept supported settings")
    let slowRain = MatrixScreensaver.canvas(time: 10, date: secondDate, showClock: true, speed: 0.25)!
    let fastRain = MatrixScreensaver.canvas(time: 10, date: secondDate, showClock: true, speed: 3)!
    check(IconImage.encode(slowRain, type: "public.png") != IconImage.encode(fastRain, type: "public.png"), "speed changes falling streams")
    profilesConfig.screensaver = paced; try store.save(profilesConfig)
    check((try? store.load())?.effectiveScreensaver.matrixSpeed == 0.25 && (try? store.load())?.effectiveScreensaver.animationFPS == 12, "Matrix speed and fluidity persist")
    paced.matrixSpeed = .nan; check(!paced.isValid, "invalid animation speed rejected")
    var pending = PendingDeckDisplay()
    pending.merge(images: [(0, Data([1])), (16, Data([2]))], brightness: 50, reinitialize: true)
    pending.merge(images: [(0, Data([3])), (1, Data([4]))], brightness: 75, reinitialize: false)
    check(pending.images == [0: Data([3]), 1: Data([4]), 16: Data([2])] && pending.brightness == 75 && pending.reinitialize,
          "USB coalescing keeps newest tile, preserves dashboard and initialization")
    let siteStep = MacroStep(kind: .website, websiteAddress: "https://example.org")
    check(siteStep.isValid && siteStep.isReady && siteStep.label == "example.org", "website macro step is executable")
    check(!MacroStep(kind: .website).isReady, "incomplete website macro cannot start")
    var capture = copy; capture.actionKind = .screenCapture
    check(capture.isConfigured && capture.effectiveCaptureMode == .area && capture.actionLabel == "Capture", "capture action works without a keyboard shortcut")
    check(ScreenCaptureMode.area.url.absoluteString == "snapzy://capture/area" && ScreenCaptureMode.fullscreen.url.absoluteString == "snapzy://capture/fullscreen" && ScreenCaptureMode.window.url.absoluteString == "snapzy://capture/application", "direct capture routes match Snapzy modes")
    capture.captureMode = .window; profilesConfig.keys[0] = capture
    try store.save(profilesConfig)
    let savedCapture = try store.load()
    check(savedCapture.keys[0].effectiveCaptureMode == .window && savedCapture.keys[0].shortcut == copy.shortcut && savedCapture.keys[0].isConfigured, "direct capture choice persists while retaining previous shortcut")
    var launchConfig = DeckConfiguration()
    var launchPage = DeckPage(name: "Mon site"); launchPage.addHomeButtons()
    launchConfig.pages = [launchPage]
    launchConfig.keys[0] = KeyAssignment(title: "Mon logiciel", actionKind: .application, applicationPath: "/Applications/Safari.app", launchPageID: launchPage.id)
    launchConfig.keys[1] = KeyAssignment(title: "Mon site", actionKind: .website, websiteAddress: "https://example.org", launchPageID: launchPage.id)
    check(launchConfig.isValid && launchPage.keys.suffix(2).allSatisfy { $0.targetPageID == homePageID }, "application and website launchers accept a page with two home buttons")
    try store.save(launchConfig)
    let savedLaunch = try store.load()
    check(savedLaunch == launchConfig && legacyKey.launchPageID == nil, "launcher pages persist and existing keys continue opening only")
    var invalidLaunch = launchConfig; invalidLaunch.pages![0].keys[0].launchPageID = UUID().uuidString
    check(!invalidLaunch.isValid, "missing launch page on a nested page is rejected")
    invalidLaunch = launchConfig; invalidLaunch.keys[0].launchPageID = "invalid"
    check(!invalidLaunch.isValid, "malformed launch page is rejected")
    invalidLaunch = launchConfig; invalidLaunch.pages![0].keys[13] = copy
    check(!invalidLaunch.isValid && launchConfig.requiresHomeNavigation(on: launchPage.id) && !launchConfig.requiresHomeNavigation(on: homePageID), "launcher pages reserve both home buttons without changing the home page")
    launchConfig.pages![0].keys[0].targetPageID = launchPage.id
    launchConfig.removeReferences(to: launchPage.id); launchConfig.pages = []
    check(launchConfig.isValid && launchConfig.keys[0].launchPageID == nil && launchConfig.keys[1].launchPageID == nil, "deleting a launch page keeps the original app and site actions")
    profilesConfig.automaticPagesEnabled = true
    var launchAuto = AutomaticPageState()
    launchAuto.beginLaunch()
    check(launchAuto.activated(bundleID: profile.bundleID, ownBundleID: nil, configuration: profilesConfig) == nil && launchAuto.launchInProgress, "app activation during launch cannot cancel the requested page")
    launchAuto.finishLaunch(pageID: launchPage.id, bundleID: profile.bundleID)
    check(launchAuto.activated(bundleID: profile.bundleID, ownBundleID: nil, configuration: profilesConfig) == nil && launchAuto.automaticPageID == launchPage.id, "late activation of the opened app does not replace its explicit launcher page")
    check(launchAuto.activated(bundleID: "com.example.other", ownBundleID: nil, configuration: profilesConfig) == homePageID, "leaving the launched app restores home")
    launchAuto.finishLaunch(pageID: launchPage.id, bundleID: profile.bundleID); launchAuto.manuallySelected()
    check(launchAuto.activated(bundleID: "com.example.other", ownBundleID: nil, configuration: profilesConfig) == nil, "manual home remains accessible after an app launcher")
    launchAuto.beginLaunch(); launchAuto.cancelLaunch()
    check(!launchAuto.launchInProgress && launchAuto.activated(bundleID: profile.bundleID, ownBundleID: nil, configuration: profilesConfig) == profilePage.id, "cancelled launch restores normal automatic application pages")
    if CommandLine.arguments.contains("--previews") {
        let phases: [Double] = [0, 4.7, 5.2, 6, 6.8, 10, 13.5, 14.2, 14.8, 15.5, 16.2, 18]
        let sheet = CGContext(data: nil, width: 1425, height: 1260, bitsPerComponent: 8, bytesPerRow: 5700,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        sheet.setFillColor(CGColor(gray: 0.035, alpha: 1)); sheet.fill(CGRect(x: 0, y: 0, width: 1425, height: 1260))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
        for (index, phase) in phases.enumerated() {
            let x = index % 3 * 475, y = (3 - index / 3) * 315
            sheet.draw(MatrixScreensaver.canvas(time: phase, date: secondDate, showClock: true)!, in: CGRect(x: x, y: y, width: 475, height: 285))
            (String(format: "%.1f s", phase) as NSString).draw(at: CGPoint(x: x + 10, y: y + 293),
                 withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        try IconImage.encode(sheet.makeImage()!, type: "public.png")!.write(to: URL(fileURLWithPath: "/private/tmp/soomfon-matrix-phases.png"))
        try IconImage.encode(MatrixScreensaver.canvas(time: 10, date: secondDate, showClock: true)!, type: "public.png")!.write(to: URL(fileURLWithPath: "/private/tmp/soomfon-matrix-preview.png"))
        try IconImage.encode(PacmanScreensaver.canvas(time: 8, duration: 20, showTitles: true, apps: appIcons)!, type: "public.png")!.write(to: URL(fileURLWithPath: "/private/tmp/soomfon-pacman-preview.png"))
        try IconImage.encode(digitCanvas, type: "public.png")!.write(to: URL(fileURLWithPath: "/private/tmp/soomfon-veille-preview.png"))
        var weatherSettings = DashboardConfiguration(); weatherSettings.location = location
        let data = DashboardImage.jpeg(slot: DashboardSlot(kind: .weather), settings: weatherSettings, date: Date(), appName: "", appIcon: nil, weather: reading, weatherMessage: "", rotation: 0)!
        try data.write(to: URL(fileURLWithPath: "/private/tmp/soomfon-meteo-preview.jpeg"))
    }
    print("PASS: USB, shortcuts, icons, migrations, dashboard slots/rendering, clock options, weather decoding, configuration persistence, icon zoom/backgrounds, idle transitions and mosaic orientation, held shortcuts, pages, macro execution/cancellation, optional captions, automatic application pages, animated idle")
}
