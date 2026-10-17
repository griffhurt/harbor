import AppKit
import SwiftUI
import Testing
@testable import HarborKit

@Suite("Icon rendering") @MainActor
struct IconRenderingTests {
    /// Parses an .icns file into (type, payload) entries, checking the length fields along the way.
    private func entries(of data: Data) throws -> [(type: String, payload: Data)] {
        func uint32(at offset: Int) -> Int {
            data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "icns")
        #expect(uint32(at: 4) == data.count)

        var result: [(String, Data)] = []
        var offset = 8
        while offset < data.count {
            let type = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let length = uint32(at: offset + 4)
            try #require(length > 8 && offset + length <= data.count)
            result.append((type, data[offset + 8..<offset + length]))
            offset += length
        }
        return result
    }

    @Test("Writes a well-formed .icns", arguments: IconStyle.allCases)
    func icnsStructure(style: IconStyle) throws {
        let data = IconRenderer.icnsData(symbol: "hammer.fill", hex: "3A9BF5", style: style)
        let parsed = try entries(of: data)

        #expect(Set(parsed.map(\.type)) == ["icp4", "icp5", "ic11", "ic12", "ic07", "ic13", "ic08", "ic14", "ic09", "ic10"])
        for entry in parsed {
            let image = try #require(NSBitmapImageRep(data: entry.payload), "\(entry.type) is not a PNG")
            #expect(image.pixelsWide == image.pixelsHigh)
        }
        let largest = try #require(parsed.first { $0.type == "ic10" })
        #expect(NSBitmapImageRep(data: largest.payload)?.pixelsWide == 1024)
    }

    @Test func macOSReadsTheIcon() throws {
        let image = try #require(NSImage(data: IconRenderer.icnsData(symbol: "star.fill", hex: "46C15A", style: .folder)))
        #expect(image.representations.count >= 5)
    }

    @Test func iconIsTintedWithTheFolderColor() throws {
        let png = IconRenderer.pngData(symbol: "star.fill", hex: "EE5A50", style: .tile, pixels: 64)
        let rep = try #require(NSBitmapImageRep(data: png))
        // Just inside the tile's top-left edge, away from the symbol.
        let color = try #require(rep.colorAt(x: 14, y: 22)?.usingColorSpace(.sRGB))
        #expect(color.redComponent > color.greenComponent + 0.2)
        #expect(color.redComponent > color.blueComponent + 0.2)
        // The corner outside the tile stays transparent.
        #expect(rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1 < 0.05)
    }
}

@Suite("Callout shape")
struct CalloutShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 300, height: 200)

    @Test func bottomArrowPointsDownAtTheOffset() {
        let shape = CalloutShape(edge: .bottom, offset: 120, arrowLength: 11)
        let path = shape.path(in: rect)
        #expect(path.boundingRect.maxY > rect.maxY - 2)
        #expect(path.contains(CGPoint(x: 120, y: rect.maxY - 3)))
        #expect(!path.contains(CGPoint(x: 200, y: rect.maxY - 3)))
    }

    @Test func arrowStaysClearOfTheCorners() {
        let shape = CalloutShape(edge: .bottom, offset: 0, arrowLength: 11)
        let path = shape.path(in: rect)
        // Clamped away from the rounded corner instead of hanging off the edge.
        #expect(!path.contains(CGPoint(x: 2, y: rect.maxY - 3)))
        #expect(path.boundingRect.minX >= rect.minX)
    }

    @Test("Side arrows point outward", arguments: [ArrowEdge.left, .right])
    func sideArrows(edge: ArrowEdge) {
        let path = CalloutShape(edge: edge, offset: 100, arrowLength: 11).path(in: rect)
        let tipX = edge == .left ? rect.minX + 3 : rect.maxX - 3
        #expect(path.contains(CGPoint(x: tipX, y: 100)))
        #expect(!path.contains(CGPoint(x: tipX, y: 40)))
    }
}
