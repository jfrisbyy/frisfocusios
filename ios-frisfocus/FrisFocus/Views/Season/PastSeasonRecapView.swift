//
//  PastSeasonRecapView.swift
//  FrisFocus
//
//  The unfolded recap of one past season — its cover, intention,
//  how long it ran, milestone results, and (when a full restorable
//  copy exists) a "Make this my season again" action that brings the
//  whole season back to life. Matches the warm cream-on-dusk profile
//  aesthetic. Reactivation is guarded behind a calm confirmation so it
//  never feels accidental.
//

import SwiftUI
import UIKit

struct PastSeasonRecapView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let chapter: PastSeasonSummary

    @State private var showReactivateConfirm: Bool = false
    @State private var didReactivate: Bool = false

    /// The full restorable copy, if the app kept one for this chapter.
    private var archive: SeasonArchive? { store.archivedSeason(for: chapter.id) }
    private var canReactivate: Bool { archive != nil }

    private var cover: SeasonCoverKind? {
        chapter.coverId.flatMap(SeasonCoverKind.init(rawValue:))
    }

    private var accent: Color {
        if let hex = chapter.accentHex { return Color(hex: hex) }
        if let cover { return Color(hex: cover.suggestedAccentHex) }
        return Theme.duskMid
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        coverHeader
                        VStack(alignment: .leading, spacing: 0) {
                            titleBlock
                            if let intention = archive?.season.intention?
                                .trimmingCharacters(in: .whitespacesAndNewlines), !intention.isEmpty {
                                JournalHairline().padding(.vertical, 18)
                                intentionBlock(intention)
                            }
                            JournalHairline().padding(.vertical, 18)
                            statsBlock
                            if let milestones = archive?.season.milestones, !milestones.isEmpty {
                                JournalHairline().padding(.vertical, 18)
                                milestonesBlock(milestones)
                            }
                            JournalHairline().padding(.vertical, 18)
                            reactivateBlock
                        }
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .confirmationDialog(
                "Make “\(chapter.name)” your season again?",
                isPresented: $showReactivateConfirm,
                titleVisibility: .visible
            ) {
                Button("Bring it back") { reactivate() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current season is safely archived first — you can switch back anytime. \(chapter.name)’s categories, tasks, milestones, and cover all return as your live season.")
            }
        }
    }

    // MARK: - Cover header

    private var coverHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let cover {
                    SeasonCoverView(kind: cover, animated: true)
                } else {
                    LinearGradient(
                        colors: [accent, accent.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(height: 220)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("A SEASON BEFORE")
                    .font(.sans(9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.8))
                Text(chapter.name)
                    .font(.serif(28, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(height: 220)
        .clipped()
    }

    // MARK: - Blocks

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateRangeText)
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
            Text(chapter.ranDescription.replacingOccurrences(of: "ran ", with: "Ran for "))
                .font(.serifItalic(16, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func intentionBlock(_ intention: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            JournalSectionHeader(label: "THE INTENTION")
            Text("“\(intention)”")
                .font(.serifItalic(18, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsBlock: some View {
        HStack(spacing: 14) {
            statTile(
                value: "\(chapter.milestonesReached)/\(max(chapter.milestonesTotal, chapter.milestonesReached))",
                label: "milestones landed"
            )
            if let archive {
                statTile(value: "\(archive.tasks.count)", label: archive.tasks.count == 1 ? "task" : "tasks")
                statTile(value: "\(archive.season.categories.count)", label: archive.season.categories.count == 1 ? "area" : "areas")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(.sans(8.5, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func milestonesBlock(_ milestones: [Milestone]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            JournalSectionHeader(label: "WHAT IT WAS REACHING FOR")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(milestones) { milestone in
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.sans(15, weight: .regular))
                            .foregroundStyle(milestone.isCompleted ? accent : Theme.textPrimary.opacity(0.3))
                        Text(milestone.title)
                            .font(.sans(14, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(milestone.isCompleted ? 0.85 : 0.6))
                            .strikethrough(milestone.isCompleted, color: Theme.textPrimary.opacity(0.4))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reactivateBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canReactivate {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showReactivateConfirm = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.sans(17, weight: .medium))
                        Text("Make this my season again")
                            .font(.sans(15, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.sans(12, weight: .semibold))
                            .opacity(0.7)
                    }
                    .foregroundStyle(Theme.textCream)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .background(Theme.duskDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Your current season is archived first, so you can always switch back.")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    Text("This season was archived before full copies were kept, so only its summary remains — it can’t be reopened in full.")
                        .font(.sans(12.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var dateRangeText: String {
        let start = chapter.startDate.formatted(.dateTime.month(.abbreviated).day().year())
        let end = chapter.endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) – \(end)"
    }

    private func reactivate() {
        guard !didReactivate else { return }
        didReactivate = true
        let ok = store.reactivatePastSeason(chapter.id)
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        dismiss()
    }
}
