//
//  MilestonesView.swift
//  FrisFocus
//
//  The season's milestones — large, one-time wins. Each carries a value
//  and a done state; marking one done credits its value to that day (and
//  the week and season totals), even when the value dwarfs the daily
//  target. Tapping the circle toggles done; tapping the row edits; swipe
//  deletes.
//

import SwiftUI
import UIKit

struct MilestonesView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Milestone?
    @State private var showForm: Bool = false

    private var milestones: [Milestone] {
        store.currentSeason.milestones.sorted { $0.weekNumber < $1.weekNumber }
    }

    private var earnedTotal: Int {
        milestones.filter { $0.isCompleted }.map(\.pointValue).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                if milestones.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(milestones) { milestone in
                                MilestoneRow(milestone: milestone)
                                    .listRowBackground(Color.white)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editing = milestone
                                        showForm = true
                                    }
                            }
                            .onDelete(perform: delete)
                        } header: {
                            Text(earnedTotal > 0 ? "+\(earnedTotal) pts earned this season" : "Map the big wins of your season")
                        }
                    }
                    .scrollContentBackground(.hidden)
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
                        editing = nil
                        showForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(Theme.alertGreen)
                }
            }
            .sheet(isPresented: $showForm) {
                MilestoneFormView(editing: editing)
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
                .padding(.horizontal, 40)
            Button {
                editing = nil
                showForm = true
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
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            store.deleteMilestone(milestones[index])
        }
    }
}

// MARK: - Row

private struct MilestoneRow: View {
    @Environment(Store.self) private var store
    let milestone: Milestone

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .stroke(milestone.isCompleted ? Theme.alertGreen : Theme.textPrimary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if milestone.isCompleted {
                        Circle().fill(Theme.alertGreen).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.warmWheat)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title.isEmpty ? "Untitled milestone" : milestone.title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(milestone.isCompleted ? 0.5 : 1.0))
                    .strikethrough(milestone.isCompleted, color: Theme.textPrimary.opacity(0.5))
                Text("Week \(milestone.weekNumber)")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 8)

            Text("\(milestone.pointValue)")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(milestone.isCompleted ? Theme.alertGreen : Theme.textPrimary.opacity(0.85))
        }
        .padding(.vertical, 4)
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if milestone.isCompleted {
            store.uncompleteMilestone(milestone)
        } else {
            store.completeMilestone(milestone)
        }
    }
}

// MARK: - Add / edit form

private struct MilestoneFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: Milestone?

    @State private var title: String
    @State private var weekNumber: Int
    @State private var pointValue: Int

    init(editing: Milestone?) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _weekNumber = State(initialValue: editing?.weekNumber ?? 1)
        _pointValue = State(initialValue: editing?.pointValue ?? 50)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Master the EP", text: $title, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...3)
                } header: {
                    Text("Milestone")
                }

                Section {
                    Stepper(value: $weekNumber, in: 1...52) {
                        HStack {
                            Text("Target week")
                            Spacer()
                            Text("Week \(weekNumber)").font(.serif(16, weight: .medium))
                        }
                    }
                } header: {
                    Text("When")
                }

                Section {
                    Stepper(value: $pointValue, in: 5...500, step: 5) {
                        HStack {
                            Text("Worth")
                            Spacer()
                            Text("\(pointValue) pts").font(.serif(17, weight: .medium)).foregroundStyle(Theme.alertGreen)
                        }
                    }
                } header: {
                    Text("Reward")
                } footer: {
                    Text("A deliberately large, one-time reward — credited to the day you reach it. It can push that day well past your daily target.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(editing == nil ? "New Milestone" : "Edit Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let editing {
            var updated = editing
            updated.title = title
            updated.weekNumber = weekNumber
            updated.pointValue = pointValue
            store.updateMilestone(updated)
        } else {
            store.addMilestone(title: title, weekNumber: weekNumber, pointValue: pointValue)
        }
        dismiss()
    }
}

#Preview {
    MilestonesView()
        .environment(Store())
}
