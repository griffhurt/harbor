import AppKit
import SwiftUI

public enum ArrowEdge: Sendable {
    case bottom, left, right
}

/// A folder's apps as shown above its Dock tile, in the chosen `PopoverStyle`. Also used as a live preview in Harbor.
/// It only launches apps; folders are edited in the Harbor window.
public struct FolderPopoverView: View {
    public static let arrowLength: CGFloat = 11

    let folder: HarborFolder
    let style: PopoverStyle
    let arrowEdge: ArrowEdge
    /// Where the arrow points: from the left edge (bottom arrow) or the top edge (side arrows). `nil` centers it.
    let arrowOffset: CGFloat?
    let runningIDs: Set<String>
    let onLaunch: (AppRef) -> Void
    let onEdit: () -> Void
    /// Called by the fan's "more" button; the host should show the folder as a grid instead.
    let onShowAll: (() -> Void)?
    /// Blurs the window's own content instead of the desktop, for previews inside another window.
    let isPreview: Bool

    @State private var hoveredApp: String?

    public init(
        folder: HarborFolder,
        style: PopoverStyle = .grid,
        arrowEdge: ArrowEdge = .bottom,
        arrowOffset: CGFloat? = nil,
        runningIDs: Set<String> = [],
        onLaunch: @escaping (AppRef) -> Void,
        onEdit: @escaping () -> Void,
        onShowAll: (() -> Void)? = nil,
        isPreview: Bool = false
    ) {
        self.folder = folder
        self.style = style
        self.arrowEdge = arrowEdge
        self.arrowOffset = arrowOffset
        self.runningIDs = runningIDs
        self.onLaunch = onLaunch
        self.onEdit = onEdit
        self.onShowAll = onShowAll
        self.isPreview = isPreview
    }

    /// Whether this renders as a fan, which must be centered on the Dock tile rather than kept on-screen.
    public var isFan: Bool { effectiveStyle == .fan }

    /// A fan only makes sense rising from a bottom Dock, and needs at least one app.
    private var effectiveStyle: PopoverStyle {
        if style == .fan, arrowEdge != .bottom { return .list }
        if style == .fan, folder.apps.isEmpty { return .grid }
        return style
    }

    public var body: some View {
        if effectiveStyle == .fan {
            FanView(folder: folder, runningIDs: runningIDs, onLaunch: onLaunch, onEdit: onEdit, onShowAll: onShowAll)
        } else {
            panel
        }
    }

    // MARK: Panel styles

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if folder.apps.isEmpty {
                emptyState
            } else {
                switch effectiveStyle {
                case .list: list
                case .compactGrid: grid(PanelGrid.compact)
                default: grid(PanelGrid.regular)
                }
            }
        }
        .frame(width: panelWidth)
        .padding(14)
        .padding(arrowPaddingEdge, Self.arrowLength)
        // A masked vibrancy view rather than Liquid Glass, which draws a light rim around the shape.
        .background(CalloutBackground(
            shape: CalloutShape(edge: arrowEdge, offset: arrowOffset, arrowLength: Self.arrowLength),
            blending: isPreview ? .withinWindow : .behindWindow
        ))
        .fixedSize()
    }

    private var panelWidth: CGFloat {
        switch effectiveStyle {
        case .list: 250
        case .compactGrid: PanelGrid.compact.width(for: folder.apps.count)
        default: PanelGrid.regular.width(for: folder.apps.count)
        }
    }

    private var arrowPaddingEdge: Edge.Set {
        switch arrowEdge {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            FolderBadge(folder: folder, size: 24)
            Text(folder.displayName)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            // Compact grids hide names, so show the hovered app's name here.
            if effectiveStyle == .compactGrid, let hoveredApp {
                Text(hoveredApp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Edit in Harbor")
        }
        .padding(.horizontal, 4)
    }

    private func grid(_ metrics: PanelGrid) -> some View {
        let columns = metrics.columns(for: folder.apps.count)
        let rows = (folder.apps.count + metrics.maxColumns - 1) / metrics.maxColumns
        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(metrics.cell.width), spacing: metrics.spacing), count: columns),
            alignment: .leading,
            spacing: metrics.spacing
        ) {
            ForEach(folder.apps) { app in
                GridCell(app: app, running: isRunning(app), metrics: metrics, hoveredApp: $hoveredApp) { onLaunch(app) }
                    .contextMenu { appMenu(app) }
            }
        }
        return Group {
            if rows > metrics.maxVisibleRows {
                ScrollView { grid }
                    .frame(height: CGFloat(metrics.maxVisibleRows) * metrics.cell.height + CGFloat(metrics.maxVisibleRows - 1) * metrics.spacing)
            } else {
                grid
            }
        }
    }

    private var list: some View {
        let rowHeight: CGFloat = 30
        let maxVisibleRows = 12
        let rows = VStack(spacing: 0) {
            ForEach(folder.apps) { app in
                ListRow(app: app, running: isRunning(app), height: rowHeight) { onLaunch(app) }
                    .contextMenu { appMenu(app) }
            }
        }
        return Group {
            if folder.apps.count > maxVisibleRows {
                ScrollView { rows }
                    .frame(height: CGFloat(maxVisibleRows) * rowHeight)
            } else {
                rows
            }
        }
    }

    @ViewBuilder
    private func appMenu(_ app: AppRef) -> some View {
        Button("Open") { onLaunch(app) }
        Button("Show in Finder") {
            if let url = app.resolvedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private func isRunning(_ app: AppRef) -> Bool {
        app.bundleID.map(runningIDs.contains) ?? false
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No apps yet")
                .font(.callout.weight(.medium))
            Text("Add apps to this folder in Harbor.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// Sizes for the two grid styles.
struct PanelGrid {
    let cell: CGSize
    let icon: CGFloat
    let showsNames: Bool
    let maxColumns: Int
    let maxVisibleRows: Int
    let spacing: CGFloat

    static let regular = PanelGrid(cell: CGSize(width: 86, height: 100), icon: 56, showsNames: true, maxColumns: 5, maxVisibleRows: 4, spacing: 6)
    static let compact = PanelGrid(cell: CGSize(width: 54, height: 54), icon: 40, showsNames: false, maxColumns: 7, maxVisibleRows: 5, spacing: 4)

    func columns(for count: Int) -> Int { min(max(count, 1), maxColumns) }

    func width(for count: Int) -> CGFloat {
        let columns = columns(for: count)
        return max(CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing, 250)
    }
}

private struct FolderBadge: View {
    let folder: HarborFolder
    let size: CGFloat

    var body: some View {
        Image(systemName: folder.symbol)
            .font(.system(size: size / 2, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: folder.colorHex).gradient, in: .rect(cornerRadius: size * 0.29, style: .continuous))
    }
}

private struct GridCell: View {
    let app: AppRef
    let running: Bool
    let metrics: PanelGrid
    @Binding var hoveredApp: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: metrics.showsNames ? 4 : 2) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: metrics.icon, height: metrics.icon)
                    .opacity(app.resolvedURL == nil ? 0.4 : 1)
                if metrics.showsNames {
                    Text(app.name)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(height: 28, alignment: .top)
                }
                RunningDot(running: running)
            }
            .frame(width: metrics.cell.width, height: metrics.cell.height)
            .background(.primary.opacity(hovering ? 0.09 : 0), in: .rect(cornerRadius: metrics.showsNames ? 14 : 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { hoveredApp = app.name } else if hoveredApp == app.name { hoveredApp = nil }
        }
        .help(app.name)
    }
}

private struct ListRow: View {
    let app: AppRef
    let running: Bool
    let height: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .opacity(app.resolvedURL == nil ? 0.4 : 1)
                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
                RunningDot(running: running)
            }
            .padding(.horizontal, 8)
            .frame(height: height)
            .background(.primary.opacity(hovering ? 0.09 : 0), in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RunningDot: View {
    let running: Bool

    var body: some View {
        Circle()
            .fill(.primary.opacity(running ? 0.55 : 0))
            .frame(width: 4, height: 4)
    }
}

// MARK: - Fan

/// Where each item of a fan sits: rising from the Dock tile and bending right toward the top, like the Dock's Fan view.
public enum FanLayout {
    public static let iconSize: CGFloat = 48
    public static let rowHeight: CGFloat = 56
    public static let labelWidth: CGFloat = 200
    /// The most apps shown before the rest are offered via a "more" button.
    public static let maxItems = 12
    private static let bend: CGFloat = 0.32

    /// Offset of the icon at `index` (0 is nearest the Dock) from the bottom icon, in points (x right, y up).
    public static func offset(at index: Int) -> CGPoint {
        CGPoint(x: bend * CGFloat(index * index), y: CGFloat(index) * rowHeight)
    }

    /// Room on each side of the bottom icon's center, so the window can be centered on the tile.
    static var halfWidth: CGFloat { labelWidth + 8 + iconSize / 2 }
}

private struct FanView: View {
    let folder: HarborFolder
    let runningIDs: Set<String>
    let onLaunch: (AppRef) -> Void
    let onEdit: () -> Void
    let onShowAll: (() -> Void)?

    private var shown: ArraySlice<AppRef> {
        folder.apps.count > FanLayout.maxItems ? folder.apps.prefix(FanLayout.maxItems - 1) : folder.apps[...]
    }
    private var overflow: Int { folder.apps.count - shown.count }
    /// Apps, then the "more" button, then the folder's name at the top.
    private var rowCount: Int { shown.count + (overflow > 0 ? 1 : 0) + 1 }

    private let bottomPadding: CGFloat = 4

    var body: some View {
        let width = FanLayout.halfWidth * 2
        let height = CGFloat(rowCount) * FanLayout.rowHeight + bottomPadding
        ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, app in
                FanItem(title: app.name, running: app.bundleID.map(runningIDs.contains) ?? false, action: { onLaunch(app) }) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .opacity(app.resolvedURL == nil ? 0.4 : 1)
                }
                .help(app.name)
                .position(position(at: index, height: height))
            }
            if overflow > 0 {
                FanItem(title: "\(overflow) More", running: false, action: { onShowAll?() }) {
                    Image(systemName: "ellipsis.circle.fill")
                        .resizable()
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .padding(6)
                }
                .help("Show all apps in this folder")
                .position(position(at: shown.count, height: height))
            }
            FanItem(title: folder.displayName, running: false, action: onEdit) {
                FolderBadge(folder: folder, size: 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .help("Edit in Harbor")
            .position(position(at: rowCount - 1, height: height))
        }
        .frame(width: width, height: height)
    }

    /// The center of a row's frame (label + icon), given where its icon belongs.
    private func position(at index: Int, height: CGFloat) -> CGPoint {
        let offset = FanLayout.offset(at: index)
        let iconCenter = CGPoint(
            x: FanLayout.halfWidth + offset.x,
            y: height - bottomPadding - FanLayout.iconSize / 2 - offset.y
        )
        return CGPoint(x: iconCenter.x - FanLayout.labelWidth / 2 - 4, y: iconCenter.y)
    }
}

/// One rung of the fan: a dark label pill to the left of an icon.
private struct FanItem<Icon: View>: View {
    let title: String
    let running: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    if running {
                        Circle().fill(.white.opacity(0.8)).frame(width: 4, height: 4)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(hovering ? 0.75 : 0.55), in: .capsule)
                .frame(width: FanLayout.labelWidth, alignment: .trailing)
                icon
                    .frame(width: FanLayout.iconSize, height: FanLayout.iconSize)
                    .scaleEffect(hovering ? 1.1 : 1)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Popover-style blur clipped to the callout shape. NSVisualEffectView only clips its
/// behind-window blur through `maskImage`, so the mask is redrawn whenever the size changes.
private struct CalloutBackground: NSViewRepresentable {
    let shape: CalloutShape
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> MaskedEffectView {
        let view = MaskedEffectView()
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ view: MaskedEffectView, context: Context) {
        view.blendingMode = blending
        view.shape = shape
    }

    final class MaskedEffectView: NSVisualEffectView {
        var shape: CalloutShape? {
            didSet { updateMask() }
        }

        override func layout() {
            super.layout()
            updateMask()
        }

        private func updateMask() {
            guard let shape, bounds.width > 0, bounds.height > 0 else { return }
            let path = shape.path(in: CGRect(origin: .zero, size: bounds.size)).cgPath
            maskImage = NSImage(size: bounds.size, flipped: true) { _ in
                NSColor.black.setFill()
                NSBezierPath(cgPath: path).fill()
                return true
            }
        }
    }
}

/// A rounded rectangle with a small arrow pointing at the Dock tile.
public struct CalloutShape: Shape {
    var edge: ArrowEdge
    var offset: CGFloat?
    var arrowLength: CGFloat
    var arrowWidth: CGFloat = 26
    var cornerRadius: CGFloat = 22

    public func path(in rect: CGRect) -> Path {
        var body = rect
        switch edge {
        case .bottom: body.size.height -= arrowLength
        case .left: body.origin.x += arrowLength; body.size.width -= arrowLength
        case .right: body.size.width -= arrowLength
        }

        let half = arrowWidth / 2
        let tipRound: CGFloat = 3
        var arrow = Path()
        switch edge {
        case .bottom:
            let x = clamp(offset ?? body.midX, body.minX + cornerRadius + half, body.maxX - cornerRadius - half)
            arrow.move(to: CGPoint(x: x - half, y: body.maxY - 1))
            arrow.addLine(to: CGPoint(x: x - tipRound, y: rect.maxY - tipRound / 2))
            arrow.addQuadCurve(to: CGPoint(x: x + tipRound, y: rect.maxY - tipRound / 2), control: CGPoint(x: x, y: rect.maxY))
            arrow.addLine(to: CGPoint(x: x + half, y: body.maxY - 1))
        case .left:
            let y = clamp(offset ?? body.midY, body.minY + cornerRadius + half, body.maxY - cornerRadius - half)
            arrow.move(to: CGPoint(x: body.minX + 1, y: y - half))
            arrow.addLine(to: CGPoint(x: rect.minX + tipRound / 2, y: y - tipRound))
            arrow.addQuadCurve(to: CGPoint(x: rect.minX + tipRound / 2, y: y + tipRound), control: CGPoint(x: rect.minX, y: y))
            arrow.addLine(to: CGPoint(x: body.minX + 1, y: y + half))
        case .right:
            let y = clamp(offset ?? body.midY, body.minY + cornerRadius + half, body.maxY - cornerRadius - half)
            arrow.move(to: CGPoint(x: body.maxX - 1, y: y - half))
            arrow.addLine(to: CGPoint(x: rect.maxX - tipRound / 2, y: y - tipRound))
            arrow.addQuadCurve(to: CGPoint(x: rect.maxX - tipRound / 2, y: y + tipRound), control: CGPoint(x: rect.maxX, y: y))
            arrow.addLine(to: CGPoint(x: body.maxX - 1, y: y + half))
        }
        arrow.closeSubpath()

        return Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous).union(arrow)
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low > high ? (low + high) / 2 : min(max(value, low), high)
    }
}
