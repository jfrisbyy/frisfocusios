//
//  RubricReviewView.swift
//  FrisFocus
//
//  Screen 3 — the whole picture in one view, fully editable. Both
//  targets live HERE, next to the tasks that produce them. Renders all
//  six element types: daily tasks (all three scoring shapes), negatives
//  (all three shapes incl. the honest frequency counter), end-of-week
//  boosters, end-of-week floors, and season milestones. Advanced
//  sections collapse so a 5-item rubric looks calm and a 40-item one
//  stays manageable.
//

import SwiftUI
import UIKit

struct RubricReviewView: View {
    @Bindable var viewModel: SeasonSetupViewModel

    @State private var editingTask: DraftTask?
    @State private var editingNegative: DraftNegative?
    @State private var editingBooster: DraftBooster?
    @State private var editingPenalty: DraftWeeklyPenalty?
    @State private var editingMilestone: DraftMilestone?

    @State private var collapsedCategories: Set<UUID> = []
    @State private var showBoosters: Bool = true
    // These were collapsed by default, so a first-time user never saw
    // the weekly deduction or the destinations they had just agreed to
    // out loud — the two parts of the season most likely to surprise
    // them later were the two parts hidden on the only screen that
    // shows the whole thing.
    @State private var showPenalties: Bool = true
    @State private var showMilestones: Bool = true

    private var draft: RubricDraft { viewModel.draftBinding }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.warmWheat.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    targetsBlock
                        .padding(.top, 14)

                    calibrationBanner
                        .padding(.top, 10)

                    // Daily tasks by category — expanded by default.
                    ForEach(draft.categories) { category in
                        categorySection(category)
                            .padding(.top, 18)
                    }

                    negativesSection
                        .padding(.top, 24)

                    boostersSection
                        .padding(.top, 22)

                    penaltiesSection
                        .padding(.top, 14)

                    milestonesSection
                        .padding(.top, 14)

                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 20)
            }

            cta
        }
        .sheet(item: $editingTask) { task in
            SetupTaskEditSheet(
                task: task,
                categories: draft.categories,
                onSave: { updated in
                    viewModel.updateDraft { d in
                        if let idx = d.tasks.firstIndex(where: { $0.id == updated.id }) {
                            d.tasks[idx] = updated
                        } else {
                            d.tasks.append(updated)
                        }
                    }
                },
                onRemove: { removed in
                    viewModel.updateDraft { d in
                        d.tasks.removeAll { $0.id == removed.id }
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $editingNegative) { negative in
            SetupNegativeEditSheet(
                negative: negative,
                onSave: { updated in
                    viewModel.updateDraft { d in
                        if let idx = d.negatives.firstIndex(where: { $0.id == updated.id }) {
                            d.negatives[idx] = updated
                        } else {
                            d.negatives.append(updated)
                        }
                    }
                },
                onRemove: { removed in
                    viewModel.updateDraft { d in
                        d.negatives.removeAll { $0.id == removed.id }
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingBooster) { booster in
            SetupRuleEditSheet(
                title: "End-of-week booster",
                helper: "Hit the threshold inside the week and the bonus lands — a missed day never resets anything.",
                name: booster.name,
                reference: booster.referenceName,
                threshold: booster.threshold,
                metric: booster.metric,
                value: booster.value,
                valueLabel: "Bonus points",
                taskNames: draft.tasks.map(\.name),
                onSave: { name, reference, threshold, value in
                    viewModel.updateDraft { d in
                        // Carry the metric through. The sheet edits name,
                        // reference, threshold and value; rebuilding the
                        // whole value without it would silently turn a
                        // weekly TOTAL back into a day count.
                        let rebuilt = DraftBooster(
                            id: booster.id, name: name, referenceName: reference,
                            metric: booster.metric, threshold: threshold, value: value,
                            isManual: booster.isManual
                        )
                        if let idx = d.boosters.firstIndex(where: { $0.id == booster.id }) {
                            d.boosters[idx] = rebuilt
                        } else {
                            d.boosters.append(rebuilt)
                        }
                    }
                },
                onRemove: {
                    viewModel.updateDraft { d in
                        d.boosters.removeAll { $0.id == booster.id }
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingPenalty) { penalty in
            SetupRuleEditSheet(
                title: "End-of-week floor",
                helper: "If the referenced task happens fewer times than the floor, the deduction lands once for the week.",
                name: penalty.name,
                reference: penalty.referenceName,
                threshold: penalty.threshold,
                metric: penalty.metric,
                value: penalty.value,
                valueLabel: "Deduction",
                taskNames: draft.tasks.map(\.name),
                onSave: { name, reference, threshold, value in
                    viewModel.updateDraft { d in
                        let rebuilt = DraftWeeklyPenalty(
                            id: penalty.id, name: name, referenceName: reference,
                            metric: penalty.metric, threshold: threshold, value: value
                        )
                        if let idx = d.weeklyPenalties.firstIndex(where: { $0.id == penalty.id }) {
                            d.weeklyPenalties[idx] = rebuilt
                        } else {
                            d.weeklyPenalties.append(rebuilt)
                        }
                    }
                },
                onRemove: {
                    viewModel.updateDraft { d in
                        d.weeklyPenalties.removeAll { $0.id == penalty.id }
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingMilestone) { milestone in
            SetupMilestoneEditSheet(
                milestone: milestone,
                onSave: { updated in
                    viewModel.updateDraft { d in
                        if let idx = d.milestones.firstIndex(where: { $0.id == updated.id }) {
                            d.milestones[idx] = updated
                        } else {
                            d.milestones.append(updated)
                        }
                    }
                },
                onRemove: { removed in
                    viewModel.updateDraft { d in
                        d.milestones.removeAll { $0.id == removed.id }
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.usedStarter {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.returnToGuidedSetup()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back to guided setup")
                            .font(.sans(12.5, weight: .medium))
                    }
                    .foregroundStyle(Theme.sunShadow)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
            }
            EyebrowText(text: viewModel.usedStarter ? "A simple starting board" : "Built from our conversation", opacity: 0.45)
            Text("Your season")
                .font(.serif(30, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, 14)
    }

    // MARK: - Targets

    private var targetsBlock: some View {
        HStack(spacing: 10) {
            targetCard(
                label: "DAILY",
                value: draft.dailyTarget,
                step: 1
            ) { newValue in
                viewModel.updateDraft { $0.dailyTarget = max(1, newValue) }
            }
            targetCard(
                label: "WEEKLY",
                value: draft.weeklyTarget,
                step: 5
            ) { newValue in
                viewModel.updateDraft { $0.weeklyTarget = max(1, newValue) }
            }
        }
    }

    private func targetCard(label: String, value: Int, step: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowText(text: label, opacity: 0.45)
            HStack {
                Text("\(value)")
                    .font(.serif(28, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.easeOut(duration: 0.25), value: value)
                Spacer()
                HStack(spacing: 0) {
                    stepButton("minus") { onChange(value - step) }
                    stepButton("plus") { onChange(value + step) }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var calibrationBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.sunShadow)
                .padding(.top, 2)
            Text("A strong day lands near \(draft.dailyTarget) — not everything, just a good day.")
                .font(.sans(12.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.sunWarm.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Category sections (daily tasks)

    private func categorySection(_ category: DraftCategory) -> some View {
        let tasks = draft.tasks(in: category)
        let tint = Color(hex: category.colorHex)
        let collapsed = collapsedCategories.contains(category.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if collapsed {
                        collapsedCategories.remove(category.id)
                    } else {
                        collapsedCategories.insert(category.id)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.8))
                    Text(category.name.uppercased())
                        .font(.sans(10.5, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(tint)
                    Spacer()
                    Text("\(tasks.count)")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(spacing: 6) {
                    ForEach(tasks) { task in
                        taskRow(task, tint: tint)
                    }

                    Button {
                        var newTask = DraftTask(name: "", categoryId: category.id)
                        newTask.value = 3
                        editingTask = newTask
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                            Text("Add task")
                                .font(.sans(12.5, weight: .regular))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.14), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func taskRow(_ task: DraftTask, tint: Color) -> some View {
        Button {
            editingTask = task
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)

                Text(task.name)
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if let summary = task.shapeSummary {
                    Text(summary)
                        .font(.sans(10.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.42))
                        .lineLimit(1)
                }

                Spacer()

                Text("\(task.headlineValue)")
                    .font(.serif(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Negatives

    private var negativesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("AVOID · PULLS FROM YOUR DAY")
                    .font(.sans(10.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.alertRed.opacity(0.85))
                Spacer()
                Button {
                    editingNegative = DraftNegative(name: "")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.alertRed.opacity(0.6))
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                if draft.negatives.isEmpty {
                    Text("Nothing pulls from your day — add one if something should.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                ForEach(draft.negatives) { negative in
                    negativeRow(negative)
                }
            }
            .padding(11)
            .background(Theme.alertRed.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.alertRed.opacity(0.22), lineWidth: 0.6)
            )
        }
    }

    @ViewBuilder
    private func negativeRow(_ negative: DraftNegative) -> some View {
        Button {
            editingNegative = negative
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(negative.name)
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(negative.shape == .perInstance ? "each time · −\(negative.value)" : "−\(negative.value) past \(negative.freeCount)")
                        .font(.sans(11.5, weight: .medium))
                        .foregroundStyle(Theme.alertRed.opacity(0.85))
                }

                // The honest counter — a neutral progress display, never
                // a shame meter. At review time the season hasn't started,
                // so it reads "still free · 0 of N".
                if negative.shape == .frequencyThreshold {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("This \(negative.window.displayName) — still free · 0 of \(negative.freeCount)")
                                .font(.sans(10.5, weight: .regular))
                                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            Spacer()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.textPrimary.opacity(0.08))
                                Capsule()
                                    .fill(Theme.sunShadow.opacity(0.5))
                                    .frame(width: 3)
                            }
                            .frame(width: geo.size.width)
                        }
                        .frame(height: 4)
                        Text("−\(negative.value) each time past \(negative.freeCount) · you see it coming.")
                            .font(.sans(10, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.42))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Boosters / floors / milestones

    private var boostersSection: some View {
        collapsibleSection(
            title: "END-OF-WEEK BOOSTERS",
            tint: Theme.alertGreen,
            isExpanded: $showBoosters,
            count: draft.boosters.count,
            onAdd: { editingBooster = DraftBooster(name: "", referenceName: draft.tasks.first?.name ?? "") }
        ) {
            ForEach(draft.boosters) { booster in
                ruleRow(
                    name: booster.name,
                    detail: booster.isManual
                        ? "you tick it at week's end"
                        : booster.metric == .sum
                            ? "\(booster.threshold) total · \(booster.referenceName)"
                            : "\(booster.threshold)× · \(booster.referenceName)",
                    value: "+\(booster.value)",
                    valueColor: Theme.alertGreen
                ) {
                    editingBooster = booster
                }
            }
            if draft.boosters.isEmpty {
                emptyLine("A consistency reward that lands at week's end.")
            }
        }
    }

    private var penaltiesSection: some View {
        collapsibleSection(
            title: "END-OF-WEEK FLOORS",
            tint: Theme.alertAmber,
            isExpanded: $showPenalties,
            count: draft.weeklyPenalties.count,
            onAdd: { editingPenalty = DraftWeeklyPenalty(name: "", referenceName: draft.tasks.first?.name ?? "") }
        ) {
            ForEach(draft.weeklyPenalties) { penalty in
                ruleRow(
                    name: penalty.name,
                    detail: penalty.metric == .sum
                        ? "under \(penalty.threshold) total · \(penalty.referenceName)"
                        : "fewer than \(penalty.threshold)× · \(penalty.referenceName)",
                    value: "−\(penalty.value)",
                    valueColor: Theme.alertAmber
                ) {
                    editingPenalty = penalty
                }
            }
            if draft.weeklyPenalties.isEmpty {
                emptyLine("Optional — a weekly minimum that costs points when missed.")
            }
        }
    }

    private var milestonesSection: some View {
        collapsibleSection(
            title: "SEASON MILESTONES",
            tint: Theme.sunShadow,
            isExpanded: $showMilestones,
            count: draft.milestones.count,
            onAdd: { editingMilestone = DraftMilestone(name: "") }
        ) {
            ForEach(draft.milestones) { milestone in
                ruleRow(
                    name: milestone.name,
                    // A staged destination has rungs, and the review
                    // screen is the only place the whole season is
                    // visible — showing "one-time" for a milestone that
                    // quietly carries three steps means the person meets
                    // them for the first time after locking in.
                    detail: milestone.steps.isEmpty
                        ? "one-time"
                        : "one-time · \(milestone.steps.count) step\(milestone.steps.count == 1 ? "" : "s")",
                    value: "+\(milestone.value)",
                    valueColor: Theme.sunShadow
                ) {
                    editingMilestone = milestone
                }
                ForEach(milestone.steps) { step in
                    HStack(spacing: 8) {
                        Text("↳")
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.35))
                        Text(step.name)
                            .font(.sans(12.5, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        Spacer()
                        if step.value > 0 {
                            Text("+\(step.value)")
                                .font(.sans(12, weight: .regular))
                                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.vertical, 2)
                }
            }
            emptyLine("A task repeats and is scored often; a milestone is one-time and worth a lot.")
        }
    }

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        tint: Color,
        isExpanded: Binding<Bool>,
        count: Int,
        onAdd: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.8))
                        Text(title)
                            .font(.sans(10.5, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(tint)
                        if count > 0 {
                            Text("\(count)")
                                .font(.sans(11, weight: .regular))
                                .foregroundStyle(Theme.textPrimary.opacity(0.4))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)

                Button {
                    isExpanded.wrappedValue = true
                    onAdd()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint.opacity(0.6))
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
            }

            if isExpanded.wrappedValue {
                VStack(spacing: 6) {
                    content()
                }
            }
        }
    }

    private func ruleRow(name: String, detail: String, value: String, valueColor: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer()
                Text(value)
                    .font(.serif(15, weight: .medium))
                    .foregroundStyle(valueColor)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.sans(11.5, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.42))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
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
            .ignoresSafeArea(edges: .bottom)
        )
    }
}
