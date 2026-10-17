import AppKit
import HarborKit
import Observation

/// Coordinates folder edits with the generated Dock apps.
@MainActor
@Observable
final class HarborModel {
    let store = FolderStore()
    var selection: UUID?
    var errorMessage: String?
    private(set) var dockedIDs: Set<UUID> = []

    @ObservationIgnored private var dockRefreshTask: Task<Void, Never>?

    init() {
        selection = store.folders.first?.id
        refreshDockState()
    }

    func isDocked(_ id: UUID) -> Bool { dockedIDs.contains(id) }

    /// Re-reads folders and which of them are pinned (the user may have dragged a tile out of the Dock).
    func refreshDockState() {
        store.reload()
        dockedIDs = Set(store.folders.compactMap { folder in
            StubInstaller.existingBundle(for: folder.id).map(DockManager.isPinned) == true ? folder.id : nil
        })
    }

    // MARK: Folders

    func createFolder() {
        let names = Set(store.folders.map(\.displayName))
        var name = "New Folder"
        var counter = 2
        while names.contains(name) {
            name = "New Folder \(counter)"
            counter += 1
        }
        let color = FolderPalette.presets[store.folders.count % FolderPalette.presets.count]
        let folder = HarborFolder(name: name, colorHex: color.hex)
        store.upsert(folder)
        selection = folder.id
    }

    func update(_ folder: HarborFolder) {
        let previous = store.folder(id: folder.id)
        store.upsert(folder)
        if previous?.appearanceKey != folder.appearanceKey, isDocked(folder.id) {
            scheduleDockRefresh()
        }
    }

    func edit(_ id: UUID, _ change: (inout HarborFolder) -> Void) {
        guard var folder = store.folder(id: id) else { return }
        change(&folder)
        update(folder)
    }

    func delete(_ id: UUID) {
        if isDocked(id) { removeFromDock(id) }
        StubInstaller.uninstall(id)
        store.delete(id: id)
        if selection == id { selection = store.folders.first?.id }
    }

    // MARK: Dock

    func addToDock(_ id: UUID) {
        guard let folder = store.folder(id: id) else { return }
        do {
            let url = try StubInstaller.install(folder)
            DockManager.pin(url, label: folder.displayName, bundleID: StubInstaller.bundleID(for: id))
            DockManager.restart()
            dockedIDs.insert(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFromDock(_ id: UUID) {
        if let url = StubInstaller.existingBundle(for: id) {
            DockManager.unpin(url)
            DockManager.restart()
        }
        StubInstaller.uninstall(id)
        dockedIDs.remove(id)
    }

    /// Appearance edits are batched: the Dock restarts once you've paused, not on every click.
    private func scheduleDockRefresh() {
        dockRefreshTask?.cancel()
        dockRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.applyPendingAppearance()
        }
    }

    /// Rebuilds Dock icons whose folder name, color, symbol or shape changed.
    func applyPendingAppearance() {
        dockRefreshTask?.cancel()
        dockRefreshTask = nil
        var changed = false
        for folder in store.folders where isDocked(folder.id) {
            guard StubInstaller.installedAppearance(for: folder.id) != folder.appearanceKey else { continue }
            let oldURL = StubInstaller.existingBundle(for: folder.id)
            do {
                let newURL = try StubInstaller.install(folder)
                if let oldURL, oldURL.standardizedFileURL != newURL.standardizedFileURL {
                    DockManager.replace(oldURL, with: newURL, label: folder.displayName, bundleID: StubInstaller.bundleID(for: folder.id))
                }
                changed = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if changed { DockManager.restart() }
    }

    /// After Harbor itself is updated, refresh the helper inside each installed folder app.
    func updateOutdatedHelpers() {
        for folder in store.folders where StubInstaller.isOutdated(folder.id) {
            _ = try? StubInstaller.install(folder)
        }
        StubInstaller.terminateStaleHelpers()
    }
}
