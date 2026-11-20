//
//  Config.swift
//  FrisFocus
//
//  Build-time configuration. THIS FILE IS A TEMPLATE.
//
//  The real `Config.swift` lives at `ios-frisfocus/FrisFocus/Config.swift`
//  and IS TRACKED: it is the build platform's own file, committed with
//  every value an empty string, and the real values are injected at iOS
//  build time. To build locally against a real backend, overwrite it
//  with:
//
//      scripts/bootstrap-config.sh
//
//  which reads the FRISFOCUS_* environment variables (falling back to the
//  placeholders below) and writes the file into place. That dirties a
//  tracked file, so discard it before committing:
//
//      git checkout -- ios-frisfocus/FrisFocus/Config.swift
//
//  Never commit a generated file carrying real values — add new keys HERE
//  and to `scripts/bootstrap-config.sh`, so a fresh clone and CI both keep
//  building.
//
//  NOTE: this template deliberately lives OUTSIDE the `FrisFocus/` folder.
//  That folder is a PBXFileSystemSynchronizedRootGroup, so any `.swift`
//  file inside it is compiled automatically — a second file declaring
//  `Config` there would be a duplicate-symbol build failure.
//

import Foundation

enum Config {
    /// Supabase project URL, e.g. https://<ref>.supabase.co
    static let EXPO_PUBLIC_SUPABASE_URL = "__SUPABASE_URL__"

    /// Supabase anon/publishable key. Safe to ship in the binary ONLY
    /// while every table is protected by row-level security.
    static let EXPO_PUBLIC_SUPABASE_ANON_KEY = "__SUPABASE_ANON_KEY__"

    /// Rork Auth issuer base URL, e.g. https://api.rork.com
    static let EXPO_PUBLIC_RORK_AUTH_URL = "__RORK_AUTH_URL__"

    /// Rork app key identifying this app to the auth service.
    static let EXPO_PUBLIC_RORK_APP_KEY = "__RORK_APP_KEY__"

    /// Rork project id, sent alongside the app key.
    static let EXPO_PUBLIC_PROJECT_ID = "__PROJECT_ID__"
}
