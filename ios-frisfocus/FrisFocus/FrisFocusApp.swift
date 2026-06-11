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
    /// The social sync bridge: mirrors the real friend graph, stories,
    /// cheers, pacts, circles, and grove presence between Supabase and
    /// the local Store, app-wide.
    @State private var socialSync = SocialSyncService()
    /// One app-wide friend graph: live friends + pending requests with
    /// realtime, so request banners and the unseen-request dot work on
    /// every screen — not just while the Friends page is open.
    @State private var friendGraph = FriendGraphService()
    /// Private journal sync: notes, folders, tags, voice memos, and
    /// photos mirror to the user's own cloud space — offline-first,
    /// latest-wins.
    @State private var notesSync = NotesSyncService()
    /// Private season sync: the season, tasks, score history, and
    /// milestones (with their steps + journey media) mirror to the
    /// user's own cloud space — offline-first, latest-wins per slice.
    @State private var seasonSync = SeasonSyncService()

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
                .environment(socialSync)
                .environment(friendGraph)
                .environment(notesSync)
                .environment(seasonSync)
                .environment(appDelegate.notifications)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}
