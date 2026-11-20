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
    /// Heading for the error alert. Not every failure is a sign-in: a
    /// failed account deletion used to appear under "Sign in failed".
    var errorTitle = "Sign in failed"
    /// True when the session was ended WITHOUT the user asking — the
    /// refresh token was rejected by the auth server. The home shows a
    /// visible "sign back in" banner instead of silently looking empty.
    var sessionExpired = false
    /// True while a sign-out or account deletion is finishing (pushing
    /// unsent edits, then clearing the device). Lets the account screen
    /// disable its buttons instead of accepting a second tap.
    var isEndingSession = false

    /// Decides — and carries out — what happens to the account data on
    /// this device when a session begins or ends. The root view attaches
    /// the Store and sync services to it once they exist.
    let accountData = AccountDataCoordinator()

    private let authURL = Config.EXPO_PUBLIC_RORK_AUTH_URL
    private let appKey = Config.EXPO_PUBLIC_RORK_APP_KEY
    private let projectID = Config.EXPO_PUBLIC_PROJECT_ID
    private var codeVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?

    /// The app's one AuthManager, so the Supabase client's token
    /// provider (which runs off the main actor, with no view in reach)
    /// can ask for a refresh. Weak: this never keeps it alive.
    static weak var live: AuthManager?
    /// The refresh a request is currently waiting on, if any — every
    /// request that finds the token stale shares this one instead of
    /// starting its own.
    @ObservationIgnored private var requestRefresh: Task<Void, Never>?
    /// When a request last asked for a refresh, so a refresh that just
    /// failed (offline) is not re-attempted by every request behind it.
    @ObservationIgnored private var lastRequestRefreshAt: Date?
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
        AuthManager.live = self
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

    /// The user for a session that was just issued, identified the way
    /// every later launch will identify them: by the access token's
    /// subject. The sign-in response and the token should agree; if
    /// they ever did not, the id would silently change between the
    /// first session and the next launch — and local data is now tied
    /// to the id it was created under, so that must not happen.
    private func sessionUser(_ responseUser: User, accessToken: String) -> User {
        guard let subject = decodePayload(accessToken)?.sub, subject != responseUser.id else {
            return responseUser
        }
        Log.auth.error("sign-in: response user id differs from the token subject — using the token subject")
        return User(
            id: subject,
            email: responseUser.email,
            name: responseUser.name,
            picture: responseUser.picture
        )
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
            accountData.prepareLocalData(forUserId: user.id)
            self.user = user
            Log.auth.sensitive("checkAuth: restored session from access token, user=\(user.id)")
            syncProfile(user)
            return
        }

        // Token missing or expired — try refresh
        if getRefreshToken() != nil {
            Log.auth.debug("checkAuth: no valid access token, attempting refresh")
            await refreshToken()
        } else {
            Log.auth.debug("checkAuth: no access token and no refresh token — signed out")
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

            // Before anything can observe the new session: if this
            // device is in the demo or holds another account's data,
            // clear it now, so no sync service ever starts on top of it.
            let signedIn = sessionUser(tokenResponse.user, accessToken: tokenResponse.access_token)
            accountData.prepareLocalData(forUserId: signedIn.id)
            user = signedIn
            sessionExpired = false
            syncProfile(signedIn)
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
                // 408 (timeout) and 429 (rate limit) say "not now", not
                // "never" — they must not end a valid session, least of
                // all now that a stale token is refreshed at request time.
                if (400...499).contains(code), code != 408, code != 429 {
                    // The auth server definitively rejected the refresh
                    // token — the session is over. Sign out, but say so
                    // visibly instead of silently looking empty.
                    Log.auth.error("refreshToken: refresh rejected (\(code)) — signing out, flagging expiry")
                    await expireSession()
                } else {
                    // Server hiccup (5xx) — keep the stored tokens and
                    // retry on the next foreground instead of destroying
                    // a probably-valid session.
                    Log.auth.debug("refreshToken: refresh endpoint returned \(code) — keeping session for retry")
                }
                return
            }

            let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
            KeychainHelper.set("access_token", value: refreshResponse.access_token)

            let refreshedUser = userFromToken(refreshResponse.access_token)
            if let refreshedUser {
                accountData.prepareLocalData(forUserId: refreshedUser.id)
            }
            user = refreshedUser
            if let refreshedUser {
                Log.auth.sensitive("refreshToken: session refreshed, user=\(refreshedUser.id)")
                sessionExpired = false
                syncProfile(refreshedUser)
            } else {
                Log.auth.debug("refreshToken: refresh succeeded but token had no user")
            }
        } catch {
            // Network failure (offline launch, timeout) — never destroy
            // the session over connectivity. Tokens stay; the app retries
            // silently when it becomes active again.
            Log.auth.error("refreshToken: network failure (\(error.localizedDescription)) — keeping session for retry")
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
        Log.auth.debug("retryRestoreIfNeeded: tokens present, retrying silent restore")
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
        Log.auth.debug("access token expires in \(Int(remaining))s — proactive refresh")
        await refreshToken()
    }

    /// Refresh the access token because a request is about to go out
    /// with one that has expired (or is about to). Until this existed
    /// the token was only refreshed on foreground, so a session left
    /// open past its expiry started failing every request with a 401
    /// until the person happened to leave the app and come back.
    ///
    /// One refresh serves every request that asks while it is in
    /// flight, and a failed attempt is not repeated for 20 seconds, so
    /// a burst of requests on a dead network costs one call, not one
    /// each.
    @MainActor
    func refreshForRequestIfNeeded() async {
        if let inFlight = requestRefresh {
            await inFlight.value
            return
        }
        // (Deliberately allowed while a sign-out is finishing: its final
        // upload of unsent edits needs a working token more than most.)
        guard user != nil, !isSigningIn else { return }
        if let last = lastRequestRefreshAt, Date().timeIntervalSince(last) < 20 { return }
        lastRequestRefreshAt = Date()
        Log.auth.debug("access token stale at request time — refreshing before sending")
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshToken()
        }
        requestRefresh = task
        await task.value
        requestRefresh = nil
    }

    /// Entry point for code that cannot hold a reference to the live
    /// AuthManager (the Supabase client's token provider).
    @MainActor
    static func refreshForRequest() async {
        await live?.refreshForRequestIfNeeded()
    }

    /// Sign out because the person asked to.
    ///
    /// Unsent edits get one bounded chance to upload first. Then the
    /// device is wiped back to first-run — the account is the source of
    /// truth for a signed-in person, and data left behind here was being
    /// uploaded into the NEXT account to sign in on this phone. If
    /// something could not be uploaded (offline, a failed request, proof
    /// media waiting for Wi-Fi), the data is kept on disk behind the
    /// first-run cover rather than destroyed; see
    /// `AccountDataCoordinator`.
    @MainActor
    func signOut() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        defer { isEndingSession = false }

        // While the token still works: push what the account is missing
        // and decide the fate of the on-device data.
        let disposition = await accountData.sessionWillEnd(.userSignOut)

        // Remove this device's push token while the session can still
        // authorise the delete, so the account being left stops
        // notifying this phone. Bounded by its own timeout — sign-out
        // never waits on the network for longer than that.
        await NotificationManager.unregisterDevice()

        clearSession(disposition)
    }

    /// End a session the auth server ended for us (refresh token
    /// rejected). Nobody asked to leave, so nothing on the device is
    /// touched: the home says "sign back in" and the same person picks
    /// up where they were. If someone ELSE signs in instead, their
    /// sign-in wipes the device first.
    @MainActor
    private func expireSession() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        defer { isEndingSession = false }

        let disposition = await accountData.sessionWillEnd(.sessionExpired)

        // No push-token removal here: the access token is already
        // rejected, so the delete could not be authorised. The next
        // account to sign in on this phone claims the token instead.

        clearSession(disposition)
        sessionExpired = true
    }

    /// The part every session ending shares: tokens, onboarding
    /// residue, the on-device data per `disposition`, then the
    /// signed-out state itself — in that order, so nothing observing
    /// `user` ever sees a signed-out app that still shows the data.
    @MainActor
    private func clearSession(_ disposition: LocalDataDisposition) {
        KeychainHelper.delete("access_token")
        KeychainHelper.delete("refresh_token")
        UserDefaults.standard.removeObject(forKey: "RORK_AUTH_REFRESH_TOKEN")
        // A half-finished season conversation is one of the most personal
        // things this app ever holds — the job, the health, the sleep, the
        // drinking, whatever the person was in the middle of saying. It
        // lived in a device-wide UserDefaults key that survived sign-out,
        // so the next account to open this phone was offered "Pick the
        // conversation back up", and the settings screen printed the last
        // question the PREVIOUS person had been asked, verbatim.
        SeasonSetupResumeStore.clear()
        OnboardingProgress.clear()
        accountData.sessionDidEnd(disposition)
        user = nil
        sessionExpired = false
    }

    /// Permanently erase all of the user's data via the `delete-account`
    /// edge function, then erase it from this device too and return to
    /// first-run. Returns true on success. Nothing is uploaded on the
    /// way out — the account no longer exists to receive it — and
    /// nothing is left behind to be re-uploaded if the same person
    /// signs in again.
    @MainActor
    func deleteAccount() async -> Bool {
        guard !isEndingSession else { return false }
        isEndingSession = true
        defer { isEndingSession = false }
        do {
            let _: DeleteAccountResponse = try await supabase.functions.invoke(
                "delete-account",
                options: .init(method: .post)
            )
        } catch {
            setError("Couldn't delete your account. Please try again.", title: "Couldn't delete account")
            return false
        }

        let disposition = await accountData.sessionWillEnd(.accountDeleted)

        // No push-token removal here: deleting the account already
        // removed its device tokens server-side.

        clearSession(disposition)
        return true
    }

    private func setError(_ message: String, title: String = "Sign in failed") {
        errorTitle = title
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
                Log.auth.error("Profile sync failed: \(error)")
            }
        }
    }
}

// MARK: - Request-time access token

/// The access token to send with a request made right now.
///
/// This is the one place every Supabase request passes through, so it
/// is where a stale token is caught: if the stored token has expired
/// (or is within a minute of it), the session is refreshed first and
/// the request goes out with the new token — instead of going out with
/// the old one and coming back 401.
///
/// `nonisolated` throughout: the Supabase client calls its token
/// provider off the main actor.
nonisolated enum SessionAccessToken {
    /// Refresh when the token has less than this long to live.
    static let refreshMargin: TimeInterval = 60

    /// The `exp` claim of a JWT, if it has a readable one. The signature
    /// is not checked — this only reads a clock off a token the app
    /// stored itself.
    static func expiry(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any],
              let exp = payload["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Whether a token with this expiry should be refreshed before it
    /// is sent. A token with no readable expiry is left alone.
    static func needsRefresh(expiry: Date?, now: Date, margin: TimeInterval) -> Bool {
        guard let expiry else { return false }
        return expiry.timeIntervalSince(now) < margin
    }

    /// The token for a request going out now — refreshed first when
    /// stale. Nil when signed out (the request runs as `anon`).
    static func current() async -> String? {
        guard let token = KeychainHelper.get("access_token") else { return nil }
        let stale = needsRefresh(expiry: expiry(ofJWT: token), now: Date(), margin: refreshMargin)
        guard stale else { return token }
        await AuthManager.refreshForRequest()
        return KeychainHelper.get("access_token")
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
