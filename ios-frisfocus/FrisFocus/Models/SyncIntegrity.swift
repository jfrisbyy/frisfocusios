//
//  SyncIntegrity.swift
//  FrisFocus
//
//  The rules that decide whose data is on this device and what may
//  travel between the device and an account.
//
//  Every function here is a pure decision over plain values — no Store,
//  no UserDefaults, no network — so the rules can be tested directly.
//  The services ask these questions and act on the answers:
//
//  • When a session ends, is the on-device data wiped, hidden, or left?
//  • When someone signs in, does the data already here belong to them?
//  • Which persisted keys are account data (and must go on a wipe)?
//  • May an EMPTY slice be uploaded over cloud content, and may cloud
//    content be applied over a local slice?
//  • After a sign-in, did the cloud restore actually succeed?
//
//  Everything is `nonisolated`: the answers are needed on the main
//  actor (services, views) and in the test target alike.
//

import Foundation

// MARK: - Vocabulary

/// Why a signed-in session is ending.
nonisolated enum SessionEndReason: String, Sendable {
    /// The person tapped "Sign out".
    case userSignOut
    /// The auth server rejected the refresh token — nobody asked.
    case sessionExpired
    /// The account was just erased on the server.
    case accountDeleted
}

/// What happens to the account data on this device when a session ends.
nonisolated enum LocalDataDisposition: String, Sendable {
    /// Erase everything and return the install to first-run.
    case wipe
    /// Keep the data on disk (it holds edits the account never
    /// received) but put it behind the first-run cover until the same
    /// person signs back in.
    case keepHidden
    /// Leave the data where it is (an expired session: the person did
    /// not ask to leave, and the home says "sign back in").
    case keepVisible
}

/// Whether the data already on the device may stay for a sign-in.
nonisolated enum LocalDataOwnerDecision: String, Sendable {
    case keep
    case wipe
}

/// How the cloud restore after a sign-in resolved.
nonisolated enum SeasonRestoreOutcome: String, Sendable {
    /// A season is on the device (restored, or already here).
    case seasonPresent
    /// The cloud was reached and the account has no season.
    case cloudEmpty
    /// The cloud could not be reached — "no season" is NOT a fact.
    case failed
}

// MARK: - Rules

nonisolated enum SyncIntegrity {

    // MARK: Session end

    /// The fate of on-device data when a session ends.
    ///
    /// A deleted account always wipes: the server copy is gone and the
    /// privacy copy promises the device copy goes with it. A deliberate
    /// sign-out wipes too — the account is the source of truth — unless
    /// the device still holds edits the account never received, in which
    /// case destroying them would be silent data loss. An expired
    /// session changes nothing on disk.
    static func dispositionOnSessionEnd(
        reason: SessionEndReason,
        hasUnsyncedChanges: Bool
    ) -> LocalDataDisposition {
        switch reason {
        case .accountDeleted:
            return .wipe
        case .sessionExpired:
            return .keepVisible
        case .userSignOut:
            return hasUnsyncedChanges ? .keepHidden : .wipe
        }
    }

    // MARK: Ownership

    /// Whether the data on this device may stay when `signingIn` signs in.
    ///
    /// With an owner on record the answer is exact. Without one (data
    /// written before ownership was recorded, or content created by
    /// nobody during pre-sign-in onboarding) the per-account sync keys
    /// are the evidence: if this device has synced for other accounts
    /// and never for this one, the data is someone else's. If it has
    /// never synced for anyone, the content belongs to nobody yet and
    /// the person signing in keeps it — that is the onboarding case the
    /// "stranded local content" upload exists for.
    static func ownerDecision(
        recordedOwner: String?,
        previouslySyncedUserIds: Set<String>,
        signingIn: String
    ) -> LocalDataOwnerDecision {
        if let recordedOwner {
            return recordedOwner == signingIn ? .keep : .wipe
        }
        if previouslySyncedUserIds.isEmpty {
            return .keep
        }
        return previouslySyncedUserIds.contains(signingIn) ? .keep : .wipe
    }

    /// Per-account sync keys end in the account id — these prefixes are
    /// how a device remembers which accounts it has synced for.
    static let perUserSyncKeyPrefixes: [String] = [
        "seasonSync.pendingSlices.",
        "seasonSync.localStamps.",
        "seasonSync.snapshots.",
        "notesSync.initialPush.",
        "proofLibrarySync.initialPush."
    ]

    /// The account ids this device has synced for, read off its
    /// persisted key names.
    static func syncedUserIds(fromDefaultsKeys keys: [String]) -> Set<String> {
        var ids: Set<String> = []
        for key in keys {
            for prefix in perUserSyncKeyPrefixes where key.hasPrefix(prefix) {
                let id = String(key.dropFirst(prefix.count))
                if !id.isEmpty { ids.insert(id) }
            }
        }
        return ids
    }

    // MARK: Wipe scope

    /// The Store's own persisted collections.
    private static let storeSliceKeys: [String] = [
        "currentSeason", "pastSeasons", "archivedSeasons", "tasks", "todos",
        "logEntries", "notes", "folders", "proofPins", "proofLibrary",
        "friends", "circles", "circleTaskCompletions", "circleContributions",
        "circleEvents", "eventRSVPs", "eventCheckIns", "signalFacts", "cheers",
        "storyPosts", "directShares", "likes", "comments", "mediaAssets",
        "avoidanceItems", "avoidanceOccurrences", "habitTrains", "boosters",
        "viewedStoryPostIds", "store.seenPactClosings.v1", "pacts",
        "pactCompletions", "circleTaskRequests", "focusSessions",
        "sharedFocusBlocks", "scheduledGroves", "cadenceLinks",
        "cadenceOutcomeFulfillments", "consumedCadenceEventIds", "buckets",
        "dayTemplates", "weekTemplateAssignments", "daySwaps", "oneShots"
    ]

    /// Per-person settings and housekeeping markers the Store keeps.
    private static let storeSettingKeys: [String] = [
        "cadenceConnected", "cadenceInviteDismissed",
        "cadenceSurfacePointsSocially", "reminderValueThreshold",
        "noteTagsEnabled", "agendaIsDefaultDayView", "dismissedEventGlanceIds",
        "lastRolloverDate", "lastCarryForwardPromptDay", "onboarding.seamPhase",
        "store.decodeFailures.v1", "activityLastSeenAt", "pendingStoryUploads",
        "pendingCircleCreates", "pendingEventCreates", "lastWeeklyPenaltySweep"
    ]

    /// Account-shaped state other parts of the app persist on their own.
    private static let sideStateKeys: [String] = [
        "planReminderPrefs.v1", "needsYou.dismissed", "needsYou.snoozedUntil",
        "needsYou.cachedRead", "share.milestone.options", "coldStart.draft.v1",
        "seasonSetup.resumeSnapshot.v1", "onboarding.phase.v1"
    ]

    /// Exact persisted keys that hold account data.
    static let accountDefaultsKeys: Set<String> = Set(
        storeSliceKeys + storeSettingKeys + sideStateKeys
    )

    /// Key families that hold account data: sync bookkeeping (queues,
    /// stamps, snapshots — for every account that ever synced here),
    /// decode-recovery copies, pre-migration backups, and per-season
    /// dismissals.
    static let accountDefaultsKeyPrefixes: [String] = [
        "seasonSync.", "notesSync.", "proofLibrarySync.", "socialSync.",
        "recovery.", "backup.v", "seasonInvitation.dismissed."
    ]

    /// Whether a persisted key holds account data and must be removed
    /// when the device is wiped.
    ///
    /// Deliberately a list of what goes rather than a list of what
    /// stays: device-level state (the age gate, the app language, the
    /// install id, the first-run mode, Apple's own keys) must survive a
    /// wipe, and a key nobody listed should err toward staying.
    static func isAccountScopedDefaultsKey(_ key: String) -> Bool {
        if accountDefaultsKeys.contains(key) { return true }
        for prefix in accountDefaultsKeyPrefixes where key.hasPrefix(prefix) {
            return true
        }
        return false
    }

    // MARK: Empty slices

    /// Whether an empty local slice is empty because the person emptied
    /// it — as opposed to a fresh install or a wiped device that simply
    /// has nothing yet.
    ///
    /// The difference is whether this device ever held the synced copy.
    /// A device that has (it applied the cloud copy, or uploaded its
    /// own) and then wrote the slice empty is reporting a decision. A
    /// device that never has is reporting nothing at all.
    static func emptySliceIsIntentional(
        localIsEmpty: Bool,
        hasSyncedBefore: Bool
    ) -> Bool {
        localIsEmpty && hasSyncedBefore
    }

    /// Whether a queued slice may be uploaded.
    ///
    /// Content always may. Emptiness travels only when it is a decision
    /// (see `emptySliceIsIntentional`) — otherwise a fresh install would
    /// blank the account.
    static func shouldUploadSlice(
        localIsEmpty: Bool,
        emptyIsIntentional: Bool
    ) -> Bool {
        if !localIsEmpty { return true }
        return emptyIsIntentional
    }

    /// Whether a cloud slice should replace the local one on a pull.
    ///
    /// - An empty or unreadable cloud copy never applies.
    /// - A merging slice (the score history) always merges.
    /// - On the first successful pull for an account on this device the
    ///   cloud wins outright: nothing local has ever been reconciled
    ///   with it, so a local stamp proves nothing — this is what stops
    ///   a season built after a FAILED restore from replacing the real
    ///   one.
    /// - Otherwise the newer stamp wins, and an empty local slice takes
    ///   the cloud copy unless the person emptied it on purpose and that
    ///   decision has not been uploaded yet.
    static func shouldApplyRemoteSlice(
        remoteHasContent: Bool,
        remoteIsNewer: Bool,
        localIsEmpty: Bool,
        localEmptyIsIntentional: Bool,
        alwaysMerges: Bool,
        isFirstPullForAccount: Bool
    ) -> Bool {
        guard remoteHasContent else { return false }
        if alwaysMerges { return true }
        if isFirstPullForAccount { return true }
        if remoteIsNewer { return true }
        return localIsEmpty && !localEmptyIsIntentional
    }

    /// Whether a device should clear its own copy of a slice because
    /// the owner emptied that slice on another device.
    ///
    /// Only a device that holds the synced copy, has nothing unsent for
    /// the slice, and is older than the emptying follows. Content this
    /// device never reconciled with the account (pre-sign-in onboarding
    /// content, unsent edits) is never deleted by someone else's marker
    /// — it uploads instead.
    static func shouldAdoptRemoteEmptiness(
        remoteIsNewer: Bool,
        localIsEmpty: Bool,
        localHasUnsentChanges: Bool,
        hasSyncedBefore: Bool
    ) -> Bool {
        if localIsEmpty { return false }
        guard hasSyncedBefore else { return false }
        if localHasUnsentChanges { return false }
        return remoteIsNewer
    }

    /// Whether a season carries nothing worth syncing — the nameless
    /// placeholder that keeps the Store non-optional before setup.
    ///
    /// A NAMED season is never empty, even with no areas or milestones
    /// yet: treating it as empty meant a new season started from a
    /// clean slate was "restored" back to the previous one on the next
    /// pull.
    static func seasonSliceIsEmpty(
        name: String,
        categoryCount: Int,
        milestoneCount: Int
    ) -> Bool {
        name.isEmpty && categoryCount == 0 && milestoneCount == 0
    }

    /// Whether a local season must be set aside (archived, restorable)
    /// before the cloud season replaces it on the first pull.
    ///
    /// Only a real, named local season that is a different season from
    /// the cloud's is worth keeping — the nameless placeholder and an
    /// older copy of the same season are not.
    static func shouldPreserveLocalSeason(
        localSeasonName: String,
        localSeasonId: UUID,
        cloudSeasonId: UUID
    ) -> Bool {
        let named = !localSeasonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return named && localSeasonId != cloudSeasonId
    }

    // MARK: Restore routing

    /// What the sign-in flow may conclude about the account's season.
    ///
    /// "No season" is only a fact when the cloud was actually reached.
    /// A restore that failed or timed out says nothing, and routing a
    /// returning person to "build a new season" on that evidence is how
    /// a real season gets overwritten.
    static func restoreOutcome(
        hasLocalSeason: Bool,
        restoreSucceeded: Bool
    ) -> SeasonRestoreOutcome {
        if hasLocalSeason { return .seasonPresent }
        return restoreSucceeded ? .cloudEmpty : .failed
    }
}
