//
//  ContentView.swift
//  FrisFocus
//
//  Root container. Reads the Store from environment, kicks off the
//  day-rollover housekeeping on appear and whenever the scene returns
//  to `.active` (so a user who left the app open overnight rolls over
//  cleanly when they tap back in).
//

import Combine
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
    @State private var showSeasonSetupFromComplete: Bool = false
    /// Drives guided season setup after a clean start or leaving the demo.
    @State private var showCleanSeasonSetup: Bool = false
    /// Confirmation before wiping the sample sandbox.
    @State private var showExitDemoConfirm: Bool = false
    /// True once a returning user signed in from the welcome intro, so
    /// dismissing the cover never bounces them into guided season setup
    /// while their real season is still restoring from the cloud.
    @State private var didSignInFromIntro: Bool = false

    /// True while the first-run welcome should cover the home. The
    /// setter is a no-op — the cover only dismisses once the user's
    /// choice flips `appMode` out of `.uninitialized`.
    private var introBinding: Binding<Bool> {
        Binding(
            get: { store.needsFirstRunIntro },
            set: { _ in }
        )
    }

    var body: some View {
        @Bindable var store = store
        return HomeView()
            // Demo marker — a small, always-legible pill while exploring
            // the sample sandbox, tappable to leave it.
            .overlay(alignment: .top) {
                if store.appMode == .demo {
                    DemoModePill { showExitDemoConfirm = true }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.appMode)
            .confirmationDialog(
                "Exit demo?",
                isPresented: $showExitDemoConfirm,
                titleVisibility: .visible
            ) {
                Button("Exit and start fresh", role: .destructive) {
                    store.exitDemo()
                }
                Button("Keep exploring", role: .cancel) {}
            } message: {
                Text("This clears all the sample data and starts your own season from scratch. Nothing from the demo is kept.")
            }
            // First-launch welcome — covers the home until the user picks
            // a path. Non-dismissible: a choice must be made.
            .fullScreenCover(isPresented: introBinding, onDismiss: {
                if store.needsSeasonSetup && !didSignInFromIntro { showCleanSeasonSetup = true }
            }) {
                FirstRunIntroView(
                    onStartDemo: { store.startDemo() }
                )
                .interactiveDismissDisabled(true)
            }
            // Guided season setup for a clean start / after exiting the demo.
            .fullScreenCover(isPresented: $showCleanSeasonSetup) {
                SeasonSetupFlowView()
            }
            // Leaving the demo (from anywhere) transitions demo → clean;
            // open guided setup once the wipe lands.
            .onChange(of: store.appMode) { old, new in
                if old == .demo && new == .clean {
                    showCleanSeasonSetup = true
                }
            }
            .sheet(isPresented: $store.showCarryForwardPrompt) {
                CarryForwardPromptView(candidates: store.carryForwardCandidates)
                    .environment(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
            .alert("Every milestone landed", isPresented: $store.showSeasonCompletePrompt) {
                Button("Start the next season") {
                    showSeasonSetupFromComplete = true
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("You’ve reached every milestone of \(store.currentSeason.name). Start a fresh season whenever you’re ready — nothing changes until you do.")
            }
            .fullScreenCover(isPresented: $showSeasonSetupFromComplete) {
                SeasonSetupFlowView()
            }
            .environment(store)
            // A returning user signing in from the welcome intro: move the
            // Store out of `.uninitialized` so the cover dismisses straight
            // onto home. Their real data restores via the sync `.task`
            // below; we flag the sign-in so setup never auto-launches.
            .onChange(of: auth.user?.id) { _, newId in
                if newId != nil && store.appMode == .uninitialized {
                    didSignInFromIntro = true
                    store.restoreFromSignIn()
                }
            }
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
                store.evaluateCarryForwardPrompt()
                // Keep milestone target-week nudges aligned with the
                // season's current milestones on every launch.
                store.refreshMilestoneNudges()
                // Safety net: if no focus block is running, make sure no
                // app shield was left applied by a previous crash/kill.
                if store.activeFocusSession == nil && store.activeSharedFocusBlock == nil {
                    FocusBlockingService.shared.endShielding()
                }
            }
            // True midnight watcher: iOS posts this the moment the local
            // calendar day changes (midnight, timezone change, DST). With
            // the app sitting open overnight, this rolls pins + notes over
            // on the spot instead of waiting for a background/foreground hop.
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .NSCalendarDayChanged)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                store.performDayRolloverIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.performDayRolloverIfNeeded()
                    store.evaluateCarryForwardPrompt()
                    // Re-check Screen Time approval on every return — the
                    // user may have granted access in Settings or signed
                    // into iCloud while away; the UI updates immediately.
                    FocusBlockingService.shared.refreshAuthStatus()
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
                    // Push the just-written season/journal slices to the
                    // account now too, so a season created right before
                    // closing the app reaches the cloud immediately rather
                    // than waiting for the next foreground. Queued slices
                    // still persist locally, so this is best-effort.
                    if auth.user?.id != nil {
                        Task { await seasonSync.flushNow() }
                        Task { await notesSync.flushNow() }
                    }
                }
            }
    }
}

// MARK: - Demo marker

/// A small, always-legible pill shown at the top of the home while the
/// user is exploring the sample sandbox. Tapping it offers a way out.
private struct DemoModePill: View {
    let onTap: () -> Void
    @State private var pulse: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.cadenceLavender)
                    .frame(width: 7, height: 7)
                    .opacity(pulse ? 0.4 : 1)
                Text("Demo · sample data")
                    .font(.sans(12.5, weight: .semibold))
                Text("Exit")
                    .font(.sans(12.5, weight: .semibold))
                    .foregroundStyle(Theme.cadenceLavenderDark)
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.cadenceLavender.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel("Exploring demo with sample data. Tap to exit.")
    }
}

#Preview {
    ContentView()
        .environment(Store())
}
