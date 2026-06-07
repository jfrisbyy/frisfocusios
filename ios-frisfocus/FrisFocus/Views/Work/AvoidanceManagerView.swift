//
//  AvoidanceManagerView.swift
//  FrisFocus
//
//  "Behaviors to reduce" — the standalone avoidance manager. Lists every
//  AvoidanceItem the user has added, shows week-to-date occurrence count
//  and points impact, and exposes a +1 log button per item plus an
//  inline add / edit / delete flow. Calm, factual, private — never
//  broadcast.
//

import SwiftUI
import UIKit

struct AvoidanceManagerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd: Bool = false
    @State private var editing: AvoidanceItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if store.avoidanceItems.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.avoidanceItems) { item in
                                AvoidanceItemCard(
                                    item: item,
                                    onLog: { logOccurrence(item) },
                                    onUndo: { undoLatest(item) },
                                    onEdit: { editing = item },
                                    onDelete: { delete(item) }
                                )
                            }
                        }
                    }

                    addButton

                    privacyFooter

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .background(Theme.warmWheat)
            .navigationTitle("Behaviors to reduce")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .sheet(isPresented: $showAdd) {
                AvoidanceItemFormView(editing: nil)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editing) { item in
                AvoidanceItemFormView(editing: item)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Private accounting")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Name a few things you'd like to reduce this season. Logging an occurrence quietly deducts points from your weekly total. Never shown to anyone else.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing tracked yet")
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
            Text("Add a behavior below to start counting.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAdd = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                Text("Add a behavior")
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var privacyFooter: some View {
        Text("Behaviors and occurrences stay on this device. They never appear in friends' feeds, signals, or stories.")
            .font(.serifItalic(12))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func logOccurrence(_ item: AvoidanceItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.logAvoidanceOccurrence(item)
    }

    private func undoLatest(_ item: AvoidanceItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.undoLatestAvoidanceOccurrence(item)
    }

    private func delete(_ item: AvoidanceItem) {
        store.deleteAvoidanceItem(item)
    }
}

// MARK: - Item card

private struct AvoidanceItemCard: View {
    @Environment(Store.self) private var store
    let item: AvoidanceItem
    let onLog: () -> Void
    let onUndo: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\u{2212}\(item.pointsPerOccurrence) pts each")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))

                    if let note = item.note, !note.isEmpty {
                        Text(note)
                            .font(.serifItalic(12))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Menu {
                    Button("Edit", systemImage: "pencil") { onEdit() }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }

            HStack(spacing: 8) {
                statBlock(value: "\(occurrenceCount)", label: occurrenceLabel)
                Divider()
                    .frame(height: 22)
                    .overlay(Theme.textPrimary.opacity(0.1))
                statBlock(value: "\u{2212}\(pointsThisWeek)", label: "pts this week")
                Spacer()
            }

            HStack(spacing: 8) {
                Button(action: onLog) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Log occurrence")
                            .font(.sans(12, weight: .medium))
                    }
                    .foregroundStyle(Theme.warmWheat)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Theme.alertAmber)
                    )
                }
                .buttonStyle(.plain)

                if occurrenceCount > 0 {
                    Button(action: onUndo) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .regular))
                            Text("Undo last")
                                .font(.sans(12, weight: .regular))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var occurrenceCount: Int {
        store.occurrencesThisWeek(for: item).count
    }

    private var occurrenceLabel: String {
        occurrenceCount == 1 ? "time this week" : "times this week"
    }

    private var pointsThisWeek: Int {
        store.avoidancePointsThisWeek(for: item)
    }

    @ViewBuilder
    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
    }
}

// MARK: - Add / edit form

private struct AvoidanceItemFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: AvoidanceItem?

    @State private var name: String
    @State private var pointsPerOccurrence: Int
    @State private var note: String

    init(editing: AvoidanceItem?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _pointsPerOccurrence = State(initialValue: editing?.pointsPerOccurrence ?? 5)
        _note = State(initialValue: editing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. doomscroll past midnight", text: $name, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...3)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("Name something concrete you'd like to reduce.")
                }

                Section {
                    Stepper(value: $pointsPerOccurrence, in: 1...50) {
                        HStack {
                            Text("Per occurrence")
                            Spacer()
                            Text("\u{2212}\(pointsPerOccurrence) pts")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.alertAmber)
                        }
                    }
                } header: {
                    Text("Cost")
                } footer: {
                    Text("How many points each logged occurrence quietly deducts from your weekly total.")
                }

                Section {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .font(.serifItalic(14))
                        .lineLimit(1...4)
                } header: {
                    Text("Note")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(editing == nil ? "Add behavior" : "Edit behavior")
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if let editing {
            var updated = editing
            updated.name = name
            updated.pointsPerOccurrence = pointsPerOccurrence
            updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
            store.updateAvoidanceItem(updated)
        } else {
            store.addAvoidanceItem(
                name: name,
                pointsPerOccurrence: pointsPerOccurrence,
                note: note
            )
        }
        dismiss()
    }
}

#Preview {
    AvoidanceManagerView()
        .environment(Store())
}
