import AppKit

struct ScreensaverAppIcon {
    var name: String
    var icon: NSImage?
}

enum PacmanScreensaver {
    // Follow the three physical rows, reversing direction on the middle row.
    static let route = [0,1,2,3,4,9,8,7,6,5,10,11,12,13,14]
    static func center(_ index: Int) -> CGPoint {
        CGPoint(x: index % 5 * 95 + 47, y: (2 - index / 5) * 95 + 47)
    }
    static func progress(time: Double, duration: Int) -> Double {
        min(14.999, max(0, time / Double(max(1, duration)) * 15))
    }
    static func remainingApplications(time: Double, duration: Int) -> [Int] {
        let eaten = Int(progress(time: time, duration: duration))
        return Array(route.dropFirst(eaten + 1))
    }
    static func canvas(time: Double, duration: Int, showTitles: Bool, apps: [ScreensaverAppIcon]) -> CGImage? {
        guard let cg = CGContext(data: nil, width: 475, height: 285, bitsPerComponent: 8, bytesPerRow: 475 * 4,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(CGColor(gray: 0, alpha: 1)); cg.fill(CGRect(x: 0, y: 0, width: 475, height: 285))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        cg.setStrokeColor(CGColor(red: 0.05, green: 0.18, blue: 0.8, alpha: 1)); cg.setLineWidth(2)
        for index in 0..<15 {
            let point = center(index)
            cg.addPath(CGPath(roundedRect: CGRect(x: point.x - 39, y: point.y - 39, width: 78, height: 78), cornerWidth: 12, cornerHeight: 12, transform: nil)); cg.strokePath()
        }
        for index in remainingApplications(time: time, duration: duration) {
            let point = center(index)
            let app = apps.isEmpty ? ScreensaverAppIcon(name: "Application", icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)) : apps[index % apps.count]
            app.icon?.draw(in: CGRect(x: point.x - 22, y: point.y - (showTitles ? 15 : 22), width: 44, height: 44), from: .zero, operation: .sourceOver, fraction: 1)
            if showTitles {
                let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
                (app.name as NSString).draw(in: CGRect(x: point.x - 36, y: point.y - 32, width: 72, height: 13),
                                           withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: p])
            }
        }
        let position = progress(time: time, duration: duration), step = min(14, Int(position))
        let start = center(route[step]), end = center(route[min(14, step + 1)])
        let fraction = position - Double(step)
        let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        let direction = step == 14 ? 0 : atan2(end.y - start.y, end.x - start.x)
        let mouth: CGFloat = Int(time * 2) % 2 == 0 ? .pi / 5 : .pi / 20
        cg.setFillColor(CGColor(red: 1, green: 0.87, blue: 0.05, alpha: 1))
        cg.move(to: point)
        cg.addArc(center: point, radius: 27, startAngle: direction + mouth, endAngle: direction + 2 * .pi - mouth, clockwise: false)
        cg.closePath(); cg.fillPath()
        let eye = CGPoint(x: point.x + cos(direction) * 4 - sin(direction) * 12,
                          y: point.y + sin(direction) * 4 + cos(direction) * 12)
        cg.setFillColor(CGColor(gray: 0, alpha: 1)); cg.fillEllipse(in: CGRect(x: eye.x - 3, y: eye.y - 3, width: 6, height: 6))
        return cg.makeImage()
    }
}
