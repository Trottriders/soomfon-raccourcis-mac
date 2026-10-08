import AppKit

enum DashboardKind: String, Codable, CaseIterable, Identifiable {
    case clock, activeApp, weather, image, empty
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clock: return "Heure"
        case .activeApp: return "Application active"
        case .weather: return "Météo"
        case .image: return "Image personnelle"
        case .empty: return "Vide"
        }
    }
}

struct DashboardSlot: Codable, Equatable {
    var kind: DashboardKind
    var title: String? = nil
    var showTitle: Bool? = nil
    var iconPNG: Data? = nil
    var appearance: IconAppearance? = nil
    var effectiveAppearance: IconAppearance { appearance ?? IconAppearance() }
    var showsTitle: Bool { showTitle ?? [.activeApp, .weather].contains(kind) }
    func caption(fallback: String) -> String? {
        guard showsTitle else { return nil }
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }
    var isValid: Bool {
        guard effectiveAppearance.isValid, (title?.count ?? 0) <= 80 else { return false }
        guard let iconPNG else { return true }
        return iconPNG.count <= 512_000 && Array(iconPNG.prefix(8)) == [137,80,78,71,13,10,26,10]
            && IconImage.decode(iconPNG) != nil
    }
}

struct WeatherLocation: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let country: String?
    var label: String { [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
    var isValid: Bool {
        !name.isEmpty && name.count <= 200 && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct DashboardConfiguration: Codable, Equatable {
    var slots = [DashboardSlot(kind: .clock), DashboardSlot(kind: .activeApp), DashboardSlot(kind: .weather)]
    var clockSeconds = false
    var clock24Hour = true
    var clockDate = true
    var weatherFahrenheit = false
    var location: WeatherLocation? = nil
    var isValid: Bool { slots.count == 3 && slots.allSatisfy(\.isValid) && (location?.isValid ?? true) }
}

struct WeatherReading: Equatable {
    let celsius: Double
    let code: Int
    let isDay: Bool
    let observedAt: Date
    let fetchedAt: Date
    func temperature(fahrenheit: Bool) -> String {
        String(format: "%.0f°", fahrenheit ? celsius * 9 / 5 + 32 : celsius)
    }
    var condition: String {
        switch code {
        case 0: return "Clair"
        case 1,2: return "Éclaircies"
        case 3: return "Nuageux"
        case 45,48: return "Brouillard"
        case 51...57: return "Bruine"
        case 61...67,80...82: return "Pluie"
        case 71...77,85,86: return "Neige"
        case 95...99: return "Orage"
        default: return "Météo"
        }
    }
    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.fill"
        case 1,2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45,48: return "cloud.fog.fill"
        case 51...57,61...67,80...82: return "cloud.rain.fill"
        case 71...77,85,86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 30 * 60 }
}

enum WeatherService {
    struct PlacesReply: Decodable { let results: [WeatherLocation]? }
    struct CurrentReply: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
            let time: Double
        }
        let current: Current
    }
    static func searchURL(city: String) -> URL {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "5"), URLQueryItem(name: "language", value: "fr"), URLQueryItem(name: "format", value: "json")]
        return components.url!
    }
    static func forecastURL(location: WeatherLocation) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [URLQueryItem(name: "latitude", value: String(location.latitude)), URLQueryItem(name: "longitude", value: String(location.longitude)), URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"), URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT"), URLQueryItem(name: "forecast_days", value: "1")]
        return components.url!
    }
    static func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), data.count < 2_000_000 else {
            throw NSError(domain: "Weather", code: 1, userInfo: [NSLocalizedDescriptionKey: "Le service météo est momentanément indisponible."])
        }
        return data
    }
    static func search(city: String) async throws -> [WeatherLocation] {
        let data = try await request(searchURL(city: city))
        return try JSONDecoder().decode(PlacesReply.self, from: data).results?.filter(\.isValid) ?? []
    }
    static func decode(_ data: Data, now: Date = Date()) throws -> WeatherReading {
        let c = try JSONDecoder().decode(CurrentReply.self, from: data).current
        guard c.temperature_2m.isFinite, (-100...70).contains(c.temperature_2m), (0...1).contains(c.is_day), c.time.isFinite else {
            throw NSError(domain: "Weather", code: 2, userInfo: [NSLocalizedDescriptionKey: "Les données météo sont illisibles."])
        }
        return WeatherReading(celsius: c.temperature_2m, code: c.weather_code, isDay: c.is_day == 1, observedAt: Date(timeIntervalSince1970: c.time), fetchedAt: now)
    }
    static func current(location: WeatherLocation) async throws -> WeatherReading {
        try decode(await request(forecastURL(location: location)))
    }
}

enum DashboardImage {
    static func clockStrings(_ date: Date, settings: DashboardConfiguration, timeZone: TimeZone = .current) -> (String, String) {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_FR"); formatter.timeZone = timeZone
        formatter.dateFormat = settings.clock24Hour ? (settings.clockSeconds ? "HH:mm:ss" : "HH:mm") : (settings.clockSeconds ? "h:mm:ss a" : "h:mm a")
        let time = formatter.string(from: date)
        formatter.dateFormat = "EEE d MMM"
        return (time, settings.clockDate ? formatter.string(from: date) : "")
    }

    static func jpeg(slot: DashboardSlot, settings: DashboardConfiguration, date: Date, appName: String, appIcon: NSImage?, weather: WeatherReading?, weatherMessage: String, rotation: Int) -> Data? {
        let size = 82
        guard let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(slot.effectiveAppearance.background); cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform(); transform.translateX(by: 41, yBy: 41)
        transform.rotate(byDegrees: CGFloat(rotation)); transform.translateX(by: -41, yBy: -41); transform.concat()
        func text(_ string: String, y: CGFloat, height: CGFloat, font: CGFloat, color: NSColor = .white) {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            (string as NSString).draw(in: NSRect(x: 2, y: y, width: 78, height: height), withAttributes: [.font: NSFont.systemFont(ofSize: font, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph])
        }
        func image(_ icon: NSImage?, rect: NSRect) { icon?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1) }
        switch slot.kind {
        case .clock:
            let strings = clockStrings(date, settings: settings)
            text(strings.0, y: slot.showsTitle ? 39 : 29, height: 29, font: settings.clockSeconds || !settings.clock24Hour ? 16 : 23,
                 color: NSColor(calibratedRed: 0.39, green: 0.88, blue: 0.74, alpha: 1))
            text(strings.1, y: slot.showsTitle ? 24 : 12, height: 14, font: 9)
            if let caption = slot.caption(fallback: "Heure") { text(caption, y: 5, height: 14, font: 9) }
        case .activeApp:
            let side = 50 * slot.effectiveAppearance.scale
            cg.saveGState(); cg.clip(to: CGRect(x: 0, y: slot.showsTitle ? 23 : 0, width: 82, height: slot.showsTitle ? 59 : 82))
            image(appIcon, rect: NSRect(x: (82 - side) / 2, y: (slot.showsTitle ? 49 : 41) - side / 2, width: side, height: side))
            cg.restoreGState()
            if let caption = slot.caption(fallback: appName) { text(caption, y: 7, height: 14, font: 9) }
        case .weather:
            if let weather {
                let palette = NSImage.SymbolConfiguration.preferringMulticolor()
                let symbol = NSImage(systemSymbolName: weather.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 23, weight: .medium).applying(palette))
                image(symbol, rect: NSRect(x: 24, y: 47, width: 34, height: 28))
                text(weather.temperature(fahrenheit: settings.weatherFahrenheit), y: 15, height: 35, font: 31)
                if let caption = slot.caption(fallback: weather.isStale ? "Anciennes données" : (settings.location?.name ?? weather.condition)) {
                    text(caption, y: 3, height: 12, font: 8)
                }
            } else {
                let placeholder = NSImage(systemSymbolName: "cloud", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [.systemGray]))
                image(placeholder, rect: NSRect(x: 25, y: 38, width: 32, height: 24))
                text(settings.location == nil ? "Choisir une ville" : (weatherMessage.hasPrefix("Actualisation") ? "Chargement…" : "Indisponible"), y: 13, height: 15, font: 9)
            }
        case .image:
            if let data = slot.iconPNG, let icon = IconImage.decode(data) {
                let area = CGRect(x: 0, y: slot.showsTitle ? 23 : 0, width: 82, height: slot.showsTitle ? 59 : 82)
                let scale = min(area.width / CGFloat(icon.width), area.height / CGFloat(icon.height)) * slot.effectiveAppearance.scale
                let w = CGFloat(icon.width) * scale, h = CGFloat(icon.height) * scale
                cg.saveGState(); cg.clip(to: area)
                cg.interpolationQuality = .high
                cg.draw(icon, in: CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h))
                cg.restoreGState()
            }
            if let caption = slot.caption(fallback: "Image") { text(caption, y: 5, height: 14, font: 9) }
        case .empty:
            if let caption = slot.caption(fallback: "Vide") { text(caption, y: 5, height: 14, font: 9) }
        }
        guard let output = cg.makeImage() else { return nil }
        return IconImage.encode(output, type: "public.jpeg")
    }
}
