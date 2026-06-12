//
//  ContentView.swift
//  FrisFocus
//
//  Root container. Reads the Store from environment, kicks off the
//  day-rollover housekeeping on appear and whenever the scene returns
//  to `.active` (so a user who left the app open overnight rolls over
//  cleanly when they tap back in).
//

import SwiftUI

/// An invite link's target, wrapped so it can drive a `.sheet(item:)`.
private struct InviteTarget: Identifiable {
    let id: String
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(ModerationService.self) private var moderation
    @Environment(NotificationManager.self) private var notifications
    @Environment(CadenceLinkService.self) private var cadence
    @Environment(MessageGraphService.self) private var messageGraph
    @Environment(GoldenHourService.self) private var goldenHour
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(FriendGraphService.self) private var friendGraph
    @Environment(NotesSyncService.self) private var notesSync
    @Environment(SeasonSyncService.self) private var seasonSync
    @Environment(\.scenePhase) private var scenePhase

    @State private var pendingInvite: InviteTarget?

    var body: some View {
        HomeView()
            .onOpenURL { url in
                // A shared invite link (or scanned QR) opens us straight
                // to the inviter's profile with an Add control.
                if let userId = InviteLink.userId(from: url) {
                    pendingInvite = InviteTarget(id: userId)
                }
            }
            .sheet(item: $pendingInvite) { target in
                AddFriendLinkView(userId: target.id)
                    .environment(auth)
            }
            .task(id: auth.user?.id) {
                // Keep the user's own editable profile (custom name,
                // @username, photo) in sync with who is signed in, and tell
                // the notification manager who owns this device's token.
                if let myId = auth.user?.id {
                    notifications.setUserId(myId)
                    // Messaging is app-wide: load the recent window and
                    // subscribe to realtime once, so unread badges stay
                    // live on every screen — not just inside Circles.
                    await messageGraph.load(myUserId: myId)
                    messageGraph.startRealtime(myUserId: myId)
                    // The friend graph is app-wide too: live requests and
                    // accepts raise in-app banners and the avatar dot from
                    // anywhere in the app.
                    await friendGraph.load(myUserId: myId)
                    friendGraph.startRealtime(myUserId: myId)
                    // Golden Hour: settings + today's moment + synchronized
                    // local notifications, live across the whole app.
                    await goldenHour.load(myUserId: myId)
                    goldenHour.startRealtime(myUserId: myId)
                    await profileStore.load(myUserId: myId)
                    await moderation.loadBlocks(myUserId: myId)
                    // The full social mirror: friends, stories, cheers,
                    // pacts, circles, and grove presence — synced into
                    // the Store and kept live over realtime.
                    await socialSync.start(myUserId: myId, store: store)
                    // Private journal sync: notes, folders, tags, and
                    // their media follow the account — offline-first.
                    await notesSync.start(myUserId: myId, store: store)
                    // Private season sync: season, tasks, score history,
                    // and milestones follow the account too.
                    await seasonSync.start(myUserId: myId, store: store)
                    await notifications.requestAuthorizationIfNeeded()
                    // Esengo link: refresh entitlements + silently credit
                    // any outcomes Cadence recorded while we were away.
                    await cadence.refresh(myUserId: myId)
                    await cadence.sync(into: store, myUserId: myId)
                } else {
                    notifications.setUserId(nil)
                    messageGraph.stopRealtime()
                    friendGraph.stopRealtime()
                    goldenHour.clear()
                    profileStore.clear()
                    moderation.clear()
                    socialSync.stop()
                    notesSync.stop()
                    seasonSync.stop()
                    await cadence.refresh(myUserId: nil)
                }
            }
            .onAppear {
                print("[FrisFocus] Tasks: \(store.tasks.count), To-dos: \(store.todos.count), Notes: \(store.notes.count), LogEntries: \(store.logEntries.count)")
                store.performDayRolloverIfNeeded()
                // Keep milestone target-week nudges aligned with the
                // season's current milestones on every launch.
                store.refreshMilestoneNudges()
                // Safety net: if no focus block is running, make sure no
                // app shield was left applied by a previous crash/kill.
                if store.activeFocusSession == nil && store.activeSharedFocusBlock == nil {
                    FocusBlockingService.shared.endShielding()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.performDayRolloverIfNeeded()
                    // The user is looking at the app — the icon badge
                    // shouldn't keep nagging about things they can now see.
                    NotificationManager.clearBadge()
                    if let myId = auth.user?.id {
                        Task { await cadence.sync(into: store, myUserId: myId) }
                        // Catch up on anything that arrived while the
                        // socket was suspended in the background.
                        Task { await messageGraph.load(myUserId: myId) }
                        Task { await friendGraph.load(myUserId: myId) }
                        // Re-resolve today's Golden Hour moment (a turns-mode
                        // pick may have landed) and refresh the alerts.
                        Task { await goldenHour.load(myUserId: myId) }
                        // Catch up the social mirror and nudge the
                        // test-user engine so simulated friends react.
                        Task {
                            await socialSync.refreshAll()
                            socialSync.pokeEngine(trigger: "foreground")
                        }
                        // Catch up the journal: pull remote edits and
                        // flush anything queued while offline.
                        Task {
                            await notesSync.pullRemote()
                            await notesSync.flushNow()
                        }
                        // Catch up the season the same way.
                        Task {
                            await seasonSync.pullRemote()
                            await seasonSync.flushNow()
                        }
                    }
                } else if newPhase == .background || newPhase == .inactive {
                    // Safety net: flush any debounced, not-yet-written
                    // saves before iOS can suspend or kill the process.
                    store.flushPendingSaves()
                }
            }
    }
}

#Preview {
    ContentView()
        .environment(Store())
}
