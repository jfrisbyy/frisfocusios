//
//  NoteZoneView.swift
//  FrisFocus
//
//  Zone 3 — the journal page on the homepage. Paper-cream background
//  with ruled lines bleeding through. Header now sits beside a clear
//  "+ New note" pill so capturing a thought is a single tap away. The
//  zone title gets a thin warm-gold underline that ties it to the
//  refined library typography below.
//
//  Tapping the header pushes the full Notes library; tapping any
//  folder pill pushes the dedicated `FolderDetailView`. Individual
//  entry rows handle their own navigation inside `NoteEntryView`.
//

import SwiftUI
import UIKit

struct NoteZoneView: View {
    @Environment(Store.self) private var store

    @State private var pushLibrary: Bool = false
    @State private var pushedFolder: NoteFolder? = nil

    /// Drives the New Note form sheet — opened by both the top-right
    /// pill and the dashed "Add a thought" prompt below the entries.
    @State private var showNewNoteForm: Bool = false

    var body: some View {
        ZStack {
            RuledPaperBackground()

            VStack(alignment: .leading, spacing: 22) {
                headerBlock
                    .padding(.top, 28)

                entriesBlock

                AddPromptView(action: openNewNote)

                folderPillsBlock
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
        }
        .navigationDestination(isPresented: $pushLibrary) {
            NotesLibraryView()
        }
        .navigationDestination(item: $pushedFolder) { folder in
            FolderDetailView(folder: folder)
        }
        .sheet(isPresented: $showNewNoteForm) {
            NewNoteFormView { }
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
        Button(action: openNewNote) {
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
        if store.todaysNotes.isEmpty {
            EmptyNoteHintView(isPast: store.isViewingPast)
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(store.todaysNotes) { note in
                    NoteEntryView(note: note)
                    if note.id != store.todaysNotes.last?.id {
                        Rectangle()
                            .fill(Theme.textPrimary.opacity(0.05))
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }

    // MARK: - Folder pills

    @ViewBuilder
    private var folderPillsBlock: some View {
        if !store.sortedFolders.isEmpty {
            FolderTagsRowView(
                folders: store.sortedFolders,
                onSelect: handleFolderTap
            )
            .padding(.top, 4)
            .padding(.bottom, 28)
        } else {
            Spacer().frame(height: 28)
        }
    }

    // MARK: - Actions

    private func openLibrary() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pushLibrary = true
    }

    private func openNewNote() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showNewNoteForm = true
    }

    /// Folder pill taps push to the folder's dedicated page now. The
    /// trailing "all folders →" link still routes to the full library.
    private func handleFolderTap(_ folder: NoteFolder?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let folder {
            pushedFolder = folder
        } else {
            pushLibrary = true
        }
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
            NoteZoneView()
        }
        .environment(Store())
    }
}
