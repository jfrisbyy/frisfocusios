//
//  FrisFocusApp.swift
//  FrisFocus
//

import SwiftUI

@main
struct FrisFocusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()
    @State private var authManager = AuthManager()
    @State private var profileStore = ProfileStore()
    @State private var moderationService = ModerationService()
    @State private var cadenceLink = CadenceLinkService()
    /// One app-wide messaging service: realtime, unread counts, and
    /// optimistic/failed sends stay consistent across Home, Circles,
    /// the inbox, and every thread — and the unread badge never goes
    /// stale just because a particular screen wasn't open.
    @State private var messageGraph = MessageGraphService()
    /// One app-wide Golden Hour service: deterministic fire moments,
    /// synchronized local notifications, posts, and the sweep — so the
    /// golden orb is accurate on every surface.
    @State private var goldenHour = GoldenHourService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(authManager)
                .environment(profileStore)
                .environment(moderationService)
                .environment(cadenceLink)
                .environment(messageGraph)
                .environment(goldenHour)
                .environment(appDelegate.notifications)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}
