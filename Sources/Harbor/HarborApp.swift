import AppKit
import CoreServices
import HarborKit
import SwiftUI

@main
struct HarborApp: App {
    static let repositoryURL = URL(string: "https://github.com/griffhurt/harbor")!
    /// The Usage section of the README, which doubles as Harbor's help.
    static let helpURL = URL(string: "https://github.com/griffhurt/harbor#usage")!

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The editor window is managed by AppDelegate; SwiftUI provides Settings (⌘,).
        Settings {
            SettingsView()
                .environment(appDelegate.model)
                .environmentObject(appDelegate.updater)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Harbor") { appDelegate.showAbout() }
                CheckForUpdatesButton(updater: appDelegate.updater)
            }
            CommandGroup(replacing: .help) {
                Button("Harbor Help") { NSWorkspace.shared.open(Self.helpURL) }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

/// Owns the folder editor window. Folders in the Dock work on their own, so Harbor quits when its window closes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = HarborModel()
    let updater = AppUpdater()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        model.updateOutdatedHelpers()
        model.refreshDockState()
        showManager()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model.applyPendingAppearance()
    }

    /// `harbor://folder/<uuid>` — sent by a folder's "Edit" button.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == HarborPaths.urlScheme {
            if let id = UUID(uuidString: url.lastPathComponent) { model.selection = id }
        }
        showManager()
    }

    func showManager() {
        if window == nil {
            let controller = NSHostingController(rootView: ManagerView().environment(model))
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.title = "Harbor"
            window.setContentSize(NSSize(width: 900, height: 640))
            window.minSize = NSSize(width: 720, height: 480)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("HarborManager")
            self.window = window
        }
        model.refreshDockState()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The standard About panel, with a link to the project under the version.
    func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(string: "github.com/griffhurt/harbor", attributes: [
            .link: HarborApp.repositoryURL,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: paragraph,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.refreshDockState()
    }

    func windowWillClose(_ notification: Notification) {
        model.applyPendingAppearance()
    }
}
