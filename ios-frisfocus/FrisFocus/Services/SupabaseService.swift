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

let supabase = SupabaseClient(
    supabaseURL: URL(string: Config.EXPO_PUBLIC_SUPABASE_URL)!,
    supabaseKey: Config.EXPO_PUBLIC_SUPABASE_ANON_KEY,
    options: .init(
        auth: .init(
            accessToken: {
                KeychainHelper.get("access_token")
            }
        )
    )
)
