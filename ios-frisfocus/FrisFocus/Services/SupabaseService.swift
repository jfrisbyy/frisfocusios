//
//  SupabaseService.swift
//  FrisFocus
//
//  Shared Supabase client. Reads the project URL + anon key from `Config`
//  (injected at build time from the EXPO_PUBLIC_SUPABASE_* environment
//  variables you connected).
//
//  The `accessToken` closure hands Supabase the Rork Auth JWT when the
//  user is signed in, so row-level-security policies can identify the user
//  via `user_id()`. When signed out it returns `nil`, so requests run as
//  the `anon` role. We read the token straight from the Keychain so this
//  closure stays free of any main-actor state.
//

import Foundation
import Supabase

/// Resolves the client's URL and key without force-unwrapping.
///
/// `Config.swift` is committed with every value empty and filled in at
/// build time. A build where that injection did not happen used to crash
/// at launch on `URL(string: "")!`, before a single screen was drawn. Now
/// an empty or unusable URL falls back to the project's live URL (the
/// same fallback `InviteLink` uses), and an empty anon key is reported
/// loudly in the console instead — requests will be rejected until the
/// key is injected, but the app stays up and says why.
private nonisolated enum SupabaseConfig {
    static let fallbackURL = "https://pgrsrgctuclcmbhqnlqo.supabase.co"

    static func resolvedURL() -> URL {
        let configured = Config.EXPO_PUBLIC_SUPABASE_URL
        if let url = URL(string: configured), url.host != nil {
            return url
        }
        Log.app.error("EXPO_PUBLIC_SUPABASE_URL is empty or invalid in this build; falling back to the known project URL.")
        return URL(string: fallbackURL) ?? URL(fileURLWithPath: "/")
    }

    static func resolvedAnonKey() -> String {
        let key = Config.EXPO_PUBLIC_SUPABASE_ANON_KEY
        if key.isEmpty {
            Log.app.error("EXPO_PUBLIC_SUPABASE_ANON_KEY is empty in this build; every Supabase request will be rejected until the key is injected.")
        }
        return key
    }
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.resolvedURL(),
    supabaseKey: SupabaseConfig.resolvedAnonKey(),
    options: .init(
        auth: .init(
            accessToken: {
                // Every request passes through here, so this is where a
                // stale token is caught: `SessionAccessToken` refreshes
                // an expired (or about-to-expire) session once before
                // the request goes out, instead of letting it 401.
                await SessionAccessToken.current()
            }
        )
    )
)
