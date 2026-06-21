//
//  TodaysReadService.swift
//  FrisFocus
//
//  Thin client for the `todays-read` edge function. Sends the assembled
//  day snapshot and decodes the structured read. Auth mirrors AIService:
//  the signed-in user's Rork Auth JWT, never the OpenRouter key.
//

import Foundation

nonisolated enum TodaysReadServiceError: LocalizedError {
    case notSignedIn
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in for a read."
        case .server(let message): return message
        case .badResponse: return "The read service returned something unexpected."
        }
    }
}

private nonisolated struct ReadErrorBody: Decodable, Sendable {
    let error: String?
}

nonisolated enum TodaysReadService {
    private static var functionURL: URL {
        URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/functions/v1/todays-read")!
    }

    /// POST the pre-encoded day snapshot, return the parsed read payload.
    static func fetch(snapshot: Data) async throws -> ReadPayload {
        guard let token = KeychainHelper.get("access_token"), !token.isEmpty else {
            throw TodaysReadServiceError.notSignedIn
        }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = snapshot

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TodaysReadServiceError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let decoded = try? JSONDecoder().decode(ReadErrorBody.self, from: data),
               let message = decoded.error, !message.isEmpty {
                throw TodaysReadServiceError.server(message)
            }
            throw TodaysReadServiceError.server("The read failed (\(http.statusCode)).")
        }
        do {
            return try JSONDecoder().decode(ReadPayload.self, from: data)
        } catch {
            throw TodaysReadServiceError.badResponse
        }
    }
}
