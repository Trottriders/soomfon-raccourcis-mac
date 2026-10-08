import AppKit

struct DeckColor: Codable, Equatable {
    var red: Double = 0
    var green: Double = 0
    var blue: Double = 0
    var isValid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: 1) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    init(red: Double = 0, green: Double = 0, blue: Double = 0) {
        self.red = red; self.green = green; self.blue = blue
    }
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        red = rgb.redComponent; green = rgb.greenComponent; blue = rgb.blueComponent
    }
}

struct IconAppearance: Codable, Equatable {
    var scale: Double = 1
    // The source PNG retains alpha; the JPEG transport requires a matte.
    var transparent = true
    var color = DeckColor(red: 0.065, green: 0.09, blue: 0.12)
    var background: CGColor { transparent ? DeckColor().cgColor : color.cgColor }
    var isValid: Bool { scale.isFinite && (0.25...2).contains(scale) && color.isValid }
}

enum ScreensaverKind: String, Codable, CaseIterable, Identifiable {
    case largeClock, repeatedClock, wallpaper, matrix
    var id: String { rawValue }
    var title: String {
        switch self {
        case .largeClock: return "Heure, un chiffre par touche"
        case .repeatedClock: return "Horloge sur chaque touche"
        case .wallpaper: return "Image sur les 15 touches"
        case .matrix: return "Matrix — pluie de caractères"
        }
    }
}

enum ScreensaverAnimation: String, Codable, CaseIterable, Identifiable {
    case none, pacman, matrix
    var id: String { rawValue }
    var title: String { switch self { case .none: return "Aucune"; case .pacman: return "Pac-Man"; case .matrix: return "Matrix" } }
}

struct ScreensaverConfiguration: Codable, Equatable {
    var enabled = true
    var delay = 60
    var wakeOnMouseMovement: Bool? = nil
    var wakesOnMouseMovement: Bool { wakeOnMouseMovement ?? true }
    var kind: ScreensaverKind = .largeClock
    var showDate = true
    var showSeconds: Bool? = true
    var pacmanEnabled: Bool? = nil
    var clockDuration: Int? = nil
    var pacmanDuration: Int? = nil
    var showApplicationTitles: Bool? = nil
    var animation: ScreensaverAnimation? = nil
    var matrixClockEnabled: Bool? = nil
    var showsMatrixClock: Bool { matrixClockEnabled ?? true }
    var matrixSpeed: Double? = nil
    var animationFPS: Int? = nil
    var effectiveMatrixSpeed: Double { matrixSpeed ?? 1 }
    var effectiveAnimationFPS: Int { animationFPS ?? 8 }
    var effectiveAnimation: ScreensaverAnimation { animation ?? ((pacmanEnabled ?? false) ? .pacman : .none) }
    var usesAnimation: Bool { kind != .matrix && effectiveAnimation != .none }
    var usesPacman: Bool { usesAnimation && effectiveAnimation == .pacman }
    var effectiveClockDuration: Int { clockDuration ?? 30 }
    var effectivePacmanDuration: Int { pacmanDuration ?? 30 }
    func animationTime(elapsed: Double) -> Double? {
        guard usesAnimation, elapsed.isFinite, elapsed >= 0 else { return nil }
        let cycle = Double(effectiveClockDuration + effectivePacmanDuration)
        let position = elapsed.truncatingRemainder(dividingBy: cycle)
        return position >= Double(effectiveClockDuration) ? position - Double(effectiveClockDuration) : nil
    }
    func pacmanTime(elapsed: Double) -> Double? {
        usesPacman ? animationTime(elapsed: elapsed) : nil
    }
    var showsSeconds: Bool { kind == .largeClock && (showSeconds ?? true) }
    func imageTick(at date: Date, elapsed: Double = 0) -> Int {
        if kind == .matrix || animationTime(elapsed: elapsed) != nil { return Int(date.timeIntervalSince1970 * Double(effectiveAnimationFPS)) * 2 + 1 }
        return Int(date.timeIntervalSince1970 / (showsSeconds ? 1 : 60))
    }
    var wallpaperPNG: Data? = nil
    var isValid: Bool {
        effectiveMatrixSpeed.isFinite && (0.25...3).contains(effectiveMatrixSpeed) && [4,8,12].contains(effectiveAnimationFPS)
        && (15...3600).contains(delay) && (5...300).contains(effectiveClockDuration) && (5...300).contains(effectivePacmanDuration) && (wallpaperPNG.map {
            $0.count <= 512_000 && Array($0.prefix(8)) == [137,80,78,71,13,10,26,10] && IconImage.decode($0) != nil
        } ?? true)
    }
}

struct IdleState {
    var lastInteraction: Date
    var active = false
    mutating func tick(now: Date, settings: ScreensaverConfiguration) -> Bool {
        let before = active
        if !settings.enabled { active = false }
        else if now.timeIntervalSince(lastInteraction) >= Double(settings.delay) { active = true }
        return before != active
    }
    // Consume the first press when waking, then allow subsequent shortcuts.
    mutating func press(now: Date) -> Bool {
        let wasActive = active
        active = false; lastInteraction = now
        return wasActive
    }
    mutating func mouseMoved(now: Date, settings: ScreensaverConfiguration) -> Bool {
        guard settings.wakesOnMouseMovement else { return false }
        return press(now: now)
    }
}

enum ScreensaverImage {
    static let width = 475, height = 285
    static func canvas(settings: ScreensaverConfiguration, date: Date, clock: DashboardConfiguration, elapsed: Double = 0, apps: [ScreensaverAppIcon] = []) -> CGImage? {
        if settings.kind == .matrix { return MatrixScreensaver.canvas(time: elapsed, date: date, showClock: settings.showsMatrixClock, speed: settings.effectiveMatrixSpeed) }
        if let animationTime = settings.animationTime(elapsed: elapsed) {
            if settings.effectiveAnimation == .matrix { return MatrixScreensaver.canvas(time: animationTime, date: date, showClock: settings.showsMatrixClock, speed: settings.effectiveMatrixSpeed) }
            return PacmanScreensaver.canvas(time: animationTime, duration: settings.effectivePacmanDuration,
                                            showTitles: settings.showApplicationTitles ?? false, apps: apps)
        }
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(DeckColor().cgColor); cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let data = settings.wallpaperPNG, let image = IconImage.decode(data) {
            let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
            let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
            cg.interpolationQuality = .high
            cg.draw(image, in: CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h))
            if settings.kind != .wallpaper {
                cg.setFillColor(CGColor(gray: 0, alpha: 0.6)); cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        var clockSettings = clock; clockSettings.clockSeconds = false; clockSettings.clockDate = settings.showDate
        let strings = DashboardImage.clockStrings(date, settings: clockSettings)
        func text(_ value: String, rect: CGRect, size: CGFloat, color: NSColor = .white) {
            let p = NSMutableParagraphStyle(); p.alignment = .center
            (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor: color, .paragraphStyle: p])
        }
        switch settings.kind {
        case .largeClock:
            let digits = clockCharacters(date)
            for (column, digit) in digits.enumerated() {
                let x = CGFloat(column * 95)
                text(digit, rect: CGRect(x: x + 2, y: 97, width: 91, height: 91), size: digit == ":" ? 66 : 76)
            }
            if settings.showsSeconds {
                for (offset, digit) in secondsCharacters(date).enumerated() {
                    // Physical buttons 14 and 15: bottom row, rightmost two.
                    text(digit, rect: CGRect(x: (offset + 3) * 95 + 2, y: 2, width: 91, height: 91), size: 76)
                }
            }
            if settings.showDate {
                text(strings.1, rect: CGRect(x: 192, y: 36, width: 91, height: 22), size: 12)
            }
        case .repeatedClock:
            for index in 0..<15 {
                let x = CGFloat(index % 5 * 95), y = CGFloat((2 - index / 5) * 95)
                text(strings.0, rect: CGRect(x: x + 2, y: y + 36, width: 91, height: 30), size: clock.clock24Hour ? 25 : 16)
                if settings.showDate { text(strings.1, rect: CGRect(x: x + 2, y: y + 17, width: 91, height: 17), size: 9) }
            }
        case .wallpaper, .matrix: break
        }
        return cg.makeImage()
    }
    static func clockCharacters(_ date: Date, timeZone: TimeZone = .current) -> [String] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_FR"); formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date).map { String($0) }
    }
    static func secondsCharacters(_ date: Date, timeZone: TimeZone = .current) -> [String] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_FR"); formatter.timeZone = timeZone
        formatter.dateFormat = "ss"
        return formatter.string(from: date).map { String($0) }
    }
    static func cropRect(index: Int) -> CGRect {
        CGRect(x: index % 5 * 95, y: index / 5 * 95, width: 95, height: 95)
    }
    static func tiles(settings: ScreensaverConfiguration, date: Date, clock: DashboardConfiguration, rotation: Int, elapsed: Double = 0, apps: [ScreensaverAppIcon] = []) -> [Data]? {
        guard let image = canvas(settings: settings, date: date, clock: clock, elapsed: elapsed, apps: apps) else { return nil }
        var tiles: [Data] = []
        for index in 0..<15 {
            guard let crop = image.cropping(to: cropRect(index: index)),
                  let cg = CGContext(data: nil, width: 95, height: 95, bitsPerComponent: 8, bytesPerRow: 380,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            cg.translateBy(x: 47.5, y: 47.5); cg.rotate(by: CGFloat(rotation) * .pi / 180); cg.translateBy(x: -47.5, y: -47.5)
            cg.draw(crop, in: CGRect(x: 0, y: 0, width: 95, height: 95))
            guard let output = cg.makeImage(), let jpeg = IconImage.encode(output, type: "public.jpeg") else { return nil }
            tiles.append(jpeg)
        }
        return tiles
    }
}
