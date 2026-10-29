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

struct DiskMapView: View {
    @EnvironmentObject var store: FileStore
    @State private var root: DiskNode?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Disk Map").font(FileRadarFont.title()).padding(.horizontal)
            Text("Each rectangle is a folder, sized by how much space it takes. Bigger rectangles, bigger footprint.")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary).padding(.horizontal)
            if let root {
                TreemapView(node: root)
            } else {
                EmptyStateView(title: "Disk map not built yet",
                               message: "Tap Build disk map to size up your indexed folders. Nothing is moved or deleted.")
                Button("Build disk map") { root = buildTree() }.padding()
            }
        }
    }

    private func buildTree() -> DiskNode {
        // One level deep by top folder + kind, so the map stays legible.
        // A full recursive treemap is a straightforward extension of this node tree.
        let byFolder = Dictionary(grouping: store.files) { $0.url.deletingLastPathComponent().lastPathComponent }
        let children = byFolder.map { name, files in
            DiskNode(name: name, url: files.first?.url.deletingLastPathComponent(),
                     size: files.reduce(0) { $0 + $1.size },
                     children: [], isFile: false)
        }.sorted { $0.size > $1.size }
        return DiskNode(name: "Indexed files", url: nil,
                        size: children.reduce(0) { $0 + $1.size }, children: children, isFile: false)
    }
}

/// Simple proportional treemap: children laid out as rows whose widths are
/// proportional to size. Deliberately simple and legible over a fancy
/// squarified layout that is hard to read on first sight.
struct TreemapView: View {
    var node: DiskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(node.children) { child in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(width: max(40, 300 * CGFloat(child.size) / CGFloat(max(node.size, 1))), height: 44)
                        .overlay(Text(child.name).font(FileRadarFont.caption()).lineLimit(1).padding(4), alignment: .leading)
                    Text(ByteCountFormatter.string(fromByteCount: child.size, countStyle: .file))
                        .font(FileRadarFont.caption()).foregroundStyle(.secondary).padding(.leading, 8)
                }
                .accessibilityLabel("\(child.name), \(ByteCountFormatter.string(fromByteCount: child.size, countStyle: .file))")
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
                    let plan = RenameService.preview(files: Array(store.files.prefix(20)), pattern: pattern)
                    ForEach(plan, id: \.file.id) { item in
                        HStack { Text(item.file.name); Spacer(); Text(item.newName).foregroundStyle(.secondary) }
                    }
                    Text("Preview only shows the first 20 files. Collisions are refused, never overwritten.")
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
