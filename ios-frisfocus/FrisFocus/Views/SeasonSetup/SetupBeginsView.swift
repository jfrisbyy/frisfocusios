//
//  SetupBeginsView.swift
//  FrisFocus
//
//  Screen 5 — the season begins. The sun fully risen, the frozen
//  season's name, a calm closing line, and the quick counts before
//  stepping into daily use. From here on, scoring is local math
//  against the frozen rubric — no AI in the hot path.
//

import SwiftUI
import UIKit

struct SetupBeginsView: View {
    let seasonName: String
    let taskCount: Int
    let categoryCount: Int
    let milestoneCount: Int
    let onSeeToday: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: Bool = false

    var body: some View {
        ZStack {
            SetupSky.risen.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                SetupHeroSun(diameter: 120, haloOpacity: 0.5)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.7)
                    .opacity(revealed || reduceMotion ? 1 : 0)
                    .padding(.bottom, 40)

                Text(seasonName)
                    .font(.serif(33, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 36)
                    .opacity(revealed || reduceMotion ? 1 : 0)
                    .padding(.bottom, 14)

                // The second line is the only place the app ever says
                // what the board does next. Everything is on today, and
                // nothing here is a promise to do all of it — without
                // that, a full board reads as a full obligation.
                VStack(spacing: 10) {
                    Text("Your season's begun. Go live a strong day — not a perfect one.")
                    Text("It's all on today. Clear what isn't happening — a day you don't reach isn't a day you failed.")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                .font(.serifItalic(15, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
                .padding(.horizontal, 44)
                .opacity(revealed || reduceMotion ? 1 : 0)

                HStack(spacing: 28) {
                    countBlock(value: taskCount, label: taskCount == 1 ? "TASK" : "TASKS")
                    countBlock(value: categoryCount, label: categoryCount == 1 ? "CATEGORY" : "CATEGORIES")
                    countBlock(value: milestoneCount, label: milestoneCount == 1 ? "MILESTONE" : "MILESTONES")
                }
                .padding(.top, 34)
                .opacity(revealed || reduceMotion ? 1 : 0)

                Spacer()
                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSeeToday()
                } label: {
                    Text("See today →")
                        .font(.sans(16, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.textPrimary.opacity(0.92))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 1.1, bounce: 0.2).delay(0.15)) {
                revealed = true
            }
        }
    }

    private func countBlock(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.serif(24, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.sans(9.5, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }
}

#Preview {
    SetupBeginsView(
        seasonName: "Keeping Up, Not Drowning",
        taskCount: 11,
        categoryCount: 5,
        milestoneCount: 1,
        onSeeToday: {}
    )
}
