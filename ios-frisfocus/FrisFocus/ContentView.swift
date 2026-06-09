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
                    await profileStore.load(myUserId: myId)
                    await moderation.loadBlocks(myUserId: myId)
                    await notifications.requestAuthorizationIfNeeded()
                    // Esengo link: refresh entitlements + silently credit
                    // any outcomes Cadence recorded while we were away.
                    await cadence.refresh(myUserId: myId)
                    await cadence.sync(into: store, myUserId: myId)
                } else {
                    notifications.setUserId(nil)
                    profileStore.clear()
                    moderation.clear()
                    await cadence.refresh(myUserId: nil)
                }
            }
            .onAppear {
                print("[FrisFocus] Tasks: \(store.tasks.count), To-dos: \(store.todos.count), Notes: \(store.notes.count), LogEntries: \(store.logEntries.count)")
                store.performDayRolloverIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.performDayRolloverIfNeeded()
                    if let myId = auth.user?.id {
                        Task { await cadence.sync(into: store, myUserId: myId) }
                    }
                }
            }
    }
}

#Preview {
    ContentView()
        .environment(Store())
}
