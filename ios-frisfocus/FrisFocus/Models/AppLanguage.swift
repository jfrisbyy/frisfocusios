//
//  AppLanguage.swift
//  FrisFocus
//
//  The language the app uses. Today this drives voice transcription in
//  season setup (so a French-set phone can still transcribe English
//  speech), and lays the groundwork for translating the rest of the app
//  later. Each case maps to a BCP-47 locale identifier that
//  `SFSpeechRecognizer` understands.
//

import Foundation

/// A language the user can choose for the app. The raw value is the
/// locale identifier used for speech recognition.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english = "en-US"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"
    case italian = "it-IT"
    case portuguese = "pt-BR"
    case dutch = "nl-NL"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case mandarin = "zh-CN"

    var id: String { rawValue }

    /// The default language the app's conversation is authored in.
    static let `default`: AppLanguage = .english

    /// Locale used to build the speech recognizer.
    var locale: Locale { Locale(identifier: rawValue) }

    /// English display name, shown in the settings list.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch: return "Dutch"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .mandarin: return "Chinese (Simplified)"
        }
    }

    /// Name written in the language itself, shown as a quiet subtitle.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .dutch: return "Nederlands"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .mandarin: return "中文"
        }
    }
}
