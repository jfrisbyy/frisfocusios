//
//  NotificationRouteHost.swift
//  FrisFocus
//
//  The destination for a tapped push. Presented full-screen from the app
//  shell whenever `NotificationManager.pendingRoute` is set, it routes the
//  four push kinds onto their exact surfaces:
//
//   • thread  → the Proofs inbox opened straight into that person's 1:1.
//   • friends → the Friends screen.
//   • circles → the shared-circles list.
//   • circle  → one circle's detail (loaded behind a brief spinner so it
//               never flashes a "missing" state on a cold open).
//
//  It's a dedicated host rather than threading state through the account
//  hub's nested navigation — cleaner, and each surface keeps its own
//  realtime + dismissal behaviour.
//

import SwiftUI

struct NotificationRouteHost: View {
    let route: DeepLinkRoute
    let myUserId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation

    var body: some View {
        switch route {
        case .thread(let peerId, let messageId):
            // The inbox owns its own header + close button (dismisses the
            // cover) and opens the thread itself via `initialPeerId`. A
            // proof push also carries the message id so the thread can
            // drop straight into the full-screen player.
            ProofsInboxView(initialPeerId: peerId, initialMessageId: messageId)
                .environment(store)
                .environment(auth)
                .environment(moderation)

        case .friends:
            NavigationStack {
                FriendsView()
                    .toolbar { doneButton }
            }
            .environment(auth)
            .environment(moderation)

        case .circles:
            NavigationStack {
                SharedCirclesListView()
                    .toolbar { doneButton }
            }
            .environment(auth)

        case .circle(let circleId):
            if let uuid = UUID(uuidString: circleId) {
                DeepLinkCircleDetailView(circleId: uuid, myUserId: myUserId) { dismiss() }
                    .environment(auth)
            } else {
                RouteFallback(message: "This circle link is no longer valid.") { dismiss() }
            }

        case .golden(let circleId):
            // Golden Hour notifications land on the golden surface itself:
            // the countdown camera while live, the wall during the hour,
            // and only the residue card after — never a story or thread.
            if let uuid = UUID(uuidString: circleId) {
                GoldenHourHostView(circleId: uuid)
                    .environment(auth)
            } else {
                RouteFallback(message: "This Golden Hour link is no longer valid.") { dismiss() }
            }

        case .milestone(let milestoneId):
            // A target-week nudge lands directly on that milestone's page.
            if let uuid = UUID(uuidString: milestoneId),
               store.milestone(by: uuid) != nil {
                NavigationStack {
                    MilestoneDetailView(milestoneId: uuid)
                        .toolbar { doneButton }
                }
                .environment(store)
            } else {
                RouteFallback(message: "This milestone was completed or removed.") { dismiss() }
            }
        }
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Gated circle detail

/// Loads one circle into a fresh service, then shows its detail. Until the
/// load lands it shows a spinner (rather than the detail's "missing"
/// state, which would otherwise flash and self-dismiss).
private struct DeepLinkCircleDetailView: View {
    let circleId: UUID
    let myUserId: String
    let onClose: () -> Void

    @State private var service = CircleGraphService()
    @State private var didLoad = false

    private var circleLoaded: Bool { service.circles.contains { $0.id == circleId } }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            if circleLoaded {
                SharedCircleDetailView(service: service, circleId: circleId, myUserId: myUserId)
            } else if didLoad {
                RouteFallback(message: "You may have left this circle, or it was deleted.", onClose: onClose)
            } else {
                ProgressView().tint(Theme.textPrimary)
            }
        }
        .task {
            guard !myUserId.isEmpty else { didLoad = true; return }
            await service.load(myUserId: myUserId)
            didLoad = true
        }
        .onDisappear { service.stopRealtime() }
    }
}

// MARK: - Fallback

/// A calm "nothing to show" state with a Done button, for malformed or
/// vanished deep-link targets.
private struct RouteFallback: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("Nothing to open")
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button(action: onClose) {
                    Text("Done")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.horizontal, 22)
                        .frame(height: 44)
                        .background(Theme.textPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(40)
        }
    }
}
