//
//  PenaltyLimitTag.swift
//  FrisFocus
//
//  Quiet, editorial tag that surfaces a task's weekly-limit rule
//  without scarlet warnings. Reads "limit · ≤2/wk" or "limit · ≥3/wk"
//  depending on the configured condition, and switches to a soft
//  amber wash when the limit is currently breached.
//
//  Strictly private — never broadcast. Lives next to the booster
//  chip in the task card.
//

import SwiftUI

struct PenaltyLimitTag: View {
    let count: Int
    let threshold: Int
    let condition: PenaltyCondition
    let penaltyPoints: Int
    let breached: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(breached ? Theme.alertAmber : Theme.textPrimary.opacity(0.35))
                .frame(width: 5, height: 5)

            Text(label)
                .font(.sans(10, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Theme.textPrimary.opacity(breached ? 0.95 : 0.7))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(background)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 0.5)
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        if breached {
            return "LIMIT \u{00B7} \u{2212}\(penaltyPoints) THIS WEEK"
        }
        return "LIMIT \u{00B7} \(condition.shortPhrase)\(threshold)/WK"
    }

    private var background: Color {
        breached ? Theme.alertAmber.opacity(0.14) : Theme.textPrimary.opacity(0.04)
    }

    private var strokeColor: Color {
        breached ? Theme.alertAmber.opacity(0.45) : Theme.textPrimary.opacity(0.15)
    }

    private var accessibilityLabel: String {
        let direction = condition == .moreThan ? "at most" : "at least"
        if breached {
            return "Weekly limit currently breached, \(penaltyPoints) points deducted"
        }
        return "Weekly limit: \(direction) \(threshold) per week, at \(count)"
    }
}

#Preview {
    VStack(spacing: 10) {
        PenaltyLimitTag(count: 1, threshold: 2, condition: .moreThan, penaltyPoints: 10, breached: false)
        PenaltyLimitTag(count: 3, threshold: 2, condition: .moreThan, penaltyPoints: 10, breached: true)
        PenaltyLimitTag(count: 1, threshold: 3, condition: .lessThan, penaltyPoints: 8, breached: true)
    }
    .padding()
    .background(Theme.warmWheat)
}
