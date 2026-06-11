//
//  NoteDetailEditView.swift
//  FrisFocus
//
//  Full-page editor for an existing Note. Reached by tapping any
//  entry on the homepage or in the Notes library. The screen mirrors
//  the New Note composer — ruled paper, serif body, photos and voice
//  memos inline, and a quiet tool strip of small icons (mic, photo,
//  folder, tags, label) instead of stacked form rows.
//
//  Autosave: every edit is mirrored to local `@State` and persisted
//  to the Store automatically. Textual edits debounce (0.5s) so we
//  don't thrash the disk on every keystroke; structural edits (folder
//  pick, memo/photo add/remove, tag edits, pin toggle) commit
//  immediately.
//

import PhotosUI
import SwiftUI
import UIKit

/// A captured body + label pair for the note editor's undo stack.
private struct NoteTextSnapshot {
    let body: String
    let label: String
}

struct NoteDetailEditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var noteText: String = ""
    @State private var label: String = ""
    @State private var selectedFolderId: UUID?
    @State private var voiceMemos: [NoteVoiceMemo] = []
    @State private var photos: [NotePhoto] = []
    @State private var tags: [String] = []

    @State private var initialized: Bool = false
    @State private var showFolderPicker: Bool = false
    @State private var showTagPicker: Bool = false
    @State private var showRecorder: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showCaptureSheet: Bool = false
    @State private var photoItems: [PhotosPickerItem] = []

    /// Proof pending removal confirmation — set when the user taps × on a
    /// proof attachment. Ordinary photos remove immediately.
    @State private var pendingProofRemoval: NotePhoto?

    /// Snapshots of body + label for the Undo control. Each entry is the
    /// state *before* a coalesced run of edits, so popping restores the
    /// previous wording.
    @State private var undoStack: [NoteTextSnapshot] = []
    /// Last time we pushed a snapshot — used to coalesce rapid typing
    /// into ~1.2s chunks instead of one entry per keystroke.
    @State private var lastSnapshotAt: Date = .distantPast
    /// Guards the change handlers while we apply an undo so restoring
    /// text doesn't itself get recorded as a new edit.
    @State private var isUndoing: Bool = false

    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool

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
                VStack(alignment: .leading, spacing: 20) {
                    header

                    titleField

                    bodyField

                    if !photos.isEmpty {
                        NotePhotoGridView(photos: photos, onRemove: removePhoto)
                    }

                    voiceMemoBlock

                    if store.noteTagsEnabled && !tags.isEmpty {
                        Button(action: openTagPicker) {
                            NoteTagChipsView(tags: tags)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit tags")
                    }

                    toolStrip
                        .padding(.top, 6)

                    deleteRow
                        .padding(.top, 10)

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
        .edgeSwipeBack()
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
            ToolbarItem(placement: .topBarTrailing) {
                undoToolbarButton
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheetView(selectedFolderId: $selectedFolderId)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTagPicker, onDismiss: persistNow) {
            TagPickerSheetView(selectedTags: $tags)
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
        .confirmationDialog(
            "Remove this proof?",
            isPresented: proofRemovalBinding,
            titleVisibility: .visible
        ) {
            Button("Remove proof", role: .destructive) {
                if let proof = pendingProofRemoval {
                    performRemovePhoto(proof)
                }
                pendingProofRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingProofRemoval = nil }
        } message: {
            Text("This proof will be detached from the note.")
        }
        .onAppear(perform: initializeOnce)
        .onChange(of: noteText) { old, _ in recordUndoSnapshot(previousBody: old, previousLabel: label); scheduleAutosave() }
        .onChange(of: label) { old, _ in recordUndoSnapshot(previousBody: noteText, previousLabel: old); scheduleAutosave() }
        .onChange(of: selectedFolderId) { _, _ in persistNow() }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
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

    /// Quiet undo control — steps back the most recent run of text edits.
    /// Dims to non-interactive when there's nothing left to undo.
    @ViewBuilder
    private var undoToolbarButton: some View {
        Button(action: performUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(undoStack.isEmpty ? 0.22 : 0.6))
        }
        .disabled(undoStack.isEmpty)
        .accessibilityLabel("Undo last edit")
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
        VStack(alignment: .leading, spacing: 8) {
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

            Rectangle()
                .fill(Theme.sunWarm.opacity(0.45))
                .frame(height: 0.5)
                .padding(.top, 2)
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

    // MARK: - Title + body fields

    /// The note's title — larger serif on the same paper so the page
    /// stays one cohesive document. Untitled notes show a quiet
    /// placeholder; return glides into the body.
    @ViewBuilder
    private var titleField: some View {
        TextField("Add a title", text: $label)
            .focused($titleFocused)
            .font(.serif(23, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .submitLabel(.next)
            .onSubmit {
                bodyFocused = true
            }
            .padding(.top, -4)
            .padding(.bottom, -8)
            .accessibilityLabel("Note title")
    }

    @ViewBuilder
    private var bodyField: some View {
        TextField(
            "What wants to be written?",
            text: $noteText,
            axis: .vertical
        )
        .focused($bodyFocused)
        .font(.serifItalic(17, weight: .regular))
        .lineSpacing(6)
        .foregroundStyle(Theme.textPrimary)
        .frame(minHeight: 160, alignment: .topLeading)
        .padding(.vertical, 4)
    }

    // MARK: - Voice memo block

    @ViewBuilder
    private var voiceMemoBlock: some View {
        if !voiceMemos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
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
        }
    }

    // MARK: - Tool strip

    /// The same quiet icon row as the composer — small understated
    /// controls separated from the page by a gold hairline.
    @ViewBuilder
    private var toolStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.sunWarm.opacity(0.35))
                .frame(height: 0.5)

            HStack(spacing: 4) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showRecorder = true
                }) {
                    toolIcon("mic", active: !voiceMemos.isEmpty)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add voice memo")

                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 6,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    toolIcon("photo.on.rectangle", active: !photos.isEmpty)
                }
                .accessibilityLabel("Attach photos")

                folderTool

                if store.noteTagsEnabled {
                    Button(action: openTagPicker) {
                        toolIcon("number", active: !tags.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tags")
                }

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var folderTool: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showFolderPicker = true
        }) {
            if let folder = currentFolder {
                HStack(spacing: 5) {
                    Circle()
                        .fill(folder.colorKey.dotColor)
                        .frame(width: 6, height: 6)
                    Text(folder.name)
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(folder.colorKey.pillText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(folder.colorKey.pillBackground)
                .clipShape(Capsule())
                .frame(height: 44)
            } else {
                toolIcon("folder", active: false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Folder")
    }

    @ViewBuilder
    private func toolIcon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(
                active ? Theme.sunShadow : Theme.textPrimary.opacity(0.55)
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    /// Quiet text-only delete — destructive intent stays available but
    /// no longer shouts from a filled red card.
    @ViewBuilder
    private var deleteRow: some View {
        Button(role: .destructive, action: { showDeleteConfirm = true }) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                Text("Delete note")
                    .font(.sans(12, weight: .regular))
            }
            .foregroundStyle(Theme.alertRed.opacity(0.7))
            .padding(.vertical, 8)
            .contentShape(Rectangle())
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
        photos = note.photos
        tags = note.tags
        initialized = true
    }

    // MARK: - Actions

    private func handleBack() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        persistNow()
        dismiss()
    }

    private func openTagPicker() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showTagPicker = true
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

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let photo = NotePhotoStore.save(image) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    photos.append(photo)
                }
            }
        }
        photoItems = []
        persistNow()
    }

    /// Photos arrive from the grid's × button. Proofs require a confirm
    /// step (they're precious, often the only copy of a moment); ordinary
    /// photos remove instantly as before.
    private func removePhoto(_ photo: NotePhoto) {
        if photo.isProof {
            pendingProofRemoval = photo
            return
        }
        performRemovePhoto(photo)
    }

    private func performRemovePhoto(_ photo: NotePhoto) {
        NotePhotoStore.delete(photo)
        withAnimation(.easeInOut(duration: 0.18)) {
            photos.removeAll { $0.id == photo.id }
        }
        persistNow()
    }

    private var proofRemovalBinding: Binding<Bool> {
        Binding(
            get: { pendingProofRemoval != nil },
            set: { if !$0 { pendingProofRemoval = nil } }
        )
    }

    // MARK: - Undo

    /// Push the pre-edit text state onto the undo stack, coalescing rapid
    /// keystrokes so one entry covers a short burst of typing rather than
    /// every character. No-ops while an undo is being applied.
    private func recordUndoSnapshot(previousBody: String, previousLabel: String) {
        guard initialized, !isUndoing else { return }
        let now = Date()
        if now.timeIntervalSince(lastSnapshotAt) < 1.2,
           let last = undoStack.last,
           last.body == previousBody, last.label == previousLabel {
            return
        }
        if now.timeIntervalSince(lastSnapshotAt) >= 1.2 || undoStack.isEmpty {
            undoStack.append(NoteTextSnapshot(body: previousBody, label: previousLabel))
            if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
            lastSnapshotAt = now
        }
    }

    private func performUndo() {
        guard let snapshot = undoStack.popLast() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isUndoing = true
        withAnimation(.easeInOut(duration: 0.15)) {
            noteText = snapshot.body
            label = snapshot.label
        }
        lastSnapshotAt = .distantPast
        // Let the change handlers fire and bail out before re-arming.
        DispatchQueue.main.async {
            isUndoing = false
            persistNow()
        }
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
    /// changes (memo/photo add/remove, folder pick, tag edits, leaving
    /// the screen).
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
           live.voiceMemos == voiceMemos,
           live.photos == photos,
           live.tags == tags {
            return
        }

        var updated = live
        updated.body = nextBody
        updated.label = nextLabel
        updated.folderId = selectedFolderId
        updated.voiceMemos = voiceMemos
        updated.photos = photos
        updated.tags = tags
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
        // Clean any takes/photos added in this session that the
        // persisted note doesn't yet reference — Store.deleteNote
        // handles the rest.
        let persistedFilenames = Set(note.voiceMemos.map(\.filename))
        for memo in voiceMemos where !persistedFilenames.contains(memo.filename) {
            if let url = memo.url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let persistedPhotos = Set(note.photos.map(\.filename))
        for photo in photos where !persistedPhotos.contains(photo.filename) {
            NotePhotoStore.delete(photo)
        }
        store.deleteNote(note)
        dismiss()
    }
}
