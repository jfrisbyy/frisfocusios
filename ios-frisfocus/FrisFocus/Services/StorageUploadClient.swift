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
//  Two things this client does that a bare POST would not:
//
//   • It asks for a fresh token first. The Keychain token is only
//     refreshed when the app returns to the foreground, and an upload
//     is exactly the kind of thing that starts hours into a session —
//     or runs long enough to outlive the token it started with. The
//     app installs `refreshAuth` once at launch; an upload calls it
//     before sending, and once more if Storage still says the token is
//     no good, retrying only when a different token came back.
//
//   • It reports the status Storage MEANT. Storage answers some
//     failures with HTTP 400 and puts the real code in the JSON body
//     (`{"statusCode":"409","error":"Duplicate",…}`), and which
//     releases do that has changed over time. Callers branch on
//     `badResponse(status:)` — 409 "already uploaded, carry on", 413
//     "too large" — so the body's code is surfaced as the status and a
//     duplicate is always 409, whichever way this server phrases it.
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
    /// Refreshes the Keychain access token when it is at or near
    /// expiry. Installed once at launch by the app root, which owns the
    /// `AuthManager`; nil (previews, tests) simply means uploads send
    /// whatever token is stored, as they always did.
    @MainActor static var refreshAuth: (@MainActor () async -> Void)?

    @MainActor
    private static func refreshAuthIfNeeded() async {
        guard let refresh = refreshAuth else { return }
        await refresh()
    }

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
        await refreshAuthIfNeeded()
        let firstToken = KeychainHelper.get("access_token")
        do {
            try await send(
                data: data,
                bucket: bucket,
                path: path,
                contentType: contentType,
                token: firstToken,
                onProgress: onProgress
            )
        } catch StorageUploadError.badResponse(let status) where status == 401 {
            // Storage refused the token. Ask once more for a fresh one
            // and retry only if a different token actually came back —
            // re-sending the same bytes under the same token would just
            // spend the person's data on a second identical refusal.
            await refreshAuthIfNeeded()
            let secondToken = KeychainHelper.get("access_token")
            guard let secondToken, secondToken != firstToken else {
                throw StorageUploadError.badResponse(status: status)
            }
            try await send(
                data: data,
                bucket: bucket,
                path: path,
                contentType: contentType,
                token: secondToken,
                onProgress: onProgress
            )
        }
    }

    /// The status Storage meant, given what it sent. See the file
    /// header: the JSON body's own `statusCode` wins over a generic
    /// HTTP 400, a duplicate object is always 409, and an expired or
    /// invalid token is always 401.
    static func effectiveStatus(httpStatus: Int, body: Data) -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let json = object as? [String: Any] else {
            return httpStatus
        }
        let errorText = (json["error"] as? String) ?? ""
        let messageText = (json["message"] as? String) ?? ""
        let combined = "\(errorText) \(messageText)".lowercased()

        if combined.contains("duplicate") || combined.contains("already exists") {
            return 409
        }
        if combined.contains("jwt") || combined.contains("token") {
            return 401
        }

        var bodyStatus: Int?
        if let text = json["statusCode"] as? String {
            bodyStatus = Int(text)
        } else if let number = json["statusCode"] as? Int {
            bodyStatus = number
        }
        if httpStatus == 400, let bodyStatus, (401...599).contains(bodyStatus) {
            return bodyStatus
        }
        return httpStatus
    }

    private static func send(
        data: Data,
        bucket: String,
        path: String,
        contentType: String,
        token: String?,
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
        request.setValue("Bearer \(token ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("3600", forHTTPHeaderField: "cache-control")
        request.setValue("false", forHTTPHeaderField: "x-upsert")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let (responseBody, response) = try await URLSession.shared.upload(for: request, from: data, delegate: delegate)

        guard let http = response as? HTTPURLResponse else {
            throw StorageUploadError.badResponse(status: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw StorageUploadError.badResponse(
                status: effectiveStatus(httpStatus: http.statusCode, body: responseBody)
            )
        }
    }
}
