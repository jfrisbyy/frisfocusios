//
//  ShapeYourWeekView.swift
//  FrisFocus
//
//  Screen 4 — where the week gets its shape.
//
//  The setup conversation is barred from asking when anything happens,
//  and rightly: someone who doesn't yet know what their season IS can't
//  say when it sits, and fifty-eight timing questions would blow a
//  budget already at twenty turns. The prompt hands scheduling to "the
//  app's scheduling layer after creation" — and until now nothing
//  picked that up, so a finished season arrived with no day shape and
//  the commit had to guess. It guessed empty, then it guessed
//  everything, and both were wrong in the same way.
//
//  This screen is the handoff. Almost nothing on it is a question:
//  frequency is read straight out of the rubric (a booster reading
//  "three gym days" IS three days a week) and shown as an answer to
//  correct, not a blank to fill. The one genuine question is what sits
//  at a fixed time, because that is the only part of a day the season
//  has no way to know — and it is exactly the part that makes an agenda
//  worth opening.
//
//  Skippable at every point. The derived week is a real week.
//

import SwiftUI
import UIKit

struct ShapeYourWeekView: View {
    @Bindable var viewModel: SeasonSetupViewModel

    @State private var editingTask: DraftTask?
    @State private var editingBlock: DraftBucket?
    @State private var showAllTasks: Bool = false

    private var draft: RubricDraft { viewModel.draftBinding }

    /// Calendar weekday indices in display order, starting on the
    /// locale's first day rather than always on Sunday.
    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.warmWheat.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    weekStrip.padding(.top, 20)
                    fixedSection.padding(.top, 30)
                    cadenceSection.padding(.top, 30)
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 20)
            }

            cta
        }
        .sheet(item: $editingTask) { task in
            SetupTaskShapeSheet(task: task) { updated in
                viewModel.updateDraft { d in
                    if let index = d.tasks.firstIndex(where: { $0.id == updated.id }) {
                        d.tasks[index] = updated
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingBlock) { block in
            SetupBlockEditSheet(
                block: block,
                categories: draft.categories,
                onSave: { updated in
                    viewModel.updateDraft { d in
                        if let index = d.buckets.firstIndex(where: { $0.id == updated.id }) {
                            d.buckets[index] = updated
                        } else {
                            d.buckets.append(updated)
                        }
                    }
                },
                onRemove: { removed in
                    viewModel.updateDraft { d in
                        d.buckets.removeAll { $0.id == removed.id }
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.backToReviewFromShape()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                .buttonStyle(.plain)
                EyebrowText(text: "Your week", opacity: 0.45)
                Spacer()
            }
            .padding(.top, 14)

            Text("How the week runs")
                .font(.serif(28, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            // Says plainly that this is read, not asked. The whole
            // screen depends on it not reading as another questionnaire.
            Text("I've read this off your season — three gym days means three days a week. Change anything that's wrong, or leave it and start.")
                .font(.sans(13.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "A typical week", opacity: 0.45)
            HStack(spacing: 6) {
                ForEach(weekdayOrder, id: \.self) { weekday in
                    dayChip(weekday)
                }
            }
        }
    }

    private func dayChip(_ weekday: Int) -> some View {
        let load = draft.load(onWeekday: weekday)
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let letter = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
        return VStack(spacing: 5) {
            Text(letter)
                .font(.sans(10.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text("\(load)")
                .font(.serif(16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - What's fixed

    private var fixedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText(text: "What sits at a set time", opacity: 0.5)
            Text("Work, a class, a standing commitment. This is the one thing your season can't work out on its own — and it's what makes a day worth looking at.")
                .font(.sans(12.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(draft.buckets) { block in
                blockRow(block)
            }

            // Long tasks are offered, never assumed. Only the person
            // knows whether their three-hour thing is a shift they must
            // attend or a Saturday they chose.
            ForEach(unpromotedCandidates) { candidate in
                candidateRow(candidate)
            }

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                editingBlock = DraftBucket(
                    title: "",
                    categoryId: draft.categories.first?.id ?? UUID()
                )
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add a block")
                        .font(.sans(13.5, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(draft.categories.isEmpty)
        }
    }

    /// Long tasks that haven't already been turned into a block.
    private var unpromotedCandidates: [DraftTask] {
        let taken = Set(draft.buckets.map { $0.title.lowercased() })
        return draft.blockCandidates.filter { !taken.contains($0.name.lowercased()) }
    }

    private func blockRow(_ block: DraftBucket) -> some View {
        Button {
            editingBlock = block
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.sunShadow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title.isEmpty ? "Untitled block" : block.title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text([block.timeText ?? block.partOfDay.displayName,
                          block.isEveryDay ? "every day" : "\(block.days.count) days"]
                            .joined(separator: " · "))
                        .font(.sans(11.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                Spacer()
                Text("+\(block.value)")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func candidateRow(_ task: DraftTask) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            editingBlock = DraftBucket(
                title: task.name,
                categoryId: task.categoryId,
                value: task.headlineValue,
                startMinutes: 9 * 60,
                endMinutes: 17 * 60,
                partOfDay: .morning,
                days: task.days
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.dashed")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    Text("\(task.estimatedMinutes ?? 0) min — does this sit at a time?")
                        .font(.sans(11.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                Spacer()
            }
            .padding(12)
            .background(Color.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - How often

    /// Tasks grouped by how often they run, most frequent first. Every
    /// day comes first because it is the biggest group and the one most
    /// worth scanning for something that shouldn't be there.
    private var cadenceGroups: [(label: String, tasks: [DraftTask])] {
        let sorted = draft.tasks.sorted { lhs, rhs in
            let l = lhs.isEveryDay ? 8 : lhs.days.count
            let r = rhs.isEveryDay ? 8 : rhs.days.count
            if l != r { return l > r }
            return lhs.headlineValue > rhs.headlineValue
        }
        return Dictionary(grouping: sorted, by: \.cadenceText)
            .sorted { lhs, rhs in
                let l = lhs.value.first.map { $0.isEveryDay ? 8 : $0.days.count } ?? 0
                let r = rhs.value.first.map { $0.isEveryDay ? 8 : $0.days.count } ?? 0
                return l > r
            }
            .map { (label: $0.key, tasks: $0.value) }
    }

    private var visibleGroups: [(label: String, tasks: [DraftTask])] {
        guard !showAllTasks else { return cadenceGroups }
        // A dense season has fifty-eight rows. Show the shape, not the
        // whole list, until someone asks for it.
        return cadenceGroups.map { group in
            (label: group.label, tasks: Array(group.tasks.prefix(4)))
        }
    }

    private var hiddenCount: Int {
        cadenceGroups.reduce(0) { $0 + max(0, $1.tasks.count - 4) }
    }

    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EyebrowText(text: "How often", opacity: 0.5)

            ForEach(visibleGroups, id: \.label) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(group.label)
                            .font(.sans(11.5, weight: .semibold))
                            .foregroundStyle(Theme.sunShadow)
                        Spacer()
                        Text("\(cadenceGroups.first { $0.label == group.label }?.tasks.count ?? 0)")
                            .font(.sans(11.5, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.35))
                    }
                    ForEach(group.tasks) { task in
                        taskRow(task)
                    }
                }
            }

            if hiddenCount > 0 && !showAllTasks {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAllTasks = true }
                } label: {
                    Text("Show all \(draft.tasks.count)")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func taskRow(_ task: DraftTask) -> some View {
        Button {
            editingTask = task
        } label: {
            HStack(spacing: 9) {
                Text(task.name)
                    .font(.sans(13.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if task.partOfDay != .anytime {
                    Text(task.partOfDay.displayName.lowercased())
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.25))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var cta: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.advanceToNaming()
        } label: {
            Text("Name your season →")
                .font(.sans(16, weight: .medium))
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.textPrimary.opacity(0.92))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Theme.warmWheat.opacity(0), Theme.warmWheat],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - One task's day shape

/// How often a task runs and where in the day it sits. Two controls,
/// because those are the only two questions the agenda actually needs
/// answered before a season starts.
struct SetupTaskShapeSheet: View {
    let task: DraftTask
    let onSave: (DraftTask) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var everyDay: Bool = true
    @State private var days: Set<Int> = []
    @State private var band: PartOfDay = .anytime

    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Every day", isOn: $everyDay)
                    if !everyDay {
                        WeekdayPicker(selection: $days, order: weekdayOrder)
                    }
                } header: {
                    Text("How often")
                } footer: {
                    Text(everyDay
                         ? "On the board every day. A day you don't get to it simply frees room for something else."
                         : "On the board only on the days you pick.")
                }

                Section {
                    Picker("When", selection: $band) {
                        ForEach(PartOfDay.allCases) { part in
                            Text(part.displayName).tag(part)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Where in the day")
                } footer: {
                    Text("Anytime is the tray — available all day without pretending to know when. Pick a band only when you actually know.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(task.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = task
                        // An empty set IS the every-day sentinel, so a
                        // "some days" choice with nothing ticked would
                        // silently mean the opposite of what it says.
                        updated.days = (everyDay || days.isEmpty) ? [] : days
                        updated.partOfDay = band
                        onSave(updated)
                        dismiss()
                    }
                    .font(.sans(15, weight: .medium))
                }
            }
        }
        .onAppear {
            everyDay = task.isEveryDay
            days = task.days.isEmpty ? Set(weekdayOrder) : task.days
            band = task.partOfDay
        }
    }
}

// MARK: - One block of committed time

struct SetupBlockEditSheet: View {
    let block: DraftBucket
    let categories: [DraftCategory]
    let onSave: (DraftBucket) -> Void
    let onRemove: (DraftBucket) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var categoryId: UUID = UUID()
    @State private var value: Int = 5
    @State private var hasClock: Bool = true
    @State private var start: Date = Date()
    @State private var end: Date = Date()
    @State private var band: PartOfDay = .morning
    @State private var everyDay: Bool = false
    @State private var days: Set<Int> = []

    private var isNew: Bool { block.title.isEmpty }

    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it?", text: $title)
                        .font(.sans(16, weight: .regular))
                    Picker("Area", selection: $categoryId) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    Stepper(value: $value, in: 1...20) {
                        HStack {
                            Text("Worth")
                            Spacer()
                            Text("\(value)")
                                .font(.serif(16, weight: .medium))
                        }
                    }
                } footer: {
                    Text("Showing up to the block is the scored thing. What you do inside it is recorded, not scored again.")
                }

                Section {
                    Toggle("It has a set time", isOn: $hasClock)
                    if hasClock {
                        DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    } else {
                        Picker("Roughly when", selection: $band) {
                            ForEach(PartOfDay.bands) { part in
                                Text(part.displayName).tag(part)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("When")
                }

                Section {
                    Toggle("Every day", isOn: $everyDay)
                    if !everyDay {
                        WeekdayPicker(selection: $days, order: weekdayOrder)
                    }
                } header: {
                    Text("Which days")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onRemove(block)
                            dismiss()
                        } label: {
                            Label("Remove this block", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(isNew ? "New block" : "Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = block
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.categoryId = categoryId
                        updated.value = max(1, value)
                        let cal = Calendar.current
                        if hasClock {
                            let s = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
                            let e = cal.component(.hour, from: end) * 60 + cal.component(.minute, from: end)
                            updated.startMinutes = s
                            updated.endMinutes = max(e, s)
                        } else {
                            updated.startMinutes = nil
                            updated.endMinutes = nil
                            updated.partOfDay = band
                        }
                        updated.days = (everyDay || days.isEmpty) ? [] : days
                        onSave(updated)
                        dismiss()
                    }
                    .font(.sans(15, weight: .medium))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            title = block.title
            categoryId = categories.contains(where: { $0.id == block.categoryId })
                ? block.categoryId
                : (categories.first?.id ?? block.categoryId)
            value = block.value
            hasClock = block.startMinutes != nil
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            start = cal.date(byAdding: .minute, value: block.startMinutes ?? 9 * 60, to: today) ?? today
            end = cal.date(byAdding: .minute, value: block.endMinutes ?? 17 * 60, to: today) ?? today
            band = block.partOfDay == .anytime ? .morning : block.partOfDay
            everyDay = block.isEveryDay
            days = block.days.isEmpty ? Set([2, 3, 4, 5, 6]) : block.days
        }
    }
}

// MARK: - Weekday chips

/// Seven tappable letters. Shared by both sheets so "which days" looks
/// and behaves identically wherever it is asked.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    let order: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    if on { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(letter(weekday))
                        .font(.sans(12, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.textCream : Theme.textPrimary.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(on ? Theme.textPrimary.opacity(0.85) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(on ? 0 : 0.15), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func letter(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }
}
