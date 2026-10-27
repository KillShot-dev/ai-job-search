import SwiftUI
import Foundation

// MARK: - Muse chat UI (FileRadar + Muse integration)
//
// Wiring (see ContentView + FileRadarApp for the other half):
//   * ContentView creates ONE ChatViewModel in .onAppear and keeps it in
//     @State; it is never recreated per render. ContentView also updates
//     the view model's folder context whenever the destination changes,
//     and passes a Binding<Destination> so show-in-FileRadar navigation
//     (tool service onShowFile) can change the destination through state
//     storage rather than through a stale View-struct copy.
//   * FileRadarApp owns the Muse services: auth and voice as
//     @StateObjects injected as environment objects, and the client as
//     a plain let passed to ContentView's init (MuseClient is not an
//     ObservableObject, so StateObject/environmentObject cannot hold
//     it). ContentView sets client.tokenProvider once, to a closure
//     calling auth.validAccessToken().
//   * License gating uses LicenseManager.isUnlocked (the exact licensed
//     flag in Services/LicenseManager.swift; isAllowed(_:) returns the
//     same value). The closure is evaluated by FileRadarToolService at
//     tool-execution time, so a licence change takes effect without a
//     rebuild of this view.
//   * This file is UI + wiring only. It contains no keys, no endpoints
//     and no tokens, and it never logs a token. Errors shown to the user
//     are generic on purpose.
//   * Never compiled on a Mac and never run against a live Model API;
//     see the coordinator's integration notes for what remains untested.
//
// Sibling-contract assumptions (flagged for the coordinator to confirm
// against the sibling files when they land):
//   * ChatMessage has a memberwise-style initializer taking role,
//     content, toolCalls and toolCallId, with an auto-generated id, and
//     its content/toolCalls properties are mutable (streaming appends
//     tokens to the last assistant message and records its tool calls).
//   * ChatRole cases are .system, .user, .assistant and .tool.
//   * MuseConfig.placeholder is a MuseConfig (used by FileRadarApp only
//     when MuseConfig.load() throws).
//   * MuseAuthService, MuseClient and VoiceService have no-argument
//     initializers except MuseClient.init(config:).

extension Notification.Name {
    /// Posted when chat history is deleted from Settings, so an open
    /// chat view clears its in-memory transcript too.
    static let museChatHistoryDeleted = Notification.Name("museChatHistoryDeleted")
}

/// Codable snapshot of one transcript entry. ChatMessage itself is a
/// sibling type and is not assumed to be Codable, so history is stored
/// through this shape and mapped back on load. Role strings are the
/// ChatRole case names ("system", "user", "assistant", "tool").
struct MuseChatHistoryEntry: Codable {
    var role: String
    var content: String
    var toolCallId: String?
}

/// Local history storage only: Application Support/MuseChat/history.json.
/// No transcript is ever sent anywhere except as model input when the
/// user sends a message (plus the optional, default-off folder context).
enum ChatHistoryStore {
    static var historyURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MuseChat", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func load() -> [MuseChatHistoryEntry] {
        guard let url = historyURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([MuseChatHistoryEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func save(_ entries: [MuseChatHistoryEntry]) {
        guard let url = historyURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: [.atomic])
        } catch {
            // History is a convenience, not the conversation itself: a
            // failed save must never surface as a chat error.
        }
    }

    /// Removes the saved history file. Does not touch sign-in tokens.
    static func deleteHistoryFile() {
        guard let url = historyURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - View model

/// One job: run a Muse conversation with at most 5 tool rounds.
///
/// Tool flow per round: stream -> execute returned tool calls one at a
/// time -> a needsApproval result pauses the loop and shows an approval
/// card; Approve runs the action, Deny records a cancellation, and the
/// loop then continues with the next round. Destructive actions only
/// ever run after Approve, because FileRadarToolService itself returns
/// needsApproval instead of executing them.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var pendingAction: PendingToolAction?
    @Published var shareCurrentFolder = false
    @Published var speakReplies = false
    @Published private(set) var errorMessage: String?

    let auth: MuseAuthService
    let client: MuseClient
    let voice: VoiceService

    private let toolService: FileRadarToolService
    private let destination: Binding<Destination>
    private var contextTitle = ""
    private var contextFileNames: [String] = []
    private var streamTask: Task<Void, Never>?
    private var currentRunID = UUID()
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    init(store: FileStore,
         trash: TrashService,
         auth: MuseAuthService,
         client: MuseClient,
         voice: VoiceService,
         isLicensed: @escaping () -> Bool,
         destination: Binding<Destination>,
         contextTitle: String,
         contextFileNames: [String]) {
        self.auth = auth
        self.client = client
        self.voice = voice
        self.destination = destination
        self.contextTitle = contextTitle
        self.contextFileNames = contextFileNames
        // showInFileRadar navigation: select the file and move to its
        // kind shelf, exactly as the task specifies.
        self.toolService = FileRadarToolService(
            store: store,
            trash: trash,
            isLicensed: isLicensed,
            onShowFile: { [destination] file in
                store.selectedIDs = [file.id]
                destination.wrappedValue = .kind(file.kind)
            })
        // Restore the saved transcript, if any.
        self.messages = ChatHistoryStore.load().compactMap { entry in
            let role: ChatRole
            switch entry.role {
            case "system": role = .system
            case "assistant": role = .assistant
            case "tool": role = .tool
            default: role = .user
            }
            return ChatMessage(role: role, content: entry.content,
                               toolCalls: [], toolCallId: entry.toolCallId)
        }
        // Mic transcripts become user messages (or draft input while a
        // reply is streaming, so speech is never silently dropped).
        voice.onTranscript = { [weak self] transcript in
            Task { @MainActor in self?.handleTranscript(transcript) }
        }
    }

    /// Called by ContentView whenever the destination changes, so the
    /// optional folder context always describes the current view.
    func updateContext(title: String, fileNames: [String]) {
        contextTitle = title
        contextFileNames = fileNames
    }

    // MARK: - Sending

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, auth.isConnected else { return }
        inputText = ""
        send(text)
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, auth.isConnected else { return }
        stop()
        append(ChatMessage(role: .user, content: trimmed, toolCalls: [], toolCallId: nil))
        runConversation()
    }

    private func handleTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isStreaming {
            inputText = inputText.isEmpty ? trimmed : inputText + " " + trimmed
        } else {
            send(trimmed)
        }
    }

    private func runConversation() {
        isStreaming = true
        errorMessage = nil
        let runID = UUID()
        currentRunID = runID
        streamTask = Task { [weak self] in
            guard let self else { return }
            // Build the request transcript once; tool results are appended
            // to both the visible transcript and this request list.
            var request: [ChatMessage] = []
            if self.shareCurrentFolder {
                // Names only, never file contents and never OCR text.
                // This context message goes to the model only; it is not
                // added to the visible transcript.
                let names = self.contextFileNames.prefix(50)
                let context = "Current FileRadar view: \(self.contextTitle). "
                    + "File names in this view (names only): "
                    + names.joined(separator: ", ")
                request.append(ChatMessage(role: .system, content: context,
                                           toolCalls: [], toolCallId: nil))
            }
            request.append(contentsOf: self.messages)

            var finalReply = ""
            for _ in 1...5 {
                if Task.isCancelled { break }
                // Streaming assistant message, appended to live.
                self.append(ChatMessage(role: .assistant, content: "",
                                        toolCalls: [], toolCallId: nil))
                let assistantIndex = self.messages.count - 1
                do {
                    let toolCalls = try await self.client.stream(
                        messages: request,
                        tools: self.toolService.toolSchemas,
                        onToken: { [weak self] token in
                            Task { @MainActor in
                                guard let self, assistantIndex < self.messages.count else { return }
                                self.messages[assistantIndex].content += token
                            }
                        })
                    self.messages[assistantIndex].toolCalls = toolCalls
                    request.append(self.messages[assistantIndex])
                    finalReply = self.messages[assistantIndex].content
                    guard !toolCalls.isEmpty else { break }
                    // Execute tool calls sequentially, in order.
                    var shouldContinue = true
                    for call in toolCalls {
                        if Task.isCancelled { shouldContinue = false; break }
                        let result = await self.execute(call: call, request: &request)
                        if result == nil { shouldContinue = false; break }
                    }
                    if !shouldContinue { break }
                } catch {
                    // Generic error only: never surface transport or
                    // service detail (which could mention configuration).
                    self.errorMessage = "Something went wrong. Please try again."
                    break
                }
            }
            // Only the newest run may clear streaming state: an older
            // run resumed by stop() must not cancel a new conversation.
            if self.currentRunID == runID {
                self.isStreaming = false
                self.streamTask = nil
            }
            if !finalReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               self.speakReplies, self.currentRunID == runID, !Task.isCancelled {
                self.voice.speak(finalReply)
            }
        }
    }

    /// Executes one tool call and appends its result as a tool message.
    /// Returns nil when the loop must stop (user stopped mid-approval).
    private func execute(call: ToolCall, request: inout [ChatMessage]) async -> Bool? {
        let result = await toolService.execute(call: call)
        switch result {
        case .completed(let text), .locked(let text), .failed(let text):
            let message = ChatMessage(role: .tool, content: text,
                                      toolCalls: [], toolCallId: call.id)
            append(message)
            request.append(message)
            return true
        case .needsApproval(let action):
            pendingAction = action
            let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                approvalContinuation = continuation
            }
            pendingAction = nil
            approvalContinuation = nil
            if Task.isCancelled { return nil }
            let text: String
            if approved {
                text = await toolService.approve(action: action)
            } else {
                text = await toolService.deny(action: action)
            }
            let message = ChatMessage(role: .tool, content: text,
                                      toolCalls: [], toolCallId: call.id)
            append(message)
            request.append(message)
            return true
        }
    }

    func approvePending() {
        approvalContinuation?.resume(returning: true)
        approvalContinuation = nil
    }

    func denyPending() {
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    /// Cancels the streaming task, stops speech, and releases a paused
    /// approval wait (treated as a denial of the pending card's wait;
    /// the card itself stays visible until the user acts or starts over).
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        voice.stopSpeaking()
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    // MARK: - History

    func newChat() {
        stop()
        pendingAction = nil
        messages = []
        saveHistory()
    }

    /// Clears the in-memory transcript after history was deleted from
    /// Settings. Does not touch sign-in tokens.
    func clearAfterHistoryDeleted() {
        messages = []
    }

    func deleteHistory() {
        stop()
        pendingAction = nil
        messages = []
        ChatHistoryStore.deleteHistoryFile()
        NotificationCenter.default.post(name: .museChatHistoryDeleted, object: nil)
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
        saveHistory()
    }

    private func saveHistory() {
        ChatHistoryStore.save(messages.map { message in
            let role: String
            switch message.role {
            case .system: role = "system"
            case .assistant: role = "assistant"
            case .tool: role = "tool"
            case .user: role = "user"
            }
            return MuseChatHistoryEntry(role: role, content: message.content,
                                        toolCallId: message.toolCallId)
        })
    }
}

// MARK: - Views

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var auth: MuseAuthService
    @EnvironmentObject var voice: VoiceService

    var body: some View {
        if !auth.isConnected {
            notConnectedView
        } else {
            chatView
        }
    }

    // MARK: Not connected (no fake messages, no simulated replies)

    private var notConnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Muse", systemImage: "sparkles")
                .font(FileRadarFont.heading())
            Text("Muse is not connected yet, so there is no conversation to show.")
                .font(FileRadarFont.body())
            Text("Connecting requires a Meta developer configuration. See the README for the setup details.")
                .font(FileRadarFont.body()).foregroundStyle(.secondary)
            if auth.isConnecting {
                ProgressView("Connecting…")
            } else {
                Button("Connect Muse") {
                    Task { await auth.connect() }
                }
                .buttonStyle(.borderedProminent)
            }
            if auth.lastError != nil {
                Text("Connection failed. Please try again.")
                    .font(FileRadarFont.body()).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Connected chat

    private var chatView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRowView(message: message)
                                .id(message.id)
                        }
                        if let pending = viewModel.pendingAction {
                            ToolApprovalCardView(action: pending) {
                                viewModel.approvePending()
                            } onDeny: {
                                viewModel.denyPending()
                            }
                        }
                        if let error = viewModel.errorMessage {
                            Text(error).font(FileRadarFont.body()).foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.last?.content) { _, _ in
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            Divider()
            composer
        }
        .onReceive(NotificationCenter.default.publisher(for: .museChatHistoryDeleted)) { _ in
            // Only clear if this view did not itself post it while already
            // empty; clearing an already-cleared transcript is a no-op.
            viewModel.clearAfterHistoryDeleted()
        }
    }

    private var header: some View {
        HStack {
            Label("Muse", systemImage: "sparkles")
                .font(FileRadarFont.heading())
            Spacer()
            if voice.isListening {
                Label("Listening…", systemImage: "mic.fill")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Button("New Chat") { viewModel.newChat() }
            Button("Delete History") { viewModel.deleteHistory() }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                TextField("Ask Muse about your files…", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.send() }
                    .disabled(viewModel.isStreaming)
                if viewModel.isStreaming {
                    Button("Stop") { viewModel.stop() }
                } else {
                    Button("Send") { viewModel.send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button(action: {
                    if voice.isListening { voice.stopListening() } else { voice.startListening() }
                }) {
                    Label(voice.isListening ? "Stop listening" : "Speak",
                          systemImage: voice.isListening ? "mic.fill" : "mic")
                }
                .help(voice.handsFree
                      ? "Tap to toggle continuous listening."
                      : "Tap to start or stop push-to-talk.")
            }
            HStack {
                Toggle("Share current folder", isOn: $viewModel.shareCurrentFolder)
                Toggle("Hands-free", isOn: $voice.handsFree)
                Toggle("Speak replies", isOn: $viewModel.speakReplies)
            }
            .toggleStyle(.checkbox)
            Text("Share current folder is off by default. When off, no folder or file location is sent. When on, only the current view's title and up to 50 file names are sent — never file contents, never recognised text. Tool results (file names and metadata only) are still sent to the model when you trigger a tool, even with this off.")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct MessageRowView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(roleLabel).font(FileRadarFont.caption()).foregroundStyle(.secondary)
            if !message.content.isEmpty {
                Text(message.content)
                    .font(FileRadarFont.body())
                    .textSelection(.enabled)
            }
            ForEach(message.toolCalls, id: \.id) { call in
                Label("Tool: \(call.name)", systemImage: "wrench")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor.opacity(0.12))
        .cornerRadius(10)
    }

    private var roleLabel: String {
        switch message.role {
        case .system: return "Context"
        case .user: return "You"
        case .assistant: return "Muse"
        case .tool: return "Tool result"
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return .gray
        case .tool: return .green
        case .system: return .orange
        }
    }
}

/// Approval card for exactly one pending action. Nothing destructive
/// runs until Approve is tapped; Deny records a cancellation and the
/// conversation continues.
private struct ToolApprovalCardView: View {
    let action: PendingToolAction
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needs your approval: \(action.toolName)", systemImage: "exclamationmark.shield")
                .font(FileRadarFont.heading())
            Text(action.title).font(FileRadarFont.body())
            Text(action.detail).font(FileRadarFont.body()).foregroundStyle(.secondary)
            HStack {
                Button("Approve") { onApprove() }.buttonStyle(.borderedProminent)
                Button("Deny") { onDeny() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(10)
    }
}
