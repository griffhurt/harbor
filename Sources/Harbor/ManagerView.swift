import HarborKit
import SwiftUI

struct ManagerView: View {
    @Environment(HarborModel.self) private var model
    @State private var pendingDelete: HarborFolder?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.store.folders) { folder in
                    FolderRow(folder: folder, docked: model.isDocked(folder.id))
                        .tag(folder.id)
                        .contextMenu {
                            if model.isDocked(folder.id) {
                                Button("Remove from Dock") { model.removeFromDock(folder.id) }
                            } else {
                                Button("Add to Dock") { model.addToDock(folder.id) }
                            }
                            Divider()
                            Button("Delete Folder…", role: .destructive) { pendingDelete = folder }
                        }
                }
                .onMove { model.store.move(fromOffsets: $0, toOffset: $1) }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            .onDeleteCommand {
                if let id = model.selection { pendingDelete = model.store.folder(id: id) }
            }
            .toolbar {
                ToolbarItem {
                    Button(action: model.createFolder) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .help("New Folder")
                }
                ToolbarItem {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Folder style and other settings")
                }
            }
        } detail: {
            if let id = model.selection, let folder = model.store.folder(id: id) {
                FolderEditorView(folder: folder, requestDelete: { pendingDelete = folder })
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Folder Selected", systemImage: "square.grid.2x2")
                } description: {
                    Text("Create a folder, give it a color and symbol, add apps, then put it in your Dock.")
                } actions: {
                    Button("New Folder", action: model.createFolder)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { folder in
            Button("Delete Folder", role: .destructive) { model.delete(folder.id) }
        } message: { _ in
            Text("The folder is removed from the Dock. The apps inside it are not affected.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct FolderRow: View {
    let folder: HarborFolder
    let docked: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconRenderer.image(for: folder, size: 32))
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.displayName)
                    .lineLimit(1)
                Text(folder.apps.count == 1 ? "1 app" : "\(folder.apps.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if docked {
                Image(systemName: "dock.rectangle")
                    .foregroundStyle(.secondary)
                    .help("In the Dock")
            }
        }
        .padding(.vertical, 2)
    }
}
