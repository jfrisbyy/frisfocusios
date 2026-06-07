//
//  FolderDetailView.swift
//  FrisFocus
//
//  Dedicated page for a single NoteFolder. Sits between the homepage
//  (where folder pills push here) and the library (where folder chips
//  push here). Same paper background and entry treatment as the rest
//  of the journal, with a hero that uses the folder's tint as a soft
//  color wash so each folder feels distinct.
//
//  The hero also exposes an "Edit folder" pill that opens the existing
//  `ManageFoldersSheetView`, so rename / recolor / delete stay one tap
//  away from anywhere a user might be browsing a folder.
//

import SwiftUI
import UIKit

struct FolderDetailView: View {
    let folder: NoteFolder

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showManage: Bool = false
    @State private var showCaptureSheet: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RuledPaperBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero

                    contentSections
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 28)
                        .padding(.bottom, 140)
                }
            }

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

    // MARK: - Derived

    /// Look the folder up fresh on every render so renames / recolors
    /// done via the Manage sheet reflect immediately. Falls back to the
    /// view's snapshot if the folder has been deleted while we were on
    /// screen (the back-nav happens via the sheet's delete flow).
    private var liveFolder: NoteFolder {
        store.folders.first { $0.id == folder.id } ?? folder
    }

    private var selection: Store.NoteSelection {
        .folder(folder.id)
    }

    private var noteCount: Int {
        store.notesCount(in: liveFolder)
    }

    /// "started in March" / "started today" — the month and year of the
    /// oldest note in this folder. Falls back to a quieter phrase when
    /// the folder is empty.
    private var startedString: String {
        let folderNotes = store.notes.filter { $0.folderId == folder.id }
        guard let oldest = folderNotes.min(by: { $0.createdAt < $1.createdAt }) else {
            return "no notes yet"
        }
        let cal = Calendar.current
        if cal.isDateInToday(oldest.createdAt) { return "started today" }
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return "started in \(f.string(from: oldest.createdAt))"
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let color = liveFolder.colorKey

        ZStack(alignment: .topLeading) {
            // Soft color wash that fades into the cream paper
            LinearGradient(
                colors: [
                    color.dotColor.opacity(0.32),
                    color.dotColor.opacity(0.12),
                    color.dotColor.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)

            VStack(alignment: .leading, spacing: 0) {
                // Top nav row
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text("Back")
                                .font(.sans(15, weight: .regular))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    editFolderPill(color: color)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 12)

                // Title block
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(color.dotColor)
                            .frame(width: 8, height: 8)
                        Text("FOLDER")
                            .font(.sans(10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(color.pillText.opacity(0.85))
                    }

                    Text(liveFolder.name)
                        .font(.serif(34, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    Text(metaLine)
                        .font(.serifItalic(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
        }
        .frame(minHeight: 200)
    }

    @ViewBuilder
    private func editFolderPill(color: FolderColor) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showManage = true
        }) {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .regular))
                Text("Edit folder")
                    .font(.sans(12, weight: .medium))
            }
            .foregroundStyle(color.pillText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.65))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(color.dotColor.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var metaLine: String {
        let pieces: [String] = [
            "\(noteCount) note\(noteCount == 1 ? "" : "s")",
            startedString
        ]
        return pieces.joined(separator: " · ")
    }

    // MARK: - Content sections

    @ViewBuilder
    private var contentSections: some View {
        let pinned = store.pinnedNotes(selection: selection)
        let days = store.unpinnedNotesGroupedByDay(selection: selection)

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
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .center, spacing: 10) {
            EyebrowText(text: "Empty folder", opacity: 0.5)
            Text("Move a note here, or write a new one.")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

#Preview {
    NavigationStack {
        FolderDetailView(folder: NoteFolder(name: "Songs", colorKey: .purple))
            .environment(Store())
    }
}
