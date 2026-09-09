//
//  SundialNavView.swift
//  FrisFocus
//
//  The app's primary bottom navigation chrome — a small, minimal
//  frosted-glass pill floating at the bottom center with just two
//  destinations: Home and Friends.
//
//  It reads as quiet chrome, not a centerpiece: at rest it's softly
//  dimmed and recedes while you scroll and read; the moment a finger
//  reaches toward it (or taps), it lifts to full strength, then eases
//  back to its quiet rest. The current page is gently highlighted.
//
//  The view is stateless about navigation: the parent owns the active
//  destination and the tap callbacks. A light haptic fires on each tap.
//
//  (The legacy sundial — engraved half-disc, swinging hand, glowing
//  sun "+" capture button — has been retired. `onCaptureTap` is kept on
//  the initializer purely for call-site compatibility and is no longer
//  surfaced; capture now flows through Today's Plan's add controls.)
//

import SwiftUI
import UIKit

/// Which destination the nav is currently showing.
enum SundialDestination: Equatable {
    case home
    case capture
    case circles
    /// Used by sub-pages — neither item reads as selected, so the user
    /// knows they're off the two main pages.
    case subPage
}

struct SundialNavView: View {
    let active: SundialDestination
    /// Retained for call-site compatibility; no longer surfaced in the
    /// minimal pill (capture moved into Today's Plan).
    var onCaptureTap: () -> Void = {}
    let onHomeTap: () -> Void
    let onCirclesTap: () -> Void
    /// Unread direct messages — rendered as a small count badge on the
    /// Friends item so new messages are visible from anywhere.
    var circlesBadgeCount: Int = 0
    /// Optional third node: the person's own avatar, opening the profile
    /// quick card. The top-right avatar remains; this is a second door
    /// to the same room, at the bottom of the screen where a thumb
    /// already lives — and well away from the corner that has been
    /// reported dead three times over.
    var onProfileTap: (() -> Void)? = nil
    var profileInitials: String = ""
    var profilePhotoURL: URL? = nil
    var profileDot: Bool = false

    // MARK: - Discreet rest / brighten-on-reach state

    /// True whenever a finger is resting on the pill. Drives the
    /// "brighten when you reach for it" behaviour — the pill lifts to
    /// full opacity while touched, then eases back to its quiet rest.
    @State private var isTouched: Bool = false
    /// Guards the delayed rest-fade so a fresh touch cancels a pending one.
    @State private var fadeToken: UUID = UUID()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Resting opacity — the pill recedes while you scroll and read,
    /// but stays legible enough to find at a glance.
    private let restOpacity: Double = 0.5

    var body: some View {
        HStack(spacing: 4) {
            navItem(
                systemImage: "sun.max",
                label: "Home",
                isActive: active == .home,
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onHomeTap()
                }
            )

            navItem(
                systemImage: "person.2",
                label: "Friends",
                isActive: active == .circles,
                badge: circlesBadgeCount,
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onCirclesTap()
                }
            )

            if let onProfileTap {
                profileNode(action: onProfileTap)
            }
        }
        .padding(5)
        .background(pillBackground)
        .overlay(
            Capsule()
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        // No .clipShape here — the background is already capsule-shaped,
        // and clipping would cut off the unread badge riding the edge.
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .opacity(isTouched ? 1.0 : restOpacity)
        .scaleEffect(isTouched ? 1.0 : 0.985, anchor: .bottom)
        .simultaneousGesture(touchGesture)
        .animation(.easeInOut(duration: 0.35), value: isTouched)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 26)
        .allowsHitTesting(true)
    }

    // MARK: - Pill background (frosted glass)

    @ViewBuilder
    private var pillBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Theme.warmWheat.opacity(0.001))
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Theme.warmWheat.opacity(0.35)))
        }
    }

    // MARK: - Nav item

    @ViewBuilder
    private func navItem(
        systemImage: String,
        label: String,
        isActive: Bool,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: isActive ? "\(systemImage).fill" : systemImage)
                .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                .foregroundStyle(
                    isActive ? Theme.textPrimary : Theme.textPrimary.opacity(0.42)
                )
                .frame(width: 60, height: 40)
                .background(
                    Capsule()
                        .fill(Theme.textPrimary.opacity(isActive ? 0.08 : 0))
                )
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.sans(9, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 4.5)
                            .frame(minWidth: 16)
                            .frame(height: 16)
                            .background(Capsule().fill(Color(hex: 0xE0454C)))
                            .overlay(
                                Capsule().strokeBorder(
                                    Theme.warmWheat.opacity(0.9),
                                    lineWidth: 1.2
                                )
                            )
                            .offset(x: 4, y: -4)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.7),
                    value: badge > 0
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(
            badge > 0 ? "\(label), \(badge) unread" : label
        )
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Profile node

    /// The avatar as a nav item — same 60×40 slot as its siblings, disc
    /// inside, dot for waiting friend requests.
    @ViewBuilder
    private func profileNode(action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Log.app.debug("profile: sundial node tap delivered")
            action()
        } label: {
            ZStack {
                Circle().fill(Theme.textPrimary)
                if let url = profilePhotoURL {
                    CachedImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        profileGlyph
                    }
                } else {
                    profileGlyph
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 1.2))
            .overlay(alignment: .topTrailing) {
                if profileDot {
                    Circle()
                        .fill(Theme.alertRed)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.warmWheat.opacity(0.9), lineWidth: 1))
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 60, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(profileDot ? "Profile, new friend requests waiting" : "Profile")
        .accessibilityHint("Open profile, settings, and help")
    }

    private var profileGlyph: some View {
        Group {
            if profileInitials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text(profileInitials)
                    .font(.sans(10.5, weight: .medium))
            }
        }
        .foregroundStyle(Theme.textCream)
    }

    // MARK: - Touch (brighten-on-reach) gesture

    /// Zero-distance drag used purely to detect that a finger is on the
    /// pill. It never commits navigation; `simultaneousGesture` keeps the
    /// buttons fully tappable.
    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                if !isTouched { isTouched = true }
            }
            .onEnded { _ in
                scheduleRestFade()
            }
    }

    /// Eases the pill back to its quiet resting opacity a beat after the
    /// finger lifts, unless another touch arrives first.
    private func scheduleRestFade() {
        let token = UUID()
        fadeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard fadeToken == token else { return }
            isTouched = false
        }
    }
}

#Preview("Home active") {
    VStack {
        Spacer()
        SundialNavView(
            active: .home,
            onHomeTap: {},
            onCirclesTap: {},
            circlesBadgeCount: 3
        )
    }
    .background(Theme.warmWheat)
}

#Preview("Friends active") {
    VStack {
        Spacer()
        SundialNavView(
            active: .circles,
            onHomeTap: {},
            onCirclesTap: {}
        )
    }
    .background(Theme.warmWheat)
}

#Preview("Sub-page") {
    VStack {
        Spacer()
        SundialNavView(
            active: .subPage,
            onHomeTap: {},
            onCirclesTap: {}
        )
    }
    .background(Theme.warmWheat)
}
