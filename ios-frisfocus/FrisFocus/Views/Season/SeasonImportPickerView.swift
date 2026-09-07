//
//  SeasonImportPickerView.swift
//  FrisFocus
//
//  Choosing what a new season inherits.
//
//  Starting a new season used to be a one-line confirmation dialog with
//  no choices in it: the task library, boosters and negatives carried
//  whether you wanted them or not, and every milestone was dropped
//  whether you were finished with it or not. A quarter is mostly the
//  last quarter with edited values and a few things retired, so the one
//  screen this flow was missing is the one that asks.
//

import SwiftUI

struct SeasonImportPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Handed the finished plan and the chosen name. The caller owns
    /// starting the season, so this screen works the same whether it's
    /// reached from settings, the season card, or the setup flow.
    var onStart: (SeasonImportPlan, String?) -> Void

    @State private var plan = SeasonImportPlan()
    @State private var name: String = ""
    @State private var seeded = false

    private var unfinishedMilestones: [Milestone] {
        store.currentSeason.milestones.filter { !$0.isCompleted }
    }
    private var openTodos: [Todo] {
        store.todos.filter { !$0.isCompleted }
    }
    private var finishedMilestoneCount: Int {
        store.currentSeason.milestones.count - unfinishedMilestones.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Season name", text: $name)
                        .font(.sans(16, weight: .regular))
                } header: {
                    Text("Name")
                } footer: {
                    Text("You can rename it later.")
                }

                Section {
                    groupRow(
                        title: "Tasks",
                        systemImage: "checklist",
                        selected: plan.taskIds.count,
                        total: store.tasks.count
                    ) {
                        SeasonImportItemList(
                            title: "Tasks",
                            items: store.tasks.map {
                                .init(id: $0.id, title: $0.title, detail: "\($0.pointValue) pts")
                            },
                            selection: $plan.taskIds
                        )
                    }

                    if !openTodos.isEmpty {
                        groupRow(
                            title: "Open to-dos",
                            systemImage: "square.and.pencil",
                            selected: plan.todoIds.count,
                            total: openTodos.count
                        ) {
                            SeasonImportItemList(
                                title: "Open to-dos",
                                items: openTodos.map {
                                    .init(id: $0.id, title: $0.title, detail: nil)
                                },
                                selection: $plan.todoIds
                            )
                        }
                    }

                    if !store.boosters.isEmpty {
                        groupRow(
                            title: "Boosters",
                            systemImage: "bolt.fill",
                            selected: plan.boosterIds.count,
                            total: store.boosters.count
                        ) {
                            SeasonImportItemList(
                                title: "Boosters",
                                items: store.boosters.map {
                                    .init(id: $0.id, title: $0.name, detail: "+\($0.bonusPoints)")
                                },
                                selection: $plan.boosterIds
                            )
                        }
                    }

                    if !store.avoidanceItems.isEmpty {
                        groupRow(
                            title: "Negatives",
                            systemImage: "minus.circle",
                            selected: plan.avoidanceIds.count,
                            total: store.avoidanceItems.count
                        ) {
                            SeasonImportItemList(
                                title: "Negatives",
                                items: store.avoidanceItems.map {
                                    .init(id: $0.id, title: $0.name, detail: "−\($0.pointsPerOccurrence)")
                                },
                                selection: $plan.avoidanceIds
                            )
                        }
                    }

                    if !store.habitTrains.isEmpty {
                        groupRow(
                            title: "Routines",
                            systemImage: "arrow.triangle.branch",
                            selected: plan.habitTrainIds.count,
                            total: store.habitTrains.count
                        ) {
                            SeasonImportItemList(
                                title: "Routines",
                                items: store.habitTrains.map {
                                    .init(id: $0.id, title: $0.name, detail: "+\($0.bonusPoints)")
                                },
                                selection: $plan.habitTrainIds
                            )
                        }
                    }

                    if !unfinishedMilestones.isEmpty {
                        groupRow(
                            title: "Unfinished milestones",
                            systemImage: "flag",
                            selected: plan.milestoneIds.count,
                            total: unfinishedMilestones.count
                        ) {
                            SeasonImportItemList(
                                title: "Unfinished milestones",
                                items: unfinishedMilestones.map {
                                    .init(id: $0.id, title: $0.title, detail: "\($0.pointValue) pts")
                                },
                                selection: $plan.milestoneIds
                            )
                        }
                    }
                } header: {
                    Text("Bring forward")
                } footer: {
                    Text(carryFooter)
                }

                Section {
                    Toggle("Categories and colors", isOn: $plan.categories)
                    Toggle("Daily and weekly targets", isOn: $plan.goals)
                    Toggle("Weekly schedule and times", isOn: $plan.schedule)
                } header: {
                    Text("Setup")
                } footer: {
                    Text("With the schedule off, your tasks arrive unscheduled so you can rebuild the week from a clean slate.")
                }

                Section {
                    Button {
                        onStart(plan, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name)
                        dismiss()
                    } label: {
                        Text("Start this season")
                            .font(.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.alertGreen)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("New season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
            .task {
                // Seed once. Re-seeding on every appearance would throw
                // away the choices someone made before stepping into a
                // sub-list and coming back.
                guard !seeded else { return }
                seeded = true
                plan = .everything(from: store)
            }
        }
    }

    private var carryFooter: String {
        let kept = store.currentSeason.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let seasonName = kept.isEmpty ? "your last season" : kept
        var text = "Everything you leave behind stays with \(seasonName) in your past seasons — it isn't erased."
        if finishedMilestoneCount > 0 {
            let noun = finishedMilestoneCount == 1 ? "milestone" : "milestones"
            text += " Your \(finishedMilestoneCount) finished \(noun) stay there too, where you earned them."
        }
        return text
    }

    @ViewBuilder
    private func groupRow<Destination: View>(
        title: String,
        systemImage: String,
        selected: Int,
        total: Int,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.sans(15, weight: .medium))
                Spacer()
                Text(selected == total ? "All \(total)" : "\(selected) of \(total)")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(selected == 0 ? Theme.textTertiary : Theme.textSecondary)
            }
        }
        .accessibilityHint("\(selected) of \(total) selected. Double-tap to choose.")
    }
}

// MARK: - Per-item picker

/// One flat, selectable list. Deliberately the same shape for tasks,
/// boosters, negatives, routines and milestones — the person is doing
/// the same thing each time and shouldn't have to learn five screens.
private struct SeasonImportItemList: View {
    struct Item: Identifiable {
        let id: UUID
        let title: String
        let detail: String?
    }

    let title: String
    let items: [Item]
    @Binding var selection: Set<UUID>

    var body: some View {
        List {
            Section {
                Button(selection.count == items.count ? "Deselect all" : "Select all") {
                    if selection.count == items.count {
                        selection.subtract(items.map(\.id))
                    } else {
                        selection.formUnion(items.map(\.id))
                    }
                }
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            }

            Section {
                ForEach(items) { item in
                    Button {
                        if selection.contains(item.id) {
                            selection.remove(item.id)
                        } else {
                            selection.insert(item.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(item.id) ? Theme.alertGreen : Theme.textTertiary)
                            Text(item.title)
                                .font(.sans(15, weight: .regular))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.sans(13, weight: .regular))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(item.id) ? [.isSelected] : [])
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.warmWheat)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
