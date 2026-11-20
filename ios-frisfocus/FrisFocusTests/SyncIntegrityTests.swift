//
//  SyncIntegrityTests.swift
//  FrisFocusTests
//
//  Regression tests for the rules that decide whose data is on a device
//  and what may travel between a device and an account.
//
//  Same discipline as FrisFocusTests.swift: every case covers a rule
//  that was actually wrong in shipped code, and all of it is pure
//  functions — nothing constructs a Store, touches UserDefaults, or
//  reaches the network.
//

import Foundation
import Testing
@testable import FrisFocus

// MARK: - What happens to the device when a session ends
//
// The bug: sign-out and account deletion cleared the tokens and nothing
// else. The season, journal, proofs and sync queues stayed on the
// device, were uploaded into the NEXT account to sign in on that phone,
// and came straight back after "Delete account".

@Suite("Session end")
struct SessionEndTests {

    @Test("A deleted account always wipes the device")
    func deletionWipes() {
        #expect(SyncIntegrity.dispositionOnSessionEnd(reason: .accountDeleted, hasUnsyncedChanges: false) == .wipe)
        // Unsent edits change nothing: there is no account left to
        // receive them, and keeping them is what re-uploaded a deleted
        // account's data on the next sign-in.
        #expect(SyncIntegrity.dispositionOnSessionEnd(reason: .accountDeleted, hasUnsyncedChanges: true) == .wipe)
    }

    @Test("A clean sign-out wipes the device")
    func signOutWipes() {
        #expect(SyncIntegrity.dispositionOnSessionEnd(reason: .userSignOut, hasUnsyncedChanges: false) == .wipe)
    }

    @Test("A sign-out with unsent edits keeps them, hidden")
    func signOutWithUnsentEditsHolds() {
        // Wiping here would silently destroy work the account never
        // received. It is put away instead — never left visible.
        let disposition = SyncIntegrity.dispositionOnSessionEnd(reason: .userSignOut, hasUnsyncedChanges: true)
        #expect(disposition == .keepHidden)
        #expect(disposition != .keepVisible)
    }

    @Test("An expired session touches nothing")
    func expiryKeepsData() {
        #expect(SyncIntegrity.dispositionOnSessionEnd(reason: .sessionExpired, hasUnsyncedChanges: false) == .keepVisible)
        #expect(SyncIntegrity.dispositionOnSessionEnd(reason: .sessionExpired, hasUnsyncedChanges: true) == .keepVisible)
    }
}

// MARK: - Whose data is on the device
//
// The bug: the "stranded local content" upload could not tell content a
// brand-new person made before creating their account (which must
// upload) from the previous account's data left on a shared phone
// (which must never).

@Suite("Local data ownership")
struct LocalDataOwnershipTests {

    @Test("The recorded owner keeps their data")
    func sameOwnerKeeps() {
        let decision = SyncIntegrity.ownerDecision(
            recordedOwner: "user-a",
            previouslySyncedUserIds: ["user-a"],
            signingIn: "user-a"
        )
        #expect(decision == .keep)
    }

    @Test("A different account never inherits the recorded owner's data")
    func differentOwnerWipes() {
        let decision = SyncIntegrity.ownerDecision(
            recordedOwner: "user-a",
            previouslySyncedUserIds: ["user-a"],
            signingIn: "user-b"
        )
        #expect(decision == .wipe)
    }

    @Test("The recorded owner wins over sync history")
    func recordedOwnerBeatsHistory() {
        // user-b has synced here before, but the data now on the device
        // is recorded as user-a's.
        let decision = SyncIntegrity.ownerDecision(
            recordedOwner: "user-a",
            previouslySyncedUserIds: ["user-a", "user-b"],
            signingIn: "user-b"
        )
        #expect(decision == .wipe)
    }

    @Test("Content made by nobody uploads to whoever signs in first")
    func onboardingContentIsKept() {
        // The legitimate case the stranded-content upload exists for: a
        // season built before the account existed. No owner, and this
        // device has never synced for anyone.
        let decision = SyncIntegrity.ownerDecision(
            recordedOwner: nil,
            previouslySyncedUserIds: [],
            signingIn: "brand-new-user"
        )
        #expect(decision == .keep)
    }

    @Test("Unrecorded data on a device that synced for someone else is theirs")
    func legacyForeignDataWipes() {
        // Data written before ownership was recorded: the per-account
        // sync keys are the evidence of whose it is.
        let decision = SyncIntegrity.ownerDecision(
            recordedOwner: nil,
            previouslySyncedUserIds: ["user-a"],
            signingIn: "user-b"
        )
        #expect(decision == .wipe)
    }

    @Test("Unrecorded data on a device that synced for this account stays")
    func legacyOwnDataIsKept() {
        // The upgrade path: an existing signed-in install must not be
        // wiped by the first launch of the build that records owners.
        let decision = SyncIntegrity.ownerDecision(
            recordedOwner: nil,
            previouslySyncedUserIds: ["user-a"],
            signingIn: "user-a"
        )
        #expect(decision == .keep)
    }

    @Test("Synced account ids are read off the per-account sync keys")
    func syncedUserIdsFromKeys() {
        let keys = [
            "seasonSync.localStamps.user-a",
            "seasonSync.snapshots.user-a",
            "notesSync.initialPush.user-b",
            "proofLibrarySync.initialPush.user-c",
            "tasks",
            "appMode"
        ]
        #expect(SyncIntegrity.syncedUserIds(fromDefaultsKeys: keys) == ["user-a", "user-b", "user-c"])
    }

    @Test("Pre-namespacing sync keys name no account")
    func legacyKeysNameNobody() {
        // The old device-wide keys have no account suffix; they must
        // not be read as an account whose id is the empty string.
        let keys = ["seasonSync.localStamps", "seasonSync.snapshots", "seasonSync.localStamps."]
        #expect(SyncIntegrity.syncedUserIds(fromDefaultsKeys: keys).isEmpty)
    }
}

// MARK: - What a wipe removes
//
// The bug this guards against is the wipe being incomplete in either
// direction: account data left behind, or device-level state (the age
// gate, the first-run mode) destroyed along with it.

@Suite("Wipe scope")
struct WipeScopeTests {

    @Test("The season, journal, and proof slices are account data")
    func coreSlicesAreWiped() {
        for key in ["currentSeason", "tasks", "todos", "logEntries", "notes", "folders", "proofLibrary", "archivedSeasons"] {
            #expect(SyncIntegrity.isAccountScopedDefaultsKey(key), "\(key) must be wiped")
        }
    }

    @Test("Agenda slices are account data too")
    func agendaSlicesAreWiped() {
        // These four were missing from the in-memory wipe, so buckets
        // and templates made in the demo followed the person out of it.
        for key in ["buckets", "dayTemplates", "weekTemplateAssignments", "daySwaps"] {
            #expect(SyncIntegrity.isAccountScopedDefaultsKey(key), "\(key) must be wiped")
        }
    }

    @Test("Sync bookkeeping for every account is wiped")
    func syncStateIsWiped() {
        // A wiped device must look never-synced: stamps and queues left
        // behind would make its emptiness read as a decision to upload.
        let keys = [
            "seasonSync.pendingSlices.user-a",
            "seasonSync.localStamps.user-b",
            "seasonSync.snapshots.user-a",
            "seasonSync.emptiedSlices.user-a",
            "seasonSync.cloudBaseline.user-a",
            "notesSync.pendingNotes",
            "notesSync.initialPush.user-a",
            "proofLibrarySync.pendingMedia",
            "socialSync.pendingStoryUploads.user-a"
        ]
        for key in keys {
            #expect(SyncIntegrity.isAccountScopedDefaultsKey(key), "\(key) must be wiped")
        }
    }

    @Test("Recovery and backup copies are wiped")
    func recoveryCopiesAreWiped() {
        #expect(SyncIntegrity.isAccountScopedDefaultsKey("recovery.currentSeason"))
        #expect(SyncIntegrity.isAccountScopedDefaultsKey("recovery.tasks"))
        #expect(SyncIntegrity.isAccountScopedDefaultsKey("backup.v12.logEntries"))
    }

    @Test("Drafts and cached reads are wiped")
    func draftsAreWiped() {
        for key in ["seasonSetup.resumeSnapshot.v1", "coldStart.draft.v1", "needsYou.cachedRead", "planReminderPrefs.v1"] {
            #expect(SyncIntegrity.isAccountScopedDefaultsKey(key), "\(key) must be wiped")
        }
    }

    @Test("Device-level state survives a wipe")
    func deviceStateSurvives() {
        let keys = [
            "ageGate.passed.v1", "ageGate.blocked.v1", "app.language",
            "appMode", "modelVersion", "currentUserId", "socialResetV1",
            "diagnostics.installId.v1", "AppleLanguages", "RORK_DEVELOPER_HINT"
        ]
        for key in keys {
            #expect(!SyncIntegrity.isAccountScopedDefaultsKey(key), "\(key) must survive")
        }
    }

    @Test("A key that merely starts like a slice is not swept up")
    func prefixesAreNotGreedy() {
        // Exact keys match exactly; only the listed families match by
        // prefix.
        #expect(!SyncIntegrity.isAccountScopedDefaultsKey("tasksTourSeen"))
        #expect(!SyncIntegrity.isAccountScopedDefaultsKey("notesHintShown"))
    }
}

// MARK: - Empty slices
//
// The bug: deleting the LAST item of a synced collection was undone.
// The flush refused to upload an empty slice while the cloud had
// content, and the pull re-applied cloud content whenever the local
// slice was empty — so the last to-do came back on the next foreground.
// The guard exists for a reason (a fresh install must never blank the
// account), so the fix has to tell the two kinds of empty apart.

@Suite("Empty slices")
struct EmptySliceTests {

    @Test("Emptying a slice this device has synced is a decision")
    func emptiedAfterSyncIsIntentional() {
        #expect(SyncIntegrity.emptySliceIsIntentional(localIsEmpty: true, hasSyncedBefore: true))
    }

    @Test("An empty slice on a device that never synced it is not")
    func neverSyncedEmptyIsNotIntentional() {
        // A fresh install, a wiped device, a slice that failed to load.
        #expect(!SyncIntegrity.emptySliceIsIntentional(localIsEmpty: true, hasSyncedBefore: false))
    }

    @Test("A slice with content is never 'emptied'")
    func contentIsNotEmptied() {
        #expect(!SyncIntegrity.emptySliceIsIntentional(localIsEmpty: false, hasSyncedBefore: true))
    }

    @Test("Content always uploads")
    func contentUploads() {
        #expect(SyncIntegrity.shouldUploadSlice(localIsEmpty: false, emptyIsIntentional: false))
    }

    @Test("A deliberate empty uploads; a phantom empty never does")
    func onlyDeliberateEmptinessUploads() {
        #expect(SyncIntegrity.shouldUploadSlice(localIsEmpty: true, emptyIsIntentional: true))
        #expect(!SyncIntegrity.shouldUploadSlice(localIsEmpty: true, emptyIsIntentional: false))
    }

    @Test("A never-synced empty device still restores from the cloud")
    func emptyDeviceRestores() {
        // Even against a stale local stamp: emptiness with no decision
        // behind it must never block real data coming down.
        let apply = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: true,
            remoteIsNewer: false,
            localIsEmpty: true,
            localEmptyIsIntentional: false,
            alwaysMerges: false,
            isFirstPullForAccount: false
        )
        #expect(apply)
    }

    @Test("A deleted last item is not restored by the next pull")
    func deliberateEmptyIsNotRestored() {
        let apply = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: true,
            remoteIsNewer: false,
            localIsEmpty: true,
            localEmptyIsIntentional: true,
            alwaysMerges: false,
            isFirstPullForAccount: false
        )
        #expect(!apply)
    }

    @Test("A newer cloud copy still beats a deliberate empty")
    func newerCloudCopyWins() {
        // Another device wrote the slice after this one emptied it —
        // latest wins, as for any other edit.
        let apply = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: true,
            remoteIsNewer: true,
            localIsEmpty: true,
            localEmptyIsIntentional: true,
            alwaysMerges: false,
            isFirstPullForAccount: false
        )
        #expect(apply)
    }

    @Test("An empty cloud copy is never applied over anything")
    func emptyCloudCopyNeverApplies() {
        let overContent = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: false,
            remoteIsNewer: true,
            localIsEmpty: false,
            localEmptyIsIntentional: false,
            alwaysMerges: false,
            isFirstPullForAccount: true
        )
        #expect(!overContent)
        let merging = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: false,
            remoteIsNewer: true,
            localIsEmpty: true,
            localEmptyIsIntentional: false,
            alwaysMerges: true,
            isFirstPullForAccount: false
        )
        #expect(!merging)
    }

    @Test("Older cloud content does not replace newer local content")
    func olderCloudCopyLoses() {
        let apply = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: true,
            remoteIsNewer: false,
            localIsEmpty: false,
            localEmptyIsIntentional: false,
            alwaysMerges: false,
            isFirstPullForAccount: false
        )
        #expect(!apply)
    }

    @Test("The score history always merges")
    func mergingSliceAlwaysApplies() {
        let apply = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: true,
            remoteIsNewer: false,
            localIsEmpty: false,
            localEmptyIsIntentional: false,
            alwaysMerges: true,
            isFirstPullForAccount: false
        )
        #expect(apply)
    }

    @Test("Another device's deliberate empty is followed by a synced, idle device")
    func remoteEmptinessIsAdopted() {
        let adopt = SyncIntegrity.shouldAdoptRemoteEmptiness(
            remoteIsNewer: true,
            localIsEmpty: false,
            localHasUnsentChanges: false,
            hasSyncedBefore: true
        )
        #expect(adopt)
    }

    @Test("Another device's empty never deletes unsent or unreconciled content")
    func remoteEmptinessNeverDeletesLocalWork() {
        // Unsent edits upload instead.
        #expect(!SyncIntegrity.shouldAdoptRemoteEmptiness(
            remoteIsNewer: true, localIsEmpty: false, localHasUnsentChanges: true, hasSyncedBefore: true
        ))
        // Content this device never reconciled with the account
        // (pre-sign-in onboarding content) uploads instead.
        #expect(!SyncIntegrity.shouldAdoptRemoteEmptiness(
            remoteIsNewer: true, localIsEmpty: false, localHasUnsentChanges: false, hasSyncedBefore: false
        ))
        // An older emptying loses to newer local content.
        #expect(!SyncIntegrity.shouldAdoptRemoteEmptiness(
            remoteIsNewer: false, localIsEmpty: false, localHasUnsentChanges: false, hasSyncedBefore: true
        ))
        // Nothing to clear.
        #expect(!SyncIntegrity.shouldAdoptRemoteEmptiness(
            remoteIsNewer: true, localIsEmpty: true, localHasUnsentChanges: false, hasSyncedBefore: true
        ))
    }

    @Test("Only the nameless placeholder season is empty")
    func namedSeasonIsContent() {
        #expect(SyncIntegrity.seasonSliceIsEmpty(name: "", categoryCount: 0, milestoneCount: 0))
        // A new season started from a clean slate has a name and nothing
        // else. Treating it as empty meant the previous season was
        // "restored" over it on the next pull.
        #expect(!SyncIntegrity.seasonSliceIsEmpty(name: "New Season", categoryCount: 0, milestoneCount: 0))
        #expect(!SyncIntegrity.seasonSliceIsEmpty(name: "", categoryCount: 2, milestoneCount: 0))
        #expect(!SyncIntegrity.seasonSliceIsEmpty(name: "", categoryCount: 0, milestoneCount: 1))
    }
}

// MARK: - A season built after a failed restore
//
// The bug: a returning person on a slow or offline network was sent to
// "build a new season" after an 8-second wait; the season they built
// carried the newer stamp and replaced their real one on the next pull.

@Suite("Failed restore")
struct FailedRestoreTests {

    @Test("A season on the device resolves the sign-in")
    func localSeasonIsPresent() {
        #expect(SyncIntegrity.restoreOutcome(hasLocalSeason: true, restoreSucceeded: true) == .seasonPresent)
        #expect(SyncIntegrity.restoreOutcome(hasLocalSeason: true, restoreSucceeded: false) == .seasonPresent)
    }

    @Test("'No season' is only a fact once the cloud has answered")
    func cloudEmptyNeedsASuccessfulRestore() {
        #expect(SyncIntegrity.restoreOutcome(hasLocalSeason: false, restoreSucceeded: true) == .cloudEmpty)
    }

    @Test("A restore that never reached the cloud is a failure, not an empty account")
    func failedRestoreIsNotEmpty() {
        let outcome = SyncIntegrity.restoreOutcome(hasLocalSeason: false, restoreSucceeded: false)
        #expect(outcome == .failed)
        #expect(outcome != .cloudEmpty)
    }

    @Test("On the first pull the cloud wins, whatever the local stamp says")
    func firstPullCloudWins() {
        // The local season was built after a failed restore: newer
        // stamp, real content — and never reconciled with the account.
        let apply = SyncIntegrity.shouldApplyRemoteSlice(
            remoteHasContent: true,
            remoteIsNewer: false,
            localIsEmpty: false,
            localEmptyIsIntentional: false,
            alwaysMerges: false,
            isFirstPullForAccount: true
        )
        #expect(apply)
    }

    @Test("A different, named local season is set aside before the cloud replaces it")
    func supersededSeasonIsPreserved() {
        let local = UUID()
        let cloud = UUID()
        #expect(SyncIntegrity.shouldPreserveLocalSeason(
            localSeasonName: "Season One", localSeasonId: local, cloudSeasonId: cloud
        ))
    }

    @Test("The placeholder and an older copy of the same season are not archived")
    func nothingWorthPreserving() {
        let id = UUID()
        #expect(!SyncIntegrity.shouldPreserveLocalSeason(
            localSeasonName: "", localSeasonId: UUID(), cloudSeasonId: id
        ))
        #expect(!SyncIntegrity.shouldPreserveLocalSeason(
            localSeasonName: "   ", localSeasonId: UUID(), cloudSeasonId: id
        ))
        #expect(!SyncIntegrity.shouldPreserveLocalSeason(
            localSeasonName: "Season One", localSeasonId: id, cloudSeasonId: id
        ))
    }
}

// MARK: - A stale token at request time
//
// The bug: the access token was only refreshed on foreground, so a
// session left open past its expiry failed every request with a 401
// until the person left the app and came back.

@Suite("Request-time token")
struct RequestTokenTests {

    /// A structurally valid JWT whose payload is `json`. The signature
    /// segment is a placeholder — nothing here verifies it.
    private func jwt(payload json: String) -> String {
        let body = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(body).signature"
    }

    @Test("The expiry is read from the token's exp claim")
    func readsExpiry() {
        let token = jwt(payload: "{\"sub\":\"user-a\",\"exp\":1800000000}")
        #expect(SessionAccessToken.expiry(ofJWT: token) == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test("A token without a readable expiry yields none")
    func unreadableExpiry() {
        #expect(SessionAccessToken.expiry(ofJWT: "not-a-jwt") == nil)
        #expect(SessionAccessToken.expiry(ofJWT: "a.b") == nil)
        #expect(SessionAccessToken.expiry(ofJWT: jwt(payload: "{\"sub\":\"user-a\"}")) == nil)
    }

    @Test("An expired token is refreshed before it is sent")
    func expiredNeedsRefresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SessionAccessToken.needsRefresh(expiry: now.addingTimeInterval(-1), now: now, margin: 60))
    }

    @Test("A token about to expire is refreshed too")
    func expiringSoonNeedsRefresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SessionAccessToken.needsRefresh(expiry: now.addingTimeInterval(30), now: now, margin: 60))
    }

    @Test("A comfortably fresh token is sent as is")
    func freshTokenIsLeftAlone() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!SessionAccessToken.needsRefresh(expiry: now.addingTimeInterval(3600), now: now, margin: 60))
    }

    @Test("A token with no readable expiry is never refreshed on a guess")
    func unknownExpiryIsLeftAlone() {
        #expect(!SessionAccessToken.needsRefresh(expiry: nil, now: Date(), margin: 60))
    }
}
