//
//  AIService.swift
//  FrisFocus
//
//  Streaming client for the `openrouter-chat` Supabase edge function —
//  the plumbing the season rubric-generation conversation (S1) sits on.
//
//  Two entry points:
//  - `stream(...)`  → AsyncThrowingStream of text deltas (SSE), for the
//    chat-style conversation UI.
//  - `complete(...)` → one-shot reply, optionally with a strict JSON
//    schema for structured output (the rubric validator step).
//
//  Auth: requests carry the signed-in user's Rork Auth JWT (read from the
//  Keychain, same token Supabase uses). The function rejects anonymous
//  calls, and the OpenRouter key never leaves the server.
//

import Foundation

/// A single chat turn sent to the AI. Raw `role` values match the edge
/// function's contract ("system" | "user" | "assistant").
nonisolated struct AIMessage: Codable, Sendable {
    let role: String
    let content: String

    static func user(_ content: String) -> AIMessage { AIMessage(role: "user", content: content) }
    static func assistant(_ content: String) -> AIMessage { AIMessage(role: "assistant", content: content) }
}

nonisolated enum AIServiceError: LocalizedError {
    case notSignedIn
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in to use AI features."
        case .server(let message): return message
        case .badResponse: return "The AI service returned an unexpected response."
        }
    }
}

/// Request body for the edge function (camelCase keys, matched to its
/// `ChatRequest`). Optional fields are omitted when nil.
private nonisolated struct AIRequestBody: Encodable, Sendable {
    let messages: [AIMessage]
    let system: String?
    let model: String?
    let stream: Bool
    let jsonSchema: AIJSONSchema?
    let maxTokens: Int?
    let temperature: Double?
}

nonisolated struct AIJSONSchema: Encodable, Sendable {
    let name: String
    /// Raw JSON-schema object, encoded verbatim.
    let schema: [String: AIJSONValue]
}

/// Minimal JSON value type so schemas can be expressed in Swift literals.
nonisolated indirect enum AIJSONValue: Encodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([AIJSONValue])
    case object([String: AIJSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

private nonisolated struct AICompletionResponse: Decodable, Sendable {
    let content: String?
    let error: String?
}

/// One parsed `delta` chunk from the OpenRouter SSE stream.
private nonisolated struct AIStreamChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            let content: String?
        }
        let delta: Delta?
    }
    let choices: [Choice]?
}

enum AIService {
    private nonisolated static var functionURL: URL {
        URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/functions/v1/openrouter-chat")!
    }

    private nonisolated static func makeRequest(
        messages: [AIMessage],
        system: String?,
        model: String?,
        stream: Bool,
        jsonSchema: AIJSONSchema?,
        maxTokens: Int?,
        temperature: Double?
    ) throws -> URLRequest {
        guard let token = KeychainHelper.get("access_token"), !token.isEmpty else {
            throw AIServiceError.notSignedIn
        }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(
            AIRequestBody(
                messages: messages,
                system: system,
                model: model,
                stream: stream,
                jsonSchema: jsonSchema,
                maxTokens: maxTokens,
                temperature: temperature
            )
        )
        return request
    }

    /// Extract a server-provided error message from a non-2xx JSON body.
    private nonisolated static func serverError(from data: Data, status: Int) -> AIServiceError {
        if let decoded = try? JSONDecoder().decode(AICompletionResponse.self, from: data),
           let message = decoded.error, !message.isEmpty {
            return .server(message)
        }
        return .server("AI request failed (\(status)).")
    }

    /// Stream the assistant's reply token-by-token. Yields text deltas as
    /// they arrive; finishes when the model is done.
    nonisolated static func stream(
        messages: [AIMessage],
        system: String? = nil,
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(
                        messages: messages,
                        system: system,
                        model: model,
                        stream: true,
                        jsonSchema: nil,
                        maxTokens: maxTokens,
                        temperature: temperature
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIServiceError.badResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw serverError(from: body, status: http.statusCode)
                    }

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(AIStreamChunk.self, from: data),
                              let delta = chunk.choices?.first?.delta?.content,
                              !delta.isEmpty else { continue }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One-shot completion. Pass `jsonSchema` to force the model to return
    /// JSON matching the schema (structured output, non-streamed).
    nonisolated static func complete(
        messages: [AIMessage],
        system: String? = nil,
        model: String? = nil,
        jsonSchema: AIJSONSchema? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> String {
        let request = try makeRequest(
            messages: messages,
            system: system,
            model: model,
            stream: false,
            jsonSchema: jsonSchema,
            maxTokens: maxTokens,
            temperature: temperature
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw serverError(from: data, status: http.statusCode)
        }
        let decoded = try JSONDecoder().decode(AICompletionResponse.self, from: data)
        guard let content = decoded.content else { throw AIServiceError.badResponse }
        return content
    }
}
