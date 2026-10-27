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
    @State private var query = ""
    @State private var parsed = ParsedQuery(chips: [], freeText: "")

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Quick Search — type in plain words", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, new in
                    withAnimation(FileRadarMotion.chip) { parsed = SearchQueryParser.parse(new) }
                }
            if !parsed.chips.isEmpty {
                HStack { ForEach(parsed.chips) { chip in
                    Text(chip.sentence).font(FileRadarFont.caption())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                } }
            }
            Text("Quick Search is a full-version feature. In demo mode, use Search in the main window.")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            Spacer()
        }.padding()
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

    private var channel: DistributionChannel { DistributionChannel.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Unlock FileRadar").font(FileRadarFont.heading())
            Text(subtitle)
                .font(FileRadarFont.body()).foregroundStyle(.secondary)

            if license.isUnlocked {
                statusBanner
            }

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
                Text("The free trial has ended. Enter a serial or buy on the App Store to keep using paid features.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }

            Text("Support: support@metaphasic.net").font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 480)
        .onAppear {
            Task { await storeKit.refresh() }
            trial.refresh()
            license.refreshEntitlements()
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
            Button("Done") { dismiss() }
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
                Text("App Store products are not available in this build yet. Configure FRStoreKitProductID in Info.plist and the product in App Store Connect.")
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
    @State private var rules: [CleanupRule] = CleanupCardType.allCases.map { CleanupRule(type: $0) }
    @State private var updateStatus = ""
    @State private var showLicense = false

    var body: some View {
        Form {
            Section("Look") {
                Picker("Look", selection: $theme.look) {
                    ForEach(AppLook.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Use system appearance", isOn: $theme.useSystemAppearance)
                if !theme.useSystemAppearance {
                    Toggle("Dark appearance", isOn: $theme.forceDark)
                }
                Toggle("Compact density", isOn: $theme.compactDensity)
                Text("Both looks use one type scale and one accent system, in light and dark. Compact tightens sidebar and grid spacing.")
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
                    Text(rule.type.explanation).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                }
                Text("Rules only ever move files to Trash, never delete them.")
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
                    Text("Muse is connected.")
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
                Button("Delete chat history") {
                    ChatHistoryStore.deleteHistoryFile()
                    NotificationCenter.default.post(name: .museChatHistoryDeleted, object: nil)
                }
                Text("Logging out removes Muse sign-in tokens only. Chat history is kept until you delete it.")
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
        .frame(width: 540, height: 620)
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }
}
