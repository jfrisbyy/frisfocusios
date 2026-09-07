//
//  AddToSectionSheet.swift
//  FrisFocus
//
//  A focused version of the "Add to today" sheet, scoped to one agenda
//  section. Reached from the small "+" in a band header (Morning /
//  Afternoon / Evening / Anytime). Picking an existing task pins it to
//  the day and drops it at the end of that section's order — soft
//  placement for the timed bands, off-the-clock for Anytime. The sheet
//  stays open so several can be queued, each landing with a light haptic
//  and a soft slide-in.
//

import SwiftUI
import UIKit

struct AddToSectionSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let band: PartOfDay
    let day: Date

    @State private var search: String = ""
    /// Tasks pinned this session — kept so they animate to the "added"
    /// state and sink to the bottom rather than vanishing.
    @State private var justAdded: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    candidateSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.warmWheat)
            .navigationTitle("Add to \(band.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationContentInteraction(.scrolls)
    }

    // MARK: - Intro

    @ViewBuilder
    private var intro: some View {
        HStack(spacing: 9) {
            Image(systemName: band.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text(band == .anytime
                 ? "Pick a task to keep off the clock."
                 : "Pick a task to drop into \(band.displayName.lowercased()).")
                .font(.serifItalic(13))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
            Spacer(minLength: 0)
        }
    }

    // MARK: - Candidates

    @ViewBuilder
    private var candidateSection: some View {
        let rows = candidates
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Your tasks", opacity: 0.55)

            if store.tasks.isEmpty {
                emptyHint("No tasks yet. Add some from Today's Plan first.")
            } else {
                searchField
                if rows.isEmpty {
                    emptyHint(search.isEmpty
                        ? "Everything's already here. Nice."
                        : "No matches for \u{201C}\(search)\u{201D}.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(rows) { task in
                            candidateRow(task)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: justAdded)
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            TextField("Search tasks", text: $search)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.textPrimary.opacity(0.05)))
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.serifItalic(13))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    @ViewBuilder
    private func candidateRow(_ task: FFTask) -> some View {
        let added = isAdded(task)
        let tint = Color(hex: store.categoryColorHex(task.category))
        Button {
            pin(task)
        } label: {
            HStack(spacing: 11) {
                Circle().fill(tint).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(added ? 0.5 : 1))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(store.categoryDisplayName(task.category))
                        if task.timeWindow != nil {
                            Text("· fixed time")
                        }
                    }
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                Spacer(minLength: 8)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(added ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(added ? Theme.alertGreen.opacity(0.08) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        added ? Theme.alertGreen.opacity(0.25) : Theme.textPrimary.opacity(0.07),
                        lineWidth: 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(added)
        .accessibilityLabel(added ? "\(task.title) already added" : "Add \(task.title) to \(band.displayName)")
    }

    // MARK: - Logic

    private func isAdded(_ task: FFTask) -> Bool {
        if justAdded.contains(task.id) { return true }
        return resolvesIntoSection(task)
    }

    /// True when a task already shows in this section on the day.
    private func resolvesIntoSection(_ task: FFTask) -> Bool {
        guard task.isPinnedFor(day) else { return false }
        if let window = task.timeWindow {
            return PartOfDay.band(forMinutes: window.startMinutes) == band
        }
        return task.partOfDay == band
    }

    private func pin(_ task: FFTask) {
        guard !isAdded(task) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.pinTask(task, intoBand: band, on: day)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            _ = justAdded.insert(task.id)
        }
    }

    /// Tasks not already in this section, filtered by search. Already-
    /// added rows (this session) sink to the bottom so the list stays
    /// settled while adding several.
    private var candidates: [FFTask] {
        var rows = store.tasks.filter { !resolvesIntoSection($0) || justAdded.contains($0.id) }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            rows = rows.filter { $0.title.localizedCaseInsensitiveContains(q) }
        }
        return rows.sorted { lhs, rhs in
            let la = justAdded.contains(lhs.id)
            let ra = justAdded.contains(rhs.id)
            if la != ra { return !la }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

#Preview {
    AddToSectionSheet(band: .morning, day: Date())
        .environment(Store())
}
