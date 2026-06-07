//
//  ScoreHeadlineView.swift
//  FrisFocus
//
//  The magazine-style headline that replaces the score-inside-the-sun
//  treatment. Eyebrow "TODAY", a very large serif number, then a
//  "GOAL · N" subtitle. Always cream so it reads across every sky
//  palette.
//

import SwiftUI

struct ScoreHeadlineView: View {
    let score: Int
    let goal: Int

    var body: some View {
        VStack(spacing: 14) {
            Text("TODAY")
                .font(.sans(10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(Theme.textCream.opacity(0.75))

            Text("\(score)")
                .font(.serif(86, weight: .medium))
                .tracking(-3.5)
                .foregroundStyle(Theme.textCream)
                // Tight line for a 1-2 digit number so the surrounding
                // copy reads as headline + score + footer in one column.
                .lineSpacing(-30)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText(value: Double(score)))
                .animation(.easeOut(duration: 0.5), value: score)

            Text("GOAL · \(goal)")
                .font(.sans(11, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Theme.textCream.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Theme.skyDeep, Theme.skyMid, Theme.skyLow],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            ScoreHeadlineView(score: 32, goal: 50)
            Spacer()
        }
        .padding(.top, 80)
    }
}
