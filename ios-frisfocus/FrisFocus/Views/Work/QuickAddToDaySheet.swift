//
//  QuickAddToDaySheet.swift
//  FrisFocus
//
//  One calm sheet that feeds Today's Plan. A text field at the top
//  creates a brand-new To-do dated for today; below it, a searchable
//  list of every Task and To-do not already on today lets the user
//  pin existing items with a single tap. The sheet stays open after
//  each add so several can be queued in a row, each landing with a
//  light haptic and a gentle slide-and-fade.
//

import SwiftUI
import UIKit

struct QuickAddToDaySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var newTitle: String = ""
    @State private var search: String = ""
    /// Items just pinned this session — kept so they animate into the
    /// "added" state and drop to the bottom rather than vanishing.
    @State private var justAdded: Set<UUID> = []
    @FocusState private var newFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    newTodoField
                    candidateSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.warmWheat)
            .navigationTitle("Add to today")
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

    // MARK: - New to-do

    @ViewBuilder
    private var newTodoField: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "New to-do", opacity: 0.55)

            HStack(spacing: 10) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))

                TextField("Add something for today…", text: $newTitle)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($newFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(commitNewTodo)

                if canCommitNew {
                    Button(action: commitNewTodo) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(Theme.alertGreen)
                            .transition(.scale.combined(with: .opacity))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        newFieldFocused ? Theme.alertGreen.opacity(0.4) : Theme.textPrimary.opacity(0.08),
                        lineWidth: newFieldFocused ? 1.2 : 0.6
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: canCommitNew)
            .animation(.easeInOut(duration: 0.2), value: newFieldFocused)
        }
    }

    private var canCommitNew: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commitNewTodo() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.quickAddTodoToToday(title: trimmed)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            newTitle = ""
        }
    }

    // MARK: - Existing items

    @ViewBuilder
    private var candidateSection: some View {
        let rows = candidates
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Pin from your lists", opacity: 0.55)

            if store.tasks.isEmpty && store.todos.isEmpty {
                emptyHint("Nothing in your lists yet. Type above to add your first item.")
            } else {
                searchField

                if rows.isEmpty {
                    emptyHint(search.isEmpty
                        ? "Everything's already on today. Nice."
                        : "No matches for \u{201C}\(search)\u{201D}.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            candidateRow(row)
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
            TextField("Search tasks & to-dos", text: $search)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Theme.textPrimary.opacity(0.05))
        )
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
    private func candidateRow(_ row: CandidateRow) -> some View {
        let added = isAdded(row)
        Button {
            pin(row)
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .fill(row.dotColor(store))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(added ? 0.5 : 1))
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }

                Spacer(minLength: 8)

                if row.value > 0 {
                    Text(row.valuePrefix + "\(row.value)")
                        .font(.serif(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(added ? 0.35 : 0.6))
                }

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
        .accessibilityLabel(added ? "\(row.title) already on today" : "Pin \(row.title) to today")
    }

    // MARK: - Logic

    private func isAdded(_ row: CandidateRow) -> Bool {
        if justAdded.contains(row.id) { return true }
        switch row.kind {
        case .task(let task): return task.isPinnedToday
        case .todo(let todo): return store.isTodoOnToday(todo)
        }
    }

    private func pin(_ row: CandidateRow) {
        guard !isAdded(row) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch row.kind {
        case .task(let task): store.pinTaskToToday(task)
        case .todo(let todo): store.pinTodoToToday(todo)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            _ = justAdded.insert(row.id)
        }
    }

    /// Tasks not pinned today + To-dos not on today, filtered by search.
    /// Already-added rows (this session) sink to the bottom so the list
    /// stays settled while you keep adding.
    private var candidates: [CandidateRow] {
        var rows: [CandidateRow] = []
        for task in store.tasks where !task.isPinnedToday || justAdded.contains(task.id) {
            rows.append(CandidateRow(kind: .task(task)))
        }
        for todo in store.todos where !todo.isCompleted && (!store.isTodoOnToday(todo) || justAdded.contains(todo.id)) {
            rows.append(CandidateRow(kind: .todo(todo)))
        }

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

// MARK: - Candidate model

private struct CandidateRow: Identifiable {
    enum Kind {
        case task(FFTask)
        case todo(Todo)
    }

    let kind: Kind

    var id: UUID {
        switch kind {
        case .task(let t): return t.id
        case .todo(let td): return td.id
        }
    }

    var title: String {
        switch kind {
        case .task(let t): return t.title
        case .todo(let td): return td.title
        }
    }

    var subtitle: String {
        switch kind {
        case .task(let t): return t.category.displayName
        case .todo: return "To-do"
        }
    }

    var value: Int {
        switch kind {
        case .task(let t): return t.nominalValue
        case .todo(let td): return td.pointValue ?? 0
        }
    }

    var valuePrefix: String {
        switch kind {
        case .task: return ""
        case .todo: return "+"
        }
    }

    func dotColor(_ store: Store) -> Color {
        switch kind {
        case .task(let t): return Color(hex: store.categoryColorHex(t.category))
        case .todo: return Theme.textPrimary.opacity(0.3)
        }
    }
}

#Preview {
    QuickAddToDaySheet()
        .environment(Store())
}
