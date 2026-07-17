//
//  SeasonSetupAI.swift
//  FrisFocus
//
//  Thin client for the `season-setup` Supabase edge function — the
//  server-mediated season conversation. The v15 system prompt, the model
//  key, and the calibration validator all live on the backend; the app
//  only sends the running message history and decodes the clean envelope.
//
//  History contract: user turns are the user's words; assistant turns are
//  the `raw` string echoed back by the server (the model's own structured
//  output), replayed verbatim so the model keeps full context.
//

import Foundation

nonisolated enum SeasonSetupAIError: LocalizedError {
    case notSignedIn
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in to set up a season."
        case .server(let message): return message
        case .badResponse: return "The setup service returned an unexpected response."
        }
    }
}

private nonisolated struct SetupRequestBody: Encodable, Sendable {
    let messages: [AIMessage]
    /// The warm-start envelope. Omitted from the JSON when nil so legacy
    /// (cold) conversations send exactly what they always did.
    let coldStartContext: ColdStartContext?

    enum CodingKeys: String, CodingKey {
        case messages
        case coldStartContext = "cold_start_context"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(coldStartContext, forKey: .coldStartContext)
    }
}

private nonisolated struct SetupErrorBody: Decodable, Sendable {
    let error: String?
}

enum SeasonSetupAI {
    private nonisolated static var functionURL: URL {
        URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/functions/v1/season-setup")!
    }

    /// Send the running history; receive the next assistant turn. An empty
    /// history asks the model to open the conversation. An optional
    /// `coldStartContext` warm-starts the chat — pass it on the opening
    /// turn so the model references what the person already chose/built.
    nonisolated static func send(
        history: [AIMessage],
        coldStartContext: ColdStartContext? = nil
    ) async throws -> SetupWireEnvelope {
        guard let token = KeychainHelper.get("access_token"), !token.isEmpty else {
            throw SeasonSetupAIError.notSignedIn
        }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(
            SetupRequestBody(messages: history, coldStartContext: coldStartContext)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SeasonSetupAIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let decoded = try? JSONDecoder().decode(SetupErrorBody.self, from: data),
               let message = decoded.error, !message.isEmpty {
                throw SeasonSetupAIError.server(message)
            }
            throw SeasonSetupAIError.server("Setup request failed (\(http.statusCode)).")
        }
        do {
            return try JSONDecoder().decode(SetupWireEnvelope.self, from: data)
        } catch {
            print("[SeasonSetupAI] decode failed: \(error)")
            throw SeasonSetupAIError.badResponse
        }
    }
}
