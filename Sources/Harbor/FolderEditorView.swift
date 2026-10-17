import HarborKit
import SwiftUI
import UniformTypeIdentifiers

struct FolderEditorView: View {
    @Environment(HarborModel.self) private var model
    let folder: HarborFolder
    let requestDelete: () -> Void

    @State private var showingPicker = false
    @State private var dropTargeted = false
    /// The app being dragged to a new position, if any.
    @State private var draggingID: String?

    var body: some View {
        Form {
            Section { header }

            Section("Color") {
                ColorSwatches(hex: binding(\.colorHex))
            }

            Section("Icon") {
                Picker("Shape", selection: binding(\.style)) {
                    ForEach(IconStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SymbolGrid(selection: binding(\.symbol), tint: Color(hex: folder.colorHex))
            }

            Section {
                if folder.apps.isEmpty {
                    Text("No apps yet. Click Add Apps, or drag apps here from Finder.")
                        .foregroundStyle(.secondary)
                } else {
                    appGrid
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Button("Sort by Name") {
                        model.edit(folder.id) { $0.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
                    }
                    .disabled(folder.apps.count < 2)
                    Button("Add Apps…") { showingPicker = true }
                }
            } footer: {
                if folder.apps.count > 1 {
                    Text("Drag apps to rearrange them. They appear in this order in the Dock folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                FolderPopoverView(folder: folder, style: model.store.settings.popoverStyle, onLaunch: { _ in }, onEdit: {}, isPreview: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            } header: {
                HStack {
                    Text("Preview")
                    Spacer()
                    SettingsLink {
                        Text("\(model.store.settings.popoverStyle.title) Style…")
                    }
                    .help("Change how all folders open")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(folder.displayName)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let refs = urls.compactMap(AppRef.init(url:))
            guard !refs.isEmpty else { return false }
            model.edit(folder.id) { $0.add(refs) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .sheet(isPresented: $showingPicker) {
            AppPickerSheet(existingIDs: Set(folder.apps.map(\.id))) { refs in
                model.edit(folder.id) { $0.add(refs) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: IconRenderer.image(for: folder, size: 88))
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: binding(\.name), prompt: Text("Folder Name"))
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .labelsHidden()
                Text(model.isDocked(folder.id) ? "In your Dock" : "Not in the Dock")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if model.isDocked(folder.id) {
                    Button("Remove from Dock") { model.removeFromDock(folder.id) }
                } else {
                    Button("Add to Dock") { model.addToDock(folder.id) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Delete Folder…", role: .destructive, action: requestDelete)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<HarborFolder, Value>) -> Binding<Value> {
        Binding(
            get: { (model.store.folder(id: folder.id) ?? folder)[keyPath: keyPath] },
            set: { value in model.edit(folder.id) { $0[keyPath: keyPath] = value } }
        )
    }

    /// Laid out like the Dock popover (5 per row), so the arrangement here is what you'll see there.
    private var appGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(AppTile.size.width), spacing: 6), count: 5), alignment: .leading, spacing: 6) {
            ForEach(Array(folder.apps.enumerated()), id: \.element.id) { index, app in
                AppTile(app: app, isDragging: draggingID == app.id) { removeApp(app) }
                    .onDrag {
                        draggingID = app.id
                        return NSItemProvider(object: app.id as NSString)
                    }
                    .onDrop(of: [.text], delegate: ReorderDropDelegate(targetID: app.id, draggingID: $draggingID) { id, target in
                        moveApp(id, to: target)
                    })
                    .contextMenu {
                        Button("Move Left") { moveApp(app.id, by: -1) }.disabled(index == 0)
                        Button("Move Right") { moveApp(app.id, by: 1) }.disabled(index == folder.apps.count - 1)
                        Button("Show in Finder") {
                            if let url = app.resolvedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Divider()
                        Button("Remove from Folder") { removeApp(app) }
                    }
            }
        }
        .padding(.vertical, 4)
        // A drag cancelled outside the window never reaches a drop delegate; clear it when the mouse comes back.
        .onHover { _ in draggingID = nil }
    }

    private func removeApp(_ app: AppRef) {
        model.edit(folder.id) { $0.apps.removeAll { $0.id == app.id } }
    }

    /// Moves an app into the position currently held by `target`.
    private func moveApp(_ id: String, to target: String) {
        model.edit(folder.id) { folder in
            guard let from = folder.apps.firstIndex(where: { $0.id == id }),
                  let to = folder.apps.firstIndex(where: { $0.id == target }), from != to else { return }
            folder.apps.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        }
    }

    private func moveApp(_ id: String, by delta: Int) {
        guard let index = folder.apps.firstIndex(where: { $0.id == id }),
              folder.apps.indices.contains(index + delta) else { return }
        moveApp(id, to: folder.apps[index + delta].id)
    }
}

/// Reorders live: as the dragged app passes over another, they swap places.
private struct ReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let move: (String, String) -> Void

    /// Only rearranging drags; apps dragged in from Finder fall through to the editor's own drop target.
    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        withAnimation(.snappy(duration: 0.2)) { move(draggingID, targetID) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private struct AppTile: View {
    static let size = CGSize(width: 86, height: 96)

    let app: AppRef
    let isDragging: Bool
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .opacity(app.resolvedURL == nil ? 0.4 : 1)
            Text(app.resolvedURL == nil ? "\(app.name) (missing)" : app.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.primary.opacity(hovering ? 0.06 : 0), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            if hovering && !isDragging {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .help("Remove from folder")
                .offset(x: 4, y: 2)
            }
        }
        .opacity(isDragging ? 0.3 : 1)
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}

private struct ColorSwatches: View {
    @Binding var hex: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FolderPalette.presets) { color in
                let selected = color.hex.caseInsensitiveCompare(hex) == .orderedSame
                Button { hex = color.hex } label: {
                    Circle()
                        .fill(Color(hex: color.hex).gradient)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color(hex: color.hex), lineWidth: 2).opacity(selected ? 1 : 0))
                }
                .buttonStyle(.plain)
                .help(color.name)
            }
            Divider().frame(height: 22)
            ColorPicker("Custom Color", selection: Binding(
                get: { Color(hex: hex) },
                set: { hex = NSColor($0).hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Custom color")
            Spacer()
        }
    }
}

private struct SymbolGrid: View {
    @Binding var selection: String
    let tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 6)], spacing: 6) {
            ForEach(SymbolCatalog.available, id: \.self) { name in
                let selected = name == selection
                Button { selection = name } label: {
                    Image(systemName: name)
                        .font(.system(size: 16))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.05)),
                            in: .rect(cornerRadius: 9, style: .continuous)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
        .padding(.vertical, 4)
    }
}
