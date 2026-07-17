//
//  NoteZoneView.swift
//  FrisFocus
//
//  Zone 3 — the journal page on the homepage. Paper-cream background
//  with ruled lines bleeding through and an inline, autosaving quick
//  composer for low-friction capture. The full library remains behind
//  the header, while folders stay off the homepage until users enter it.
//

import SwiftUI
import UIKit

struct NoteZoneView: View {
    @Environment(Store.self) private var store

    @Binding var isQuickNoteOpen: Bool

    @State private var pushLibrary: Bool = false
    @State private var pushExpandedNote: Bool = false
    @State private var expandedNote: Note?
    @State private var quickDraftNoteID: UUID?

    var body: some View {
        ZStack {
            RuledPaperBackground()

            VStack(alignment: .leading, spacing: 22) {
                headerBlock
                    .padding(.top, 28)

                if isQuickNoteOpen {
                    QuickNoteComposerView(
                        isPresented: $isQuickNoteOpen,
                        draftNoteID: $quickDraftNoteID,
                        onExpand: expandQuickNote
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                entriesBlock

                if !isQuickNoteOpen {
                    AddPromptView(action: openQuickNote)
                        .transition(.opacity)
                }

                Spacer()
                    .frame(height: 28)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
        }
        .navigationDestination(isPresented: $pushLibrary) {
            NotesLibraryView()
        }
        .navigationDestination(isPresented: $pushExpandedNote) {
            if let expandedNote {
                NoteDetailEditView(note: expandedNote)
            }
        }
    }

    // MARK: - Header

    /// "The note" zone header on the left, "+ New note" pill on the
    /// right. The header text is tappable as a whole — pushes to the
    /// library — and gets a hairline warm-gold underline that echoes
    /// the day-group rules used inside the library and folder pages.
    @ViewBuilder
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(action: openLibrary) {
                    ZoneHeaderView(
                        title: "The note",
                        eyebrowRight: "Zone 3 of 4",
                        subline: store.isViewingPast
                            ? "that day's page · tap for everything"
                            : "today's page · tap for everything"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open notes library")

                Spacer(minLength: 0)

                newNotePill
                    .accessibilityLabel("New note")
            }

            // Hairline warm-gold rule under the whole header block —
            // ties the homepage zone visually to the library's day rules.
            Rectangle()
                .fill(Theme.sunWarm.opacity(0.45))
                .frame(height: 0.5)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var newNotePill: some View {
        Button(action: openQuickNote) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("New note")
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.warmWheat)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Theme.sunWarm.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Theme.sunWarm.opacity(0.22), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entries

    @ViewBuilder
    private var entriesBlock: some View {
        let visibleNotes = store.todaysNotes.filter { $0.id != quickDraftNoteID }

        if visibleNotes.isEmpty {
            if !isQuickNoteOpen {
                Button(action: openQuickNote) {
                    EmptyNoteHintView(isPast: store.isViewingPast)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isViewingPast ? "Return to today and add a note" : "Add a note today")
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(visibleNotes) { note in
                    NoteEntryView(note: note)
                    if note.id != visibleNotes.last?.id {
                        Rectangle()
                            .fill(Theme.textPrimary.opacity(0.05))
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openLibrary() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pushLibrary = true
    }

    private func openQuickNote() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if store.isViewingPast {
            store.viewingDay = nil
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            isQuickNoteOpen = true
        }
    }

    private func expandQuickNote(_ note: Note) {
        expandedNote = note
        pushExpandedNote = true
    }
}

/// Quiet placeholder shown when no notes have been written today —
/// keeps the zone breathing rather than collapsing it into the header.
private struct EmptyNoteHintView: View {
    var isPast: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: isPast ? "That day" : "Today", opacity: 0.5)
            Text(isPast ? "no notes were written this day" : "the page is blank")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            NoteZoneView(isQuickNoteOpen: .constant(false))
        }
        .environment(Store())
    }
}
