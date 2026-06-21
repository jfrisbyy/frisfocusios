//
//  MilestoneNoteLinkSheet.swift
//  FrisFocus
//
//  Pick journal notes to link to a milestone. Notes list newest first
//  with a quiet search; tapping toggles the link, already-linked notes
//  show a checkmark. The note itself never moves — linking just makes
//  it visible on the milestone's page.
//

import SwiftUI
import UIKit

struct MilestoneNoteLinkSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let milestoneId: UUID

    @State private var search: String = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    private var linkedIds: Set<UUID> {
        Set(store.milestone(by: milestoneId)?.linkedNoteIds ?? [])
    }

    private var filteredNotes: [Note] {
        let all = store.notes
            .filter(\.hasContent)
            .sorted { $0.createdAt > $1.createdAt }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { note in
            (note.body?.localizedStandardContains(query) ?? false)
                || (note.label?.localizedStandardContains(query) ?? false)
                || note.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                if filteredNotes.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredNotes) { note in
                            noteRow(note)
                                .listRowBackground(Color.white.opacity(0.6))
                                .listRowSeparatorTint(Theme.textPrimary.opacity(0.06))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .searchable(text: $search, prompt: "Search your notes")
            .navigationTitle("Link a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        let isLinked = linkedIds.contains(note.id)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isLinked {
                store.unlinkNote(note.id, from: milestoneId)
            } else {
                store.linkNote(note.id, to: milestoneId)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isLinked ? Theme.alertGreen : Theme.textPrimary.opacity(0.25), lineWidth: 1.3)
                        .frame(width: 20, height: 20)
                    if isLinked {
                        Circle().fill(Theme.alertGreen).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.warmWheat)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let label = note.label, !label.isEmpty {
                            Text(label)
                                .font(.sans(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        }
                        Spacer()
                        Text(Self.dateFormatter.string(from: note.createdAt))
                            .font(.sans(10, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    }

                    if let body = note.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        NoteBodyText(text: body, size: 13, lineSpacing: 3, italic: false, lineLimit: 2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    } else if !note.voiceMemos.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                            Text("Voice memo")
                                .font(.sans(11, weight: .regular))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    } else if !note.photos.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 10))
                            Text("Photo note")
                                .font(.sans(11, weight: .regular))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLinked ? "Unlink note" : "Link note")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(0.35))
            Text(search.isEmpty ? "No notes yet" : "Nothing matches")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(search.isEmpty
                 ? "Write something in the note zone first, then link it here."
                 : "Try a different search.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(40)
    }
}
