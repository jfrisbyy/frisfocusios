//
//  CoachmarkKit.swift
//  FrisFocus
//
//  Shared UI for both walkthrough layers:
//
//   • CoachmarkCard — the dark rounded card (serif-italic title + plain
//     sub) used by the interactive mechanics tour, with an optional
//     gesture hint, a "Skip tour" link, and a tap-through "Continue".
//   • TapPulseHint / SwipeArrowHint — gentle, reduced-motion-safe gesture
//     hints (a tap pulse, a swipe arrow).
//   • WalkthroughLessonSheet + .walkthroughLessonSheet — the quiet
//     bottom-sheet used by the contextual concept layer.
//   • WalkthroughHelpButton — the small "?" that resurfaces a lesson.
//
//  Voice: calm, a little literary, never peppy. Line-icons only, no emoji.
//

import SwiftUI
import UIKit

// MARK: - Gesture hints

/// A soft tap pulse — a ring blooming out from a solid dot. Reduced
/// motion shows a static ring + dot.
struct TapPulseHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = Theme.sunWarm
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.55), lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(reduceMotion ? 1.0 : (animate ? 1.55 : 0.7))
                .opacity(reduceMotion ? 0.5 : (animate ? 0 : 0.85))
            Circle()
                .fill(tint)
                .frame(width: 13, height: 13)
        }
        .frame(width: 54, height: 50)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// A swipe arrow that nudges sideways — the hint for the hidden
/// swipe-to-capture gesture. Reduced motion holds it still.
struct SwipeArrowHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = Theme.sunWarm
    @State private var shift = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 17, weight: .regular))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .opacity(0.55)
        }
        .foregroundStyle(tint)
        .offset(x: reduceMotion ? 0 : (shift ? 9 : -5))
        .frame(height: 50)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shift = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// A calendar with a gently breathing repeat mark — the hint for the
/// rhythm lesson (recurring schedules). Reduced motion holds it still.
struct RhythmHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = Theme.sunWarm
    @State private var breathe = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .regular))
            Image(systemName: "repeat")
                .font(.system(size: 13, weight: .semibold))
                .opacity(reduceMotion ? 0.8 : (breathe ? 1.0 : 0.3))
        }
        .foregroundStyle(tint)
        .frame(height: 50)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small sun easing down to (and below) a horizon line — the hint
/// for the tour's closing "tomorrow" beat. Reduced motion holds the
/// sun resting on the line.
struct SunsetHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dipped = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(Theme.sunWarm)
                .frame(width: 22, height: 22)
                .offset(y: reduceMotion ? 8 : (dipped ? 16 : 2))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                    value: dipped
                )
        }
        .frame(width: 54, height: 42, alignment: .bottom)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.textCream.opacity(0.55))
                .frame(height: 1.5)
        }
        .onAppear { dipped = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Coachmark card (mechanics tour)

/// The dark coachmark card used by the interactive tour. Sits above a
/// soft scrim, never blocking the real element it points at.
struct CoachmarkCard<Hint: View>: View {
    let title: String
    let message: String
    /// Quiet "Skip tour" link, hidden when nil. The ONLY skip — the
    /// other buttons always DO something (advance, or act for you).
    var onSkip: (() -> Void)? = nil
    /// Stuck fallback — appears only after a short idle. Renders as the
    /// filled capsule when the step has no primary action, or as a quiet
    /// text link beside it when it does.
    var continueTitle: String? = nil
    var onContinue: (() -> Void)? = nil
    /// The step's always-visible primary doing-button (e.g. "Set a
    /// rhythm") — used when the real action can't be a page gesture.
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    @ViewBuilder var hint: () -> Hint

    var body: some View {
        VStack(spacing: 13) {
            hint()

            VStack(spacing: 6) {
                Text(title)
                    .font(.serifItalic(18, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.sans(13.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if onSkip != nil || onContinue != nil || onAction != nil {
                HStack(spacing: 12) {
                    if let onSkip {
                        Button(action: onSkip) {
                            Text("Skip tour")
                                .font(.sans(13, weight: .semibold))
                                .foregroundStyle(Theme.textCream.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    if let continueTitle, let onContinue {
                        if onAction != nil {
                            // Quiet link beside the filled primary.
                            Button(action: onContinue) {
                                Text(continueTitle)
                                    .font(.sans(13, weight: .semibold))
                                    .foregroundStyle(Theme.textCream.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        } else {
                            filledCapsule(continueTitle, action: onContinue)
                        }
                    }
                    if let actionTitle, let onAction {
                        filledCapsule(actionTitle, action: onAction)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.sunWarm.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
    }

    /// The warm filled capsule shared by the primary action and the
    /// no-action fallback.
    private func filledCapsule(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.sans(13.5, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.sunWarm))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contextual lesson sheet (concept layer)

/// The quiet bottom-sheet shown for a contextual concept lesson. Light
/// on the warm paper, serif-italic title, one calm line, one button.
struct WalkthroughLessonSheet: View {
    let lesson: WalkthroughLesson
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Theme.textPrimary.opacity(0.12))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            ZStack {
                Circle()
                    .fill(Theme.sunWarm.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: lesson.icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.sunOuter)
            }
            .padding(.top, 4)

            VStack(spacing: 8) {
                Text(lesson.title)
                    .font(.serifItalic(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lesson.message)
                    .font(.sans(14.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 0)

            Button(action: onDone) {
                Text("Got it")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.warmWheat)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .presentationBackground(Theme.warmWheat)
    }
}

/// The small "?" that resurfaces a contextual lesson on its surface.
struct WalkthroughHelpButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What does this mean?")
    }
}

// MARK: - Presentation helper

extension View {
    /// Presents a contextual concept lesson as a quiet bottom-sheet,
    /// marking it seen when dismissed.
    func walkthroughLessonSheet(
        _ item: Binding<WalkthroughLesson?>,
        onSeen: @escaping (WalkthroughLesson) -> Void
    ) -> some View {
        sheet(item: item) { lesson in
            WalkthroughLessonSheet(lesson: lesson) {
                onSeen(lesson)
                item.wrappedValue = nil
            }
        }
    }
}
