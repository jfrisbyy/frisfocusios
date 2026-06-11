//
//  MilestoneZoneView.swift
//  FrisFocus
//
//  Zone 4 — the season's big goals as a vertical journey on the same
//  warm paper as the note zone above it. Each milestone is a pinned
//  card with its target week, reward, step progress, and journey
//  thumbnails; the next one in motion gets a warm glow. Tapping a card
//  pushes the full milestone page; the "+ New milestone" pill matches
//  the New Note pill above.
//

import SwiftUI
import UIKit

/// Identifiable wrapper so a milestone id can drive
/// `navigationDestination(item:)` pushes.
struct MilestoneRoute: Identifiable, Hashable {
    let id: UUID
}

struct MilestoneZoneView: View {
    @Environment(Store.self) private var store

    @State private var pushedMilestone: MilestoneRoute? = nil
    @State private var showComposer: Bool = false

    var body: some View {
        ZStack {
            Theme.paperCream

            VStack(alignment: .leading, spacing: 22) {
                headerBlock
                    .padding(.top, 28)

                if store.journeyMilestones.isEmpty {
                    emptyState
                } else {
                    journeyList
                }

                newMilestonePrompt
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
        }
        .navigationDestination(item: $pushedMilestone) { route in
            MilestoneDetailView(milestoneId: route.id)
        }
        .sheet(isPresented: $showComposer) {
            MilestoneComposerSheet(editing: nil)
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ZoneHeaderView(
                    title: "Milestones",
                    eyebrowRight: "Zone 4 of 4",
                    subline: seasonSubline
                )

                Spacer(minLength: 0)

                newMilestonePill
                    .accessibilityLabel("New milestone")
            }

            // Hairline warm-gold rule — same language as the note zone.
            Rectangle()
                .fill(Theme.sunWarm.opacity(0.45))
                .frame(height: 0.5)
                .padding(.top, 2)
        }
    }

    private var seasonSubline: String {
        let milestones = store.journeyMilestones
        guard !milestones.isEmpty else { return "the season's big wins" }
        let done = milestones.filter(\.isCompleted).count
        return "the season's big wins · \(done) of \(milestones.count) landed"
    }

    private var newMilestonePill: some View {
        Button(action: openComposer) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("New milestone")
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.warmWheat)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Theme.sunWarm.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Theme.sunWarm.opacity(0.22), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Journey

    private var journeyList: some View {
        let milestones = store.journeyMilestones
        let nextId = store.nextMilestoneInMotion?.id

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                HStack(alignment: .top, spacing: 12) {
                    journeyMarker(
                        for: milestone,
                        isNext: milestone.id == nextId,
                        isLast: index == milestones.count - 1
                    )

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        pushedMilestone = MilestoneRoute(id: milestone.id)
                    } label: {
                        MilestoneCardView(milestone: milestone, isNext: milestone.id == nextId)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(milestone.title)
                    .accessibilityHint("Opens the milestone's page")
                    .padding(.bottom, index == milestones.count - 1 ? 0 : 16)
                }
            }
        }
    }

    /// The journey thread beside each card — a dot for the milestone
    /// and a hairline continuing down to the next one.
    @ViewBuilder
    private func journeyMarker(for milestone: Milestone, isNext: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if milestone.isCompleted {
                    Circle()
                        .fill(Theme.alertGreen.opacity(0.85))
                        .frame(width: 11, height: 11)
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Theme.paperCream)
                } else if isNext {
                    Circle()
                        .fill(Theme.sunWarm.opacity(0.35))
                        .frame(width: 17, height: 17)
                    Circle()
                        .fill(Theme.sunOuter)
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .strokeBorder(Theme.textPrimary.opacity(0.3), lineWidth: 1.2)
                        .frame(width: 11, height: 11)
                }
            }
            .frame(width: 18, height: 18)
            .padding(.top, 14)

            if !isLast {
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 18)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "This season", opacity: 0.5)
            Text("no big wins mapped yet")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            Text("Set the season's first milestone — a goal worth a deliberately large, one-time reward.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - New milestone prompt

    private var newMilestonePrompt: some View {
        Button(action: openComposer) {
            HStack(spacing: 10) {
                Image(systemName: "flag")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))

                Text("Map the next big win of the season")
                    .font(.serifItalic(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.textPrimary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a new milestone")
    }

    private func openComposer() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showComposer = true
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            MilestoneZoneView()
        }
        .environment(Store())
    }
}
