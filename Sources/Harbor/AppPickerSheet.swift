import HarborKit
import SwiftUI

/// Lists installed apps with checkboxes so several can be added at once.
struct AppPickerSheet: View {
    let existingIDs: Set<String>
    let onAdd: ([AppRef]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [AppRef]?
    @State private var query = ""
    @State private var chosen: [String: AppRef] = [:]

    private var filtered: [AppRef] {
        let all = apps ?? []
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Applications", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .padding(12)

            Divider()

            Group {
                if apps == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { app in
                        let alreadyAdded = existingIDs.contains(app.id)
                        Toggle(isOn: Binding(
                            get: { alreadyAdded || chosen[app.id] != nil },
                            set: { chosen[app.id] = $0 ? app : nil }
                        )) {
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
                                Text(app.name)
                                if alreadyAdded {
                                    Text("Added").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(alreadyAdded)
                    }
                }
            }

            Divider()

            HStack {
                Text(chosen.isEmpty ? "" : "\(chosen.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let order = apps ?? []
                    onAdd(order.filter { chosen[$0.id] != nil })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
        .task { apps = await AppCatalog.installedApps() }
    }
}
