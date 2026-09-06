//
//  AuthManager.swift
//  FrisFocus
//
//  Rork Auth (Google / Apple) sign-in. The app talks directly to Rork's
//  auth API — no backend auth routes needed. Tokens are stored in the
//  Keychain; the Supabase client reads the access token from there.
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase

@Observable
class AuthManager {
    var user: User?
    var isLoading = true
    var isSigningIn = false
    var showError = false
    var errorMessage = ""
    /// True when the session was ended WITHOUT the user asking — the
    /// refresh token was rejected by the auth server. The home shows a
    /// visible "sign back in" banner instead of silently looking empty.
    var sessionExpired = false

    private let authURL = Config.EXPO_PUBLIC_RORK_AUTH_URL
    private let appKey = Config.EXPO_PUBLIC_RORK_APP_KEY
    private let projectID = Config.EXPO_PUBLIC_PROJECT_ID
    private var codeVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?
    // Injected by Rork into UserDefaults at install time on the iOS Simulator
    // only. Tells the backend which developer's browser tab should receive the
    // OAuth popup. Absent on real devices and in non-Rork environments — that
    // case falls back to ASWebAuthenticationSession in-app.
    //
    // Computed (not stored / not lazy): the simctl write that puts this key
    // into UserDefaults runs *after* installApp has already launched the
    // fresh app process. If we cached the value via `lazy var`, an early
    // Sign In tap (before the simctl write lands) would freeze `nil` for
    // the rest of the session even after the hint becomes available. Reading
    // UserDefaults on every access means the next tap picks up the value.
    private var developerHint: String? {
        UserDefaults.standard.string(forKey: "RORK_DEVELOPER_HINT")
    }

    struct User: Codable {
        let id: String
        let email: String
        let name: String?
        let picture: String?

        /// Up to two uppercase initials drawn from the user's name,
        /// falling back to the first letter of their email. Empty only
        /// when we have neither — callers treat that as "show a glyph".
        var initials: String {
            if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
                if !letters.isEmpty { return String(letters).uppercased() }
            }
            if let first = email.first { return String(first).uppercased() }
            return ""
        }

        /// The avatar image URL the identity provider supplied, if any.
        var photoURL: URL? {
            guard let picture, let url = URL(string: picture) else { return nil }
            return url
        }
    }

    init() {
        Task { await checkAuth() }
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private var authEnv: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "native"
        #endif
    }

    private struct JWTPayload: Codable {
        let sub: String
        let email: String?
        let name: String?
        let picture: String?
        let exp: TimeInterval?
    }

    /// Decode a JWT's payload segment. We trust the token we stored
    /// locally — signature was verified by Rork when issued.
    private func decodePayload(_ token: String) -> JWTPayload? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(JWTPayload.self, from: data)
    }

    /// Decode the JWT payload to extract user info and check expiration.
    private func userFromToken(_ token: String) -> User? {
        guard let payload = decodePayload(token) else { return nil }

        if let exp = payload.exp, Date(timeIntervalSince1970: exp) < Date() {
            return nil
        }

        return User(id: payload.sub, email: payload.email ?? "", name: payload.name, picture: payload.picture)
    }

    /// Read refresh token from UserDefaults (simulator-injected) first, then Keychain.
    /// Simulators don't have Keychain access, so the simctl-injected token in
    /// UserDefaults is the primary source on simulator.
    private func getRefreshToken() -> String? {
        #if targetEnvironment(simulator)
        if let ud = UserDefaults.standard.string(forKey: "RORK_AUTH_REFRESH_TOKEN") {
            return ud
        }
        #endif
        return KeychainHelper.get("refresh_token")
    }

    @MainActor
    func checkAuth() async {
        defer { isLoading = false }

        if let accessToken = KeychainHelper.get("access_token"),
           let user = userFromToken(accessToken) {
            self.user = user
            print("[AuthManager] checkAuth: restored session from access token, user=\(user.id)")
            syncProfile(user)
            return
        }

        // Token missing or expired — try refresh
        if getRefreshToken() != nil {
            print("[AuthManager] checkAuth: no valid access token, attempting refresh")
            await refreshToken()
        } else {
            print("[AuthManager] checkAuth: no access token and no refresh token — signed out")
        }
    }

    @MainActor
    func signIn(provider: String) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let verifier = generateCodeVerifier()
            let challenge = generateCodeChallenge(from: verifier)
            codeVerifier = verifier

            guard let url = URL(string: "\(authURL)/oauth/initiate") else {
                setError("Invalid URL")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var initiateBody: [String: String] = [
                "app_key": appKey,
                "provider": provider,
                "code_challenge": challenge,
                "target": "swift",
                "env": authEnv,
            ]
            if authEnv == "simulator", let hint = developerHint {
                initiateBody["developer_hint"] = hint
            }
            request.httpBody = try JSONEncoder().encode(initiateBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    setError(errorResponse.error)
                } else {
                    setError("Sign in failed (\(statusCode))")
                }
                return
            }
            let initiateResponse = try JSONDecoder().decode(InitiateResponse.self, from: data)

            let code: String
            if initiateResponse.flow == "popup" {
                // The OAuth UI is being shown in the developer's host browser via a
                // websocket-dispatched popup. Poll until the callback writes the
                // rork_code into Redis keyed by `state`.
                do {
                    code = try await pollForCode(state: initiateResponse.state)
                } catch AuthError.cancelledByUser {
                    // Developer clicked "Use simulator instead" on the host-
                    // browser toast. The backend has already flipped
                    // popupFlow=false on this state, so /oauth/callback will
                    // 302 to the custom scheme — exactly what
                    // ASWebAuthenticationSession needs. Reuse the same
                    // auth_url; no second /oauth/initiate.
                    code = try await runWebAuthSession(authURL: initiateResponse.auth_url)
                }
            } else {
                code = try await runWebAuthSession(authURL: initiateResponse.auth_url)
            }

            await exchangeCode(code)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            setError(error.localizedDescription)
        }
    }

    /// Poll /oauth/poll-code until the host-browser popup completes the OAuth
    /// callback or the 5-min state TTL elapses. Used only when the backend
    /// returned `flow: "popup"` from /oauth/initiate.
    ///
    /// Throws `AuthError.cancelledByUser` when the developer hit "Use
    /// simulator instead" on the host-browser toast — the caller then
    /// falls back to ASWebAuthenticationSession with the same auth_url.
    private func pollForCode(state: String) async throws -> String {
        guard let url = URL(string: "\(authURL)/oauth/poll-code") else {
            throw AuthError.invalidURL
        }

        let deadline = Date().addingTimeInterval(5 * 60)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 1_500_000_000)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["app_key": appKey, "state": state])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }

            guard let pollResponse = try? JSONDecoder().decode(PollCodeResponse.self, from: data) else { continue }

            if pollResponse.status == "cancelled" {
                throw AuthError.cancelledByUser
            }

            if pollResponse.status == "ready", let code = pollResponse.code {
                return code
            }
        }

        throw AuthError.popupTimeout
    }

    /// Open the OAuth authorize URL inside ASWebAuthenticationSession and
    /// resolve to the auth code captured from the rork-{projectID}:// callback.
    /// Used both for the native real-device path and as the in-sim fallback
    /// when the developer declined the host-browser popup.
    private func runWebAuthSession(authURL authURLString: String) async throws -> String {
        let callbackScheme = "rork-\(projectID)"
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            guard let url = URL(string: authURLString) else {
                continuation.resume(throwing: AuthError.invalidURL)
                return
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.noCode)
                    return
                }

                continuation.resume(returning: code)
            }

            self.webAuthSession = session
            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    @MainActor
    private func exchangeCode(_ code: String) async {
        guard let verifier = codeVerifier else { return }
        codeVerifier = nil

        guard let url = URL(string: "\(authURL)/oauth/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "app_key": appKey,
            "code": code,
            "code_verifier": verifier,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    setError(errorResponse.error)
                } else {
                    setError("Sign in failed (\(statusCode))")
                }
                return
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            KeychainHelper.set("access_token", value: tokenResponse.access_token)
            KeychainHelper.set("refresh_token", value: tokenResponse.refresh_token)

            user = tokenResponse.user
            sessionExpired = false
            syncProfile(tokenResponse.user)
        } catch {
            setError("Sign in failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshToken() async {
        guard let storedRefreshToken = getRefreshToken() else {
            user = nil
            return
        }

        guard let url = URL(string: "\(authURL)/oauth/refresh") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "app_key": appKey,
            "refresh_token": storedRefreshToken,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                if (400...499).contains(code) {
                    // The auth server definitively rejected the refresh
                    // token — the session is over. Sign out, but say so
                    // visibly instead of silently looking empty.
                    print("[AuthManager] refreshToken: refresh rejected (\(code)) — signing out, flagging expiry")
                    await signOut()
                    sessionExpired = true
                } else {
                    // Server hiccup (5xx) — keep the stored tokens and
                    // retry on the next foreground instead of destroying
                    // a probably-valid session.
                    print("[AuthManager] refreshToken: refresh endpoint returned \(code) — keeping session for retry")
                }
                return
            }

            let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
            KeychainHelper.set("access_token", value: refreshResponse.access_token)

            let refreshedUser = userFromToken(refreshResponse.access_token)
            user = refreshedUser
            if let refreshedUser {
                print("[AuthManager] refreshToken: session refreshed, user=\(refreshedUser.id)")
                sessionExpired = false
                syncProfile(refreshedUser)
            } else {
                print("[AuthManager] refreshToken: refresh succeeded but token had no user")
            }
        } catch {
            // Network failure (offline launch, timeout) — never destroy
            // the session over connectivity. Tokens stay; the app retries
            // silently when it becomes active again.
            print("[AuthManager] refreshToken: network failure (\(error.localizedDescription)) — keeping session for retry")
        }
    }

    /// True when stored credentials exist that could still restore a
    /// session (used to retry a silent restore after a network failure).
    var hasRestorableSession: Bool {
        KeychainHelper.get("access_token") != nil || getRefreshToken() != nil
    }

    /// Re-attempt a silent session restore — called on foreground when
    /// a network failure left the app signed out with tokens intact.
    @MainActor
    func retryRestoreIfNeeded() async {
        guard user == nil, !isLoading, !isSigningIn, hasRestorableSession else { return }
        print("[AuthManager] retryRestoreIfNeeded: tokens present, retrying silent restore")
        await checkAuth()
    }

    /// Proactively refresh the access token when it's inside the expiry
    /// window — called on every foreground so a session that stays open
    /// for hours never starts silently 401ing mid-use. Cheap no-op when
    /// the token is still comfortably fresh.
    @MainActor
    func refreshSessionIfExpiringSoon() async {
        guard user != nil, !isSigningIn else { return }
        guard let token = KeychainHelper.get("access_token") else {
            // Signed in but the access token vanished — restore it now.
            await refreshToken()
            return
        }
        guard let exp = decodePayload(token)?.exp else { return }
        let remaining = Date(timeIntervalSince1970: exp).timeIntervalSinceNow
        guard remaining < 15 * 60 else { return }
        print("[AuthManager] access token expires in \(Int(remaining))s — proactive refresh")
        await refreshToken()
    }

    @MainActor
    func signOut() async {
        KeychainHelper.delete("access_token")
        KeychainHelper.delete("refresh_token")
        UserDefaults.standard.removeObject(forKey: "RORK_AUTH_REFRESH_TOKEN")
        user = nil
        sessionExpired = false
    }

    /// Permanently erase all of the user's data via the `delete-account`
    /// edge function, then sign out locally. Returns true on success.
    @MainActor
    func deleteAccount() async -> Bool {
        do {
            let _: DeleteAccountResponse = try await supabase.functions.invoke(
                "delete-account",
                options: .init(method: .post)
            )
            await signOut()
            return true
        } catch {
            setError("Couldn't delete your account. Please try again.")
            return false
        }
    }

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }

    /// Mirror the signed-in user's identity into the `profiles` table so
    /// RLS-protected rows in other tables can safely reference a real
    /// profile row via `user_id()`. Fire-and-forget: a sync failure is
    /// logged but never blocks the UI or the sign-in flow. The Supabase
    /// client reads the freshly-stored access token from the Keychain, so
    /// the upsert runs as the authenticated user.
    private func syncProfile(_ user: User) {
        Task {
            do {
                try await supabase
                    .from("profiles")
                    .upsert(
                        ProfileUpsert(
                            id: user.id,
                            email: user.email,
                            name: user.name,
                            avatarUrl: user.picture
                        ),
                        // `email` is write-only: signed-in members have no
                        // SELECT privilege on that column, so asking
                        // PostgREST to return the row would fail the whole
                        // upsert. Nothing here needs the row back.
                        returning: .minimal
                    )
                    .execute()
            } catch {
                print("[AuthManager] Profile sync failed: \(error)")
            }
        }
    }
}

// MARK: - Profile sync

/// Encodable payload for upserting the current user's `profiles` row.
nonisolated struct ProfileUpsert: Encodable, Sendable {
    let id: String
    let email: String
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case avatarUrl = "avatar_url"
    }
}

// MARK: - Response Types

nonisolated struct DeleteAccountResponse: Codable, Sendable {
    let ok: Bool?
}

private struct InitiateResponse: Codable {
    let auth_url: String
    let state: String
    let flow: String?
}

private struct PollCodeResponse: Codable {
    let status: String
    let code: String?
}

private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let user: AuthManager.User
}

private struct RefreshResponse: Codable {
    let access_token: String
    let expires_in: Int
}

private struct ErrorResponse: Codable {
    let error: String
}

enum AuthError: LocalizedError {
    case noCode
    case invalidURL
    case serverError(statusCode: Int)
    case popupTimeout
    case cancelledByUser

    var errorDescription: String? {
        switch self {
        case .noCode: return "No authorization code received"
        case .invalidURL: return "Invalid URL"
        case .serverError(let code): return "Server error (\(code))"
        case .popupTimeout: return "Sign-in timed out — please try again"
        case .cancelledByUser: return "Sign-in cancelled by user"
        }
    }
}

// MARK: - ASWebAuthenticationSession Helper

class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
