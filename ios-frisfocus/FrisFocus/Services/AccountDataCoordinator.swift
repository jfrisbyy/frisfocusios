//
//  AccountDataCoordinator.swift
//  FrisFocus
//
//  Decides what happens to the account data on this device when a
//  session begins or ends, and carries it out in a safe order.
//
//  Before this existed, sign-out and account deletion cleared the
//  tokens and nothing else: the season, journal, proofs, sync queues
//  and media all stayed on the device. The next person to sign in on
//  the same phone had it uploaded into THEIR account as "stranded
//  local content", and a deleted account's data came straight back the
//  moment its owner signed in again.
//
//  The rules (the decisions themselves live in `SyncIntegrity`):
//
//  • Account deleted → wipe the device, back to first-run.
//  • Signed out on purpose → push anything unsent first; then wipe.
//    If something could NOT be pushed (offline, a failed upload, proof
//    media waiting for Wi-Fi), the data is kept on disk behind the
//    first-run cover instead of being destroyed — it comes back when
//    the same person signs in, and is wiped if anyone else does.
//  • Session expired → nothing changes on disk; the home asks the
//    person to sign back in.
//  • Someone signs in → if the device is in the demo, or holds another
//    account's data, it is wiped BEFORE any sync starts. So the only
//    local content a sign-in can ever upload is content created by
//    nobody (pre-sign-in onboarding) or by that same person.
//
//  Order matters everywhere here: sync must be stopped, and must have
//  forgotten its queues, before the Store is emptied — otherwise the
//  emptiness itself is uploaded as if the person had deleted it all.
//

import Foundation

@MainActor
final class AccountDataCoordinator {
    private weak var store: Store?
    private weak var seasonSync: SeasonSyncService?
    private weak var notesSync: NotesSyncService?
    private weak var proofLibrarySync: ProofLibrarySyncService?
    private weak var socialSync: SocialSyncService?

    /// How long a sign-out waits for unsent edits to upload before it
    /// stops waiting and keeps them on the device instead.
    private static let finalFlushBudget: Double = 15

    /// `nonisolated` so the auth layer can own one as a plain stored
    /// property; there is nothing to isolate until `attach` runs.
    nonisolated init() {}

    /// Wire the app's long-lived objects in. Called once from the root
    /// view, which is the first place they are all in hand.
    func attach(
        store: Store,
        seasonSync: SeasonSyncService,
        notesSync: NotesSyncService,
        proofLibrarySync: ProofLibrarySyncService,
        socialSync: SocialSyncService
    ) {
        self.store = store
        self.seasonSync = seasonSync
        self.notesSync = notesSync
        self.proofLibrarySync = proofLibrarySync
        self.socialSync = socialSync
    }

    // MARK: Session begins

    /// Make the device safe for `userId` to sync on. Must run before
    /// any sync service starts for them. Idempotent — the auth layer
    /// calls it the moment a session exists and the root view calls it
    /// again before starting sync (which also covers a session restored
    /// at launch, before anything was attached).
    func prepareLocalData(forUserId userId: String) {
        guard let store else { return }
        let wasInDemo = store.appMode == .demo
        let homeWasShowing = store.appMode != .uninitialized

        var mustWipe = wasInDemo
        if !mustWipe {
            let decision = SyncIntegrity.ownerDecision(
                recordedOwner: store.localDataOwnerId,
                previouslySyncedUserIds: store.previouslySyncedUserIds,
                signingIn: userId
            )
            mustWipe = decision == .wipe
        }

        if mustWipe {
            Log.auth.debug("sign-in: clearing data that is not this account's (demo=\(wasInDemo)) before sync starts")
            wipeLocalData()
            // The wipe drops the install back to first-run. If the home
            // was showing (the demo, or an expired session someone else
            // just signed into), re-enter the flow at the account step
            // so it resolves this sign-in: existing season → home,
            // otherwise claim-name / the fork.
            if homeWasShowing {
                OnboardingProgress.save(.account)
            }
        }
        store.localDataOwnerId = userId
    }

    // MARK: Session ends

    /// Called while the access token still works. For a deliberate
    /// sign-out this is the last chance to upload unsent edits. Returns
    /// what must happen to the on-device data once the tokens are gone.
    func sessionWillEnd(_ reason: SessionEndReason) async -> LocalDataDisposition {
        guard store != nil else {
            // Nothing attached yet (a session that expired during
            // launch) — there is nothing this can safely touch.
            return .keepVisible
        }
        var unsynced = false
        if reason == .userSignOut {
            unsynced = await attemptFinalFlush()
        }
        let disposition = SyncIntegrity.dispositionOnSessionEnd(
            reason: reason,
            hasUnsyncedChanges: unsynced
        )
        Log.auth.debug("session ending (\(reason.rawValue)) — local data: \(disposition.rawValue)")
        return disposition
    }

    /// Called once the tokens are gone, before the app observes the
    /// signed-out state.
    func sessionDidEnd(_ disposition: LocalDataDisposition) {
        switch disposition {
        case .keepVisible:
            break
        case .keepHidden:
            // Stop, but keep each service's per-account queues and
            // stamps on disk: they are how the held edits get uploaded
            // when the same person signs back in.
            socialSync?.stop()
            seasonSync?.stop()
            notesSync?.stop()
            proofLibrarySync?.stop()
            store?.holdAccountDataWhileSignedOut()
        case .wipe:
            wipeLocalData()
        }
    }

    // MARK: Internals

    /// Stop every sync service, make them forget their queues, and only
    /// then empty the Store and the disk.
    private func wipeLocalData() {
        socialSync?.stop()
        seasonSync?.discardLocalState()
        notesSync?.discardLocalState()
        proofLibrarySync?.discardLocalState()
        store?.wipeAccountData()
    }

    private var hasUnsyncedChanges: Bool {
        if let seasonSync, seasonSync.hasUnsyncedChanges { return true }
        if let notesSync, notesSync.hasUnsyncedChanges { return true }
        if let proofLibrarySync, proofLibrarySync.hasUnsyncedChanges { return true }
        return false
    }

    /// Give every unsent edit a bounded chance to reach the account.
    /// Returns whether anything is STILL unsent afterwards.
    private func attemptFinalFlush() async -> Bool {
        guard let store else { return false }
        // Write anything still debouncing, then let the Store hand its
        // change notifications to the sync services (it does so on a
        // later main-actor turn) so they are queued before we flush.
        store.flushPendingSaves()
        try? await Task.sleep(for: .milliseconds(120))

        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainSyncQueues()
        }
        let budget = Self.finalFlushBudget
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(budget))
            work.cancel()
        }
        await work.value
        watchdog.cancel()
        return hasUnsyncedChanges
    }

    private func drainSyncQueues() async {
        for _ in 0..<4 {
            if Task.isCancelled { return }
            // Uploads are gated on a successful restore; a session that
            // never got one (launched offline, now back online) needs a
            // pull before anything can go up.
            if let seasonSync, !seasonSync.restoreSucceeded {
                await seasonSync.pullRemote()
            }
            if let notesSync, !notesSync.isRestoreConfirmed {
                await notesSync.pullRemote()
            }
            await seasonSync?.flushNow()
            await notesSync?.flushNow()
            await proofLibrarySync?.flushNow(fetchMissing: false)
            if !hasUnsyncedChanges { return }
            if Task.isCancelled { return }
            // A flush already in flight makes `flushNow` return at once;
            // give it a moment and look again.
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}
