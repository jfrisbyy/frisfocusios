//
//  PlayerDismissal.swift
//  FrisFocus
//
//  Shared pieces that make the full-screen players (stories, proofs,
//  direct shares) feel premium:
//
//   • `PlayerDragMetrics` — the math behind interactive dismissal. As
//     the user drags down, the player card scales down, grows a corner
//     radius, follows the finger with a little horizontal parallax,
//     and the black backdrop fades. Release is velocity-aware: a calm
//     long pull or a quick flick both dismiss.
//   • `playerCardEffect` — applies those metrics to the card.
//   • `zoomSource` / zoom destination helpers — opt-in wrappers around
//     the iOS 18 zoom transition so a player can grow out of the exact
//     avatar / pill that opened it and shrink back into it on close.
//

import SwiftUI

// MARK: - Interactive dismissal metrics

/// The state + derived visuals of a drag-to-dismiss in progress.
/// Stored as plain translation; everything else is derived so the
/// card, corner radius, and backdrop always stay in lockstep.
struct PlayerDragMetrics: Equatable {
    var translation: CGSize = .zero

    /// 0 at rest → 1 fully dragged. Tuned so the card reads as "letting
    /// go" well before the finger reaches the bottom of the screen.
    var progress: CGFloat {
        min(max(translation.height / 560, 0), 1)
    }

    var scale: CGFloat { 1 - 0.3 * progress }

    /// Corner radius ramps in quickly so the very first few points of
    /// drag already read as "this is a card now."
    var cornerRadius: CGFloat { 44 * min(progress * 4, 1) }

    /// The black canvas behind the card quietly falls away as you drag.
    var backdropOpacity: Double { 1 - 0.6 * Double(progress) }

    /// The card follows the finger vertically and trails it
    /// horizontally with a soft parallax.
    var offset: CGSize {
        CGSize(width: translation.width * 0.55, height: max(0, translation.height))
    }

    var isActive: Bool { translation.height > 0 }

    /// Velocity-aware release: a deliberate pull past the threshold or
    /// a quick flick (large predicted end point) both dismiss.
    static func shouldDismiss(translation: CGSize, predicted: CGSize) -> Bool {
        translation.height > 150 || predicted.height > 320
    }
}

extension View {
    /// Applies the in-flight drag-to-dismiss visuals to a full-screen
    /// player card: clip → scale → follow the finger.
    func playerCardEffect(_ drag: PlayerDragMetrics) -> some View {
        self
            .clipShape(.rect(cornerRadius: drag.cornerRadius))
            .scaleEffect(drag.scale)
            .offset(drag.offset)
    }
}

// MARK: - Zoom transition helpers

extension View {
    /// Tags a view as the visual origin of a zoom transition. No-ops
    /// when no namespace is supplied (e.g. previews), so callers can
    /// thread the namespace through optionally.
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Marks presented/pushed content as the destination of a zoom
    /// transition growing out of the `zoomSource` with the same id.
    @ViewBuilder
    func zoomDestination(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
