//
//  Log.swift
//  FrisFocus
//
//  One `Logger` per subsystem, replacing 162 `print` calls.
//
//  Three reasons this is not cosmetic:
//
//  1. `print` still runs in a Release build. Every one of those calls
//     formats its string and writes to stdout on a shipped device, where
//     nothing is listening. `Logger` at .debug is compiled to a no-op
//     unless something is actually collecting.
//
//  2. A line like "signed in as user=\(id)" wrote a real account id
//     into the device log, readable by anything that could read the log
//     — including a sysdiagnose the person emails to support. `sensitive`
//     marks those call sites so the value is redacted in the log store.
//
//  3. Categories make the log filterable. "Why did this sync fail" used
//     to mean reading everything; now it is one predicate in Console.
//
//  The category names are the tags the old `[Tag]` prefixes already
//  used, so the mapping from an old log line to a new one is direct.
//

import Foundation
import os

/// One category's log.
///
/// A thin wrapper rather than a bare `Logger` on purpose. `Logger`'s own
/// interpolation only accepts a fixed set of types — String, the numeric
/// families, Bool, NSObject — and 133 of the call sites here interpolate
/// a Swift `Error`, which is none of those and does not compile. Taking
/// an already-built `String` accepts every existing message unchanged.
///
/// The `@autoclosure` is what keeps the first reason above true: at
/// `.debug`, the message is not even built unless something is
/// collecting.
struct AppLog: Sendable {
    private let logger: Logger

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    /// Ordinary tracing. Free when nothing is listening.
    func debug(_ message: @autoclosure () -> String) {
        guard logger.isEnabled(type: .debug) else { return }
        logger.debug("\(message(), privacy: .public)")
    }

    /// Something went wrong. Always recorded — this is what a support
    /// sysdiagnose is read for.
    func error(_ message: @autoclosure () -> String) {
        logger.error("\(message(), privacy: .public)")
    }

    /// Carries something belonging to a person — an account id, a name,
    /// the content of a message. Redacted in the log store, so it reads
    /// as `<private>` to anyone who did not attach a debugger.
    func sensitive(_ message: @autoclosure () -> String) {
        guard logger.isEnabled(type: .debug) else { return }
        logger.debug("\(message(), privacy: .private)")
    }
}

enum Log {
    /// Everything ships under one subsystem so Console can filter the
    /// whole app in one predicate.
    private static let subsystem = "com.frisfocus.app"

    private static func make(_ category: String) -> AppLog {
        AppLog(subsystem: subsystem, category: category)
    }

    // Sync + networking
    static let socialSync = make("SocialSync")
    static let seasonSync = make("SeasonSync")
    static let notesSync = make("NotesSync")
    static let messageGraph = make("MessageGraph")
    static let friendGraph = make("FriendGraph")
    static let circleGraph = make("CircleGraph")
    static let cadence = make("Cadence")
    static let discover = make("Discover")
    static let contactsMatch = make("ContactsMatch")

    // Identity + safety
    static let auth = make("AuthManager")
    static let moderation = make("Moderation")
    static let profileStore = make("ProfileStore")

    // Delivery
    static let notifications = make("Notifications")
    static let push = make("Push")
    static let reminders = make("Reminders")
    static let events = make("Events")
    static let milestoneNudge = make("MilestoneNudge")

    // Media
    static let proofLibrary = make("ProofLibrary")
    static let proofMediaCache = make("ProofMediaCache")
    static let proofPin = make("ProofPin")
    static let proofPlayer = make("ProofPlayer")
    static let notePhotoStore = make("NotePhotoStore")
    static let milestoneMediaStore = make("MilestoneMediaStore")
    static let videoTranscoder = make("VideoTranscoder")
    static let videoPlaybackAudio = make("VideoPlaybackAudio")
    static let captureDraft = make("CaptureDraft")

    // The app itself
    static let store = make("Store")
    static let app = make("FrisFocus")
    static let goldenHour = make("GoldenHour")
    static let focusBlocking = make("FocusBlocking")
    static let walkthrough = make("Walkthrough")
    static let seasonSetup = make("SeasonSetup")
    static let seasonSetupAI = make("SeasonSetupAI")
    static let seasonSetupResume = make("SeasonSetupResume")
    static let diagnostics = make("Diagnostics")
}
