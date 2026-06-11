//
//  CreateCircleView.swift
//  FrisFocus
//
//  The real "start a circle" flow, reached from the Circles page's
//  start/join chooser (a pact is the two-person sibling, made via
//  ProposePactView). Name it, choose how it works (parallel = everyone
//  runs the same list, collective = everyone adds to one number), pick
//  the friends in it, define the shared list or the shared target, set
//  the window — then it lands in `store.circles` and the page updates
//  live. Calm moonlit hero to match the Circles room.
//

import SwiftUI
import UIKit

struct CreateCircleView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// One editable shared-task row. A stable id keeps TextField
    /// identity steady across add/remove (never index-based).
    private struct TaskDraft: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    @State private var name: String = ""
    @State private var type: CircleType = .parallel
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var tasks: [TaskDraft] = [TaskDraft(text: ""), TaskDraft(text: "")]
    @State private var targetText: String = ""
    @State private var unitText: String = ""
    @State private var timeframe: TimeframeChoice = .thirtyDays

    /// Handed the freshly-created circle so the caller can route
    /// straight into its detail if it wants to.
    var onCreated: ((FFCircle) -> Void)? = nil

    enum TimeframeChoice: Hashable, CaseIterable, Identifiable {
        case ongoing, twoWeeks, thirtyDays, sixtyDays
        var id: Self { self }
        var label: String {
            switch self {
            case .ongoing: return "Ongoing"
            case .twoWeeks: return "2 weeks"
            case .thirtyDays: return "30 days"
            case .sixtyDays: return "60 days"
            }
        }
        var days: Int? {
            switch self {
            case .ongoing: return nil
            case .twoWeeks: return 14
            case .thirtyDays: return 30
            case .sixtyDays: return 60
            }
        }
    }

    // MARK: - Derived

    private var cleanedTasks: [String] {
        tasks
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var targetValue: Double? {
        Double(targetText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedFriendIds.isEmpty else { return false }
        switch type {
        case .witness:
            return true
        case .parallel:
            return !cleanedTasks.isEmpty
        case .collective:
            return (targetValue ?? 0) > 0
                && !unitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .hybrid:
            return !cleanedTasks.isEmpty
                && (targetValue ?? 0) > 0
                && !unitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 22) {
                    nameSection
                    typeSection
                    withSection
                    if type == .parallel {
                        tasksSection
                    } else if type == .collective {
                        targetSection
                    }
                    durationSection
                    createSection
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 36)
            }
        }
        .background(Theme.warmWheat)
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1830),
                    Color(hex: 0x2A2438),
                    Color(hex: 0x5A4868)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textCream)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 56)
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                Text("START A CIRCLE")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.75))
                Text("A goal, shared")
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            }
            .padding(.leading, Theme.pageHorizontalPadding)
            .padding(.trailing, Theme.pageHorizontalPadding)
            .padding(.bottom, 18)
        }
        .frame(height: 190)
        .clipped()
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("NAME IT")
            TextField("e.g. Run a 5K", text: $name)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .background(fieldBackground)
        }
    }

    // MARK: - Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("HOW IT WORKS")
            VStack(spacing: 8) {
                typeRow(
                    .parallel,
                    title: "Everyone runs the same list",
                    blurb: "A shared checklist — each person works their own copy each day."
                )
                typeRow(
                    .collective,
                    title: "Everyone adds to one number",
                    blurb: "One shared target you build toward together — miles, plunges, pages."
                )
                typeRow(
                    .witness,
                    title: "Just be present together",
                    blurb: "No shared goal — everyone keeps their own. A calm room you're in together. You can add a goal anytime."
                )
            }
        }
    }

    private func typeRow(_ value: CircleType, title: String, blurb: String) -> some View {
        let isSelected = type == value
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) { type = value }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Theme.alertGreen : Theme.textPrimary.opacity(0.3), lineWidth: isSelected ? 6 : 1.6)
                        .frame(width: 22, height: 22)
                }
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(blurb)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.alertGreen.opacity(0.5) : Theme.textPrimary.opacity(0.08),
                        lineWidth: isSelected ? 1.4 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Members

    private var withSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow(selectedFriendIds.isEmpty ? "WITH" : "WITH · \(selectedFriendIds.count) PICKED")
            if store.friends.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No friends yet — add someone right here, and they can join once they accept.")
                        .font(.serifItalic(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    PeopleSuggestionsCard(palette: .parchment, maxCount: 3)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(store.friends) { friend in
                        friendRow(friend)
                    }
                }
            }
        }
    }

    private func friendRow(_ friend: Friend) -> some View {
        let isSelected = selectedFriendIds.contains(friend.id)
        let accent = Color(hex: friend.accentColorHex)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected { selectedFriendIds.remove(friend.id) }
            else { selectedFriendIds.insert(friend.id) }
        } label: {
            HStack(spacing: 12) {
                FriendAvatarView(friend: friend, size: 34)

                Text(friend.displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? accent : Color.clear)
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : Theme.textPrimary.opacity(0.25), lineWidth: 1.4)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.sans(11, weight: .bold))
                            .foregroundStyle(Theme.textCream)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.55) : Theme.textPrimary.opacity(0.08),
                        lineWidth: isSelected ? 1.4 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(friend.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Parallel tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("THE SHARED LIST")
            VStack(spacing: 8) {
                ForEach($tasks) { $task in
                    taskRow($task)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    tasks.append(TaskDraft(text: ""))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.sans(12, weight: .semibold))
                        Text("Add a shared task").font(.sans(13, weight: .regular))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                Theme.textPrimary.opacity(0.22),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func taskRow(_ task: Binding<TaskDraft>) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.alertGreen.opacity(0.7))
                .frame(width: 8, height: 8)
            TextField("e.g. Run a mile", text: task.text)
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
            if tasks.count > 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    tasks.removeAll { $0.id == task.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.sans(16, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove task")
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(fieldBackground)
    }

    // MARK: - Collective target

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("THE TARGET")
            HStack(spacing: 10) {
                TextField("1000", text: $targetText)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
                    .keyboardType(.numberPad)
                    .frame(width: 96)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 14)
                    .background(fieldBackground)

                TextField("miles, plunges, pages…", text: $unitText)
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 14)
                    .background(fieldBackground)
            }
            Text("Everyone's contributions add up toward this number.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("FOR HOW LONG")
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    durationChip(.ongoing)
                    durationChip(.twoWeeks)
                }
                HStack(spacing: 10) {
                    durationChip(.thirtyDays)
                    durationChip(.sixtyDays)
                }
            }
        }
    }

    private func durationChip(_ choice: TimeframeChoice) -> some View {
        let isSelected = timeframe == choice
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) { timeframe = choice }
        } label: {
            Text(choice.label)
                .font(.sans(13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.06))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Create

    private var createSection: some View {
        VStack(spacing: 10) {
            Button {
                create()
            } label: {
                Text("Create the circle")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(canCreate ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
            .accessibilityLabel("Create the circle")

            Text("You're the owner. You can add tasks, members, and a story together.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared chrome

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
            )
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .medium))
            .tracking(2)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }

    private func create() {
        let timeframeValue: CircleTimeframe
        if let days = timeframe.days {
            let end = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
            timeframeValue = .timeBoxed(endDate: end)
        } else {
            timeframeValue = .ongoing
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let created = store.createCircle(
            name: name,
            type: type,
            memberFriendIds: Array(selectedFriendIds),
            timeframe: timeframeValue,
            taskTitles: type == .parallel ? cleanedTasks : [],
            collectiveUnit: type == .collective ? unitText : nil,
            collectiveTarget: type == .collective ? targetValue : nil
        )
        onCreated?(created)
        dismiss()
    }
}

#Preview {
    CreateCircleView()
        .environment(Store())
}
