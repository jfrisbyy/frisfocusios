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
    @Environment(WalkthroughManager.self) private var walkthrough
    @Environment(\.scenePhase) private var scenePhase

    @State private var pendingInvite: InviteTarget?
    @State private var showSeasonSetupFromComplete: Bool = false
    /// Drives guided season setup after a clean start.
    @State private var showCleanSeasonSetup: Bool = false
    /// True once a returning user signed in from the welcome intro, so
    /// dismissing the cover never bounces them into guided season setup
    /// while their real season is still restoring from the cloud.
    @State private var didSignInFromIntro: Bool = false

    /// True while the first-run welcome should cover the home. The
    /// setter is a no-op — the cover only dismisses once the user's
    /// choice flips `appMode` out of `.uninitialized`.
    private var introBinding: Binding<Bool> {
        Binding(
            get: { store.needsFirstRunIntro || store.accountSeamActive },
            set: { _ in }
        )
    }

    var body: some View {
        @Bindable var store = store
        return HomeView()
            // A returning sign-in whose season is still coming down
            // from the cloud — say so instead of looking empty.
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if auth.user != nil,
                       seasonSync.isRestoring,
                       store.appMode == .clean,
                       store.currentSeason.name.isEmpty {
                        CloudRestoreBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 4)
            }
            .animation(.easeInOut(duration: 0.3), value: store.appMode)
            .animation(.easeInOut(duration: 0.3), value: seasonSync.isRestoring)
            // First-launch welcome — covers the home until the user picks
            // a path. Non-dismissible: a choice must be made.
            .fullScreenCover(isPresented: introBinding, onDismiss: {
                if store.needsSeasonSetup && !didSignInFromIntro {
                    showCleanSeasonSetup = true
                } else if !didSignInFromIntro && store.appMode == .clean {
                    // A fresh cold-start user has just saved their board and
                    // account — teach the core gestures interactively before
                    // they start tracking. (Returning sign-ins skip this.)
                    startMechanicsTourIfFresh()
                }
            }) {
                // A cold launch with restorable credentials: hold a calm
                // "restoring" cover instead of flashing the welcome
                // buttons while the silent session restore is in flight.
                Group {
                    if auth.isLoading && auth.hasRestorableSession {
                        AccountRestoreCover()
                    } else {
                        FirstRunIntroView()
                    }
                }
                .interactiveDismissDisabled(true)
            }
            // Guided season setup for a clean start.
            .fullScreenCover(isPresented: $showCleanSeasonSetup) {
                SeasonSetupFlowView()
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
                // to the inviter's profile with an Add control. Arriving
                // signed out, the invite is also remembered so it replays
                // right after sign-in — the link never has to be re-tapped.
                if let userId = InviteLink.userId(from: url) {
                    if auth.user == nil {
                        UserDefaults.standard.set(userId, forKey: "pendingInviteUserId")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "pendingInviteUserId")
                    }
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
                    print("[FrisFocus] startup: signed in as user=\(myId) — loading account data")
                    notifications.setUserId(myId)
                    // Replay an invite link that arrived before sign-in —
                    // the inviter's profile reopens with a live Add control.
                    if let storedInvite = UserDefaults.standard.string(forKey: "pendingInviteUserId") {
                        UserDefaults.standard.removeObject(forKey: "pendingInviteUserId")
                        if storedInvite != myId {
                            pendingInvite = InviteTarget(id: storedInvite)
                        }
                    }
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
                    print("[FrisFocus] startup: NO signed-in session (auth.user is nil) — nothing to load; app will look empty until sign-in")
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
                // Build today's on-device reminders and hand the widget
                // its first snapshot of the day.
                store.schedulePlanReminderRefresh()
                WidgetBridge.publish(from: store)
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
                    store.schedulePlanReminderRefresh()
                    // A network hiccup at launch may have left the app
                    // signed out with valid tokens still stored — retry
                    // the silent restore now that we're back.
                    Task { await auth.retryRestoreIfNeeded() }
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
                        // Catch up the social mirror.
                        Task { await socialSync.refreshAll() }
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

// MARK: - Mechanics tour kickoff

extension ContentView {
    /// Launch the Layer-A mechanics tour for a brand-new cold-start user,
    /// flagging the quantity lesson only when their board actually has a
    /// tiered/increment task to log.
    fileprivate func startMechanicsTourIfFresh() {
        // An empty board (every setup page skipped) has nothing to
        // practice on — the gesture tour would point at a task that
        // doesn't exist. The plan's own "add" affordance and the coach
        // banner lead instead; the tour stays available for later.
        guard !store.todaysPlan.isEmpty else { return }
        let hasQuantity = store.todaysPlan.contains { item in
            if case .task(let task) = item { return task.requiresQuantityLogging }
            return false
        }
        walkthrough.startMechanicsTour(includesQuantity: hasQuantity)
    }
}

// MARK: - Account restore states

/// Full-screen cover shown during a cold launch while stored
/// credentials are being silently restored — in place of the welcome
/// intro, which would otherwise flash for returning users.
private struct AccountRestoreCover: View {
    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.textPrimary)
                        .frame(width: 76, height: 76)
                        .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 2))
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(Theme.sunWarm)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)

                VStack(spacing: 8) {
                    Text("Restoring your account…")
                        .font(.serif(22, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Signing you back in and gathering your season.")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                ProgressView()
                    .tint(Theme.textPrimary)
                    .padding(.top, 6)
            }
            .padding(40)
        }
    }
}

/// Quiet top pill while a signed-in account's season is still coming
/// down from the cloud — the moment data lands, it disappears.
private struct CloudRestoreBanner: View {
    var body: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.textPrimary)
            Text("Restoring your season from your account…")
                .font(.sans(12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.sunWarm.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityLabel("Restoring your season from your account")
    }
}

#Preview {
    ContentView()
        .environment(Store())
}
