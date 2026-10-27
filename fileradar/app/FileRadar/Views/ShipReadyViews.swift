import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Column browser (Finder-style, keyboard-friendly)

/// Optional third view mode: Miller columns. One job — browse a folder
/// hierarchy by columns. Does not replace shelves/search as the default.
struct ColumnBrowserView: View {
    var rootFiles: [FileItem]
    @EnvironmentObject var store: FileStore
    @State private var path: [URL] = []
    @State private var columnSelections: [String?] = [nil]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Columns").font(FileRadarFont.title()).padding([.horizontal, .top])
            Text("Arrow keys move; Return opens; Space Quick Looks.")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                .padding(.horizontal).padding(.bottom, 8)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    column(files: rootSorted, index: 0)
                    ForEach(Array(path.enumerated()), id: \.offset) { idx, folder in
                        column(files: children(of: folder), index: idx + 1)
                    }
                }
            }
        }
    }

    private var rootSorted: [FileItem] { store.sorted(rootFiles) }

    private func children(of folder: URL) -> [FileItem] {
        store.sorted(store.files.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
        })
    }

    @ViewBuilder
    private func column(files: [FileItem], index: Int) -> some View {
        List(files, id: \.id, selection: binding(for: index)) { file in
            HStack {
                Image(systemName: file.kind.systemImage)
                Text(file.name).lineLimit(1)
                Spacer()
                if file.kind == .folder {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .tag(file.id as String?)
            .contextMenu { fileContextMenu(for: file) }
            .onTapGesture(count: 2) {
                if file.kind == .folder {
                    drill(into: file.url, at: index)
                } else {
                    NSWorkspace.shared.open(file.url)
                }
            }
        }
        .frame(width: 240)
        .background(.background)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func binding(for index: Int) -> Binding<String?> {
        Binding(
            get: {
                if columnSelections.indices.contains(index) { return columnSelections[index] }
                return nil
            },
            set: { newValue in
                while columnSelections.count <= index { columnSelections.append(nil) }
                columnSelections[index] = newValue
                columnSelections = Array(columnSelections.prefix(index + 1))
                if let id = newValue,
                   let file = store.files.first(where: { $0.id == id }) {
                    store.selectedIDs = [file.id]
                    if file.kind == .folder {
                        drill(into: file.url, at: index)
                    } else {
                        path = Array(path.prefix(index))
                    }
                }
            }
        )
    }

    private func drill(into folder: URL, at index: Int) {
        path = Array(path.prefix(index)) + [folder]
        columnSelections = Array(columnSelections.prefix(index + 1)) + [nil]
    }
}

// MARK: - Async thumbnail image

struct AsyncFileThumbnail: View {
    var file: FileItem
    var size: CGSize
    @ObservedObject private var cache = ThumbnailCache.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.10))
            if file.kind == .image, !file.isICloudOnly, let image = cache.image(for: file.url) {
                Image(nsImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: file.kind.systemImage)
                    .font(.system(size: min(size.width, size.height) * 0.28, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            if file.kind == .image {
                cache.load(url: file.url, isICloudOnly: file.isICloudOnly)
            }
        }
    }
}

// MARK: - Manual tag editor (inspector module)

struct ManualTagEditor: View {
    var file: FileItem
    @EnvironmentObject var tags: ManualTagStore
    @State private var newName = ""
    @State private var color: TagColor = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tags.tags(for: file.url.path)) { tag in
                HStack {
                    Circle().fill(tagSwiftColor(tag.color)).frame(width: 8, height: 8)
                    Text(tag.name)
                    Spacer()
                    Button(role: .destructive) {
                        tags.remove(name: tag.name, from: file.url.path)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag \(tag.name)")
                }
            }
            HStack {
                TextField("Add tag", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Picker("Colour", selection: $color) {
                    ForEach(TagColor.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                Button("Add") { add() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        tags.add(name: newName, color: color, to: file.url.path)
        newName = ""
    }

    private func tagSwiftColor(_ c: TagColor) -> Color {
        switch c {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}

// MARK: - Save search sheet

struct SaveSearchSheet: View {
    var query: String
    @EnvironmentObject var saved: SavedSearchStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save this search").font(FileRadarFont.heading())
            Text(query).font(FileRadarFont.caption()).foregroundStyle(.secondary)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") {
                    saved.save(name: name, query: query)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(width: 360)
    }
}

// MARK: - Parcel export action

enum ParcelExportUI {
    @MainActor
    static func export(files: [FileItem], license: LicenseManager) {
        guard license.isAllowed(.parcelExport) else {
            NotificationCenter.default.post(name: .showLicenseSheet, object: nil)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "FileRadar-Parcel.zip"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ParcelExportService.export(files: files, to: url)
        } catch {
            // Generic only — never echo paths.
            let alert = NSAlert()
            alert.messageText = "Parcel export failed"
            alert.informativeText = "The selection could not be packed. Check that the files are still on disk and try again."
            alert.runModal()
        }
    }
}

extension Notification.Name {
    static let showLicenseSheet = Notification.Name("FileRadarShowLicenseSheet")
    static let applySavedSearch = Notification.Name("FileRadarApplySavedSearch")
    static let exportParcel = Notification.Name("FileRadarExportParcel")
}
