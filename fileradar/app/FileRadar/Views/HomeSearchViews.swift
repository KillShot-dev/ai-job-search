import SwiftUI
import AppKit

// MARK: - Home (principle 2: shelves + recents, one job)

struct HomeView: View {
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @State private var showLicense = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Home").font(FileRadarFont.title())
                if store.isIndexing {
                    Label("Indexing your files in the background…", systemImage: "arrow.triangle.2.circlepath")
                        .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("Recent").font(FileRadarFont.heading())
                    if store.recents.isEmpty {
                        EmptyStateView(title: "No recent files yet",
                                       message: "Once FileRadar finishes its first background index, your newest files will live here.")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(store.recents.prefix(20)) { file in
                                    FileCardView(file: file, size: store.cardSize)
                                }
                            }
                        }
                    }
                }
                ForEach(store.shelves, id: \.0) { kind, files in
                    if !files.isEmpty {
                        VStack(alignment: .leading) {
                            Text(kind.displayName).font(FileRadarFont.heading())
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(files.prefix(20)) { file in
                                        FileCardView(file: file, size: store.cardSize)
                                    }
                                }
                            }
                        }
                    }
                }
                // Downloaded From grouping (beat the brief: by source, not just by date).
                VStack(alignment: .leading) {
                    Text("Downloaded From").font(FileRadarFont.heading())
                    let groups = Dictionary(grouping: store.files) { $0.downloadSource.displayName }
                    ForEach(groups.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key)
                            Spacer()
                            Text("\(groups[key]?.count ?? 0) files").foregroundStyle(.secondary)
                        }
                        .font(FileRadarFont.body())
                    }
                }
                // Beat-extras teaser row (all on-device, all real views).
                VStack(alignment: .leading) {
                    Text("Smart Collections").font(FileRadarFont.heading())
                    ForEach(TagService.smartCollections(in: store.files), id: \.title) { col in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(col.title).font(FileRadarFont.body())
                                Text(col.explanation).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(col.files.count)").foregroundStyle(.secondary)
                        }
                    }
                }
                if !license.isUnlocked {
                    Button("Enter serial number to unlock the full version") { showLicense = true }
                }
            }.padding()
        }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }
}

// MARK: - Search (principle 5 + 6: chips animate in, read like sentences)

struct SearchView: View {
    @Binding var searchText: String
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @State private var parsed = ParsedQuery(chips: [], freeText: "")
    @State private var showSave = false
    @State private var showLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Search in plain words — try “images from last week over 100 MB”", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(FileRadarFont.body())
                    .accessibilityLabel("Search files")
                    .onChange(of: searchText) { _, new in
                        withAnimation(FileRadarMotion.chip) { parsed = SearchQueryParser.parse(new) }
                    }
                if !searchText.isEmpty {
                    Button("Save") {
                        if license.isAllowed(.savedSearches) { showSave = true }
                        else { showLicense = true }
                    }
                    .help(license.isUnlocked ? "Save this search" : "Saved searches are a full-version feature.")
                }
            }
            .padding(.horizontal)
            if !parsed.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(parsed.chips) { chip in
                        Text(chip.sentence)
                            .font(FileRadarFont.caption())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .accessibilityLabel("Filter: \(chip.sentence)")
                    }
                    Spacer()
                }.padding(.horizontal)
                if !parsed.sentence.isEmpty {
                    Text(parsed.sentence).font(FileRadarFont.caption()).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
            let results = store.search(parsed)
            if searchText.isEmpty {
                EmptyStateView(title: "Search everything, in plain words",
                               message: "Type a kind, a time, a size, or a source. FileRadar turns it into filters you can see — and searches file names, tags, and text inside files.")
            } else if results.isEmpty {
                EmptyStateView(title: "No files match",
                               message: "Try fewer words, or a different time or size. Nothing was changed or deleted.")
            } else {
                FileCollectionView(title: "\(results.count) result\(results.count == 1 ? "" : "s")", files: results)
            }
        }
        .sheet(isPresented: $showSave) { SaveSearchSheet(query: searchText) }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }
}

// MARK: - Shared empty state (principle 8: kind empty states)

struct EmptyStateView: View {
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(FileRadarFont.heading())
            Text(message).font(FileRadarFont.body()).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inspector (principle 3: hover inspector + full detail pane)
//
// Iteration 1: modular inspector — Preview, Info, Tags, and Permissions
// as collapsible modules in one inspector, replacing the previous flat
// section list. All previous detail content is kept (dimensions,
// duration, camera, download source, tags with explanations, recognised
// text with its paid-gated copy-all). Permissions is read-only display
// in this build; editing permissions is not built. The optional Git
// module appears only when Git badges are opted in (Settings, off by
// default) and is read-only.

struct InspectorView: View {
    var file: FileItem
    @EnvironmentObject var license: LicenseManager
    @AppStorage("gitBadgesEnabled") private var gitBadgesEnabled = false
    @State private var showLicense = false
    @State private var copied = false
    @State private var gitBadge: String?
    @State private var previewExpanded = true
    @State private var infoExpanded = true
    @State private var tagsExpanded = true
    @State private var permissionsExpanded = false
    @State private var gitExpanded = false

    var body: some View {
        Form {
            DisclosureGroup("Preview", isExpanded: $previewExpanded) {
                AsyncFileThumbnail(file: file, size: CGSize(width: 280, height: 180))
                    .frame(maxHeight: 220)
                if file.isICloudOnly {
                    Label("iCloud only — FileRadar will not download this file.", systemImage: "icloud")
                        .font(FileRadarFont.caption())
                }
            }
            DisclosureGroup("Info", isExpanded: $infoExpanded) {
                LabeledContent("Name", value: file.name)
                LabeledContent("Kind", value: file.kind.displayName)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                LabeledContent("Modified", value: file.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Added", value: file.createdDate.formatted(date: .abbreviated, time: .shortened))
                if let w = file.width, let h = file.height { LabeledContent("Dimensions", value: "\(w) × \(h)") }
                if let d = file.duration { LabeledContent("Duration", value: "\(Int(d / 60)):\(String(format: "%02d", Int(d) % 60))") }
                if let cam = file.cameraModel { LabeledContent("Camera", value: cam) }
                LabeledContent("Downloaded from", value: file.downloadSource.displayName)
            }
            DisclosureGroup("Tags", isExpanded: $tagsExpanded) {
                if file.tags.isEmpty {
                    Text("No automatic tags yet.").foregroundStyle(.secondary)
                }
                ForEach(file.tags) { tag in
                    VStack(alignment: .leading) {
                        Text(tag.name)
                        if let explanation = tag.explanation {
                            Text(explanation).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Text("Your tags").font(FileRadarFont.caption()).foregroundStyle(.secondary)
                ManualTagEditor(file: file)
            }
            DisclosureGroup("Permissions", isExpanded: $permissionsExpanded) {
                if let permissions = permissionText {
                    Text(permissions).font(FileRadarFont.body())
                } else {
                    Text("Permissions could not be read for this file.").foregroundStyle(.secondary)
                }
                Text("Shown read-only in this build; changing permissions is not offered here.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            if gitBadgesEnabled {
                DisclosureGroup("Git status", isExpanded: $gitExpanded) {
                    if let badge = gitBadge {
                        Text("Status: \(badge) — read-only; FileRadar never stages, commits, or resets.")
                            .font(FileRadarFont.body())
                    } else {
                        Text("Not in a Git working copy, or no changes for this file.")
                            .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    }
                }
                .onAppear { gitBadge = GitStatusService.badge(for: file.url) }
            }
            if let ocr = file.ocrText, !ocr.isEmpty {
                Section("Text in this file") {
                    Text(ocr).font(FileRadarFont.body()).lineLimit(10)
                    Button(copied ? "Copied" : "Copy all recognised text") {
                        if license.isAllowed(.ocrCopyAll) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ocr, forType: .string)
                            copied = true
                        } else { showLicense = true }
                    }
                    .help(license.isUnlocked ? "Copy the recognised text" : "Copy all recognised text is a full-version feature.")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }

    private var permissionText: String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path) else { return nil }
        var parts: [String] = []
        if let perms = attributes[.posixPermissions] as? NSNumber {
            parts.append("Permissions: \(String(perms.intValue, radix: 8))")
        }
        if let owner = attributes[.ownerAccountName] as? String {
            parts.append("Owner: \(owner)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
