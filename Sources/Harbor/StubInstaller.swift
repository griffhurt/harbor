import AppKit
import CoreServices
import CryptoKit
import HarborKit

/// Generates the small per-folder apps that sit in the Dock.
/// Each one is `~/Applications/Harbor Folders/<Name>.app`, containing a copy of HarborStub and the folder's icon.
@MainActor
enum StubInstaller {
    enum InstallError: LocalizedError {
        case missingHelper
        case codesignFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .missingHelper: "Harbor's helper is missing. Run Harbor from the built Harbor.app bundle."
            case .codesignFailed(let status): "Signing the folder app failed (codesign exit \(status))."
            }
        }
    }

    private static let executableName = "HarborStub"
    private static var helperURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/\(executableName)")
    }

    static func bundleID(for id: UUID) -> String {
        "com.griffhurt.harbor.folder.\(id.uuidString.lowercased())"
    }

    /// The installed app for a folder, wherever it currently is (its name may be out of date).
    static func existingBundle(for id: UUID) -> URL? {
        let apps = (try? FileManager.default.contentsOfDirectory(at: HarborPaths.stubsDir, includingPropertiesForKeys: nil)) ?? []
        return apps.first { $0.pathExtension == "app" && info(at: $0)?["HarborFolderID"] as? String == id.uuidString }
    }

    /// The appearance the installed Dock icon was built with.
    static func installedAppearance(for id: UUID) -> String? {
        existingBundle(for: id).flatMap { info(at: $0)?["HarborAppearance"] as? String }
    }

    /// True when the folder app was built from a different helper than the one bundled in Harbor (e.g. after an update).
    /// Compares a recorded hash, since signing the folder app rewrites its copy of the binary.
    static func isOutdated(_ id: UUID) -> Bool {
        guard let bundle = existingBundle(for: id) else { return false }
        return info(at: bundle)?["HarborHelperHash"] as? String != helperHash
    }

    private static let helperHash: String? = (try? Data(contentsOf: helperURL)).map {
        SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
    }

    /// Creates or rebuilds the folder's app, renaming it if the folder was renamed. Returns its location.
    @discardableResult
    static func install(_ folder: HarborFolder) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: helperURL.path) else { throw InstallError.missingHelper }
        try fm.createDirectory(at: HarborPaths.stubsDir, withIntermediateDirectories: true)
        terminateRunning(folder.id)

        let target = targetURL(for: folder)
        if let existing = existingBundle(for: folder.id), existing.standardizedFileURL != target.standardizedFileURL {
            try fm.moveItem(at: existing, to: target)
        }

        let contents = target.appending(path: "Contents")
        let macOS = contents.appending(path: "MacOS")
        let resources = contents.appending(path: "Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let executable = macOS.appending(path: executableName)
        if fm.fileExists(atPath: executable.path) { try fm.removeItem(at: executable) }
        try fm.copyItem(at: helperURL, to: executable)

        let icns = IconRenderer.icnsData(for: folder)
        try icns.write(to: resources.appending(path: "AppIcon.icns"))
        try infoPlist(for: folder).write(to: contents.appending(path: "Info.plist"))
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)

        // A custom icon from a previous install is Finder metadata that codesign rejects; clear it first.
        NSWorkspace.shared.setIcon(nil, forFile: target.path, options: [])
        try codesign(target)
        // macOS 26 shrinks non-squircle app icons onto a gray tile in the Dock, but leaves
        // custom (Get Info–style) icons alone — so the folder shape is applied as a custom icon.
        if let image = NSImage(data: icns) {
            NSWorkspace.shared.setIcon(image, forFile: target.path, options: [])
        }
        LSRegisterURL(target as CFURL, true)
        return target
    }

    static func uninstall(_ id: UUID) {
        terminateRunning(id)
        if let bundle = existingBundle(for: id) {
            try? FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        }
    }

    /// Quits folder helpers still running code older than what's on disk (started before their
    /// helper was last replaced). They relaunch with the current code on their next click.
    static func terminateStaleHelpers() {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleURL, bundle.standardizedFileURL.path.hasPrefix(HarborPaths.stubsDir.standardizedFileURL.path),
                  let launched = app.launchDate,
                  let modified = try? bundle.appending(path: "Contents/MacOS/\(executableName)")
                      .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  launched < modified
            else { continue }
            app.forceTerminate()
        }
    }

    /// Quits the folder's running helper. Matches by location too, so a copy started under an
    /// older bundle ID (or an older build) is still found and replaced.
    static func terminateRunning(_ id: UUID) {
        let bundle = existingBundle(for: id)?.standardizedFileURL
        let identifier = bundleID(for: id)
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == identifier || (bundle != nil && app.bundleURL?.standardizedFileURL == bundle) {
            app.forceTerminate()
        }
    }

    // MARK: -

    /// A file name for the folder app: no path separators, and no leading dot (which would hide it).
    static func bundleBaseName(for displayName: String) -> String {
        var name = displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "Untitled" : name
    }

    private static func targetURL(for folder: HarborFolder) -> URL {
        let base = bundleBaseName(for: folder.displayName)
        var candidate = HarborPaths.stubsDir.appending(path: "\(base).app")
        var counter = 2
        // Avoid clobbering another folder that happens to have the same name.
        while let owner = info(at: candidate)?["HarborFolderID"] as? String, owner != folder.id.uuidString {
            candidate = HarborPaths.stubsDir.appending(path: "\(base) \(counter).app")
            counter += 1
        }
        return candidate
    }

    private static func infoPlist(for folder: HarborFolder) throws -> Data {
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID(for: folder.id),
            "CFBundleName": folder.displayName,
            "CFBundleDisplayName": folder.displayName,
            "CFBundleExecutable": executableName,
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleShortVersionString": "1.0",
            // Bumped on every rebuild so the Dock and Launch Services refresh their icon caches.
            "CFBundleVersion": String(Int(Date().timeIntervalSince1970)),
            "LSMinimumSystemVersion": "26.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
            "HarborFolderID": folder.id.uuidString,
            "HarborAppearance": folder.appearanceKey,
            "HarborHelperHash": helperHash ?? "",
        ]
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    private static func info(at bundle: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundle.appending(path: "Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func codesign(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw InstallError.codesignFailed(process.terminationStatus) }
    }
}
