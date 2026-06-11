//
//  MilestonesBoardView.swift
//  FrisFocus
//
//  The Milestones entry point from the season options — the same
//  journey cards as the homepage zone, hosted in a sheet with its own
//  navigation so cards push the full milestone page. Replaces the old
//  plain list (`MilestonesView`).
//

import SwiftUI
import UIKit

struct MilestonesBoardView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pushedMilestone: MilestoneRoute? = nil
    @State private var showComposer: Bool = false

    private var earnedTotal: Int {
        store.logEntries
            .filter { $0.milestoneId != nil && ($0.entryType == .milestone || $0.entryType == .milestoneStep) }
            .map(\.pointsEarned)
            .reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paperCream.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerStrip

                        if store.journeyMilestones.isEmpty {
                            emptyState
                        } else {
                            journeyList
                        }
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Milestones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.alertGreen)
                    }
                    .accessibilityLabel("New milestone")
                }
            }
            .navigationDestination(item: $pushedMilestone) { route in
                MilestoneDetailView(milestoneId: route.id)
            }
            .sheet(isPresented: $showComposer) {
                MilestoneComposerSheet(editing: nil)
            }
        }
    }

    private var headerStrip: some View {
        HStack {
            EyebrowText(
                text: earnedTotal > 0
                    ? "+\(earnedTotal) pts earned this season"
                    : "Map the big wins of your season",
                opacity: 0.55
            )
            Spacer()
        }
    }

    private var journeyList: some View {
        let milestones = store.journeyMilestones
        let nextId = store.nextMilestoneInMotion?.id

        return VStack(spacing: 14) {
            ForEach(milestones) { milestone in
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
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(0.35))
            Text("No milestones yet")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Add the season's big wins — each one scores a large, one-time reward when you reach it.")
                .font(.serifItalic(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .padding(.horizontal, 24)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showComposer = true
            } label: {
                Text("Add a milestone")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.warmWheat)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Theme.alertGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
