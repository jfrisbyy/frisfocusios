//
//  NoteDetailEditView.swift
//  FrisFocus
//
//  Full-page editor for an existing Note. Reached by tapping any
//  entry on the homepage or in the Notes library. The screen reuses
//  the ruled-paper background so it still feels like a journal —
//  the text field is the focus, and the folder / label / delete
//  controls sit underneath as a quiet toolbar.
//
//  Autosave: every edit is mirrored to local `@State` and persisted
//  to the Store automatically. Textual edits debounce (0.5s) so we
//  don't thrash the disk on every keystroke; structural edits (folder
//  pick, voice memo add/remove, pin toggle) commit immediately.
//
//  Voice memos: a note can carry any number of takes. The editor lists
//  them in order, with a per-memo remove control, and an "Add voice
//  memo" button that always appears so users can stack additional
//  recordings on the same note.
//

import SwiftUI
import UIKit

struct NoteDetailEditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var noteText: String = ""
    @State private var label: String = ""
    @State private var selectedFolderId: UUID?
    @State private var voiceMemos: [NoteVoiceMemo] = []

    @State private var initialized: Bool = false
    @State private var showFolderPicker: Bool = false
    @State private var showRecorder: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showCaptureSheet: Bool = false

    /// Debounce token for textual autosave. Bumped on every keystroke;
    /// the trailing task only fires the persist when it's still current.
    @State private var saveDebounceToken: UUID = UUID()

    /// Quiet "Saved" indicator in the toolbar — flashes briefly after a
    /// persist completes so the user has a tiny confirmation that their
    /// edits stuck without needing a Save button.
    @State private var savedFlash: Bool = false

    /// Local mirror of the live note's pinned state so the toolbar
    /// star reflects taps instantly. The toggle commits straight to
    /// the store (it's a one-tap action, not a pending form edit).
    @State private var starPulse: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RuledPaperBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    bodyField

                    voiceMemoBlock

                    folderRow

                    labelField

                    deleteButton

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }

            SundialNavView(
                active: .subPage,
                onCaptureTap: { showCaptureSheet = true },
                onHomeTap: { dismiss() },
                onCirclesTap: { dismiss() }
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: handleBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Back")
                            .font(.sans(15, weight: .regular))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                savedIndicator
            }
            ToolbarItem(placement: .topBarTrailing) {
                pinToolbarButton
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheetView(selectedFolderId: $selectedFolderId)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showRecorder) {
            VoiceMemoRecorderSheet { completed in
                appendVoiceMemo(completed)
            }
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .onAppear(perform: initializeOnce)
        .onChange(of: noteText) { _, _ in scheduleAutosave() }
        .onChange(of: label) { _, _ in scheduleAutosave() }
        .onChange(of: selectedFolderId) { _, _ in persistNow() }
        .onDisappear {
            // Flush any pending textual autosave when the screen closes so
            // a fast back-tap never loses the last keystroke.
            persistNow()
        }
    }

    // MARK: - Toolbar bits

    /// Tiny "Saved" pill that fades in after a successful persist and
    /// fades back out. Replaces the explicit Save button — autosave
    /// makes the action implicit, the indicator confirms it landed.
    @ViewBuilder
    private var savedIndicator: some View {
        Text("Saved")
            .font(.sans(12, weight: .medium))
            .foregroundStyle(Theme.alertGreen.opacity(savedFlash ? 0.9 : 0))
            .animation(.easeInOut(duration: 0.25), value: savedFlash)
            .accessibilityHidden(!savedFlash)
    }

    @ViewBuilder
    private var pinToolbarButton: some View {
        let pinned = liveNote?.isPinned ?? false
        Button(action: togglePinned) {
            Image(systemName: pinned ? "star.fill" : "star")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(pinned ? Theme.sunWarm : Theme.textPrimary.opacity(0.55))
                .scaleEffect(starPulse ? 1.22 : 1.0)
                .shadow(
                    color: pinned ? Theme.sunWarm.opacity(0.55) : .clear,
                    radius: pinned ? 6 : 0
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: starPulse)
                .animation(.easeInOut(duration: 0.18), value: pinned)
        }
        .accessibilityLabel(pinned ? "Unpin note" : "Pin note")
    }

    /// Read the freshest version of the note from the store so the
    /// star reflects pin changes immediately after `togglePinned`.
    /// Falls back to the constructor's snapshot if the note has been
    /// deleted while open.
    private var liveNote: Note? {
        store.notes.first { $0.id == note.id }
    }

    private func togglePinned() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.togglePinned(note)
        starPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            starPulse = false
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            EyebrowText(text: createdString, opacity: 0.5)
            HStack(spacing: 8) {
                if let folder = currentFolder {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(folder.colorKey.dotColor)
                            .frame(width: 5, height: 5)
                        Text(folder.name)
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(folder.colorKey.pillText.opacity(0.85))
                    }
                }

                if liveNote?.isPinned ?? false {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(Theme.sunWarm)
                        Text("PINNED")
                            .font(.sans(9, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.sunShadow)
                    }
                }
            }
        }
    }

    private var createdString: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(note.createdAt) {
            f.dateFormat = "'Today · 'h:mm a"
        } else if cal.isDateInYesterday(note.createdAt) {
            f.dateFormat = "'Yesterday · 'h:mm a"
        } else {
            f.dateFormat = "EEE · MMM d · h:mm a"
        }
        return f.string(from: note.createdAt)
    }

    // MARK: - Body field

    @ViewBuilder
    private var bodyField: some View {
        TextField(
            "Write a thought…",
            text: $noteText,
            axis: .vertical
        )
        .font(.serifItalic(17, weight: .regular))
        .lineSpacing(6)
        .foregroundStyle(Theme.textPrimary)
        .frame(minHeight: 180, alignment: .topLeading)
        .padding(.vertical, 4)
    }

    // MARK: - Voice memo block

    @ViewBuilder
    private var voiceMemoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !voiceMemos.isEmpty {
                HStack(spacing: 6) {
                    EyebrowText(
                        text: voiceMemos.count == 1
                            ? "Voice memo"
                            : "Voice memos · \(voiceMemos.count)",
                        opacity: 0.5
                    )
                    Spacer()
                }

                ForEach(voiceMemos) { memo in
                    if let url = memo.url {
                        VoiceMemoStripView(
                            url: url,
                            duration: memo.duration,
                            onRemove: { removeVoiceMemo(memo) }
                        )
                    }
                }
            }

            Button(action: { showRecorder = true }) {
                HStack(spacing: 8) {
                    Image(systemName: voiceMemos.isEmpty ? "mic" : "plus")
                        .font(.system(size: 13))
                    Text(voiceMemos.isEmpty ? "Add voice memo" : "Add another voice memo")
                        .font(.sans(13, weight: .regular))
                    Spacer()
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Theme.textPrimary.opacity(0.18),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Folder + label

    @ViewBuilder
    private var folderRow: some View {
        Button(action: { showFolderPicker = true }) {
            HStack(spacing: 10) {
                Text("Folder")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Spacer()
                if let folder = currentFolder {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(folder.colorKey.dotColor)
                            .frame(width: 8, height: 8)
                        Text(folder.name)
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary)
                    }
                } else {
                    Text("None")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var labelField: some View {
        TextField("Label (e.g. morning pages)", text: $label)
            .font(.sans(14, weight: .regular))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive, action: { showDeleteConfirm = true }) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                Text("Delete note")
                    .font(.sans(13, weight: .medium))
            }
            .foregroundStyle(Theme.alertRed.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.alertRed.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.alertRed.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var currentFolder: NoteFolder? {
        guard let id = selectedFolderId else { return nil }
        return store.folders.first { $0.id == id }
    }

    // MARK: - Lifecycle

    private func initializeOnce() {
        guard !initialized else { return }
        noteText = note.body ?? ""
        label = note.label ?? ""
        selectedFolderId = note.folderId
        voiceMemos = note.voiceMemos
        initialized = true
    }

    // MARK: - Actions

    private func handleBack() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        persistNow()
        dismiss()
    }

    private func appendVoiceMemo(_ completed: AudioRecorderService.Completed) {
        let memo = NoteVoiceMemo(
            filename: completed.filename,
            duration: completed.duration
        )
        voiceMemos.append(memo)
        persistNow()
    }

    private func removeVoiceMemo(_ memo: NoteVoiceMemo) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Delete the on-disk file so we don't leak orphaned audio.
        if let url = memo.url {
            try? FileManager.default.removeItem(at: url)
        }
        voiceMemos.removeAll { $0.id == memo.id }
        persistNow()
    }

    // MARK: - Autosave

    /// Debounced textual autosave. Each keystroke bumps a token; after
    /// 500ms of quiet, the trailing task fires the persist iff its
    /// token is still the most recent one.
    private func scheduleAutosave() {
        guard initialized else { return }
        let token = UUID()
        saveDebounceToken = token
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard saveDebounceToken == token else { return }
            persistNow()
        }
    }

    /// Flush local edits to the Store immediately. Used by structural
    /// changes (memo add/remove, folder pick, leaving the screen).
    private func persistNow() {
        guard initialized else { return }
        guard let live = liveNote else { return }

        let trimmedBody = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextBody: String? = trimmedBody.isEmpty ? nil : trimmedBody
        let nextLabel: String? = trimmedLabel.isEmpty ? nil : trimmedLabel

        // Skip the write when nothing changed — avoids needless disk
        // churn from `onChange` firing on no-op edits.
        if live.body == nextBody,
           live.label == nextLabel,
           live.folderId == selectedFolderId,
           live.voiceMemos == voiceMemos {
            return
        }

        var updated = live
        updated.body = nextBody
        updated.label = nextLabel
        updated.folderId = selectedFolderId
        updated.voiceMemos = voiceMemos
        store.updateNote(updated)

        flashSaved()
    }

    private func flashSaved() {
        savedFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            savedFlash = false
        }
    }

    private func delete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Clean any takes added in this session that the persisted note
        // doesn't yet reference — Store.deleteNote handles the rest.
        let persistedFilenames = Set(note.voiceMemos.map(\.filename))
        for memo in voiceMemos where !persistedFilenames.contains(memo.filename) {
            if let url = memo.url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        store.deleteNote(note)
        dismiss()
    }
}
