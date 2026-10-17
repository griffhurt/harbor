import AppKit
import HarborKit

/// Each folder in the Dock is a copy of this helper. Clicking the Dock tile launches it (first click)
/// or sends it a reopen event (later clicks); either way it shows the folder's popover above the tile.
/// The popover only launches apps — folders are edited in the Harbor window.
@MainActor
final class StubDelegate: NSObject, NSApplicationDelegate {
    private let folderID: UUID? = (Bundle.main.object(forInfoDictionaryKey: "HarborFolderID") as? String).flatMap(UUID.init)
    private let store = FolderStore()
    private let popover = PopoverController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard folderID != nil else {
            NSApp.terminate(nil)
            return
        }
        store.onExternalChange = { [weak self] in self?.folderDidChange() }
        showPopover()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if popover.isShown {
            popover.close()
        } else if !popover.closedJustNow {
            // Clicking the tile while open can deactivate us first; don't immediately reopen in that case.
            showPopover()
        }
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        popover.close()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let folder = currentFolder() else { return nil }
        let menu = NSMenu()
        for app in folder.apps {
            let item = NSMenuItem(title: app.name, action: #selector(launchFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.id
            let icon = app.icon.copy() as! NSImage
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !folder.apps.isEmpty { menu.addItem(.separator()) }
        let edit = NSMenuItem(title: "Edit “\(folder.displayName)” in Harbor…", action: #selector(editFromMenu), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        return menu
    }

    // MARK: -

    private func currentFolder() -> HarborFolder? {
        guard let folderID else { return nil }
        store.reload()
        return store.folder(id: folderID)
    }

    private func showPopover() {
        guard let folder = currentFolder() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(makeView(for: folder))
    }

    private func folderDidChange() {
        guard let folderID else { return }
        guard let folder = store.folder(id: folderID) else {
            NSApp.terminate(nil)
            return
        }
        if popover.isShown { popover.update(makeView(for: folder)) }
    }

    /// - Parameter style: Overrides the user's chosen style (the fan's "More" button switches to a grid).
    private func makeView(for folder: HarborFolder, style: PopoverStyle? = nil) -> (ArrowEdge, CGFloat?) -> FolderPopoverView {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let style = style ?? store.settings.popoverStyle
        return { [weak self] edge, offset in
            FolderPopoverView(
                folder: folder,
                style: style,
                arrowEdge: edge,
                arrowOffset: offset,
                runningIDs: running,
                onLaunch: { self?.launch($0) },
                onEdit: { self?.openEditor() },
                onShowAll: { self?.showAll(folder) }
            )
        }
    }

    private func showAll(_ folder: HarborFolder) {
        popover.update(makeView(for: folder, style: .grid))
    }

    private func launch(_ app: AppRef) {
        popover.close()
        guard let url = app.resolvedURL else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openEditor() {
        popover.close()
        guard let folderID else { return }
        NSWorkspace.shared.open(HarborPaths.editURL(for: folderID))
    }

    @objc private func launchFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let app = currentFolder()?.apps.first(where: { $0.id == id }) else { return }
        launch(app)
    }

    @objc private func editFromMenu() {
        openEditor()
    }
}
