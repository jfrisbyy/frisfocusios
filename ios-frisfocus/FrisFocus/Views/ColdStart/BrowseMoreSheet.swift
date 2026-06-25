//
//  BrowseMoreSheet.swift
//  FrisFocus
//
//  The Tier-2 bench for the current direction — the only deep surface,
//  and entirely opt-in. Grouped by life-area; tap + to pull any task
//  into the working list. Pure local retrieval, no network.
//

import SwiftUI

struct BrowseMoreSheet: View {
    @Bindable var viewModel: ColdStartViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                    ForEach(grouped, id: \.area) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: group.area.symbol)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(group.area.tint)
                                Text(group.area.displayName)
                                    .font(.sans(13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            ForEach(group.tasks) { task in
                                benchRow(task)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.paperCream)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Browse more")
                        .font(.serif(22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tap + to add to \(viewModel.current?.title ?? "your list").")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func benchRow(_ task: StarterTask) -> some View {
        let added = viewModel.benchAdded(task)
        return Button {
            guard !added else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                viewModel.pullFromBench(task)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.label)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if !task.blurb.isEmpty {
                        Text(task.blurb)
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(added ? Theme.alertGreen : task.lifeArea.tint)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.warmWheat.opacity(added ? 0.6 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    private struct Group {
        let area: LibraryLifeArea
        let tasks: [StarterTask]
    }

    private var grouped: [Group] {
        guard let areaId = viewModel.current?.id else { return [] }
        // Custom directions have ids prefixed "custom-"; fall back to the
        // general bench in that case.
        let benchAreaId = viewModel.current?.area?.id ?? "calm"
        let bench = StarterLibrary.tier2(for: areaId == benchAreaId ? areaId : benchAreaId)
        var byArea: [LibraryLifeArea: [StarterTask]] = [:]
        for task in bench {
            byArea[task.lifeArea, default: []].append(task)
        }
        return LibraryLifeArea.allCases.compactMap { area in
            guard let tasks = byArea[area], !tasks.isEmpty else { return nil }
            return Group(area: area, tasks: tasks)
        }
    }
}
