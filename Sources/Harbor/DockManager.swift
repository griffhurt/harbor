import Foundation

/// Edits the pinned apps on the left side of the Dock (`persistent-apps` in com.apple.dock).
enum DockManager {
    private static var domain: CFString { "com.apple.dock" as CFString }
    private static var appsKey: CFString { "persistent-apps" as CFString }

    static func isPinned(_ url: URL) -> Bool {
        index(of: url, in: persistentApps()) != nil
    }

    /// Pins the app at the end of the pinned apps (just before running apps).
    static func pin(_ url: URL, label: String, bundleID: String) {
        write(pinning(url, label: label, bundleID: bundleID, in: persistentApps()))
    }

    static func unpin(_ url: URL) {
        write(unpinning(url, in: persistentApps()))
    }

    /// Points an existing tile at a new location (after a rename), keeping its position.
    static func replace(_ old: URL, with new: URL, label: String, bundleID: String) {
        write(replacing(old, with: new, label: label, bundleID: bundleID, in: persistentApps()))
    }

    /// The Dock only picks up preference changes (and new icons) when it restarts.
    static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }

    // MARK: Tile list editing

    static func pinning(_ url: URL, label: String, bundleID: String, in apps: [[String: Any]]) -> [[String: Any]] {
        guard index(of: url, in: apps) == nil else { return apps }
        return apps + [tile(for: url, label: label, bundleID: bundleID)]
    }

    static func unpinning(_ url: URL, in apps: [[String: Any]]) -> [[String: Any]] {
        guard let index = index(of: url, in: apps) else { return apps }
        var apps = apps
        apps.remove(at: index)
        return apps
    }

    static func replacing(_ old: URL, with new: URL, label: String, bundleID: String, in apps: [[String: Any]]) -> [[String: Any]] {
        var apps = apps
        if let index = index(of: old, in: apps) {
            apps[index] = tile(for: new, label: label, bundleID: bundleID)
        } else if index(of: new, in: apps) == nil {
            apps.append(tile(for: new, label: label, bundleID: bundleID))
        }
        return apps
    }

    static func index(of url: URL, in apps: [[String: Any]]) -> Int? {
        let target = normalized(url.path)
        return apps.firstIndex { path(of: $0).map(normalized) == target }
    }

    // MARK: Preferences

    private static func persistentApps() -> [[String: Any]] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(appsKey, domain) as? [[String: Any]] ?? []
    }

    private static func write(_ apps: [[String: Any]]) {
        CFPreferencesSetAppValue(appsKey, apps as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    static func path(of tile: [String: Any]) -> String? {
        guard let tileData = tile["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let string = fileData["_CFURLString"] as? String
        else { return nil }
        if (fileData["_CFURLStringType"] as? Int) == 0 { return string }
        return URL(string: string)?.path
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func tile(for url: URL, label: String, bundleID: String) -> [String: Any] {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": label,
                "bundle-identifier": bundleID,
                "file-type": 41,
                "file-data": [
                    "_CFURLString": URL(fileURLWithPath: url.path, isDirectory: true).absoluteString,
                    "_CFURLStringType": 15,
                ],
            ] as [String: Any],
        ]
    }
}
