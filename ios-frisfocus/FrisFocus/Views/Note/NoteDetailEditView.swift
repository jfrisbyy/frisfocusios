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
    @State private var showLabelField: Bool = false
    @State private var photoItems: [PhotosPickerItem] = []

    @FocusState private var labelFocused: Bool

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

                    if showLabelField || !label.isEmpty {
                        labelField
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
        .onAppear(perform: initializeOnce)
        .onChange(of: noteText) { _, _ in scheduleAutosave() }
        .onChange(of: label) { _, _ in scheduleAutosave() }
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

    // MARK: - Body field

    @ViewBuilder
    private var bodyField: some View {
        TextField(
            "What wants to be written?",
            text: $noteText,
            axis: .vertical
        )
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

    // MARK: - Label field

    @ViewBuilder
    private var labelField: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            TextField("label (e.g. morning pages)", text: $label)
                .focused($labelFocused)
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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

                Button(action: toggleLabelField) {
                    toolIcon("bookmark", active: showLabelField || !label.isEmpty)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Label")

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

    private func toggleLabelField() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            showLabelField.toggle()
        }
        if showLabelField {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                labelFocused = true
            }
        }
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

    private func removePhoto(_ photo: NotePhoto) {
        NotePhotoStore.delete(photo)
        withAnimation(.easeInOut(duration: 0.18)) {
            photos.removeAll { $0.id == photo.id }
        }
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
