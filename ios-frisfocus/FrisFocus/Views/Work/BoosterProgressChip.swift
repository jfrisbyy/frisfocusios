//
//  BoosterProgressChip.swift
//  FrisFocus
//
//  Quiet, editorial chip that shows booster progress: "{n}/{required} this
//  week (or month)". Charcoal text on a soft category-tinted wash while
//  in progress; switches to a warm gold fill when the booster has been
//  earned this period. Never uses streak language or flame iconography.
//

import SwiftUI

struct BoosterProgressChip: View {
    let progress: Int
    let required: Int
    let earned: Bool
    let period: BoosterPeriod
    let category: Category

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(earned ? Theme.alertAmber : category.color.opacity(0.6))
                .frame(width: 5, height: 5)

            Text(label)
                .font(.sans(10, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(textColor)
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
        if earned {
            return "BOOSTER EARNED"
        }
        return "\(progress)/\(required) THIS \(period.displayName.uppercased())"
    }

    private var background: Color {
        if earned {
            return Theme.sunWarm.opacity(0.55)
        }
        return category.color.opacity(0.06)
    }

    private var strokeColor: Color {
        if earned {
            return Theme.alertAmber.opacity(0.55)
        }
        return category.color.opacity(0.18)
    }

    private var textColor: Color {
        if earned {
            return Theme.textPrimary
        }
        return Theme.textPrimary.opacity(0.8)
    }

    private var accessibilityLabel: String {
        if earned {
            return "Booster earned this \(period.displayName)"
        }
        return "Booster progress: \(progress) of \(required) this \(period.displayName)"
    }
}

#Preview {
    VStack(spacing: 10) {
        BoosterProgressChip(progress: 1, required: 3, earned: false, period: .week, category: .fitness)
        BoosterProgressChip(progress: 3, required: 3, earned: true, period: .week, category: .fitness)
        BoosterProgressChip(progress: 4, required: 10, earned: false, period: .month, category: .work)
    }
    .padding()
    .background(Theme.warmWheat)
}
