import HarborKit
import SwiftUI

/// Harbor › Settings: how folders open from the Dock. Applies to every folder.
struct SettingsView: View {
    @Environment(HarborModel.self) private var model

    private var style: PopoverStyle { model.store.settings.popoverStyle }

    /// Your first folder with apps, or a sample made of built-in apps.
    private var previewFolder: HarborFolder {
        model.store.folders.first { !$0.apps.isEmpty } ?? Self.sampleFolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Folder Style")
                .font(.headline)
            HStack(spacing: 10) {
                ForEach(PopoverStyle.allCases, id: \.self) { option in
                    StyleCard(style: option, selected: option == style) {
                        var settings = model.store.settings
                        settings.popoverStyle = option
                        model.store.updateSettings(settings)
                    }
                }
            }
            Text(style.summary + " Applies to all folders.")
                .font(.callout)
                .foregroundStyle(.secondary)

            FolderPopoverView(folder: previewFolder, style: style, onLaunch: { _ in }, onEdit: {}, isPreview: true)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .bottom)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .animation(.snappy(duration: 0.2), value: style)
        }
        .padding(20)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let sampleFolder = HarborFolder(
        name: "Sample",
        symbol: "star.fill",
        apps: ["Safari", "Mail", "Calendar", "Notes", "Music", "Photos", "Maps"].compactMap { name in
            ["/Applications/\(name).app", "/System/Applications/\(name).app"]
                .lazy
                .compactMap { AppRef(url: URL(fileURLWithPath: $0)) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
    )
}

private struct StyleCard: View {
    let style: PopoverStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: style.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(height: 32)
                Text(style.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(selected ? 0.9 : 0.4), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
