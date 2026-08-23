//
//  EdgeSwipe.swift
//  FrisFocus
//
//  One left-edge gesture, two meanings:
//
//   • `edgeSwipeBack()` — deep pages (friend profile, circle, pact,
//     notes, milestones, your own profile) hide the system navigation
//     bar for their custom look, which silently disables the system
//     back gesture. This restores it: a drag from the left edge peeks
//     the page sideways and, past the commit point, dismisses it —
//     works identically for pushed pages and full-screen covers.
//
//   • `edgeSwipeCamera()` — the two root pages (homepage and the
//     Friends room) have nothing to go back to, so the same edge swipe
//     opens the proof camera full screen instead.
//
//  Both claim only drags that *start* in a thin strip at the very
//  edge and move predominantly rightward, attached as simultaneous
//  gestures — taps, vertical scrolling, the side rail, and story rows
//  are never disturbed.
//

import SwiftUI
import UIKit

// MARK: - Back swipe (deep pages)

private struct EdgeSwipeBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    /// Live horizontal peek while the finger drags.
    @State private var dragX: CGFloat = 0
    /// True once a drag has qualified (edge start + horizontal).
    @State private var isActive = false
    /// Latched while the slide-out + dismiss is in flight.
    @State private var isDismissing = false

    private let edgeWidth: CGFloat = 36
    private let commitDistance: CGFloat = 100

    func body(content: Content) -> some View {
        let screenWidth = UIScreen.main.bounds.width
        let progress = min(max(dragX / screenWidth, 0), 1)
        return ZStack {
            // The layer revealed behind the peeking page — warm
            // parchment sliding in with a UIKit-style parallax and a
            // dim that lifts as the page lets go, so the previous
            // page reads as arriving underneath rather than a void.
            if dragX > 0 {
                Theme.warmWheat
                    .overlay(Color.black.opacity(0.12 * (1 - progress)))
                    .offset(x: (dragX - screenWidth) * 0.3)
                    .ignoresSafeArea()
            }

            content
                .offset(x: dragX)
                .shadow(
                    color: .black.opacity(dragX > 0 ? 0.20 : 0),
                    radius: 14,
                    x: -5,
                    y: 0
                )
        }
        .simultaneousGesture(backGesture)
    }

    private var backGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard !isDismissing else { return }
                if !isActive {
                    guard value.startLocation.x <= edgeWidth,
                          value.translation.width > 0,
                          value.translation.width > abs(value.translation.height)
                    else { return }
                    isActive = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                dragX = max(0, value.translation.width)
            }
            .onEnded { value in
                guard isActive, !isDismissing else { return }
                isActive = false
                let commit = value.translation.width > commitDistance
                    || value.predictedEndTranslation.width > 260
                if commit {
                    isDismissing = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.20)) {
                        dragX = UIScreen.main.bounds.width
                    }
                    // The page has visually slid away — dismiss without
                    // a second animation so it never double-plays.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { dismiss() }
                    }
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        dragX = 0
                    }
                }
            }
    }
}

// MARK: - Camera swipe (root pages)

private struct EdgeSwipeCameraModifier: ViewModifier {
    @Environment(Store.self) private var store

    @State private var showCamera = false
    /// Prevents re-triggering within one continuous drag.
    @State private var firedThisDrag = false

    private let edgeWidth: CGFloat = 36
    private let triggerDistance: CGFloat = 70

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(cameraGesture)
            .fullScreenCover(isPresented: $showCamera) {
                // Opens on the clean, overlay-free page — swipe on the
                // viewfinder to reach the season and milestone cards.
                ShareCameraView(subject: .blank)
            }
    }

    private var cameraGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard !firedThisDrag, !showCamera,
                      value.startLocation.x <= edgeWidth,
                      value.translation.width > triggerDistance,
                      value.translation.width > abs(value.translation.height)
                else { return }
                firedThisDrag = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCamera = true
            }
            .onEnded { _ in
                firedThisDrag = false
            }
    }
}

// MARK: - View extensions

extension View {
    /// Left-edge drag-to-peek back swipe for deep pages that hide the
    /// system navigation bar. Works for pushed pages and full-screen
    /// covers alike.
    func edgeSwipeBack() -> some View {
        modifier(EdgeSwipeBackModifier())
    }

    /// Left-edge swipe on root pages: opens the proof camera full
    /// screen with all its destinations (story, send, save, attach).
    func edgeSwipeCamera() -> some View {
        modifier(EdgeSwipeCameraModifier())
    }
}
