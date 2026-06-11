//
//  FriendRequestBanner.swift
//  FrisFocus
//
//  A quiet in-app banner for live friend-graph moments — a request just
//  arrived, or someone accepted yours. Slides in from the top of the
//  home shell, auto-dismisses after a few seconds, and tapping it opens
//  the Friends page. Reads the app-wide `FriendGraphService.banner`
//  event and consumes it once shown.
//

import SwiftUI
import UIKit

struct FriendRequestBanner: View {
    @Environment(FriendGraphService.self) private var friendGraph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called when the banner is tapped — the host opens the Friends page.
    let onOpen: () -> Void

    /// The event currently on screen (held locally so the slide-out can
    /// finish even after the service's `banner` is cleared).
    @State private var shown: FriendBannerEvent?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            if let event = shown {
                bannerCard(event)
                    .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: shown?.id)
        .onChange(of: friendGraph.banner?.id) { _, _ in
            guard let event = friendGraph.banner else { return }
            present(event)
        }
    }

    private func present(_ event: FriendBannerEvent) {
        // Consume the service event; the local copy drives the UI.
        friendGraph.banner = nil
        shown = event
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            shown = nil
        }
    }

    private func bannerCard(_ event: FriendBannerEvent) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissTask?.cancel()
            shown = nil
            onOpen()
        } label: {
            HStack(spacing: 11) {
                RemoteAvatarView(profile: event.profile, size: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.kind == .requestAccepted ? "NOW FRIENDS" : "FRIEND REQUEST")
                        .font(.sans(9, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(event.kind == .requestAccepted
                                         ? Theme.alertGreen
                                         : Theme.sunShadow)
                    Text(event.message)
                        .font(.sans(13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Image(systemName: event.kind == .requestAccepted
                      ? "checkmark.circle.fill"
                      : "person.crop.circle.badge.plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(event.kind == .requestAccepted
                                     ? Theme.alertGreen
                                     : Theme.textPrimary.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.paperCream.opacity(0.88))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -12 {
                        dismissTask?.cancel()
                        shown = nil
                    }
                }
        )
        .accessibilityLabel(event.message)
        .accessibilityHint("Opens the Friends page")
    }
}
