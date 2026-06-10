//
//  LogQuantitySheet.swift
//  FrisFocus
//
//  Amount entry for tiered and quantity-based tasks. Flat tasks never
//  reach here — they log with a single check. Here the user dials in how
//  much they did (hours slept, reps done, steps walked) and sees the
//  points they'll earn update live before committing. Logging writes a
//  completion with the computed points and the amount, so the card can
//  show what was logged.
//

import SwiftUI
import UIKit

struct LogQuantitySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let task: FFTask

    @State private var amount: Double

    init(task: FFTask) {
        self.task = task
        let initial: Double = {
            switch task.scoring.type {
            case .tiered: return task.scoring.sortedTiers.first?.threshold ?? 1
            case .quantity: return task.scoring.baseThreshold
            case .flat: return 0
            }
        }()
        _amount = State(initialValue: initial)
    }

    private var earned: Int {
        task.scoring.points(forQuantity: amount, flatValue: task.pointValue)
    }

    private var step: Double {
        switch task.scoring.type {
        case .quantity: return max(1, task.scoring.unitSize)
        case .tiered:
            let u = task.scoring.unit.lowercased()
            return (u.contains("hour") || u.contains("hr")) ? 0.5 : 1
        case .flat: return 1
        }
    }

    private var unitLabel: String { task.scoring.unit }

    /// Whole-number display when the amount is integral, else one decimal.
    private var amountText: String {
        amount == amount.rounded() ? String(Int(amount)) : String(format: "%.1f", amount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    dial
                    pointsPreview
                    if task.scoring.type == .tiered {
                        tierLadder
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("Log amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
            .safeAreaInset(edge: .bottom) { logButton }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(Color(hex: store.categoryColorHex(task.category)))
                .frame(width: 10, height: 10)
            Text(task.title)
                .font(.serif(20, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
            Text("How much did you do?")
                .font(.serifItalic(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
    }

    private var dial: some View {
        HStack(spacing: 22) {
            roundButton(systemName: "minus") {
                amount = max(0, amount - step)
            }

            VStack(spacing: 0) {
                Text(amountText)
                    .font(.serif(52, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: amount))
                    .animation(.snappy(duration: 0.25), value: amount)
                if !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }
            .frame(minWidth: 120)

            roundButton(systemName: "plus") {
                amount += step
            }
        }
    }

    private func roundButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .frame(width: 50, height: 50)
                .background(Color.white)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var pointsPreview: some View {
        VStack(spacing: 2) {
            Text("\(earned)")
                .font(.serif(40, weight: .medium))
                .foregroundStyle(earned > 0 ? Theme.alertGreen : Theme.textPrimary.opacity(0.4))
                .contentTransition(.numericText(value: Double(earned)))
                .animation(.snappy(duration: 0.25), value: earned)
            Text(earned == 1 ? "point" : "points")
                .font(.sans(12, weight: .medium))
                .tracking(1)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tierLadder: some View {
        VStack(spacing: 0) {
            ForEach(task.scoring.sortedTiers) { tier in
                let active = amount >= tier.threshold
                let isTop = topMetTierId == tier.id
                HStack {
                    Text("\(tierThresholdText(tier.threshold))\(unitLabel.isEmpty ? "" : " \(unitLabel)")")
                        .font(.sans(13, weight: isTop ? .semibold : .regular))
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textPrimary.opacity(0.4))
                    Spacer()
                    Text("\(tier.points) pts")
                        .font(.serif(15, weight: isTop ? .semibold : .regular))
                        .foregroundStyle(isTop ? Theme.alertGreen : (active ? Theme.textPrimary.opacity(0.7) : Theme.textPrimary.opacity(0.35)))
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(isTop ? Theme.alertGreen.opacity(0.1) : Color.clear)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var topMetTierId: UUID? {
        task.scoring.sortedTiers.filter { amount >= $0.threshold }.last?.id
    }

    private func tierThresholdText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var logButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            store.completeTask(task, quantity: amount)
            dismiss()
        } label: {
            Text(earned > 0 ? "Log \(earned) pts" : "Log")
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(Theme.warmWheat)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.alertGreen)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

#Preview {
    LogQuantitySheet(
        task: FFTask(
            title: "Sleep 7+ hours",
            category: .health,
            pointValue: 4,
            pinSchedule: .daily,
            scoring: ScoringConfig(
                type: .tiered,
                unit: "hours",
                tiers: [
                    ScoreTier(threshold: 6, points: 2),
                    ScoreTier(threshold: 7, points: 4),
                    ScoreTier(threshold: 8, points: 6)
                ]
            )
        )
    )
    .environment(Store())
}
