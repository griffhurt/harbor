import AppKit
import Testing
@testable import HarborKit

@Suite("HarborFolder")
struct HarborFolderTests {
    private let calculator = AppRef(bundleID: "com.apple.calculator", path: "/System/Applications/Calculator.app", name: "Calculator")
    private let notes = AppRef(bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app", name: "Notes")

    @Test("Blank names display as Untitled", arguments: ["", "   ", "\n\t"])
    func blankDisplayName(name: String) {
        #expect(HarborFolder(name: name).displayName == "Untitled")
    }

    @Test func displayNameIsTrimmed() {
        #expect(HarborFolder(name: "  Dev Tools \n").displayName == "Dev Tools")
    }

    @Test func addSkipsDuplicates() {
        var folder = HarborFolder(name: "Utilities", apps: [calculator])
        let added = folder.add([calculator, notes, notes])
        #expect(added == 1)
        #expect(folder.apps.map(\.id) == [calculator.id, notes.id])
    }

    @Test func appearanceKeyTracksTheDockIcon() {
        let base = HarborFolder(name: "Work")
        var reordered = base
        reordered.apps = [calculator]
        #expect(reordered.appearanceKey == base.appearanceKey, "Apps don't affect the Dock icon")

        for change: (inout HarborFolder) -> Void in [
            { $0.name = "Play" },
            { $0.colorHex = "EE5A50" },
            { $0.symbol = "star.fill" },
            { $0.style = .tile },
        ] {
            var changed = base
            change(&changed)
            #expect(changed.appearanceKey != base.appearanceKey)
        }
    }

    @Test func codableRoundTrip() throws {
        let folder = HarborFolder(name: "Media", colorHex: "EC5C93", symbol: "music.note", style: .tile, apps: [calculator, notes])
        let decoded = try JSONDecoder().decode(HarborFolder.self, from: JSONEncoder().encode(folder))
        #expect(decoded == folder)
    }
}

@Suite("AppRef")
struct AppRefTests {
    @Test func identifiesByBundleIDThenPath() {
        #expect(AppRef(bundleID: "com.example.app", path: "/Applications/Example.app", name: "Example").id == "com.example.app")
        #expect(AppRef(bundleID: nil, path: "/Applications/Example.app", name: "Example").id == "/Applications/Example.app")
    }

    @Test func rejectsNonApplications() {
        #expect(AppRef(url: URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")) == nil)
    }

    @Test func readsInstalledApplication() throws {
        let ref = try #require(AppRef(url: URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        #expect(ref.bundleID == "com.apple.calculator")
        #expect(ref.name == "Calculator")
    }

    @Test @MainActor func resolvesMovedAppsByBundleID() {
        let moved = AppRef(bundleID: "com.apple.calculator", path: "/nonexistent/Calculator.app", name: "Calculator")
        #expect(moved.resolvedURL?.lastPathComponent == "Calculator.app")
    }
}

@Suite("Palette and symbols")
struct PaletteTests {
    @Test("Hex round-trips through NSColor", arguments: FolderPalette.presets.map(\.hex))
    func hexRoundTrip(hex: String) {
        #expect(NSColor(hex: hex).hexString == hex)
    }

    @Test func hexAcceptsLeadingHashAndLowercase() {
        #expect(NSColor(hex: "#ee5a50").hexString == "EE5A50")
    }

    @Test func presetsAreUnique() {
        #expect(Set(FolderPalette.presets.map(\.hex)).count == FolderPalette.presets.count)
    }

    @Test @MainActor func defaultSymbolIsAvailable() {
        #expect(SymbolCatalog.available.contains(HarborFolder(name: "x").symbol))
        #expect(SymbolCatalog.available.count > 50)
    }
}

@Suite("Settings and styles")
struct SettingsTests {
    @Test("Missing or unknown values fall back to defaults", arguments: ["{}", #"{"popoverStyle":"spiral"}"#])
    func lenientDecoding(json: String) throws {
        let settings = try JSONDecoder().decode(HarborSettings.self, from: Data(json.utf8))
        #expect(settings.popoverStyle == .grid)
    }

    @Test func styleRoundTrip() throws {
        for style in PopoverStyle.allCases {
            let data = try JSONEncoder().encode(HarborSettings(popoverStyle: style))
            #expect(try JSONDecoder().decode(HarborSettings.self, from: data).popoverStyle == style)
        }
    }

    @Test func fanRisesAndBendsRight() {
        let points = (0..<FanLayout.maxItems).map(FanLayout.offset(at:))
        #expect(points[0] == .zero, "The first app sits directly above the tile")
        for (lower, upper) in zip(points, points.dropFirst()) {
            #expect(upper.y - lower.y == FanLayout.rowHeight)
            #expect(upper.x >= lower.x)
        }
        // Gentle: the top of a full fan drifts less than one icon width.
        #expect(points.last!.x < FanLayout.iconSize)
    }
}
