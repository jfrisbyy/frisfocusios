//
//  ContentView.swift
//  FrisFocus
//
//  Root container. Reads the Store from environment, kicks off the
//  day-rollover housekeeping on appear and whenever the scene returns
//  to `.active` (so a user who left the app open overnight rolls over
//  cleanly when they tap back in).
//
//  Presents the ONE onboarding cover (FirstRunIntroView) whenever the
//  flow needs to run: a brand-new install, resumed post-commit beats,
//  or the forever fork-landing for any authenticated person with no
//  season. The real home is unreachable without a session + a season.
//
//  No OS permission dialogs at startup — notifications are offered via
//  a soft prime card only after something deliverable actually arrives.
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
    @State private var showExitDemoDialog: Bool = false

    /// True when a signed-in account has finished (or exhausted) its
    /// cloud restore and still has no season — the fork is the landing,
    /// forever, for this state.
    private var forkLandingActive: Bool {
        auth.user != nil
            && store.appMode == .clean
            && store.needsSeasonSetup
            && seasonSync.hasAttemptedRestore
            && !seasonSync.isRestoring
    }

    /// True while the onboarding flow should cover the home. The setter
    /// is a no-op — the cover only dismisses when the underlying state
    /// resolves (a season exists, or the seam beats complete).
    private var introBinding: Binding<Bool> {
        Binding(
            get: { store.needsFirstRunIntro || store.accountSeamActive || forkLandingActive },
            set: { _ in }
        )
    }

    /// The honest moment for the notification offer: signed in, on the
    /// live home, OS dialog never shown, offer never declined, and
    /// something push-worthy has actually arrived.
    private var shouldOfferNotificationPrime: Bool {
        auth.user != nil
            && store.appMode == .clean
            && !store.needsFirstRunIntro
            && !store.accountSeamActive
            && !forkLandingActive
            && !store.needsSeasonSetup
            && notifications.primeEligible
            && (store.hasDeliverableSocialEvent || !friendGraph.incoming.isEmpty)
    }

    var body: some View {
        @Bindable var store = store
        return HomeView()
            // Quiet top-of-home layers: cloud-restore state, the demo
            // marker, and the soft notification prime card.
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if auth.user != nil,
                       seasonSync.isRestoring,
                       store.appMode == .clean,
                       store.currentSeason.name.isEmpty {
                        CloudRestoreBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if store.appMode == .demo {
                        DemoModePill { showExitDemoDialog = true }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if shouldOfferNotificationPrime {
                        NotificationPrimeCard(
                            onAccept: { Task { await notifications.acceptPrime() } },
                            onDecline: { notifications.declinePrime() }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.3), value: shouldOfferNotificationPrime)
            }
            .animation(.easeInOut(duration: 0.3), value: store.appMode)
            .animation(.easeInOut(duration: 0.3), value: seasonSync.isRestoring)
            .confirmationDialog(
                "Leave the demo?",
                isPresented: $showExitDemoDialog,
                titleVisibility: .visible
            ) {
                Button("Exit demo and start for real") {
                    store.exitDemoToFlow()
                }
                Button("Keep exploring", role: .cancel) {}
            } message: {
                Text("Every sample row is wiped. You'll pick your own path next — nothing here follows you.")
            }
            // The one onboarding cover — non-dismissible; it resolves
            // itself when a season exists and the seam beats finish.
            .fullScreenCover(isPresented: introBinding, onDismiss: {
                // A fresh season was just built — teach the core gestures
                // interactively before the person starts tracking.
                // (Returning sign-ins restoring a season skip this.)
                if store.coldStartCoaching {
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
                    // Independent service loads run concurrently — the
                    // app reaches first interactivity in one round-trip
                    // instead of six stacked ones. Realtime subscriptions
                    // attach right after each load lands.
                    async let messagesLoad: Void = messageGraph.load(myUserId: myId)
                    async let friendsLoad: Void = friendGraph.load(myUserId: myId)
                    async let goldenLoad: Void = goldenHour.load(myUserId: myId)
                    async let profileLoad: Void = profileStore.load(myUserId: myId)
                    async let blocksLoad: Void = moderation.loadBlocks(myUserId: myId)
                    _ = await (messagesLoad, friendsLoad, goldenLoad, profileLoad, blocksLoad)
                    messageGraph.startRealtime(myUserId: myId)
                    friendGraph.startRealtime(myUserId: myId)
                    goldenHour.startRealtime(myUserId: myId)
                    // The full social mirror: friends, stories, cheers,
                    // pacts, circles, and grove presence — synced into
                    // the Store and kept live over realtime. Runs after
                    // blocks so hidden/blocked content filters on ingest.
                    await socialSync.start(myUserId: myId, store: store)
                    // Private journal sync: notes, folders, tags, and
                    // their media follow the account — offline-first.
                    await notesSync.start(myUserId: myId, store: store)
                    // Private season sync: season, tasks, score history,
                    // and milestones follow the account too.
                    await seasonSync.start(myUserId: myId, store: store)
                    // NO permission prompt here — the soft prime card on
                    // the home owns that moment, and only after something
                    // deliverable has actually arrived.
                    await notifications.refreshPrimeEligibility()
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
                    // Keep a long-lived session fresh: refresh the access
                    // token before it expires mid-use.
                    Task { await auth.refreshSessionIfExpiringSoon() }
                    // Re-check Screen Time approval on every return — the
                    // user may have granted access in Settings or signed
                    // into iCloud while away; the UI updates immediately.
                    FocusBlockingService.shared.refreshAuthStatus()
                    // The user is looking at the app — the icon badge
                    // shouldn't keep nagging about things they can now see.
                    NotificationManager.clearBadge()
                    // The prime card's eligibility may have changed in
                    // Settings while away.
                    Task { await notifications.refreshPrimeEligibility() }
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
    /// Launch the Layer-A guided tour for a brand-new user who just
    /// built a season (either path). A fresh season's tasks live on the
    /// board UNPINNED — Today's Plan starts empty — so the tour opens
    /// with the pin lesson and teaches the whole loop: build the day,
    /// do the work, set the rhythm, meet the agenda.
    fileprivate func startMechanicsTourIfFresh() {
        // A completely empty board (every setup page skipped) has
        // nothing to practice on — the plan's own "add" affordance and
        // the coach banner lead instead; the tour stays available later.
        let hasBoard = !store.tasks.isEmpty
        let hasPlan = !store.todaysPlan.isEmpty
        guard hasBoard || hasPlan else { return }
        let hasQuantity = store.todaysPlan.contains { item in
            if case .task(let task) = item { return task.requiresQuantityLogging }
            return false
        }
        walkthrough.startMechanicsTour(
            startsAtPinning: !hasPlan,
            includesQuantity: hasQuantity
        )
    }
}

// MARK: - Demo marker

/// The always-visible sandbox marker: this is a sample life, and the
/// door out is one tap away. Tapping it confirms, wipes every sample
/// row, and routes back into the real flow at the fork.
private struct DemoModePill: View {
    let onExit: () -> Void

    var body: some View {
        Button(action: onExit) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text("Demo — a sample life")
                    .font(.sans(12.5, weight: .semibold))
                Text("Exit")
                    .font(.sans(12.5, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.textPrimary.opacity(0.1)))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.sunWarm.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("This is a demo with sample data. Tap to exit and start for real.")
    }
}

// MARK: - Notification prime card

/// The soft pre-permission offer — shown only once something
/// deliverable has actually arrived, and only while the OS dialog has
/// never been shown. An explicit yes is required before the one system
/// dialog; "No thanks" is respected for good (settings keeps a toggle).
private struct NotificationPrimeCard: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.sunWarm.opacity(0.22))
                        .frame(width: 34, height: 34)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.sunWarm)
                }
                Text("Want a quiet note when your people cheer you? No nags, ever — that's a promise.")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Text("Yes, quietly")
                        .font(.sans(13.5, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.textPrimary))
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("No thanks")
                        .font(.sans(13.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.paperCream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.sunWarm.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
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
