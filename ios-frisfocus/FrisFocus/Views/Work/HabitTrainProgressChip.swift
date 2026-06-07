//
//  HabitTrainProgressChip.swift
//  FrisFocus
//
//  Quiet "{done}/{total} today" chip used everywhere a habit train is
//  listed. Charcoal text on a soft cream wash while in progress;
//  switches to a warm gold fill when the train is fully done for
//  today. Never uses streak language.
//

import SwiftUI

struct HabitTrainProgressChip: View {
    let done: Int
    let total: Int
    let earned: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(earned ? Theme.alertAmber : Theme.textPrimary.opacity(0.45))
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
        .accessibilityLabel(earned ? "Routine complete today" : "Routine progress: \(done) of \(total) today")
    }

    private var label: String {
        earned ? "ROUTINE DONE" : "\(done)/\(max(total, 0)) TODAY"
    }

    private var background: Color {
        earned ? Theme.sunWarm.opacity(0.55) : Theme.textPrimary.opacity(0.05)
    }

    private var strokeColor: Color {
        earned ? Theme.alertAmber.opacity(0.55) : Theme.textPrimary.opacity(0.15)
    }

    private var textColor: Color {
        earned ? Theme.textPrimary : Theme.textPrimary.opacity(0.75)
    }
}
