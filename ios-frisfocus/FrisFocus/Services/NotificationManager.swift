//
//  NotificationManager.swift
//  FrisFocus
//
//  The client half of push notifications. Owns the permission prompt,
//  the APNs device-token upload into `device_tokens`, the account's
//  per-kind push preferences (`notification_preferences`), and the route
//  a tapped notification resolves to (`pendingRoute`), which the app
//  shell observes to open the exact screen the push is about.
//
//  The `AppDelegate` feeds it the raw device token and notification taps;
//  `ContentView` tells it who is signed in (so a token that arrives before
//  sign-in is stored against the right account) and asks it to request
//  permission right after sign-in.
//
//  Pushes only ever deliver on a real device once the Apple push key is
//  configured at publish time — but registration, token storage, and tap
//  routing all run cleanly here regardless.
//

import SwiftUI
import UserNotifications
import UIKit
import Supabase

// MARK: - Deep-link route

/// Where a tapped notification should take the user. Decoded from the
/// `route` / `peerId` / `circleId` keys the `send-push` edge function
/// attaches to every payload.
enum DeepLinkRoute: Identifiable, Equatable {
    /// Open the Proofs inbox straight into this person's 1:1 thread.
    /// When `messageId` resolves to a proof, the thread opens it in the
    /// full-screen player directly — the push lands you *inside* the
    /// moment, not on a list.
    case thread(peerId: String, messageId: String? = nil)
    /// Open the Friends screen (a request was sent or accepted).
    case friends
    /// Open the shared-circles list (a circle invitation landed).
    case circles
    /// Open a specific circle's detail (a partner checked off / logged progress).
    case circle(circleId: String)
    /// Open a circle's Golden Hour surface — the countdown camera while
    /// the 5-minute window is live, the ephemeral wall during the hour,
    /// and only the attendance residue after.
    case golden(circleId: String)
    /// Open one milestone's page (a target-week nudge was tapped).
    case milestone(milestoneId: String)
    /// A cheer / cheer reaction — the home itself is the destination.
    case home
    /// A like or comment on the user's story — opens their own tape.
    case stories
    /// A pact was proposed or accepted — opens the pacts list.
    case pacts
    /// A friend invited the user to focus together — lands on home,
    /// where the live grove surfaces.
    case grove

    var id: String {
        switch self {
        case .thread(let peerId, _): return "thread:\(peerId)"
        case .friends: return "friends"
        case .circles: return "circles"
        case .circle(let circleId): return "circle:\(circleId)"
        case .golden(let circleId): return "golden:\(circleId)"
        case .milestone(let milestoneId): return "milestone:\(milestoneId)"
        case .home: return "home"
        case .stories: return "stories"
        case .pacts: return "pacts"
        case .grove: return "grove"
        }
    }

    /// Build a route from a notification's `userInfo`. Returns nil when the
    /// payload carries no recognizable route (e.g. a plain alert).
    init?(userInfo: [AnyHashable: Any]) {
        guard let route = userInfo["route"] as? String else { return nil }
        switch route {
        case "thread":
            guard let peerId = userInfo["peerId"] as? String, !peerId.isEmpty else { return nil }
            self = .thread(peerId: peerId, messageId: userInfo["messageId"] as? String)
        case "friends":
            self = .friends
        case "circles":
            self = .circles
        case "circle":
            guard let circleId = userInfo["circleId"] as? String, !circleId.isEmpty else { return nil }
            self = .circle(circleId: circleId)
        case "golden":
            guard let circleId = userInfo["circleId"] as? String, !circleId.isEmpty else { return nil }
            self = .golden(circleId: circleId)
        case "milestone":
            guard let milestoneId = userInfo["milestoneId"] as? String, !milestoneId.isEmpty else { return nil }
            self = .milestone(milestoneId: milestoneId)
        case "home":
            self = .home
        case "stories":
            self = .stories
        case "pacts":
            self = .pacts
        case "grove":
            self = .grove
        default:
            return nil
        }
    }
}

// MARK: - Manager

@Observable
@MainActor
final class NotificationManager {
    /// The destination a tapped notification asked for. The app shell
    /// presents the matching surface and clears this back to nil.
    var pendingRoute: DeepLinkRoute?

    /// Guards against re-prompting on every sign-in state change.
    @ObservationIgnored private var didRequestAuthorization = false
    /// The most recent APNs device token (hex), buffered until we know
    /// which signed-in account owns it.
    @ObservationIgnored private var pendingToken: String?
    /// The signed-in user id, set right after sign-in.
    @ObservationIgnored private var currentUserId: String?

    // MARK: Permission

    /// Ask for notification permission once per launch and, if granted,
    /// register for remote notifications. Safe to call repeatedly.
    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("[Notifications] Authorization request failed: \(error)")
        }
    }

    // MARK: Soft prime card (PULL, not push)

    /// True when the one OS permission dialog has never been shown AND
    /// the person hasn't declined the in-app offer — the soft prime
    /// card on the home may show. Onboarding never asks; this only
    /// becomes relevant once something deliverable has actually arrived.
    var primeEligible: Bool = false

    @ObservationIgnored private let primeDeclinedKey = "notifications.primeDeclined"

    /// Re-evaluate whether the soft prime card may be offered.
    func refreshPrimeEligibility() async {
        if UserDefaults.standard.bool(forKey: primeDeclinedKey) {
            primeEligible = false
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        primeEligible = settings.authorizationStatus == .notDetermined
    }

    /// The person said yes on the prime card — NOW show the one OS dialog.
    func acceptPrime() async {
        await requestAuthorizationIfNeeded()
        await refreshPrimeEligibility()
    }

    /// "No thanks" — respected for good. The settings toggle remains the
    /// only other door; the card never returns.
    func declinePrime() {
        UserDefaults.standard.set(true, forKey: primeDeclinedKey)
        primeEligible = false
    }

    // MARK: Identity

    /// Remember who is signed in, and flush any token that arrived before
    /// sign-in completed. Pass nil on sign-out.
    func setUserId(_ userId: String?) {
        currentUserId = userId
        if userId != nil, let token = pendingToken {
            storeToken(token)
        }
        // Per-kind preferences follow the account. The cached copy lands
        // first so the settings screen is right instantly and offline;
        // the server read then reconciles anything changed elsewhere.
        if let userId {
            disabledPushKinds = Set(
                UserDefaults.standard.stringArray(forKey: Self.disabledKindsKey(userId)) ?? []
            )
            Task { await refreshPushPreferences() }
        } else {
            disabledPushKinds = []
        }
    }

    // MARK: Per-kind push preferences

    /// The push kinds this account has switched off, held as
    /// `PushKind.rawValue` strings — the exact wire values `send-push`
    /// matches on.
    ///
    /// The *disabled* set, never the enabled one: no row means everything
    /// is on, so a kind introduced in a later release reaches existing
    /// accounts without a backfill. Raw strings rather than `PushKind`
    /// values for the same reason from the other side — a kind this build
    /// doesn't know about survives a read/write round-trip here instead of
    /// being quietly switched back on.
    private(set) var disabledPushKinds: Set<String> = []

    /// Bumped on every local change, so a server read that was already in
    /// flight can tell it has been overtaken and drop its stale answer.
    @ObservationIgnored private var pushPrefsRevision = 0

    /// Timestamps go up as ISO-8601 strings, like every other table this
    /// app writes.
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Cache key namespaced by account, so two sign-ins on one device
    /// never inherit each other's preferences.
    private static func disabledKindsKey(_ userId: String) -> String {
        "notifications.disabledKinds.\(userId)"
    }

    /// Whether pushes of this kind may still reach the signed-in user.
    func isPushEnabled(_ kind: PushKind) -> Bool {
        !disabledPushKinds.contains(kind.rawValue)
    }

    /// Switch a group of kinds on or off together and write it through.
    /// Local state and the cache move first so the toggle never lags and
    /// survives a relaunch; the upsert is fire-and-forget, since a failed
    /// save is worth a log line and nothing more.
    func setPushKinds(_ kinds: [PushKind], enabled: Bool) {
        let raws = Set(kinds.map(\.rawValue))
        var next = disabledPushKinds
        if enabled {
            next.subtract(raws)
        } else {
            next.formUnion(raws)
        }
        guard next != disabledPushKinds else { return }
        disabledPushKinds = next
        pushPrefsRevision += 1
        guard let userId = currentUserId else { return }
        let disabled = next.sorted()
        UserDefaults.standard.set(disabled, forKey: Self.disabledKindsKey(userId))
        Task {
            do {
                try await supabase
                    .from("notification_preferences")
                    .upsert(
                        NotificationPrefsUpsert(
                            userId: userId,
                            disabledKinds: disabled,
                            updatedAt: Self.iso.string(from: Date())
                        ),
                        onConflict: "user_id"
                    )
                    .execute()
            } catch {
                print("[Notifications] Preference save failed: \(error)")
            }
        }
    }

    /// Re-read the account's preferences. Called on sign-in and again when
    /// the settings screen opens, so a change made on another device is
    /// reflected rather than silently overwritten by this one.
    func refreshPushPreferences() async {
        guard let userId = currentUserId else { return }
        let revision = pushPrefsRevision
        do {
            let rows: [NotificationPrefsRow] = try await supabase
                .from("notification_preferences")
                .select("disabled_kinds")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            // A sign-out, an account switch, or a switch the person
            // flipped while this was in flight all outrank the answer.
            guard currentUserId == userId, pushPrefsRevision == revision else { return }
            let kinds = Set(rows.first?.disabledKinds ?? [])
            disabledPushKinds = kinds
            UserDefaults.standard.set(kinds.sorted(), forKey: Self.disabledKindsKey(userId))
        } catch {
            print("[Notifications] Preference load failed: \(error)")
        }
    }

    // MARK: Device token

    /// Called by the AppDelegate with the raw APNs token. Converts to hex,
    /// buffers it, and stores it when a signed-in user is known.
    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = hex
        storeToken(hex)
    }

    func didFailToRegister(_ error: Error) {
        print("[Notifications] Remote registration failed: \(error)")
    }

    /// Upsert the token against the current user. `token` is the table's
    /// primary key, so a device re-registering under a new account simply
    /// reassigns the row. Fire-and-forget — a failure is logged, never
    /// surfaced.
    private func storeToken(_ token: String) {
        guard let userId = currentUserId else { return }
        Task {
            do {
                try await supabase
                    .from("device_tokens")
                    .upsert(
                        DeviceTokenUpsert(userId: userId, token: token, platform: "ios"),
                        onConflict: "token"
                    )
                    .execute()
            } catch {
                print("[Notifications] Token upsert failed: \(error)")
            }
        }
    }

    // MARK: Tap handling

    /// Decode a tapped notification's payload into a route the app shell
    /// can present. No-op when the payload has no recognizable route.
    /// Cheers and focus invites land on the home itself — opening the
    /// app IS the destination, so no cover is presented for those.
    func handleTap(userInfo: [AnyHashable: Any]) {
        guard let route = DeepLinkRoute(userInfo: userInfo) else { return }
        switch route {
        case .home, .grove:
            pendingRoute = nil
        default:
            pendingRoute = route
        }
    }

    // MARK: App icon badge

    /// Set the icon badge to the real number of waiting items. Pushes
    /// carry a server-counted badge; the client re-syncs as threads are
    /// read so the icon never shows a stale count. Fire-and-forget.
    static func syncBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { error in
            if let error {
                print("[Notifications] Badge sync failed: \(error)")
            }
        }
    }

    /// Clear the badge entirely — called when the app comes to the
    /// foreground (the user is looking at the app; the icon shouldn't nag).
    static func clearBadge() {
        syncBadge(0)
    }
}

// MARK: - Wire payload

/// The account's per-kind preferences row. Only the disabled set is ever
/// read or written — an absent row is the default "everything on".
private nonisolated struct NotificationPrefsRow: Decodable, Sendable {
    let disabledKinds: [String]

    enum CodingKeys: String, CodingKey {
        case disabledKinds = "disabled_kinds"
    }
}

/// Encodable payload for upserting the disabled set. `user_id` is the
/// table's primary key, so this replaces the account's row in one call.
private nonisolated struct NotificationPrefsUpsert: Encodable, Sendable {
    let userId: String
    let disabledKinds: [String]
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case disabledKinds = "disabled_kinds"
        case updatedAt = "updated_at"
    }
}

/// Encodable payload for upserting this device's APNs token.
nonisolated struct DeviceTokenUpsert: Encodable, Sendable {
    let userId: String
    let token: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case token, platform
        case userId = "user_id"
    }
}
