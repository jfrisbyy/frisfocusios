//
//  ProposePactView.swift
//  FrisFocus
//
//  The compose flow for a new pact. Pick one friend, name the
//  commitment, add at least one shared task (with optional category +
//  optional bridge to a personal FFTask), choose a duration, send.
//  A pact lands as `.pending` and only flips active when the partner
//  accepts — the footer copy ("{Friend} accepts, and you both start
//  together.") makes the mutual nature explicit.
//

import SwiftUI
import UIKit

struct ProposePactView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFriendId: UUID?
    @State private var title: String = ""
    @State private var tasks: [PactTask] = [
        PactTask(name: "Write — 20 minutes", category: .creative, linkedPersonalTaskId: nil)
    ]
    @State private var duration: DurationChoice = .tenDays
    @State private var editingTaskId: UUID?
    @State private var preselectedFriendId: UUID?

    /// Optional initializer so other surfaces (e.g. FriendDetailView)
    /// can open the composer pre-targeted at a specific friend.
    init(preselectedFriendId: UUID? = nil) {
        _preselectedFriendId = State(initialValue: preselectedFriendId)
        _selectedFriendId = State(initialValue: preselectedFriendId)
    }

    enum DurationChoice: Int, CaseIterable, Identifiable {
        case oneWeek = 7
        case tenDays = 10
        case oneMonth = 30
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .oneWeek: return "1 week"
            case .tenDays: return "10 days"
            case .oneMonth: return "1 month"
            }
        }
    }

    private var selectedFriend: Friend? {
        guard let id = selectedFriendId else { return nil }
        return store.friend(by: id)
    }

    private var canSend: Bool {
        selectedFriend != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tasks.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 22) {
                    withSection
                    pactSection
                    durationSection
                    sendSection
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.warmWheat)
        .ignoresSafeArea(edges: .top)
        .sheet(item: $editingTaskId) { id in
            PactTaskEditSheet(
                initial: tasks.first { $0.id == id } ?? PactTask(name: ""),
                onSave: { updated in
                    if let idx = tasks.firstIndex(where: { $0.id == id }) {
                        tasks[idx] = updated
                    }
                    editingTaskId = nil
                },
                onDelete: tasks.count > 1 ? {
                    tasks.removeAll { $0.id == id }
                    editingTaskId = nil
                } : nil
            )
            .environment(store)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
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
                Text("PROPOSE A PACT")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.75))
                Text("Make it with someone")
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            }
            .padding(.leading, Theme.pageHorizontalPadding)
            .padding(.bottom, 18)
            .padding(.trailing, Theme.pageHorizontalPadding)
        }
        .frame(height: 190)
        .clipped()
    }

    // MARK: - Sections

    private var withSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("WITH")

            VStack(spacing: 8) {
                ForEach(store.friends) { friend in
                    friendRow(friend)
                }
            }
        }
    }

    private func friendRow(_ friend: Friend) -> some View {
        let isSelected = selectedFriendId == friend.id

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedFriendId = isSelected ? nil : friend.id
        } label: {
            HStack(spacing: 12) {
                FriendAvatarView(friend: friend, size: 34)

                Text(friend.displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Color(hex: friend.accentColorHex))
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
                        isSelected
                            ? Color(hex: friend.accentColorHex).opacity(0.6)
                            : Theme.textPrimary.opacity(0.08),
                        lineWidth: isSelected ? 1.4 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Propose to \(friend.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var pactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("THE PACT")

            TextField("e.g. Write every day", text: $title)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
                )

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    taskRow(task)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let new = PactTask(name: "", category: nil, linkedPersonalTaskId: nil)
                    tasks.append(new)
                    editingTaskId = new.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.sans(12, weight: .semibold))
                        Text("Add a shared task")
                            .font(.sans(13, weight: .regular))
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

    private func taskRow(_ task: PactTask) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editingTaskId = task.id
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(task.category?.color ?? Theme.textTertiary)
                    .frame(width: 8, height: 8)
                Text(task.name.isEmpty ? "Untitled task" : task.name)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(task.name.isEmpty
                                     ? Theme.textPrimary.opacity(0.45)
                                     : Theme.textPrimary)
                Spacer()
                Text("tap to edit")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("FOR HOW LONG")

            HStack(spacing: 10) {
                ForEach(DurationChoice.allCases) { choice in
                    durationChip(choice)
                }
            }
        }
    }

    private func durationChip(_ choice: DurationChoice) -> some View {
        let isSelected = duration == choice
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) {
                duration = choice
            }
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

    private var sendSection: some View {
        VStack(spacing: 10) {
            Button {
                send()
            } label: {
                Text(sendLabel)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(canSend ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(sendLabel)

            Text("\(selectedFriend?.displayName ?? "They") accepts, and you both start together.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var sendLabel: String {
        guard let name = selectedFriend?.displayName else { return "Send the pact" }
        return "Send the pact to \(name)"
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .medium))
            .tracking(2)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }

    private func send() {
        guard let partner = selectedFriend else { return }
        let cleaned = tasks
            .map { task -> PactTask in
                var t = task
                t.name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return t
            }
            .filter { !$0.name.isEmpty }
        guard !cleaned.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.proposePact(
            title: title,
            partner: partner,
            tasks: cleaned,
            durationDays: duration.rawValue
        )
        dismiss()
    }
}

// MARK: - sheet(item:) helper for UUID

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Task edit sheet

private struct PactTaskEditSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: Category?
    @State private var linkedPersonalTaskId: UUID?

    private let initial: PactTask
    private let onSave: (PactTask) -> Void
    private let onDelete: (() -> Void)?

    init(
        initial: PactTask,
        onSave: @escaping (PactTask) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.initial = initial
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: initial.name)
        _category = State(initialValue: initial.category)
        _linkedPersonalTaskId = State(initialValue: initial.linkedPersonalTaskId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("e.g. Write — 20 minutes", text: $name)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("None").tag(Optional<Category>.none)
                        ForEach(Category.allCases, id: \.self) { c in
                            Text(c.displayName).tag(Optional<Category>.some(c))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Picker("Link to personal task", selection: $linkedPersonalTaskId) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(store.tasks) { t in
                            Text(t.title).tag(Optional<UUID>.some(t.id))
                        }
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("Completing this in the pact also completes the linked task on your day.")
                }

                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Text("Remove task")
                        }
                    }
                }
            }
            .navigationTitle("Shared task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = initial
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.category = category
                        updated.linkedPersonalTaskId = linkedPersonalTaskId
                        onSave(updated)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ProposePactView()
        .environment(Store())
}
