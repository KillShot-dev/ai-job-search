import Foundation

// MARK: - Muse chat contract (shared with the chat-UI sibling)
//
// This file defines ONLY the shared value types for the in-app Muse chat.
// It owns no networking, no secrets, and no file access.
//
// Privacy rules that every type here serves:
// - Tool outputs carry file NAMES, metadata, and summaries only. They
//   never carry full paths, file contents, or OCR text. (The tool layer
//   in FileRadarToolService enforces this; these types simply have no
//   field in which a path or content could hide.)
// - Nothing here is ever logged. MuseClient performs no logging at all.
//
// Dependency note (read before compiling standalone): `MuseConfig` is
// the auth sibling's type (baseURL, clientID, redirectURI, scopes,
// model, plus a static `placeholder`). It is deliberately NOT defined
// here, so the auth sibling's definition is the single source of truth.
// This target does not compile until that type lands.

// MARK: - Roles and messages

/// Roles in a chat-completions conversation. `tool` messages carry the
/// result of a local tool call back to the model.
enum ChatRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

/// One message in the chat transcript. `id` is local-only (SwiftUI
/// identity); it is never sent to the model API.
struct ChatMessage: Identifiable {
    let id: UUID
    var role: ChatRole
    var content: String
    var toolCalls: [ToolCall]
    /// Set only on `tool`-role messages: the id of the call being answered.
    var toolCallId: String?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        toolCalls: [ToolCall] = [],
        toolCallId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

// MARK: - Tool calls

/// A single function call requested by the model. `argumentsJSON` is the
/// raw JSON object string for the call; an empty string means "no
/// arguments" (FileRadarToolService treats it as an empty object).
struct ToolCall {
    let id: String
    let name: String
    let argumentsJSON: String
}

/// A tool the model may call. `parametersJSON` is a raw JSON-schema
/// string (an object schema); MuseClient parses it into the request
/// body with JSONSerialization, so it must be valid JSON.
struct ToolSchema {
    let name: String
    let description: String
    let parametersJSON: String
}

// MARK: - Tool execution outcomes

/// A destructive or externally visible action waiting on the user.
/// `detail` is shown in the approval UI; it lists file names only,
/// never full paths.
struct PendingToolAction {
    let id: UUID
    let title: String
    let detail: String
    let toolName: String
}

/// What a local tool execution produced. Destructive and externally
/// visible actions never complete inline: they return `needsApproval`
/// and only run when the user approves via `FileRadarToolService.approve`.
enum ToolExecutionResult {
    /// The tool ran; the string is a summary for the model (names and
    /// metadata only, never paths, contents, or OCR text).
    case completed(String)
    /// The action is staged and waiting on user approval.
    case needsApproval(PendingToolAction)
    /// The tool is gated behind a paid licence.
    case locked(String)
    /// The tool could not run; the string is a generic message that
    /// never echoes server bodies, tokens, or file paths.
    case failed(String)
}

// MARK: - Client errors

/// The only error MuseClient surfaces to callers: deliberately generic.
/// Server response bodies are never echoed (they could contain account
/// or request details), and request/token/message content is never logged.
enum MuseClientError: Error {
    case generic
}
