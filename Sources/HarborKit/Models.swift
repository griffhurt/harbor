import AppKit

/// A reference to an installed application inside a folder.
public struct AppRef: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String?
    public var path: String
    public var name: String

    public var id: String { bundleID ?? path }

    public init(bundleID: String?, path: String, name: String) {
        self.bundleID = bundleID
        self.path = path
        self.name = name
    }

    public init?(url: URL) {
        guard url.pathExtension == "app" else { return nil }
        self.bundleID = Bundle(url: url)?.bundleIdentifier
        self.path = url.path
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        self.name = name
    }

    /// Where the app lives now. Falls back to the bundle ID so apps that moved still resolve.
    @MainActor
    public var resolvedURL: URL? {
        if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        if let bundleID { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
        return nil
    }

    @MainActor
    public var icon: NSImage {
        if let url = resolvedURL { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

public enum IconStyle: String, Codable, CaseIterable, Sendable {
    case folder, tile

    public var title: String {
        switch self {
        case .folder: "Folder"
        case .tile: "Tile"
        }
    }
}

public struct HarborFolder: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var symbol: String
    public var style: IconStyle
    public var apps: [AppRef]

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = FolderPalette.presets[0].hex,
        symbol: String = "square.grid.2x2.fill",
        style: IconStyle = .folder,
        apps: [AppRef] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.style = style
        self.apps = apps
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Everything that affects the Dock tile. When this changes, the helper app is rebuilt.
    public var appearanceKey: String {
        "\(displayName)|\(colorHex)|\(symbol)|\(style.rawValue)"
    }

    /// Adds apps that aren't already present. Returns how many were added.
    @discardableResult
    public mutating func add(_ refs: [AppRef]) -> Int {
        var existing = Set(apps.map(\.id))
        let fresh = refs.filter { existing.insert($0.id).inserted }
        apps.append(contentsOf: fresh)
        return fresh.count
    }
}

/// How a folder's apps are laid out when it's opened from the Dock.
public enum PopoverStyle: String, Codable, CaseIterable, Sendable {
    case grid, compactGrid, list, fan

    public var title: String {
        switch self {
        case .grid: "Grid"
        case .compactGrid: "Compact Grid"
        case .list: "List"
        case .fan: "Fan"
        }
    }

    public var summary: String {
        switch self {
        case .grid: "Large icons with names."
        case .compactGrid: "Smaller icons, names on hover. Fits more apps."
        case .list: "Small icons in a list. Good for big folders."
        case .fan: "Icons rise from the Dock in a curve, like the Dock's Fan view."
        }
    }

    public var symbol: String {
        switch self {
        case .grid: "square.grid.3x3.fill"
        case .compactGrid: "square.grid.4x3.fill"
        case .list: "list.bullet.rectangle.fill"
        case .fan: "square.stack.3d.up.fill"
        }
    }
}

/// App-wide preferences, shared with the folder apps through settings.json.
public struct HarborSettings: Codable, Hashable, Sendable {
    public var popoverStyle: PopoverStyle

    public init(popoverStyle: PopoverStyle = .grid) {
        self.popoverStyle = popoverStyle
    }

    // Missing or unknown values fall back to defaults, so older and newer files both load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        popoverStyle = (try? container.decodeIfPresent(PopoverStyle.self, forKey: .popoverStyle)) ?? .grid
    }
}

public struct PaletteColor: Identifiable, Sendable {
    public let name: String
    public let hex: String
    public var id: String { hex }
}

public enum FolderPalette {
    public static let presets: [PaletteColor] = [
        .init(name: "Blue", hex: "3A9BF5"),
        .init(name: "Teal", hex: "2FB5C2"),
        .init(name: "Green", hex: "46C15A"),
        .init(name: "Yellow", hex: "F4C23C"),
        .init(name: "Orange", hex: "F5913C"),
        .init(name: "Red", hex: "EE5A50"),
        .init(name: "Pink", hex: "EC5C93"),
        .init(name: "Purple", hex: "A160DA"),
        .init(name: "Indigo", hex: "5F64DF"),
        .init(name: "Brown", hex: "A68262"),
        .init(name: "Graphite", hex: "8A8F98"),
    ]
}

/// A curated set of SF Symbols, in the spirit of Finder's folder customization.
public enum SymbolCatalog {
    private static let curated = [
        "square.grid.2x2.fill", "folder.fill", "star.fill", "heart.fill", "bolt.fill", "flame.fill", "sparkles", "wand.and.stars",
        "hammer.fill", "wrench.and.screwdriver.fill", "chevron.left.forwardslash.chevron.right", "terminal.fill", "curlybraces", "cpu.fill", "server.rack", "externaldrive.fill",
        "paintbrush.pointed.fill", "paintpalette.fill", "pencil.and.ruler.fill", "scribble.variable", "photo.fill", "camera.fill", "film.fill", "video.fill",
        "music.note", "headphones", "mic.fill", "guitars.fill", "gamecontroller.fill", "puzzlepiece.fill", "dice.fill", "tv.fill",
        "book.fill", "books.vertical.fill", "graduationcap.fill", "brain.head.profile", "lightbulb.fill", "doc.text.fill", "note.text", "list.bullet.clipboard.fill",
        "briefcase.fill", "calendar", "chart.bar.fill", "chart.pie.fill", "dollarsign.circle.fill", "creditcard.fill", "cart.fill", "bag.fill",
        "message.fill", "bubble.left.and.bubble.right.fill", "envelope.fill", "phone.fill", "person.2.fill", "person.crop.circle.fill", "globe", "network",
        "cloud.fill", "lock.fill", "key.fill", "shield.lefthalf.filled", "gearshape.fill", "slider.horizontal.3", "desktopcomputer", "laptopcomputer",
        "house.fill", "building.2.fill", "airplane", "car.fill", "map.fill", "leaf.fill", "sun.max.fill", "moon.fill",
        "atom", "flask.fill", "stethoscope", "cross.case.fill", "dumbbell.fill", "figure.run", "fork.knife", "cup.and.saucer.fill",
        "gift.fill", "tag.fill", "flag.fill", "bookmark.fill", "tray.full.fill", "archivebox.fill", "shippingbox.fill", "sailboat.fill",
    ]

    /// The curated symbols that exist on this system.
    @MainActor
    public static let available: [String] = curated.filter {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
    }
}

public enum HarborPaths {
    public static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Harbor", directoryHint: .isDirectory)
    public static let foldersFile = supportDir.appending(path: "folders.json")
    public static let settingsFile = supportDir.appending(path: "settings.json")
    /// Where the generated folder apps live.
    public static let stubsDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Applications/Harbor Folders", directoryHint: .isDirectory)

    public static let urlScheme = "harbor"

    public static func editURL(for id: UUID) -> URL {
        URL(string: "\(urlScheme)://folder/\(id.uuidString)")!
    }
}
