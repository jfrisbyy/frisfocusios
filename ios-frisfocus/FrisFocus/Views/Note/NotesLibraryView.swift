//
//  NotesLibraryView.swift
//  FrisFocus
//
//  The full Notes library, reached by tapping the Note zone header on
//  the homepage. The layout reads like a kept journal:
//
//    1. Inline search bar
//    2. Slim filter chip row — "All" / folder chips / "Unfiled"
//    3. Quiet "Manage folders" row
//    4. Optional Pinned block (when there are pinned matches)
//    5. Day-grouped flow with refined serif headers and gold rules
//
//  Folder chips push the dedicated `FolderDetailView` (each folder has
//  its own page now); "All" and "Unfiled" remain in-place filters. The
//  sundial nav stays anchored at the bottom in `.subPage` mode.
//

import SwiftUI
import UIKit

struct NotesLibraryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Library-level filter. Folder filtering now lives on the
    /// dedicated folder page, so only the two top-level modes survive.
    enum Selection: Equatable {
        case all
        case unfiled
    }

    @State private var selection: Selection = .all
    @State private var query: String = ""
    @State private var pushedFolder: NoteFolder? = nil
    @State private var showManage: Bool = false
    @State private var showCaptureSheet: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RuledPaperBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 22)

                    NotesSearchField(query: $query)
                        .padding(.top, 18)

                    filterStrip
                        .padding(.top, 14)

                    manageRow
                        .padding(.top, 6)

                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.top, 14)
                        .padding(.bottom, 18)

                    notesContent
                        .padding(.bottom, 140)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
            }
            .animation(.easeInOut(duration: 0.18), value: query.isEmpty)

            SundialNavView(
                active: .subPage,
                onCaptureTap: { showCaptureSheet = true },
                onHomeTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                },
                onCirclesTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushedFolder) { folder in
            FolderDetailView(folder: folder)
        }
        .sheet(isPresented: $showManage) {
            ManageFoldersSheetView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Home")
                            .font(.sans(15, weight: .regular))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.serif(30, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Text(headerSubtitle)
                    .font(.serifItalic(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
            .padding(.top, 14)
        }
    }

    private var headerSubtitle: String {
        let total = store.notes.count
        let folders = store.folders.count
        return "\(total) note\(total == 1 ? "" : "s") · \(folders) folder\(folders == 1 ? "" : "s")"
    }

    // MARK: - Filter strip

    @ViewBuilder
    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                modeFilterChip(label: "All", isSelected: selection == .all) {
                    setSelection(.all)
                }

                ForEach(store.sortedFolders) { folder in
                    folderNavChip(folder: folder)
                }

                if hasUnfiled {
                    modeFilterChip(label: "Unfiled", isSelected: selection == .unfiled) {
                        setSelection(.unfiled)
                    }
                }
            }
            .padding(.horizontal, 2) // breathing room for the focus ring
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var hasUnfiled: Bool {
        store.notes.contains { $0.folderId == nil }
    }

    /// "All" / "Unfiled" — toggle the library's in-place filter. Active
    /// chips fill with charcoal and read in cream with a warm-gold ring.
    @ViewBuilder
    private func modeFilterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.sans(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Theme.textPrimary : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected
                                ? Theme.sunWarm.opacity(0.7)
                                : Theme.textPrimary.opacity(0.22),
                            lineWidth: isSelected ? 1.2 : 0.5
                        )
                )
                .shadow(
                    color: isSelected ? Theme.sunWarm.opacity(0.18) : .clear,
                    radius: isSelected ? 4 : 0,
                    y: 1
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    /// Folder chip pushes the dedicated `FolderDetailView`. Outline-only
    /// look with the folder's color dot and a small chevron to suggest
    /// navigation.
    @ViewBuilder
    private func folderNavChip(folder: NoteFolder) -> some View {
        Button(action: { openFolder(folder) }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(folder.colorKey.dotColor)
                    .frame(width: 6, height: 6)
                Text(folder.name)
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(folder.colorKey.pillText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(folder.colorKey.pillText.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(folder.colorKey.pillBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(folder.colorKey.dotColor.opacity(0.28), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func openFolder(_ folder: NoteFolder) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pushedFolder = folder
    }

    private func setSelection(_ new: Selection) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            selection = new
        }
    }

    // MARK: - Manage folders row

    @ViewBuilder
    private var manageRow: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showManage = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 11, weight: .regular))
                Text("Manage folders")
                    .font(.sans(11, weight: .regular))
                Spacer()
                Text("\(store.folders.count)")
                    .font(.sans(11, weight: .regular))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notes content

    private var storeSelection: Store.NoteSelection {
        switch selection {
        case .all: return .all
        case .unfiled: return .unfiled
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            searchResults(query: trimmed)
        } else {
            groupedContent
        }
    }

    @ViewBuilder
    private func searchResults(query: String) -> some View {
        let results = store.searchNotes(query: query, selection: storeSelection)
        if results.isEmpty {
            VStack(alignment: .center, spacing: 10) {
                EyebrowText(text: "No matches", opacity: 0.5)
                Text("nothing matches \u{201C}\(query)\u{201D}")
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Results")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(results.count) match\(results.count == 1 ? "" : "es")")
                        .font(.sans(11, weight: .regular))
                        .tracking(1)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }

                Rectangle()
                    .fill(Theme.sunWarm.opacity(0.5))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 22) {
                    ForEach(results) { note in
                        NoteEntryView(note: note)
                        if note.id != results.last?.id {
                            Rectangle()
                                .fill(Theme.textPrimary.opacity(0.05))
                                .frame(height: 0.5)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var groupedContent: some View {
        let pinned = store.pinnedNotes(selection: storeSelection)
        let days = store.unpinnedNotesGroupedByDay(selection: storeSelection)

        if pinned.isEmpty && days.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 36) {
                if !pinned.isEmpty {
                    PinnedNotesSectionView(notes: pinned)
                }
                ForEach(days, id: \.date) { group in
                    NoteDayGroupView(date: group.date, notes: group.notes)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .center, spacing: 10) {
            EyebrowText(text: emptyEyebrow, opacity: 0.5)
            Text(emptyMessage)
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var emptyEyebrow: String {
        switch selection {
        case .all: return "Empty"
        case .unfiled: return "Nothing unfiled"
        }
    }

    private var emptyMessage: String {
        switch selection {
        case .all: return "Tap + below to capture the first one."
        case .unfiled: return "Every note has a home."
        }
    }
}

#Preview {
    NavigationStack {
        NotesLibraryView()
            .environment(Store())
    }
}
