import Foundation
import Observation

public enum HarborNotifications {
    /// Posted (distributed) whenever any process saves folders.json or settings.json.
    public static let foldersChanged = Notification.Name("com.griffhurt.harbor.foldersChanged")
    static let senderID = String(ProcessInfo.processInfo.processIdentifier)
}

/// Reads and writes the folders and settings shared by the manager app and every folder helper.
@MainActor
@Observable
public final class FolderStore {
    public private(set) var folders: [HarborFolder] = []
    public private(set) var settings = HarborSettings()

    @ObservationIgnored public var onExternalChange: (() -> Void)?
    @ObservationIgnored private var observer: DistributedObserver?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let settingsURL: URL
    @ObservationIgnored private let sharesChanges: Bool

    /// - Parameters:
    ///   - fileURL: Where folders are stored. Settings are kept next to it in settings.json.
    ///   - sharesChanges: Whether to tell other Harbor processes about saves and listen for theirs.
    public init(fileURL: URL = HarborPaths.foldersFile, sharesChanges: Bool = true) {
        self.fileURL = fileURL
        self.settingsURL = fileURL.deletingLastPathComponent().appending(path: "settings.json")
        self.sharesChanges = sharesChanges
        reload()
        guard sharesChanges else { return }
        observer = DistributedObserver(name: HarborNotifications.foldersChanged) { [weak self] in
            self?.reload()
            self?.onExternalChange?()
        }
    }

    public func reload() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([HarborFolder].self, from: data),
           decoded != folders {
            folders = decoded
        }
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(HarborSettings.self, from: data),
           decoded != settings {
            settings = decoded
        }
    }

    public func updateSettings(_ newSettings: HarborSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        write(settings, to: settingsURL)
    }

    public func folder(id: UUID) -> HarborFolder? {
        folders.first { $0.id == id }
    }

    public func upsert(_ folder: HarborFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            guard folders[index] != folder else { return }
            folders[index] = folder
        } else {
            folders.append(folder)
        }
        save()
    }

    public func delete(id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        write(folders, to: fileURL)
    }

    private func write(_ value: some Encodable, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
            guard sharesChanges else { return }
            DistributedNotificationCenter.default().postNotificationName(
                HarborNotifications.foldersChanged,
                object: HarborNotifications.senderID,
                userInfo: nil,
                deliverImmediately: true
            )
        } catch {
            NSLog("Harbor: failed to save \(url.lastPathComponent): \(error)")
        }
    }
}

/// Listens for changes from other Harbor processes, even while this app is in the background.
@MainActor
private final class DistributedObserver: NSObject {
    private let handler: @MainActor () -> Void

    init(name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(fire(_:)), name: name, object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func fire(_ note: Notification) {
        guard (note.object as? String) != HarborNotifications.senderID else { return }
        handler()
    }
}
