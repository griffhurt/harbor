import AppKit
import SwiftUI

extension NSColor {
    public convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt32(cleaned, radix: 16) ?? 0x3A9BF5
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    public var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "3A9BF5" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    func lighter(_ amount: CGFloat) -> NSColor { blended(withFraction: amount, of: .white) ?? self }
    func darker(_ amount: CGFloat) -> NSColor { blended(withFraction: amount, of: .black) ?? self }
}

extension Color {
    public init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
