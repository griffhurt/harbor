import AppKit
import HarborKit
import SwiftUI

/// A borderless panel that floats above the Dock, pointing at the tile that was clicked.
@MainActor
final class PopoverController {
    typealias ViewBuilder = (ArrowEdge, CGFloat?) -> FolderPopoverView

    private var panel: FolderPanel?
    private var hostingView: NSHostingView<FolderPopoverView>?
    private var anchor: DockAnchor?
    private var keyMonitor: Any?
    private var lastClose = Date.distantPast

    var isShown: Bool { panel?.isVisible == true }
    var closedJustNow: Bool { Date().timeIntervalSince(lastClose) < 0.4 }

    func show(_ build: @escaping ViewBuilder) {
        let anchor = DockAnchor.current()
        self.anchor = anchor
        let panel = panel ?? makePanel()
        let frame = layout(build, anchor: anchor)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(anchor.startFrame(for: frame), display: false)
            panel.orderFrontRegardless()
            panel.makeKey()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        installKeyMonitor()
    }

    /// Re-renders in place (e.g. the folder's apps changed) without moving the anchor.
    func update(_ build: @escaping ViewBuilder) {
        guard let panel, panel.isVisible, let anchor else { return }
        panel.setFrame(layout(build, anchor: anchor), display: true)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        lastClose = Date()
        removeKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    // MARK: -

    /// Sizes the SwiftUI content, positions it, then re-renders with the arrow pointing at the anchor.
    private func layout(_ build: ViewBuilder, anchor: DockAnchor) -> NSRect {
        let hostingView = hostingView ?? NSHostingView(rootView: build(anchor.edge, nil))
        if self.hostingView == nil {
            self.hostingView = hostingView
            panel?.contentView = hostingView
        }
        let view = build(anchor.edge, nil)
        hostingView.rootView = view
        // A fan has to rise straight out of its tile, so it isn't nudged back on-screen. It has no panel,
        // and a window shadow would outline every label and icon, so it draws its own shadows instead.
        let frame = anchor.frame(for: hostingView.fittingSize, keepOnScreen: !view.isFan)
        panel?.hasShadow = !view.isFan
        hostingView.rootView = build(anchor.edge, anchor.arrowOffset(in: frame))
        return frame
    }

    private func makePanel() -> FolderPanel {
        let panel = FolderPanel()
        self.panel = panel
        return panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                MainActor.assumeIsolated { self?.close() }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

final class FolderPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

/// Where the Dock is and which tile was clicked (approximated by the mouse location at click time).
struct DockAnchor {
    let point: NSPoint
    let edge: ArrowEdge
    let screen: NSScreen

    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 8

    static func current() -> DockAnchor {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let edge: ArrowEdge = switch dockPreference("orientation") as? String {
        case "left": .left
        case "right": .right
        default: .bottom
        }
        return DockAnchor(point: mouse, edge: edge, screen: screen)
    }

    private static func dockPreference(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString)
    }

    /// How far the Dock extends from the screen edge.
    private var dockThickness: CGFloat {
        let full = screen.frame, visible = screen.visibleFrame
        let reserved = switch edge {
        case .bottom: visible.minY - full.minY
        case .left: visible.minX - full.minX
        case .right: full.maxX - visible.maxX
        }
        if reserved > 10 { return reserved }
        // Auto-hidden Dock: estimate from the tile size.
        let tile = (Self.dockPreference("tilesize") as? NSNumber)?.doubleValue ?? 48
        return tile + 16
    }

    func frame(for size: NSSize, keepOnScreen: Bool = true) -> NSRect {
        let full = screen.frame, visible = screen.visibleFrame
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            keepOnScreen ? min(max(v, lo), max(lo, hi)) : v
        }
        var origin = NSPoint.zero
        switch edge {
        case .bottom:
            origin.x = clamp(point.x - size.width / 2, visible.minX + Self.margin, visible.maxX - size.width - Self.margin)
            origin.y = full.minY + dockThickness + Self.gap
        case .left:
            origin.x = full.minX + dockThickness + Self.gap
            origin.y = clamp(point.y - size.height / 2, visible.minY + Self.margin, visible.maxY - size.height - Self.margin)
        case .right:
            origin.x = full.maxX - dockThickness - Self.gap - size.width
            origin.y = clamp(point.y - size.height / 2, visible.minY + Self.margin, visible.maxY - size.height - Self.margin)
        }
        return NSRect(origin: origin, size: size)
    }

    /// The arrow position in SwiftUI coordinates (x from the left, or y from the top).
    func arrowOffset(in frame: NSRect) -> CGFloat {
        switch edge {
        case .bottom: point.x - frame.minX
        case .left, .right: frame.maxY - point.y
        }
    }

    /// Slightly offset toward the Dock, so the popover glides out of the tile.
    func startFrame(for frame: NSRect) -> NSRect {
        switch edge {
        case .bottom: frame.offsetBy(dx: 0, dy: -8)
        case .left: frame.offsetBy(dx: -8, dy: 0)
        case .right: frame.offsetBy(dx: 8, dy: 0)
        }
    }
}
