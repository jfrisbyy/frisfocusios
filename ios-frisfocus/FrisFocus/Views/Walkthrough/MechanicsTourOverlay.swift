//
//  MechanicsTourOverlay.swift
//  FrisFocus
//
//  Layer A — the interactive mechanics tour. A soft scrim dims the page
//  (never a harsh cutout) while a coachmark + gesture hint prompts the
//  real gesture on the real Today plan below. The scrim never blocks
//  touches, so the user performs the actual action and the real result
//  teaches; the host (HomeView / WorkZoneView) advances the tour when
//  the gesture lands. "Skip tour" is always present, and a tap-through
//  "Continue" appears if the user is stuck for a few seconds — so the
//  tour can never trap.
//

import SwiftUI

struct MechanicsTourOverlay: View {
    @Environment(WalkthroughManager.self) private var walkthrough
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reveals the tap-through "Continue" after a short idle, so a stuck
    /// user is never trapped. Reset on every step change.
    @State private var showFallback = false
    @State private var fallbackTask: Task<Void, Never>?

    var body: some View {
        if walkthrough.tourActive, let step = walkthrough.tourStep {
            ZStack(alignment: .bottom) {
                // Soft scrim — dims the page but passes every touch
                // through to the real cards beneath.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                card(for: step)
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.bottom, 128)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .id(step)
            }
            .animation(
                reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.86),
                value: step
            )
            .onAppear { armFallback() }
            .onChange(of: step) { _, _ in armFallback() }
            .onDisappear { fallbackTask?.cancel() }
        }
    }

    @ViewBuilder
    private func card(for step: WalkthroughManager.MechanicsStep) -> some View {
        switch step {
        case .checkOff:
            CoachmarkCard(
                title: "Tap the circle to check it off.",
                message: "Your sun rises a little with every task you complete — that’s your day, at a glance.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Skip this" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil
            ) { TapPulseHint() }

        case .swipeCapture:
            CoachmarkCard(
                title: "Swipe a finished task to capture it.",
                message: "It opens the camera to snap proof — the lift, the meal, the moment. Then you choose who sees it; proofs go only to the friends you pick.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Skip this" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil
            ) { SwipeArrowHint() }

        case .quantity:
            CoachmarkCard(
                title: "Some tasks track an amount.",
                message: "Enter how much, not just done — the sun knows the difference between a step and a mile.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Got it" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil
            ) { TapPulseHint() }
        }
    }

    /// Show the tap-through fallback after a short idle on each step.
    private func armFallback() {
        fallbackTask?.cancel()
        showFallback = false
        fallbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showFallback = true }
        }
    }
}
