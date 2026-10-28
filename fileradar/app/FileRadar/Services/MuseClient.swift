import Foundation

// MARK: - MuseClient: OpenAI-compatible streaming chat transport
//
// What this is:
// - A thin transport for the Model API (Muse Spark), speaking the
//   OpenAI-compatible chat-completions protocol over server-sent events
//   (SSE). It sends messages + tool schemas, streams assistant tokens
//   through `onToken`, and returns the model's requested tool calls.
// - It executes NOTHING itself. Tool calls it returns are executed
//   locally by FileRadarToolService, never in the cloud.
//
// What this is not:
// - Not an auth store. Tokens come from `tokenProvider` (the auth
//   sibling owns Keychain storage); this client never persists a token.
// - Not a logger. No request, token, message, or response content is
//   ever printed or stored here.
//
// Endpoint assumption: `config.baseURL` is the API root (for example a
// `.../v1` root), NOT the full completions URL. The request goes to
// `baseURL` + `/chat/completions`. If the auth sibling defines baseURL
// as the full endpoint instead, this path-join must change with it.
//
// Threading: `onToken` is invoked on the streaming task's executor, not
// the main actor. The chat UI must hop to the main actor before touching
// UI state. Task cancellation propagates: cancelling the awaiting task
// aborts the stream (URLSession bytes iteration throws on cancellation).
//
// Errors: every failure surfaces as `MuseClientError.generic`. Non-200
// responses never have their bodies read or echoed. A 401 refreshes the
// token via `tokenProvider` and retries exactly once; a second failure
// (of any kind) is generic, with no further retries.

/// Internal retry signal only. Never escapes `stream`: a 401 with no
/// provider, or any failure on the retry, is converted to
/// `MuseClientError.generic` before returning to callers.
private enum StreamAttemptError: Error {
    case unauthorized
    case generic
}

/// Accumulator for one tool call spread across SSE delta fragments.
private struct ToolCallAccumulator {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}

final class MuseClient {

    /// Supplies a fresh bearer token. Called before the first attempt
    /// (when set) and once more after a 401. Throwing propagates as a
    /// generic error; the underlying reason is never surfaced.
    var tokenProvider: (() async throws -> String)?

    private let config: MuseConfig
    private let session: URLSession

    init(config: MuseConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        // Explicit timeouts: a hung stream must fail rather than spin.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }

    /// Streams one assistant turn. `messages` is the full transcript
    /// (including prior tool results); `tools` are the local tools the
    /// model may request. Each content token is delivered via `onToken`
    /// as it arrives. Returns the model's tool calls (empty for a plain
    /// text reply). Throws `MuseClientError.generic` on any failure.
    func stream(
        messages: [ChatMessage],
        tools: [ToolSchema],
        onToken: @escaping (String) -> Void
    ) async throws -> [ToolCall] {
        guard config.baseURL.scheme == "https" else {
            throw MuseClientError.generic
        }
        do {
            let initialToken = try await currentToken()
            return try await perform(messages: messages, tools: tools, token: initialToken, onToken: onToken)
        } catch StreamAttemptError.unauthorized {
            // Exactly one refresh + one retry. No provider means no retry.
            guard let provider = tokenProvider else {
                throw MuseClientError.generic
            }
            do {
                let refreshedToken = try await provider()
                return try await perform(messages: messages, tools: tools, token: refreshedToken, onToken: onToken)
            } catch {
                throw MuseClientError.generic
            }
        } catch {
            throw MuseClientError.generic
        }
    }

    // MARK: - Token

    private func currentToken() async throws -> String? {
        guard let provider = tokenProvider else { return nil }
        do {
            return try await provider()
        } catch {
            throw StreamAttemptError.generic
        }
    }

    // MARK: - One attempt

    private func perform(
        messages: [ChatMessage],
        tools: [ToolSchema],
        token: String?,
        onToken: @escaping (String) -> Void
    ) async throws -> [ToolCall] {
        let request: URLRequest
        do {
            request = try buildRequest(messages: messages, tools: tools, token: token)
        } catch {
            throw StreamAttemptError.generic
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StreamAttemptError.generic
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamAttemptError.generic
        }
        // Bodies are never read on errors: a non-200 body could contain
        // account or request details, and the contract requires generic
        // errors only. (The 401 case is the one exception to "generic
        // immediately": it triggers the single refresh + retry in stream.)
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw StreamAttemptError.unauthorized
        default:
            throw StreamAttemptError.generic
        }

        return try await parseStream(bytes, onToken: onToken)
    }

    // MARK: - Request building (JSONSerialization dictionaries)

    private func buildRequest(messages: [ChatMessage], tools: [ToolSchema], token: String?) throws -> URLRequest {
        let url = config.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var messageDicts: [[String: Any]] = []
        for message in messages {
            var dict: [String: Any] = [
                "role": message.role.rawValue,
                "content": message.content,
            ]
            if message.role == .assistant, !message.toolCalls.isEmpty {
                dict["tool_calls"] = message.toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.argumentsJSON],
                    ] as [String: Any]
                }
            }
            if message.role == .tool, let toolCallId = message.toolCallId {
                dict["tool_call_id"] = toolCallId
            }
            messageDicts.append(dict)
        }

        let toolDicts: [[String: Any]] = tools.map { schema in
            [
                "type": "function",
                "function": [
                    "name": schema.name,
                    "description": schema.description,
                    // parametersJSON is a raw JSON-schema string; embed it
                    // as parsed JSON, not as an escaped string. A schema
                    // that fails to parse degrades to an empty object
                    // schema rather than failing the whole request.
                    "parameters": parsedJSON(schema.parametersJSON) ?? ["type": "object"],
                ] as [String: Any],
            ] as [String: Any]
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": messageDicts,
            "tools": toolDicts,
            "tool_choice": "auto",
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func parsedJSON(_ string: String) -> Any? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    // MARK: - SSE parsing

    private func parseStream(
        _ bytes: URLSession.AsyncBytes,
        onToken: @escaping (String) -> Void
    ) async throws -> [ToolCall] {
        var toolCallsByIndex: [Int: ToolCallAccumulator] = [:]

        do {
            for try await line in bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("data:") else { continue }
                let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any] else {
                    continue
                }
                if let content = delta["content"] as? String, !content.isEmpty {
                    onToken(content)
                }
                if let toolCallDeltas = delta["tool_calls"] as? [[String: Any]] {
                    for fragment in toolCallDeltas {
                        let index = (fragment["index"] as? NSNumber)?.intValue ?? 0
                        var accumulator = toolCallsByIndex[index] ?? ToolCallAccumulator()
                        if let id = fragment["id"] as? String, !id.isEmpty {
                            accumulator.id = id
                        }
                        if let function = fragment["function"] as? [String: Any] {
                            if let name = function["name"] as? String, !name.isEmpty {
                                accumulator.name += name
                            }
                            if let arguments = function["arguments"] as? String {
                                accumulator.arguments += arguments
                            }
                        }
                        toolCallsByIndex[index] = accumulator
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StreamAttemptError.generic
        }

        // Tool calls in index order. Calls without a name are dropped:
        // a nameless call cannot be executed or reported meaningfully.
        return toolCallsByIndex.keys.sorted().compactMap { index in
            let accumulator = toolCallsByIndex[index]!
            guard !accumulator.name.isEmpty else { return nil }
            return ToolCall(id: accumulator.id, name: accumulator.name, argumentsJSON: accumulator.arguments)
        }
    }
}
