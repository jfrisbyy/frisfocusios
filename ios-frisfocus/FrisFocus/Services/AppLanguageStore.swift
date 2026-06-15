//
//  AppLanguageStore.swift
//  FrisFocus
//
//  Owns the user's chosen app language and persists it. Today it drives
//  speech transcription in season setup; it's the single source of truth
//  for any future localization work.
//
//  A small shared singleton so non-UI services (like the speech capture
//  service, which isn't in the SwiftUI environment) can read the current
//  language without prop-drilling.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppLanguageStore {
    /// Shared instance — read by services outside the view tree.
    static let shared = AppLanguageStore()

    private static let defaultsKey = "app.language"
    private let defaults = UserDefaults.standard

    /// The active language. Setting it persists immediately.
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let stored = AppLanguage(rawValue: raw) {
            language = stored
        } else {
            language = .default
        }
    }

    /// Locale to build a speech recognizer with for the current language.
    var speechLocale: Locale { language.locale }
}
