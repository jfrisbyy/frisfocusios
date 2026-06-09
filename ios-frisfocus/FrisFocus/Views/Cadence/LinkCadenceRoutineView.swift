//
//  LinkCadenceRoutineView.swift
//  FrisFocus
//
//  The "Link a routine" flow (middle reference panel). Two steps in one
//  scroll: choose a Cadence routine (or a passive outcome rule), then
//  decide what it's worth — points (capped), season, priority,
//  recurrence, optional skip penalty. A live preview shows exactly how
//  it will appear before you add it.
//
//  The scoring decision lives entirely on the FrisFocus side; the stored
//  result is a `CadenceLink`.
//

import SwiftUI
import UIKit

struct LinkCadenceRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(CadenceLinkService.self) private var cadence
    @Environment(AuthManager.self) private var auth

    /// What the user picked in step 1 — a launch-run routine or a
    /// passive-outcome rule.
    private enum Choice: Equatable {
        case routine(CadenceRoutineSummary)
        case outcome(CadenceOutcomeKind)
    }

    @State private var choice: Choice?
    @State private var points: Int = 8
    @State private var tier: Tier = .should
    @State private var recurrence: CadenceRecurrence = .nightly
    @State private var skipPenalty: Int = -5
    @State private var threshold: Double = CadenceOutcomeKind.sleepDuration.defaultThreshold

    private var isOutcome: Bool {
        if case .outcome = choice { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statusCard
                    stepOne
                    if choice != nil {
                        stepTwo
                        previewSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.warmWheat.ignoresSafeArea())
            .navigationTitle("Link a routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { addLink() }
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(choice == nil ? Theme.textTertiary : Theme.cadenceLavenderDark)
                        .disabled(choice == nil)
                }
            }
            .toolbarBackground(Theme.warmWheat, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.cadenceLavender)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cadence connected")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Same Esengo account · \(cadence.routineCount) routine\(cadence.routineCount == 1 ? "" : "s")")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.cadenceLavender)
        }
        .padding(14)
        .background(Theme.cadenceLavenderWash)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Step 1

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepEyebrow("1", "Choose a Cadence routine")

            VStack(spacing: 10) {
                ForEach(cadence.routines) { routine in
                    choiceRow(
                        icon: routineIcon(routine.kind),
                        title: routine.name,
                        subtitle: "\(routine.stepCount) step\(routine.stepCount == 1 ? "" : "s") · ~\(routine.estMinutes) min",
                        isSelected: choice == .routine(routine)
                    ) { select(.routine(routine)) }
                }
            }

            Text("Or score an outcome that fills itself")
                .font(.sans(11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .padding(.top, 6)

            VStack(spacing: 10) {
                ForEach(CadenceOutcomeKind.allCases) { kind in
                    choiceRow(
                        icon: kind.icon,
                        title: kind.ruleTitle(threshold: kind.defaultThreshold),
                        subtitle: outcomeSubtitle(kind),
                        isSelected: choice == .outcome(kind)
                    ) { select(.outcome(kind)) }
                }
            }
        }
    }

    // MARK: - Step 2

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepEyebrow("2", "What it's worth")

            VStack(spacing: 0) {
                pointsRow
                rowDivider
                if isOutcome {
                    thresholdRow
                    rowDivider
                }
                staticRow(label: "Season", value: store.currentSeason.name)
                rowDivider
                priorityRow
                if !isOutcome {
                    rowDivider
                    repeatsRow
                }
                if !isOutcome && tier == .must {
                    rowDivider
                    skipPenaltyRow
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )

            Text("Points are capped at \(CadenceLink.pointCeiling) so linked items can't run away with the score.")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var pointsRow: some View {
        HStack {
            Text("Points")
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 16) {
                stepButton(system: "minus", filled: false) {
                    points = max(1, points - 1)
                }
                Text("\(points)")
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 26)
                    .contentTransition(.numericText(value: Double(points)))
                stepButton(system: "plus", filled: true) {
                    points = min(CadenceLink.pointCeiling, points + 1)
                }
            }
            .animation(.easeOut(duration: 0.15), value: points)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var thresholdRow: some View {
        let kind = currentOutcomeKind ?? .sleepDuration
        return HStack {
            Text("Goal")
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 16) {
                stepButton(system: "minus", filled: false) {
                    threshold = max(kind.thresholdRange.lowerBound, threshold - kind.thresholdStep)
                }
                Text(kind.thresholdLabel(threshold))
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 64)
                    .multilineTextAlignment(.center)
                stepButton(system: "plus", filled: true) {
                    threshold = min(kind.thresholdRange.upperBound, threshold + kind.thresholdStep)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var priorityRow: some View {
        HStack {
            Text("Priority")
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Menu {
                Picker("Priority", selection: $tier) {
                    Text("Must").tag(Tier.must)
                    Text("Should").tag(Tier.should)
                    Text("Could").tag(Tier.could)
                }
            } label: {
                menuValue(tier.label.capitalized)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var repeatsRow: some View {
        HStack {
            Text("Repeats")
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Menu {
                Picker("Repeats", selection: $recurrence) {
                    ForEach(CadenceRecurrence.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
            } label: {
                menuValue(recurrence.label)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var skipPenaltyRow: some View {
        HStack {
            Text("Skip penalty")
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 16) {
                stepButton(system: "minus", filled: false) {
                    skipPenalty = max(-20, skipPenalty - 1)
                }
                Text("\(skipPenalty) pts")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(skipPenalty < 0 ? Theme.alertRed : Theme.textSecondary)
                    .frame(minWidth: 56)
                stepButton(system: "plus", filled: true) {
                    skipPenalty = min(0, skipPenalty + 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func staticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        if let link = draftLink {
            VStack(alignment: .leading, spacing: 12) {
                EyebrowText(text: isOutcome ? "Preview in your season" : "Preview in your plan")
                if isOutcome {
                    CadenceOutcomeRow(link: link, isPreview: true)
                } else {
                    CadenceRoutineRow(link: link, isPreview: true)
                }
            }
        }
    }

    // MARK: - Pieces

    private func stepEyebrow(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.sans(10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.cadenceLavender))
            Text(title.uppercased())
                .font(.sans(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
    }

    private func choiceRow(
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.cadenceLavender.opacity(isSelected ? 0.20 : 0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.cadenceLavenderDark)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.cadenceLavender : Theme.textPrimary.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Theme.cadenceLavender).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.cadenceLavender : Theme.textPrimary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func stepButton(system: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? .white : Theme.textPrimary.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(filled ? Theme.cadenceLavender : Theme.textPrimary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func menuValue(_ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.cadenceLavenderDark)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.cadenceLavenderDark.opacity(0.7))
        }
    }

    // MARK: - Selection + build

    private var currentOutcomeKind: CadenceOutcomeKind? {
        if case .outcome(let kind) = choice { return kind }
        return nil
    }

    private func select(_ newChoice: Choice) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            choice = newChoice
            if case .outcome(let kind) = newChoice {
                threshold = kind.defaultThreshold
            }
        }
    }

    private var draftLink: CadenceLink? {
        guard let choice else { return nil }
        let capped = min(max(points, 1), CadenceLink.pointCeiling)
        let accountId = auth.user?.id ?? ""
        switch choice {
        case .routine(let r):
            return CadenceLink(
                accountId: accountId,
                type: .launchRun,
                routineId: r.id,
                routineName: r.name,
                routineKind: r.kind,
                stepCount: r.stepCount,
                estMinutes: r.estMinutes,
                category: routineCategory(r.kind),
                points: capped,
                seasonId: store.currentSeason.id,
                tier: tier,
                recurrence: recurrence,
                skipPenalty: (tier == .must && skipPenalty < 0) ? skipPenalty : nil
            )
        case .outcome(let kind):
            return CadenceLink(
                accountId: accountId,
                type: .passiveOutcome,
                routineName: kind.ruleTitle(threshold: threshold),
                category: outcomeCategory(kind),
                outcomeKind: kind,
                threshold: threshold,
                points: capped,
                seasonId: store.currentSeason.id,
                tier: tier,
                recurrence: recurrence
            )
        }
    }

    private func addLink() {
        guard let link = draftLink else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.addCadenceLink(link)
        dismiss()
    }

    private func routineIcon(_ kind: String?) -> String {
        switch kind?.lowercased() {
        case "sleep": return "moon.stars.fill"
        case "morning": return "sunrise.fill"
        case "focus": return "timer"
        case "fitness", "workout": return "figure.run"
        default: return "play.fill"
        }
    }

    private func routineCategory(_ kind: String?) -> Category {
        switch kind?.lowercased() {
        case "sleep": return .health
        case "morning": return .spiritual
        case "focus", "work": return .work
        case "fitness", "workout": return .fitness
        default: return .health
        }
    }

    private func outcomeCategory(_ kind: CadenceOutcomeKind) -> Category {
        switch kind {
        case .sleepDuration, .windDownTiming: return .health
        case .focusBlock: return .work
        }
    }

    private func outcomeSubtitle(_ kind: CadenceOutcomeKind) -> String {
        switch kind {
        case .sleepDuration: return "Fills from your sleep"
        case .focusBlock: return "Fills from a focus block"
        case .windDownTiming: return "Fills from your wind-down time"
        }
    }
}

#Preview {
    LinkCadenceRoutineView()
        .environment(Store())
        .environment(CadenceLinkService())
        .environment(AuthManager())
}
