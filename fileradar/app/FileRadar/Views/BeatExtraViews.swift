import SwiftUI

// MARK: - Timeline (principle 8: browsing as discovery; Agenda lesson: "when" is findable)

struct TimelineView: View {
    @EnvironmentObject var store: FileStore

    var body: some View {
        VStack(alignment: .leading) {
            Text("Timeline").font(FileRadarFont.title()).padding(.horizontal)
            let months = Dictionary(grouping: store.files) { monthKey(for: $0.createdDate) }
            if months.isEmpty {
                EmptyStateView(title: "Your timeline is empty",
                               message: "Once files are indexed, they will appear here grouped by month — a way to rediscover things by when they arrived.")
            } else {
                List(months.keys.sorted().reversed(), id: \.self) { key in
                    Section(key) {
                        ForEach(months[key] ?? []) { file in
                            HStack {
                                Image(systemName: file.kind.systemImage)
                                Text(file.name)
                                Spacer()
                                Text(file.createdDate, style: .date).foregroundStyle(.secondary)
                            }
                            .contextMenu { fileContextMenu(for: file) }
                        }
                    }
                }
            }
        }
    }

    private func monthKey(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: date)
    }
}

// MARK: - Disk Map treemap (beat-extra, on-device)
// Auto-builds on appear; storage breakdown bar by kind; clickable proportional rows.

struct DiskMapView: View {
    @Binding var destination: Destination
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var theme: ThemeSettings
    @State private var root: DiskNode?

    private var kindBreakdown: [(FileKind, Int64)] {
        let grouped = Dictionary(grouping: store.files, by: \.kind)
        return FileKind.allCases.compactMap { kind in
            guard let files = grouped[kind], !files.isEmpty else { return nil }
            return (kind, files.reduce(0) { $0 + $1.size })
        }.sorted { $0.1 > $1.1 }
    }

    private var totalBytes: Int64 {
        kindBreakdown.reduce(0) { $0 + $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disk Map").font(FileRadarFont.title()).padding(.horizontal)
            Text("Each bar is a folder, sized by how much space it takes. Bigger bars, bigger footprint. Tap a row to open that folder.")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary).padding(.horizontal)

            if totalBytes > 0 {
                storageBreakdownBar
                    .padding(.horizontal)
            }

            if let root {
                TreemapView(node: root) { child in
                    if let url = child.url {
                        if !store.pinnedFolderURLs.contains(url) {
                            store.pinnedFolderURLs.append(url)
                        }
                        withAnimation(FileRadarMotion.panel) {
                            destination = .pinned(url)
                        }
                    }
                }
            } else if store.files.isEmpty {
                EmptyStateView(title: "Nothing indexed yet",
                               message: "Add a folder to index, then the disk map builds itself. Nothing is moved or deleted.")
            } else {
                ProgressView("Building disk map…")
                    .padding()
            }
        }
        .task(id: store.files.count) {
            await rebuildAsync()
        }
    }

    private var storageBreakdownBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage by kind").font(FileRadarFont.heading())
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(kindBreakdown, id: \.0) { kind, bytes in
                        let fraction = CGFloat(bytes) / CGFloat(max(totalBytes, 1))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(theme.look.accent.opacity(0.25 + 0.55 * fraction))
                            .frame(width: max(4, geo.size.width * fraction))
                            .help("\(kind.displayName): \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                    }
                }
            }
            .frame(height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            FlowKindLegend(items: kindBreakdown, accent: theme.look.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func rebuildAsync() async {
        let snapshot = store.files
        guard !snapshot.isEmpty else {
            root = nil
            return
        }
        let tree = await Task.detached(priority: .utility) {
            Self.buildTree(from: snapshot)
        }.value
        root = tree
    }

    nonisolated private static func buildTree(from files: [FileItem]) -> DiskNode {
        let byFolder = Dictionary(grouping: files) { $0.url.deletingLastPathComponent().lastPathComponent }
        let children = byFolder.map { name, files in
            DiskNode(name: name, url: files.first?.url.deletingLastPathComponent(),
                     size: files.reduce(0) { $0 + $1.size },
                     children: [], isFile: false)
        }.sorted { $0.size > $1.size }
        return DiskNode(name: "Indexed files", url: nil,
                        size: children.reduce(0) { $0 + $1.size }, children: children, isFile: false)
    }
}

private struct FlowKindLegend: View {
    var items: [(FileKind, Int64)]
    var accent: Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items.prefix(6), id: \.0) { kind, bytes in
                HStack(spacing: 4) {
                    Circle().fill(accent.opacity(0.55)).frame(width: 8, height: 8)
                    Text("\(kind.displayName) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                        .font(FileRadarFont.caption())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Simple proportional treemap: children laid out as rows whose widths are
/// proportional to size. Rows are buttons — tap opens that folder below.
struct TreemapView: View {
    var node: DiskNode
    var onSelect: (DiskNode) -> Void = { _ in }
    @EnvironmentObject var theme: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(node.children) { child in
                Button {
                    onSelect(child)
                } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: theme.look.cardCorner / 2, style: .continuous)
                            .fill(theme.look.accent.opacity(0.35))
                            .frame(width: max(40, 320 * CGFloat(child.size) / CGFloat(max(node.size, 1))), height: 44)
                            .overlay(
                                Text(child.name)
                                    .font(FileRadarFont.caption())
                                    .lineLimit(1)
                                    .padding(4),
                                alignment: .leading
                            )
                        Text(ByteCountFormatter.string(fromByteCount: child.size, countStyle: .file))
                            .font(FileRadarFont.caption())
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(child.name), \(ByteCountFormatter.string(fromByteCount: child.size, countStyle: .file))")
                .accessibilityHint("Shows files in this folder.")
            }
            if node.children.isEmpty {
                Text("No folders to map yet.").foregroundStyle(.secondary)
            }
        }.padding()
    }
}

// MARK: - Rename, Parcel, Health, Forecast, Version Stacks (beat-extras)

struct ExtrasView: View {
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @State private var pattern = "{name} {n}"
    @State private var showLicense = false

    var body: some View {
        Form {
            Section("Batch rename") {
                if !license.isAllowed(.batchRename) {
                    LockedFeatureView(feature: .batchRename) { showLicense = true }
                } else {
                    TextField("Pattern — {name}, {n}, {date}", text: $pattern)
                    let selected = store.files.filter { store.selectedIDs.contains($0.id) }
                    let targets = selected.isEmpty ? Array(store.files.prefix(20)) : selected
                    let plan = RenameService.preview(files: targets, pattern: pattern)
                    ForEach(plan, id: \.file.id) { item in
                        HStack { Text(item.file.name); Spacer(); Text(item.newName).foregroundStyle(.secondary) }
                    }
                    Button("Apply Rename") {
                        let refused = RenameService.apply(plan)
                        let refusedIDs = Set(refused.map(\.id))
                        for (file, newName) in plan where !refusedIDs.contains(file.id) {
                            let dest = file.url.deletingLastPathComponent().appendingPathComponent(newName)
                            store.updateFileURL(from: file.url, to: dest)
                        }
                    }
                    .disabled(plan.allSatisfy { $0.newName == $0.file.name })
                    Text(selected.isEmpty
                          ? "No selection — preview shows the first 20 files. Collisions are refused, never overwritten."
                          : "Applying renames the current selection. Collisions are refused, never overwritten.")
                        .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                }
            }
            Section("Storage forecast (estimate)") {
                let f = ForecastService.forecast(files: store.files)
                LabeledContent("Added per day (last 90 days)", value: ByteCountFormatter.string(fromByteCount: f.dailyBytes, countStyle: .file))
                LabeledContent("In 30 days", value: ByteCountFormatter.string(fromByteCount: f.in30Days, countStyle: .file))
                LabeledContent("In 90 days", value: ByteCountFormatter.string(fromByteCount: f.in90Days, countStyle: .file))
                Text("This is a simple average, not a prediction.").font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Section("File health") {
                let issues = HealthCheckService.check(files: store.files)
                if issues.isEmpty { Text("No empty or legacy-format files found.").foregroundStyle(.secondary) }
                ForEach(issues) { issue in
                    VStack(alignment: .leading) {
                        Text(issue.file.name)
                        Text("\(issue.kind.rawValue) — \(issue.suggestion)").font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Version stacks") {
                let stacks = VersionStackService.stacks(for: store.files)
                if stacks.isEmpty { Text("No versioned groups found (look for v1, v2, final in file names).").foregroundStyle(.secondary) }
                ForEach(stacks) { stack in
                    VStack(alignment: .leading) {
                        Text(stack.baseName).font(FileRadarFont.heading())
                        ForEach(stack.files) { Text($0.name).font(FileRadarFont.body()) }
                    }
                }
            }
            Section("Parcel export") {
                if !license.isAllowed(.parcelExport) {
                    LockedFeatureView(feature: .parcelExport) { showLicense = true }
                } else {
                    Text("Pack the current selection into a zip plus a JSON manifest (names, sizes, dates, download sources). Symlinks and iCloud-only files are skipped.")
                        .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    Button("Export selected files as Parcel…") {
                        let selected = store.files.filter { store.selectedIDs.contains($0.id) }
                        guard !selected.isEmpty else { return }
                        ParcelExportUI.export(files: selected, license: license)
                    }
                    .disabled(store.selectedIDs.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }
}
