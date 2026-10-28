import SwiftUI
import AppKit

// MARK: - Menu bar extra

struct MenuBarExtraView: View {
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var theme: ThemeSettings
    @State private var showLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent downloads").font(FileRadarFont.heading())
            if !license.isAllowed(.menuBarExtras) {
                Text("Menu bar downloads are a full-version feature.")
                    .font(FileRadarFont.body()).foregroundStyle(.secondary)
                Button("Unlock") { showLicense = true }
            } else {
                let last10 = Array(store.downloads.prefix(10))
                if last10.isEmpty {
                    Text("No downloads indexed yet.").foregroundStyle(.secondary)
                }
                ForEach(last10) { file in
                    HStack {
                        AsyncFileThumbnail(file: file, size: CGSize(width: 32, height: 32))
                        VStack(alignment: .leading) {
                            Text(file.name).lineLimit(1)
                            Text("From \(file.downloadSource.displayName)").font(FileRadarFont.caption()).foregroundStyle(.secondary)
                        }
                    }
                    .onDrag { NSItemProvider(object: file.url as NSURL) }
                    .contextMenu { fileContextMenu(for: file) }
                }
            }
            Divider()
            Button("Open FileRadar") { NSApp.activate(ignoringOtherApps: true) }
            Button("Support: support@metaphasic.net") {
                if let url = URL(string: "mailto:support@metaphasic.net") {
                    NSWorkspace.shared.open(url)
                }
            }
            .sheet(isPresented: $showLicense) { LicenseEntryView() }
        }
        .padding()
        .frame(width: 320)
        .tint(theme.look.accent)
    }
}

// MARK: - Quick Search panel content

struct QuickSearchPanelView: View {
    var store: FileStore?
    var license: LicenseManager?
    @State private var query = ""
    @State private var parsed = ParsedQuery(chips: [], freeText: "")

    private var results: [FileItem] {
        guard let store, license?.isAllowed(.quickSearch) == true else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return Array(store.search(parsed).prefix(40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
                TextField("Quick Search — type in plain words", text: $query)
                    .textFieldStyle(.plain)
                    .font(FileRadarFont.heading())
                    .onChange(of: query) { _, new in
                        withAnimation(FileRadarMotion.chip) { parsed = SearchQueryParser.parse(new) }
                    }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            if !parsed.chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(parsed.chips) { chip in
                        Text(chip.sentence).font(FileRadarFont.caption())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            if license?.isAllowed(.quickSearch) != true {
                Text("Quick Search is a full-version feature. Unlock to search from this panel.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            } else if query.isEmpty {
                Text("Results appear as you type.").font(FileRadarFont.caption()).foregroundStyle(.secondary)
            } else if results.isEmpty {
                Text("No matches.").font(FileRadarFont.caption()).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(results) { file in
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: file.kind.systemImage)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name).font(FileRadarFont.body()).lineLimit(1)
                                        Text(file.url.deletingLastPathComponent().lastPathComponent)
                                            .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                        .font(FileRadarFont.caption()).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Licence / purchase / trial hub

struct LicenseEntryView: View {
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var storeKit: StoreKitLicense
    @EnvironmentObject var trial: TrialManager
    @Environment(\.dismiss) var dismiss
    @State private var serial = ""
    @State private var error: String?
    @State private var trialBusy = false

    private var channel: DistributionChannel { DistributionChannel.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Unlock FileRadar").font(FileRadarFont.heading())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("licenseClose")
            }
            Text(subtitle)
                .font(FileRadarFont.body()).foregroundStyle(.secondary)

            if license.isUnlocked {
                statusBanner
            }

            // Always-available escape hatches — empty StoreKit / MAS / expired
            // trial must never trap the user on this sheet.
            escapeHatches

            if channel == .macAppStore || storeKit.product != nil {
                storeKitSection
                if channel == .direct {
                    Divider()
                    Text("Or unlock with a website serial").font(FileRadarFont.caption()).foregroundStyle(.secondary)
                }
            }

            if channel == .direct {
                serialSection
            }

            if !license.isUnlocked, trial.isActive {
                Text("Your free trial is active (\(trial.daysRemaining) day\(trial.daysRemaining == 1 ? "" : "s") left). Paid features are unlocked until it ends.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            } else if !license.isUnlocked, !trial.isActive {
                Text(channel == .macAppStore
                     ? "The free trial has ended. Buy on the App Store to keep using paid features, or continue with free browsing."
                     : "The free trial has ended. Enter a serial, buy on the App Store, or continue with free browsing.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }

            Text("Support: support@metaphasic.net").font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 480)
        .onAppear {
            Task {
                await storeKit.refresh()
                await trial.refresh()
                await license.refreshEntitlementsAsync()
                // Debug / Apple Development: never leave this sheet as a wall.
                if LocalDevBuild.isActive, license.isUnlocked {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var escapeHatches: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    Task {
                        trialBusy = true
                        defer { trialBusy = false }
                        _ = await trial.startTrial(restartIfExpired: true)
                        await license.refreshEntitlementsAsync()
                        dismiss()
                    }
                } label: {
                    Text(trialBusy ? "Starting…" : "Continue with Trial")
                }
                .buttonStyle(.borderedProminent)
                .disabled(trialBusy)
                .accessibilityLabel("Continue with Trial")
                .accessibilityIdentifier("continueTrial")

                Button {
                    dismiss()
                } label: {
                    Text("Use Free Features")
                }
                .accessibilityLabel("Use Free Features")
                .accessibilityIdentifier("useFreeFeatures")

                Button {
                    dismiss()
                } label: {
                    Text("Skip for now")
                }
                .accessibilityLabel("Skip for now")
                .accessibilityIdentifier("skipLicense")
            }
            if storeKit.product == nil, channel == .macAppStore {
                Text("App Store products are not loaded in this build. You can still continue with Trial or free features — you are not blocked.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        switch channel {
        case .macAppStore:
            return "Buy once through the Mac App Store. Purchases restore on any Mac signed into the same Apple ID. No serial numbers."
        case .direct:
            return "Website serials use format FR-XXXX-XXXX-XXXX-XXXX. Serials live in the Keychain on this Mac. Optional server confirmation runs only when FRLicensingBaseURL is configured."
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("Full version unlocked")
                if let message = license.statusMessage {
                    Text(message).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                } else {
                    Text(sourceLabel).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .accessibilityLabel("Done")
            .accessibilityIdentifier("licenseDone")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
    }

    private var sourceLabel: String {
        switch license.source {
        case .storeKit: return "Mac App Store purchase"
        case .serial: return "Serial on this Mac"
        case .trial: return "Free trial"
        case .none: return ""
        }
    }

    @ViewBuilder
    private var storeKitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let product = storeKit.product {
                Text(product.displayName).font(FileRadarFont.body())
                Text(product.description).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                HStack {
                    Button(storeKit.isLoading ? "Working…" : "Buy \(product.displayPrice)") {
                        Task {
                            await storeKit.purchase()
                            license.refreshEntitlements()
                            if license.isUnlocked { dismiss() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storeKit.isLoading || storeKit.isEntitled)
                    Button("Restore Purchases") {
                        Task {
                            await storeKit.restore()
                            license.refreshEntitlements()
                            if license.isUnlocked { dismiss() }
                        }
                    }
                    .disabled(storeKit.isLoading)
                }
            } else {
                Text("App Store products are not available in this build yet. Use Continue with Trial or Skip above — do not wait on an empty catalog.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                Button("Refresh Store") {
                    Task { await storeKit.refresh() }
                }
            }
            if let err = storeKit.lastError {
                Text(err).foregroundStyle(.red).font(FileRadarFont.caption())
            }
        }
    }

    @ViewBuilder
    private var serialSection: some View {
        TextField("FR-XXXX-XXXX-XXXX-XXXX", text: $serial)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .onSubmit { Task { await activate() } }
        if let error { Text(error).foregroundStyle(.red).font(FileRadarFont.body()) }
        if let message = license.statusMessage, !license.isUnlocked {
            Text(message).font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        HStack {
            Button(license.isBusy ? "Checking…" : "Activate") {
                Task { await activate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serial.trimmingCharacters(in: .whitespaces).isEmpty || license.isBusy)
            Button("Cancel") { dismiss() }
            Spacer()
            if license.source == .serial {
                Button("Deactivate (move to another Mac)") {
                    license.deactivate()
                    dismiss()
                }
            }
        }
    }

    private func activate() async {
        if await license.activateOnline(serial) {
            dismiss()
        } else {
            error = license.statusMessage ?? "That serial number did not check out. Please check it and try again."
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var museAuth: MuseAuthService
    @EnvironmentObject var storeKit: StoreKitLicense
    @EnvironmentObject var trial: TrialManager
    @AppStorage("gitBadgesEnabled") private var gitBadgesEnabled = false
    @State private var rules: [CleanupRule] = CleanupRulesStore.load()
    @State private var museAPIKey = ""
    @State private var updateStatus = ""
    @State private var showLicense = false

    var body: some View {
        Form {
            Section("Look & Style") {
                Picker("Look", selection: $theme.look) {
                    ForEach(AppLook.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Appearance", selection: $theme.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Compact density", isOn: $theme.compactDensity)
                Text("Four looks share one type scale and one accent system, each in System, Light, or Dark. Compact tightens sidebar and grid spacing. Cycle looks with Shift-Cmd-L.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Section("Quick Search") {
                Text("Default shortcut: Shift-Command-Space. The in-app CommandMenu shortcut always works; the global hotkey needs Input Monitoring permission.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Section("Power features") {
                Toggle("Git status badges in the inspector (read-only, opt-in)", isOn: $gitBadgesEnabled)
                Text("When on, the inspector shows a one-letter Git status for the selected file. FileRadar never stages, commits, or resets.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Section("Automatic clean-up rules (all off by default)") {
                ForEach($rules) { $rule in
                    Toggle(rule.type.rawValue, isOn: $rule.isEnabled)
                        .onChange(of: rule.isEnabled) { _, _ in CleanupRulesStore.save(rules) }
                    Text(rule.type.explanation).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                }
                Text("Rules only ever move files to Trash, never delete them. Preferences persist in UserDefaults.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("FileRadar indexes on-device. Nothing is uploaded for licensing. Muse chat (optional) sends only messages and metadata you approve to the configured HTTPS Model API — never file contents or OCR text. iCloud-only files are never downloaded.")
                    .font(FileRadarFont.body())
            }
            Section("Licence") {
                Text("Channel: \(DistributionChannel.current == .macAppStore ? "Mac App Store" : "Direct / website")")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                if license.isUnlocked {
                    Text("Full version unlocked (\(license.source.rawValue)).")
                    if let message = license.statusMessage {
                        Text(message).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    }
                    if license.source == .serial {
                        Button("Deactivate (move to another Mac)") { license.deactivate() }
                    }
                    if license.source == .storeKit {
                        Button("Refresh App Store entitlement") {
                            Task {
                                await storeKit.refresh()
                                license.refreshEntitlements()
                            }
                        }
                    }
                } else {
                    Text("Demo / locked: browse, search, and preview. Trial days left: \(trial.isActive ? "\(trial.daysRemaining)" : "0").")
                    Button("Unlock…") { showLicense = true }
                }
            }
            Section("Muse") {
                if museAuth.isConnected {
                    Text(museAuth.apiKeyConfigured()
                         ? "Muse is connected via API key."
                         : "Muse is connected.")
                    Button("Log out of Muse") {
                        Task { await museAuth.logout() }
                    }
                } else {
                    Text("Muse is not connected.")
                    if museAuth.isConnecting {
                        ProgressView("Connecting…")
                    } else {
                        Button("Connect Muse") {
                            Task { await museAuth.connect() }
                        }
                    }
                }
                if museAuth.lastError != nil {
                    Text("Connection failed. Please try again.")
                        .font(FileRadarFont.caption()).foregroundStyle(.red)
                }
                SecureField("API key (optional fallback)", text: $museAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveMuseAPIKey() }
                HStack {
                    Button("Save API key") { saveMuseAPIKey() }
                        .disabled(museAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if museAuth.apiKeyConfigured() {
                        Button("Clear API key") {
                            _ = museAuth.setAPIKey(nil)
                            museAPIKey = ""
                        }
                    }
                }
                Text("Prefer Connect for OAuth. An API key is a Keychain-only fallback when OAuth is unavailable. Never paste secrets into tickets or logs.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                Button("Delete chat history") {
                    ChatHistoryStore.deleteHistoryFile()
                    NotificationCenter.default.post(name: .museChatHistoryDeleted, object: nil)
                }
                Text("Logging out removes Muse sign-in tokens only. Chat history is kept until you delete it. Clearing the API key is separate.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Button("Check for updates") {
                    Task { updateStatus = await UpdateService.checkForUpdates() }
                }
                if !updateStatus.isEmpty { Text(updateStatus).font(FileRadarFont.caption()).foregroundStyle(.secondary) }
                Text("Automatic updates are not built into this version. MAS builds update through the App Store; direct builds need Sparkle later.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Section("Support") {
                Text("support@metaphasic.net").font(FileRadarFont.body())
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }

    private func saveMuseAPIKey() {
        if museAuth.setAPIKey(museAPIKey) {
            museAPIKey = ""
        }
    }
}
