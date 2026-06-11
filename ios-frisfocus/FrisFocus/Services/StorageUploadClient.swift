//
//  StorageUploadClient.swift
//  FrisFocus
//
//  A thin direct-to-Storage uploader used for proof media. The Supabase
//  SDK's upload call gives no progress feedback, so a multi-MB video
//  send looks frozen; this client POSTs the same bytes to the same
//  Storage endpoint through URLSession with a task delegate, surfacing
//  real byte-level progress the UI can render.
//
//  Auth mirrors `SupabaseService`: the signed-in user's Rork Auth JWT
//  (from the Keychain) rides as the bearer token so the bucket's RLS
//  policies see the same identity as every other storage call.
//

import Foundation

nonisolated enum StorageUploadError: Error, LocalizedError {
    case badResponse(status: Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "Upload failed with status \(status)"
        }
    }
}

/// URLSession task delegate that forwards byte-level upload progress.
nonisolated private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

nonisolated enum StorageUploadClient {
    /// Upload `data` into `bucket` at `path` with live progress
    /// callbacks (0...1, delivered off the main actor). Throws on any
    /// non-2xx response so callers can surface a friendly error.
    static func upload(
        data: Data,
        bucket: String,
        path: String,
        contentType: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let base = Config.EXPO_PUBLIC_SUPABASE_URL
        let encodedPath = path
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "\(base)/storage/v1/object/\(bucket)/\(encodedPath)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let anonKey = Config.EXPO_PUBLIC_SUPABASE_ANON_KEY
        let token = KeychainHelper.get("access_token") ?? anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("3600", forHTTPHeaderField: "cache-control")
        request.setValue("false", forHTTPHeaderField: "x-upsert")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let (_, response) = try await URLSession.shared.upload(for: request, from: data, delegate: delegate)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw StorageUploadError.badResponse(status: status)
        }
    }
}
