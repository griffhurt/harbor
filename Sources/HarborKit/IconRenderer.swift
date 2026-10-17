import AppKit

/// Draws folder icons (a tinted folder or tile with an SF Symbol) and packages them as .icns.
/// All drawing happens on a 1024×1024 canvas that is scaled to the requested size.
@MainActor
public enum IconRenderer {
    public static func image(for folder: HarborFolder, size: CGFloat) -> NSImage {
        image(symbol: folder.symbol, hex: folder.colorHex, style: folder.style, size: size)
    }

    public static func image(symbol: String, hex: String, style: IconStyle, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(symbol: symbol, hex: hex, style: style, in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        return image
    }

    public static func icnsData(for folder: HarborFolder) -> Data {
        icnsData(symbol: folder.symbol, hex: folder.colorHex, style: folder.style)
    }

    public static func icnsData(symbol: String, hex: String, style: IconStyle) -> Data {
        // (OSType, pixel size) — PNG payloads for every slot macOS looks up.
        let slots: [(String, Int)] = [
            ("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128),
            ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024),
        ]
        var cache: [Int: Data] = [:]
        var body = Data()
        for (type, pixels) in slots {
            let png = cache[pixels] ?? pngData(symbol: symbol, hex: hex, style: style, pixels: pixels)
            cache[pixels] = png
            body.append(contentsOf: Array(type.utf8))
            body.append(bigEndian: UInt32(png.count + 8))
            body.append(png)
        }
        var file = Data("icns".utf8)
        file.append(bigEndian: UInt32(body.count + 8))
        file.append(body)
        return file
    }

    static func pngData(symbol: String, hex: String, style: IconStyle, pixels: Int) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return Data() }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(symbol: symbol, hex: hex, style: style, in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    // MARK: - Drawing

    private static func draw(symbol: String, hex: String, style: IconStyle, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let base = NSColor(hex: hex)
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
        switch style {
        case .folder: drawFolder(symbol: symbol, base: base, ctx: ctx)
        case .tile: drawTile(symbol: symbol, base: base, ctx: ctx)
        }
        ctx.restoreGState()
    }

    private static func drawFolder(symbol: String, base: NSColor, ctx: CGContext) {
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        // Back panel with the tab.
        let back = NSBezierPath(roundedRect: NSRect(x: 96, y: 176, width: 832, height: 600), xRadius: 64, yRadius: 64)
        back.append(NSBezierPath(roundedRect: NSRect(x: 96, y: 690, width: 350, height: 140), xRadius: 56, yRadius: 56))
        base.darker(0.16).setFill()
        back.fill()

        // Front panel.
        let frontRect = NSRect(x: 96, y: 176, width: 832, height: 540)
        let front = NSBezierPath(roundedRect: frontRect, xRadius: 64, yRadius: 64)
        NSGradient(starting: base.lighter(0.28), ending: base)?.draw(in: front, angle: -90)

        // Soft highlight along the top edge of the front panel.
        NSGraphicsContext.saveGraphicsState()
        front.addClip()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let highlight = NSBezierPath(roundedRect: frontRect.insetBy(dx: -4, dy: 4).offsetBy(dx: 0, dy: -6), xRadius: 64, yRadius: 64)
        highlight.lineWidth = 6
        highlight.stroke()
        NSGraphicsContext.restoreGraphicsState()

        ctx.endTransparencyLayer()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // Embossed symbol, like Finder's custom folders.
        drawSymbol(symbol, color: base.darker(0.42).withAlphaComponent(0.8), pointSize: 300,
                   box: NSRect(x: 312, y: 262, width: 400, height: 360))
    }

    private static func drawTile(symbol: String, base: NSColor, ctx: CGContext) {
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        NSGradient(colors: [base.lighter(0.3), base, base.darker(0.12)])?.draw(in: tile, angle: -90)
        ctx.endTransparencyLayer()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        drawSymbol(symbol, color: .white, pointSize: 400, box: NSRect(x: 262, y: 262, width: 500, height: 500))
    }

    private static func drawSymbol(_ name: String, color: NSColor, pointSize: CGFloat, box: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let target = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
