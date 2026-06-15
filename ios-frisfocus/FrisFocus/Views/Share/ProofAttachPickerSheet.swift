//
//  ProofAttachPickerSheet.swift
//  FrisFocus
//
//  The destination picker for a composed proof card — now a MULTI-SELECT
//  checklist instead of a one-tap pick. Tick the camera roll plus any
//  number of tasks, to-dos, notes, and milestones, then hit one Save to
//  attach the proof to all of them at once.
//
//  Anything the proof is already pinned to (e.g. a task whose sticker
//  was added to the card) arrives pre-ticked and locked, so the user can
//  see where it already lives and add more without losing those. A
//  search field opens the full task / to-do library, not just today's
//  plan, so a proof can document any task in the season.
//

import SwiftUI
import UIKit

struct ProofAttachPickerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Offered first — the capture's own milestone when there is one.
    var suggestedMilestoneId: UUID? = nil
    /// Targets the proof is already pinned to (sticker auto-pins). These
    /// arrive ticked and can't be unticked — the picker only adds more.
    var alreadyAttached: Set<ProofAttachTarget> = []
    /// Hands back every ticked destination. The caller writes only the
    /// newly-added ones (selection minus `alreadyAttached`).
    let onSave: (Set<ProofAttachTarget>) -> Void

    @State private var search: String = ""
    @State private var selected: Set<ProofAttachTarget> = []
    @State private var didSeed: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Data

    private var orderedMilestones: [Milestone] {
        let base = store.attachableMilestones
        guard let suggestedMilestoneId,
              let suggested = base.first(where: { $0.id == suggestedMilestoneId })
        else { return base }
        return [suggested] + base.filter { $0.id != suggestedMilestoneId }
    }

    private var filteredNotes: [Note] {
        let all = store.attachableNotes
        guard !trimmedSearch.isEmpty else { return Array(all.prefix(8)) }
        return all.filter { note in
            let haystacks = [note.body, note.label].compactMap { $0 }
            return haystacks.contains { $0.localizedStandardContains(trimmedSearch) }
        }
    }

    private var planTasks: [FFTask] { store.planTasksToday }
    private var planTodos: [Todo] { store.dueTodosToday }

    /// Every task NOT already on today's plan — surfaced so a proof can
    /// document any task in the season, not just the scheduled ones.
    private var otherTasks: [FFTask] {
        let planIds = Set(planTasks.map(\.id))
        let library = store.tasks.filter { !planIds.contains($0.id) }
        guard !trimmedSearch.isEmpty else { return library }
        return library.filter { $0.title.localizedStandardContains(trimmedSearch) }
    }

    private var searchedPlanTasks: [FFTask] {
        guard !trimmedSearch.isEmpty else { return planTasks }
        return planTasks.filter { $0.title.localizedStandardContains(trimmedSearch) }
    }

    private var searchedPlanTodos: [Todo] {
        guard !trimmedSearch.isEmpty else { return planTodos }
        return planTodos.filter { $0.title.localizedStandardContains(trimmedSearch) }
    }

    private var newCount: Int { selected.subtracting(alreadyAttached).count }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.paperCream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    cameraRollRow

                    if !orderedMilestones.isEmpty {
                        sectionLabel("MILESTONES")
                        VStack(spacing: 6) {
                            ForEach(orderedMilestones) { milestone in
                                milestoneRow(milestone)
                            }
                        }
                    }

                    sectionLabel("TASKS")
                    searchField

                    if searchedPlanTasks.isEmpty && searchedPlanTodos.isEmpty && otherTasks.isEmpty {
                        emptyHint(trimmedSearch.isEmpty
                                  ? "No tasks yet."
                                  : "No tasks match \u{201C}\(search)\u{201D}.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(searchedPlanTasks) { task in
                                taskRow(task, onPlan: true)
                            }
                            ForEach(searchedPlanTodos) { todo in
                                todoRow(todo)
                            }
                            ForEach(otherTasks) { task in
                                taskRow(task, onPlan: false)
                            }
                        }
                    }

                    sectionLabel("NOTES")
                    if filteredNotes.isEmpty {
                        emptyHint(trimmedSearch.isEmpty
                                  ? "No notes yet — write one from the journal first."
                                  : "No notes match \u{201C}\(search)\u{201D}.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(filteredNotes) { note in
                                noteRow(note)
                            }
                        }
                    }

                    Spacer(minLength: 96)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 20)
            }
            .scrollDismissesKeyboard(.immediately)

            saveBar
        }
        .onAppear {
            guard !didSeed else { return }
            selected = alreadyAttached
            didSeed = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keep this proof")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Tick everywhere it should land — the camera roll, any tasks, notes, or milestones — then save once.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.serifItalic(13, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
            .padding(.top, 2)
    }

    // MARK: - Generic toggle row

    private func toggleRow(
        target: ProofAttachTarget,
        title: String,
        subtitle: String,
        accent: Color,
        @ViewBuilder leading: () -> some View,
        trailingBadge: String? = nil
    ) -> some View {
        let isLocked = alreadyAttached.contains(target)
        let isOn = selected.contains(target)
        return Button {
            guard !isLocked else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            if isOn { selected.remove(target) } else { selected.insert(target) }
        } label: {
            HStack(spacing: 12) {
                leading()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(isLocked ? "Already pinned" : subtitle)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(isLocked ? accent.opacity(0.9) : Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let trailingBadge {
                    Text(trailingBadge)
                        .font(.sans(8.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.sunShadow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.sunWarm.opacity(0.22)))
                }

                checkIndicator(on: isOn, locked: isLocked, accent: accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(isOn ? 0.85 : 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isOn ? accent.opacity(0.45) : Theme.textPrimary.opacity(0.08),
                        lineWidth: isOn ? 1 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "selected" : "not selected")
    }

    private func checkIndicator(on: Bool, locked: Bool, accent: Color) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.textPrimary.opacity(on ? 0 : 0.25), lineWidth: 1.5)
                .frame(width: 24, height: 24)
            if on {
                Circle().fill(locked ? accent.opacity(0.55) : accent).frame(width: 24, height: 24)
                Image(systemName: locked ? "lock.fill" : "checkmark")
                    .font(.system(size: locked ? 9 : 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
    }

    // MARK: - Rows

    private var cameraRollRow: some View {
        toggleRow(
            target: .cameraRoll,
            title: "Camera roll",
            subtitle: "Save the card to your photo library",
            accent: Theme.sunShadow,
            leading: {
                ZStack {
                    Circle().fill(Theme.textPrimary.opacity(0.08))
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                }
            }
        )
    }

    private func taskRow(_ task: FFTask, onPlan: Bool) -> some View {
        toggleRow(
            target: .task(task.id),
            title: task.title,
            subtitle: onPlan
                ? "Pin to today's task"
                : "Pin to \(store.categoryDisplayName(task.category))",
            accent: Theme.alertGreen,
            leading: {
                ZStack {
                    SwiftUI.Circle()
                        .stroke(Theme.alertGreen.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if store.hasLogEntryToday(forTaskId: task.id) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.alertGreen)
                    }
                }
            }
        )
    }

    private func todoRow(_ todo: Todo) -> some View {
        toggleRow(
            target: .todo(todo.id),
            title: todo.title,
            subtitle: "Pin to today's to-do",
            accent: Theme.alertGreen,
            leading: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.alertGreen.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if todo.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.alertGreen)
                    }
                }
            }
        )
    }

    private func milestoneRow(_ milestone: Milestone) -> some View {
        toggleRow(
            target: .milestone(milestone.id),
            title: milestone.title.isEmpty ? "Untitled milestone" : milestone.title,
            subtitle: milestoneSubtitle(milestone),
            accent: Theme.sunShadow,
            leading: {
                ZStack {
                    Circle()
                        .fill((milestone.isCompleted ? Theme.alertGreen : Theme.sunWarm).opacity(0.16))
                    Image(systemName: milestone.isCompleted ? "flag.checkered" : "flag")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(milestone.isCompleted ? Theme.alertGreen : Theme.sunShadow)
                }
            },
            trailingBadge: milestone.id == suggestedMilestoneId ? "THIS ONE" : nil
        )
    }

    private static let milestoneTargetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func milestoneSubtitle(_ milestone: Milestone) -> String {
        if milestone.isCompleted { return "Landed · the journey keeps growing" }
        let lead = milestone.targetDate.map { "By \(Self.milestoneTargetFormatter.string(from: $0))" } ?? "In motion"
        let done = milestone.steps.filter(\.isCompleted).count
        if milestone.steps.isEmpty { return lead }
        return "\(lead) · \(done) of \(milestone.steps.count) steps"
    }

    private func noteRow(_ note: Note) -> some View {
        toggleRow(
            target: .note(note.id),
            title: noteTitle(note),
            subtitle: Self.dateFormatter.string(from: note.createdAt),
            accent: Theme.sunShadow,
            leading: {
                ZStack {
                    Circle().fill(Theme.textPrimary.opacity(0.06))
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
        )
    }

    private func noteTitle(_ note: Note) -> String {
        if let label = note.label, !label.isEmpty { return label }
        if let body = note.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }
        if !note.voiceMemos.isEmpty { return "Voice memo" }
        if !note.photos.isEmpty { return "Media note" }
        return "Untitled note"
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            TextField("Search any task or note…", text: $search)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSave(selected)
            } label: {
                Text(saveLabel)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(newCount > 0 ? Color(hex: 0x2C2C2A) : Theme.textPrimary.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule().fill(newCount > 0 ? Theme.sunWarm : Theme.textPrimary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .disabled(newCount == 0)
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Theme.paperCream.opacity(0), Theme.paperCream],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var saveLabel: String {
        switch newCount {
        case 0: return "Pick where to keep it"
        case 1: return "Save to 1 place"
        default: return "Save to \(newCount) places"
        }
    }
}
