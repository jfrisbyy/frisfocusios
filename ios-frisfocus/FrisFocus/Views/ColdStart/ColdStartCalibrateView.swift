//
//  ColdStartCalibrateView.swift
//  FrisFocus
//
//  The calibrate beat — the quick path's answer to "what is a good day
//  worth?", and the screen that keeps the sun reachable.
//
//  The board a person just built is a SEASON'S library, not a day's plan:
//  nothing on it is scheduled, and the mechanics tour teaches pulling the
//  day's few onto today. Before this screen existed the daily target was
//  derived from the whole board, so a full sun demanded most of the season
//  every single day — and the more someone engaged with onboarding, the
//  further out of reach it moved.
//
//  So the number is shown, not hidden. The deep path already ends on a
//  rubric review that says "A strong day lands near N — not everything,
//  just a good day"; this is that same honesty, compressed into one beat,
//  so both doors leave a person understanding their own sun.
//
//  It also teaches the pin-a-few ritual before the tour has to: the few
//  cards listed here are what a real day looks like.
//

import SwiftUI

struct ColdStartCalibrateView: View {
    @Bindable var viewModel: ColdStartViewModel
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    /// Never let the dial reach zero — a sun with no target has no shape.
    private let lowerBound = 1

    /// The suggestion, computed once per appearance so the steppers move a
    /// stable number rather than one that shifts underneath the thumb.
    private var suggestion: Int { viewModel.suggestedDailyTarget }

    private var target: Int { viewModel.resolvedDailyTarget }

    /// The handful of cards the suggestion is built from — shown so the
    /// number reads as a real day rather than an arbitrary figure.
    private var strongDayCards: [ColdStartFinalTask] {
        Array(
            viewModel.finalBoard()
                .sorted { $0.value > $1.value }
                .prefix(ColdStartViewModel.strongDayCardCount)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    prompt
                    dial
                    exampleDay
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { shown = true }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textCream.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
        }
    }

    // MARK: Prompt

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What does a good\nday look like?")
                .font(.serif(28, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your season holds everything you might do. A day holds a few of it — that's the whole idea.")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 10)
    }

    // MARK: The dial

    private var dial: some View {
        VStack(spacing: 14) {
            HStack(spacing: 26) {
                stepButton("minus", enabled: target > lowerBound) {
                    viewModel.chosenDailyTarget = max(lowerBound, target - 1)
                }

                VStack(spacing: 2) {
                    Text("\(target)")
                        .font(.serif(46, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: target)
                    EyebrowText(text: "A STRONG DAY", opacity: 0.6, color: Theme.textCream)
                }
                .frame(minWidth: 96)

                stepButton("plus", enabled: true) {
                    viewModel.chosenDailyTarget = target + 1
                }
            }

            Text("A strong day lands near \(target) — not everything, just a good day.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Only offered once it would actually change something, so it
            // never reads as an accusation that the person got it wrong.
            if viewModel.chosenDailyTarget != nil, target != suggestion {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.chosenDailyTarget = nil
                } label: {
                    Text("Use the suggested \(suggestion)")
                        .font(.sans(12.5, weight: .medium))
                        .foregroundStyle(Theme.textCream.opacity(0.65))
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A strong day is worth \(target) points")
        .accessibilityHint("Adjust if this feels too high or too low")
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 12)
    }

    private func stepButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textCream.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(enabled ? 0.14 : 0.06)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "Lower the target" : "Raise the target")
    }

    // MARK: A day, made concrete

    @ViewBuilder
    private var exampleDay: some View {
        if !strongDayCards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                EyebrowText(text: "A DAY LIKE THIS", opacity: 0.6, color: Theme.textCream)
                VStack(spacing: 8) {
                    ForEach(Array(strongDayCards.enumerated()), id: \.offset) { _, card in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.sunCore.opacity(0.85))
                                .frame(width: 5, height: 5)
                            Text(card.label)
                                .font(.sans(14, weight: .regular))
                                .foregroundStyle(Theme.textCream.opacity(0.88))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(card.value)")
                                .font(.serif(14, weight: .medium))
                                .foregroundStyle(Theme.textCream.opacity(0.5))
                        }
                    }
                }
                Text("You'll choose the day's few each morning — nothing is scheduled for you.")
                    .font(.sans(12.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
        }
    }

    // MARK: Footer

    private var footer: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
        } label: {
            HStack(spacing: 8) {
                Text("That sounds right")
                    .font(.sans(16.5, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.textCream)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        DawnBackdrop(progress: 0.75).ignoresSafeArea()
        ColdStartCalibrateView(viewModel: ColdStartViewModel(), onBack: {}, onContinue: {})
    }
}
