//
//  NotificationManager.swift
//  FrisFocus
//
//  The client half of push notifications. Owns the permission prompt,
//  the APNs device-token upload into `device_tokens`, and the route a
//  tapped notification resolves to (`pendingRoute`), which the app shell
//  observes to open the exact screen the push is about.
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

    var id: String {
        switch self {
        case .thread(let peerId, _): return "thread:\(peerId)"
        case .friends: return "friends"
        case .circles: return "circles"
        case .circle(let circleId): return "circle:\(circleId)"
        case .golden(let circleId): return "golden:\(circleId)"
        case .milestone(let milestoneId): return "milestone:\(milestoneId)"
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

    // MARK: Identity

    /// Remember who is signed in, and flush any token that arrived before
    /// sign-in completed. Pass nil on sign-out.
    func setUserId(_ userId: String?) {
        currentUserId = userId
        if userId != nil, let token = pendingToken {
            storeToken(token)
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
    func handleTap(userInfo: [AnyHashable: Any]) {
        guard let route = DeepLinkRoute(userInfo: userInfo) else { return }
        pendingRoute = route
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
