//
//  SeasonSetupResumeStore.swift
//  FrisFocus
//
//  Lightweight persistence for a single in-progress season-setup
//  conversation. The whole conversation (history, recognized threads,
//  the live question, and arc progress) is encoded into UserDefaults so
//  the user can leave the guided setup and resume the exact same chat
//  later — even across an app relaunch.
//
//  Only ONE in-progress setup is kept at a time; saving overwrites the
//  previous snapshot. The snapshot is cleared once setup is finished
//  (the season starts) or the user discards it.
//

import Foundation

enum SeasonSetupResumeStore {
    private static let key = "seasonSetup.resumeSnapshot.v1"

    /// True when a resumable in-progress conversation exists.
    static var hasSaved: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    /// The saved snapshot, if any.
    static func load() -> SetupConversationSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(SetupConversationSnapshot.self, from: data)
        } catch {
            Log.seasonSetupResume.error("decode failed: \(error)")
            // A corrupt snapshot shouldn't strand the user — drop it.
            clear()
            return nil
        }
    }

    /// Persist (or overwrite) the in-progress conversation.
    static func save(_ snapshot: SetupConversationSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            Log.seasonSetupResume.error("encode failed: \(error)")
        }
    }

    /// Forget the saved conversation.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
