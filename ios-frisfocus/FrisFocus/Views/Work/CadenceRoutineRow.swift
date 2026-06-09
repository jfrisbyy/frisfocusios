//
//  CadenceRoutineRow.swift
//  FrisFocus
//
//  A linked Cadence routine in Today's Plan. It reads like a task but is
//  unmistakably Cadence: a soft lavender accent stripe, a "CADENCE" tag,
//  a category dot, and "N steps · ~N min". Instead of a checkbox it has a
//  lavender play control — tapping it deep-links into Cadence to run the
//  routine; the user never returns to check it off here.
//
//  When Cadence records the routine finished, a verified `routine_completed`
//  event credits the points (see Store+Cadence) and the row flips to done:
//  struck through, "✓ earned from Cadence · {time}", with the points earned.
//
//  Used both in Today's Plan and as the live preview in the link flow
//  (an un-added draft link always reads as not-yet-earned).
//

import SwiftUI
import UIKit

struct CadenceRoutineRow: View {
    @Environment(Store.self) private var store
    let link: CadenceLink

    /// When true the row is a static preview (link form) — no deep link.
    var isPreview: Bool = false

    private var isEarned: Bool {
        guard !isPreview else { return false }
        return store.isCadenceLinkEarnedToday(link)
    }

    private var earnedTime: String? {
        store.cadenceEarnedTimeLabel(link)
    }

    private var earnedPoints: Int {
        store.cadenceEarnedPoints(link) ?? cappedPoints
    }

    private var cappedPoints: Int {
        min(max(link.points, 0), CadenceLink.pointCeiling)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Lavender accent stripe — the Cadence cue.
            Rectangle()
                .fill(Theme.cadenceLavender)
                .frame(width: 4)

            HStack(alignment: .top, spacing: 13) {
                control

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(link.routineName)
                            .font(.sans(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(isEarned ? 0.5 : 1.0))
                            .strikethrough(isEarned, color: Theme.textPrimary.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)

                        if link.tier == .must {
                            TierTag(tier: link.tier)
                        }
                    }

                    if isEarned {
                        earnedSubline
                    } else {
                        openSubline
                    }
                }

                Spacer(minLength: 8)

                pointsView
            }
            .padding(14)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.cadenceLavender.opacity(0.22), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.3), value: isEarned)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            isEarned
                ? "\(link.routineName), earned from Cadence"
                : "\(link.routineName), opens in Cadence to run"
        )
        .onTapGesture {
            guard !isEarned, !isPreview else { return }
            openInCadence()
        }
    }

    // MARK: - Control

    @ViewBuilder
    private var control: some View {
        ZStack {
            Circle().fill(Theme.cadenceLavender)
            Image(systemName: isEarned ? "checkmark" : "play.fill")
                .font(.system(size: isEarned ? 13 : 12, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: isEarned ? 0 : 1) // optically centre the play glyph
        }
        .frame(width: 38, height: 38)
        .padding(.top, 1)
    }

    // MARK: - Sublines

    private var openSubline: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(link.category.color)
                    .frame(width: 5, height: 5)
                Text(link.planMeta)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }

            HStack(spacing: 8) {
                CadenceTag()
                Text("↗ Opens in Cadence to run")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.cadenceLavenderDark)
            }
        }
    }

    private var earnedSubline: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text(earnedTime.map { "earned from Cadence · \($0)" } ?? "earned from Cadence")
                .font(.sans(11, weight: .medium))
        }
        .foregroundStyle(Theme.alertGreen)
    }

    // MARK: - Points

    @ViewBuilder
    private var pointsView: some View {
        if isEarned {
            Text("+\(earnedPoints)")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.alertGreen)
                .padding(.top, 2)
        } else {
            Text("\(cappedPoints)")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 2)
        }
    }

    // MARK: - Action

    private func openInCadence() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let url = link.runURL else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success { print("[Cadence] couldn't open \(url) — is Cadence installed?") }
        }
    }
}

// MARK: - CADENCE tag

/// The small lavender "CADENCE" pill marking a linked item.
struct CadenceTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 8, weight: .semibold))
            Text("CADENCE")
                .font(.sans(9, weight: .semibold))
                .tracking(1.0)
        }
        .foregroundStyle(Theme.cadenceLavenderDark)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.cadenceLavender.opacity(0.16))
        .clipShape(Capsule())
    }
}

// MARK: - Tier tag (compact)

private struct TierTag: View {
    let tier: Tier

    var body: some View {
        Text(tier.label)
            .font(.sans(9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(tier.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tier.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

#Preview {
    let store = Store()
    let link = CadenceLink(
        accountId: "demo",
        type: .launchRun,
        routineId: UUID(),
        routineName: "Wind-down routine",
        routineKind: "sleep",
        stepCount: 5,
        estMinutes: 10,
        category: .health,
        points: 10,
        tier: .should,
        recurrence: .nightly
    )
    return VStack(spacing: 10) {
        CadenceRoutineRow(link: link)
    }
    .padding()
    .background(Theme.warmWheat)
    .environment(store)
}
