import AppKit

enum MatrixScreensaver {
    private static let glyphs = Array("アイウエオカキクケコサシスセソタチツテトナニヌネノ012345789<>:+*")
    struct ClockFragment {
        let image: CGImage
        let rect: CGRect
        let gridX: Int
        let gridY: Int
    }
    private struct ClockGlyph {
        let image: CGImage
        let fragments: [ClockFragment]
    }
    struct FragmentMotion {
        let offset: CGPoint
        let opacity: Double
        let codeOpacity: Double
        let moving: Bool
    }
    // Cache the glyph masks and their nonempty pieces once, not on each USB frame.
    private static let clockGlyphs: [String: ClockGlyph] = {
        var result: [String: ClockGlyph] = [:]
        for character in Array("0123456789:").map({ String($0) }) {
            guard let context = CGContext(data: nil, width: 95, height: 95, bitsPerComponent: 8, bytesPerRow: 380,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (character as NSString).draw(in: CGRect(x: 2, y: 2, width: 91, height: 91), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: character == ":" ? 66 : 76, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.65, green: 1, blue: 0.73, alpha: 1),
                .paragraphStyle: paragraph
            ])
            NSGraphicsContext.restoreGraphicsState()
            guard let image = context.makeImage(), let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { continue }
            var fragments: [ClockFragment] = []
            for y in stride(from: 0, to: 95, by: 7) {
                for x in stride(from: 0, to: 95, by: 6) {
                    let width = min(6, 95 - x), height = min(7, 95 - y)
                    let hasInk = (y..<(y + height)).contains { row in
                        (x..<(x + width)).contains { col in pixels[row * 380 + col * 4 + 3] > 12 }
                    }
                    guard hasInk, let piece = image.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else { continue }
                    fragments.append(ClockFragment(image: piece, rect: CGRect(x: x, y: 95 - y - height, width: width, height: height), gridX: x / 6, gridY: y / 7))
                }
            }
            result[character] = ClockGlyph(image: image, fragments: fragments)
        }
        return result
    }()

    static func clockFragments(character: String) -> [ClockFragment] { clockGlyphs[character]?.fragments ?? [] }

    static func fragmentMotion(time: Double, column: Int, gridX: Int, gridY: Int, speed: Double = 1) -> FragmentMotion {
        let hidden = FragmentMotion(offset: .zero, opacity: 0, codeOpacity: 0, moving: false)
        guard time.isFinite, time >= 0, (0..<5).contains(column), (0..<16).contains(gridX), (0..<14).contains(gridY),
              speed.isFinite, (0.25...3).contains(speed) else { return hidden }
        let phase = time.truncatingRemainder(dividingBy: 20)
        let seed = (column * 97 + gridX * 31 + gridY * 17) % 101
        let jitter = Double(seed) / 100
        let arrival = 4 + Double(column) * 0.6 + Double(gridY) / 14 * 0.4 + jitter * 0.38
        guard phase >= arrival else { return hidden }
        let departure = 13 + Double(column) * 0.5 + Double(gridY) / 14 * 0.6 + jitter * 0.4
        if phase >= departure {
            let age = phase - departure
            guard age < 1.65 else { return hidden }
            let fallSpeed = min(1.75, max(0.65, sqrt(speed)))
            let distance = (Double(70 + seed % 45) * age + 130 * age * age) * fallSpeed
            let drift = Double(seed % 7 - 3) * age * 1.5
            return FragmentMotion(offset: CGPoint(x: drift, y: -distance), opacity: min(1, max(0, (1.65 - age) / 0.55)),
                                  codeOpacity: min(0.8, age / 1.2), moving: true)
        }
        let progress = min(1, (phase - arrival) / 0.65)
        let offset = pow(1 - progress, 2) * Double(155 + seed % 65)
        return FragmentMotion(offset: CGPoint(x: 0, y: offset), opacity: 1,
                              codeOpacity: max(0, 1 - progress * 1.5), moving: progress < 1)
    }

    // Deterministic streams keep previews and device frames identical, without storing animation state.
    static func clockOpacity(time: Double, column: Int) -> Double {
        guard time.isFinite, time >= 0, (0..<5).contains(column) else { return 0 }
        let phase = time.truncatingRemainder(dividingBy: 20)
        let appear = min(1, max(0, phase - 4 - Double(column) * 0.6))
        let disappear = min(1, max(0, (phase - 13 - Double(column) * 0.5) / 1.2))
        return appear * (1 - disappear)
    }
    static func canvas(time: Double, date: Date = Date(), showClock: Bool = false, speed: Double = 1) -> CGImage? {
        guard time.isFinite, speed.isFinite, (0.25...3).contains(speed), let cg = CGContext(data: nil, width: 475, height: 285, bitsPerComponent: 8,
            bytesPerRow: 1900, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(CGColor(gray: 0, alpha: 1)); cg.fill(CGRect(x: 0, y: 0, width: 475, height: 285))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let rainTime = max(0, time) * speed
        for column in 0..<38 {
            let seed = (column * 137 + 29) % 997
            let speed = Double(22 + seed % 49)
            let length = 9 + seed % 15
            let head = (rainTime * speed + Double(seed)).truncatingRemainder(dividingBy: 560)
            for trail in 0..<length {
                let top = head - Double(trail * 13)
                guard top >= -13 && top <= 298 else { continue }
                let brightness = pow(1 - Double(trail) / Double(length), 1.7)
                let symbol = glyphs[(seed + trail * 31 + Int(rainTime * 3)) % glyphs.count]
                let color = trail == 0 ? NSColor(srgbRed: 0.72, green: 1, blue: 0.82, alpha: 1)
                    : NSColor(srgbRed: 0.015, green: 0.12 + 0.85 * brightness, blue: 0.06 + 0.14 * brightness, alpha: 1)
                cg.saveGState()
                if trail < 3 { cg.setShadow(offset: .zero, blur: trail == 0 ? 5 : 3, color: NSColor.green.withAlphaComponent(CGFloat(brightness * 0.6)).cgColor) }
                (String(symbol) as NSString).draw(at: CGPoint(x: Double(column * 13 - 4), y: 272 - top),
                    withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: color])
                cg.restoreGState()
            }
        }
        if showClock {
            for (column, character) in ScreensaverImage.clockCharacters(date).enumerated() {
                let opacity = clockOpacity(time: time, column: column)
                guard let glyph = clockGlyphs[character] else { continue }
                cg.saveGState()
                cg.setFillColor(CGColor(gray: 0, alpha: opacity * 0.72))
                cg.fill(CGRect(x: column * 95, y: 95, width: 95, height: 95))
                let phase = time.truncatingRemainder(dividingBy: 20)
                if phase >= 6 + Double(column) * 0.6 && phase < 13 + Double(column) * 0.5 {
                    cg.setShadow(offset: .zero, blur: 6, color: NSColor.green.withAlphaComponent(0.65).cgColor)
                    cg.draw(glyph.image, in: CGRect(x: column * 95, y: 95, width: 95, height: 95))
                } else {
                    for fragment in glyph.fragments {
                        let motion = fragmentMotion(time: time, column: column, gridX: fragment.gridX, gridY: fragment.gridY, speed: speed)
                        guard motion.opacity > 0 else { continue }
                        let rect = fragment.rect.offsetBy(dx: CGFloat(column * 95) + motion.offset.x, dy: 95 + motion.offset.y)
                        guard rect.maxY >= -12, rect.minY <= 300 else { continue }
                        cg.saveGState()
                        cg.setAlpha(CGFloat(motion.opacity))
                        if motion.moving {
                            cg.setFillColor(NSColor.green.withAlphaComponent(0.15).cgColor)
                            cg.fill(CGRect(x: rect.midX - 1, y: rect.maxY, width: 2, height: 9 + motion.codeOpacity * 10))
                        }
                        if motion.codeOpacity > 0 {
                            let symbol = glyphs[(fragment.gridX * 7 + fragment.gridY * 19 + column * 11 + Int(rainTime * 4)) % glyphs.count]
                            (String(symbol) as NSString).draw(at: CGPoint(x: rect.minX, y: rect.minY), withAttributes: [
                                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                                .foregroundColor: NSColor(srgbRed: 0.72, green: 1, blue: 0.82, alpha: motion.codeOpacity)
                            ])
                        }
                        cg.setShadow(offset: .zero, blur: motion.moving ? 3 : 2, color: NSColor.green.withAlphaComponent(0.55).cgColor)
                        cg.setAlpha(CGFloat(motion.opacity * (1 - motion.codeOpacity * 0.7)))
                        cg.draw(fragment.image, in: rect)
                        cg.restoreGState()
                    }
                }
                cg.restoreGState()
            }
        }
        return cg.makeImage()
    }
}
