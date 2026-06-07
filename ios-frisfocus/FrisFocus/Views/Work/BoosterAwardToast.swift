//
//  BoosterAwardToast.swift
//  FrisFocus
//
//  Quiet, one-shot toast that surfaces a freshly earned booster. Slides
//  down from the top, holds briefly, then auto-dismisses by clearing the
//  store's `pendingBoosterAward`. Tap to dismiss early.
//

import SwiftUI
import UIKit

struct BoosterAwardToast: View {
    let award: BoosterAward?
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
                            // Only clear if the same award is still showing —
                            // prevents racing a newer award that arrived first.
                            if award.id == id {
                                onDismiss()
                            }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: award?.id)
    }

    @ViewBuilder
    private func toast(for award: BoosterAward) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.alertAmber)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text("Booster earned")
                    .font(.serif(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(award.taskTitle) \u{00B7} +\(award.bonusPoints) bonus this \(award.period.displayName)")
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
                .strokeBorder(Theme.alertAmber.opacity(0.4), lineWidth: 0.75)
        )
        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 24)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { onDismiss() }
    }
}
