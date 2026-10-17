import Foundation

/// Finds the applications installed on this Mac.
public enum AppCatalog {
    public static func installedApps() async -> [AppRef] {
        await Task.detached(priority: .userInitiated) { scan() }.value
    }

    private static func scan() -> [AppRef] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
            "\(home)/Applications",
        ]
        let stubsPrefix = HarborPaths.stubsDir.path
        var seen = Set<String>()
        var result: [AppRef] = []

        func consider(_ url: URL) {
            guard !url.path.hasPrefix(stubsPrefix), let ref = AppRef(url: url) else { return }
            if seen.insert(ref.id).inserted { result.append(ref) }
        }

        consider(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.pathExtension == "app" {
                    consider(url)
                } else if enumerator.level >= 3 {
                    enumerator.skipDescendants()
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
