//
//  HabitTrainAwardToast.swift
//  FrisFocus
//
//  Quiet, one-shot toast surfaced when a habit-train's daily completion
//  bonus is awarded. Same shape as the booster toast — different copy,
//  different tint — slides down from the top and auto-dismisses.
//

import SwiftUI
import UIKit

struct HabitTrainAwardToast: View {
    let award: TrainAward?
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if let award {
                toast(for: award)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(award.id)
                    .onAppear {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        let id = award.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                            if award.id == id { onDismiss() }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: award?.id)
    }

    @ViewBuilder
    private func toast(for award: TrainAward) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.sunOuter)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text("Routine complete")
                    .font(.serif(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(award.trainName) \u{00B7} +\(award.bonusPoints) bonus today")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.warmWheat)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.sunOuter.opacity(0.5), lineWidth: 0.75)
        )
        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 24)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { onDismiss() }
    }
}
