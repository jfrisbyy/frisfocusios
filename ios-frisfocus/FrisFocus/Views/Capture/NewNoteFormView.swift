//
//  NewNoteFormView.swift
//  FrisFocus
//
//  The New Note composer — a full-height writing surface on the same
//  ruled paper as the rest of the journal. No grouped form sections:
//  the cursor lands in the page immediately and you just write.
//
//  A quiet tool strip rides above the keyboard: mic (records in
//  place, multiple takes allowed), photo (attach from the library),
//  folder, tags (only when the user opted in), and label. Save is a
//  warm pill in the top bar, dimmed until the note has any content.
//
//  Cancel cleans up any orphaned voice clips and photo files on disk.
//

import PhotosUI
import SwiftUI
import UIKit

struct NewNoteFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    // The note body lives here as `noteText` so it doesn't shadow
    // `View.body`.
    @State private var noteText: String = ""
    /// The note's title — stored as the note's label so existing notes
    /// and previews pick it up everywhere.
    @State private var title: String = ""
    @State private var selectedFolderId: UUID?
    @State private var tags: [String] = []
    @State private var photos: [NotePhoto] = []
    @State private var voiceMemos: [NoteVoiceMemo] = []
    /// Whether the note saves as pinned — same star as edit mode.
    @State private var isPinned: Bool = false
    @State private var starPulse: Bool = false

    @State private var showFolderPicker: Bool = false
    @State private var showTagPicker: Bool = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showProofCamera: Bool = false

    @State private var recorder = AudioRecorderService()

    /// Snapshots of title + body for the Undo control, coalescing rapid
    /// typing into ~1.2s chunks — mirrors the edit screen exactly.
    @State private var undoStack: [NewNoteTextSnapshot] = []
    @State private var lastSnapshotAt: Date = .distantPast
    @State private var isUndoing: Bool = false

    @FocusState private var titleFocused: Bool

    /// Bridge to the smart body editor (focus + formatting commands).
    @State private var editorController = SmartNoteEditorController()
    /// Whether the formatting options row is open.
    @State private var formatExpanded: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMM d · h:mm a"
        return f
    }()

    var body: some View {
        ZStack {
            RuledPaperBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                            .padding(.top, 16)

                        titleField

                        bodyField

                        if !photos.isEmpty {
                            NotePhotoGridView(photos: photos, onRemove: removePhoto)
                        }

                        if !voiceMemos.isEmpty {
                            memoList
                        }

                        if !tags.isEmpty {
                            NoteTagChipsView(tags: tags)
                        }

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                }
                .scrollDismissesKeyboard(.never)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if formatExpanded {
                    NoteFormatOptionsRow(controller: editorController)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                toolStrip
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheetView(selectedFolderId: $selectedFolderId)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerSheetView(selectedTags: $tags)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showProofCamera) {
            ShareCameraView(
                subject: .note(ShareNoteContext(date: Date(), seasonName: store.currentSeason.name)),
                attachContext: .noteComposer,
                onSavedToNoteComposer: { saved in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        photos.append(saved)
                    }
                }
            )
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .onChange(of: noteText) { old, _ in recordUndoSnapshot(previousBody: old, previousTitle: title) }
        .onChange(of: title) { old, _ in recordUndoSnapshot(previousBody: noteText, previousTitle: old) }
        .onAppear {
            // Land the cursor in the title once the sheet settles —
            // return glides straight into the body.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                titleFocused = true
            }
        }
        .interactiveDismissDisabled(hasContent)
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        HStack(alignment: .center) {
            Button(action: cancel) {
                Text("Cancel")
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
            }
            .buttonStyle(.plain)

            Spacer()

            EyebrowText(text: "New note", opacity: 0.5)

            Spacer()

            undoButton

            pinButton

            Button(action: save) {
                Text("Save")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(hasContent ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(hasContent ? Theme.warmWheat : Color.white.opacity(0.4))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                hasContent ? Theme.sunWarm.opacity(0.65) : Theme.textPrimary.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: hasContent ? Theme.sunWarm.opacity(0.22) : .clear,
                        radius: 5, y: 1
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasContent)
            .animation(.easeInOut(duration: 0.18), value: hasContent)
        }
    }

    // MARK: - Header + body

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(
                text: Self.dateFormatter.string(from: Date()),
                opacity: 0.45
            )
            Rectangle()
                .fill(Theme.sunWarm.opacity(0.45))
                .frame(height: 0.5)
        }
    }

    /// Quiet undo control — steps back the most recent run of typing.
    @ViewBuilder
    private var undoButton: some View {
        Button(action: performUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(undoStack.isEmpty ? 0.22 : 0.6))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(undoStack.isEmpty)
        .accessibilityLabel("Undo last edit")
    }

    /// The same warm star as the editor — the note saves as pinned.
    @ViewBuilder
    private var pinButton: some View {
        Button(action: togglePinned) {
            Image(systemName: isPinned ? "star.fill" : "star")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isPinned ? Theme.sunWarm : Theme.textPrimary.opacity(0.55))
                .scaleEffect(starPulse ? 1.22 : 1.0)
                .shadow(
                    color: isPinned ? Theme.sunWarm.opacity(0.55) : .clear,
                    radius: isPinned ? 6 : 0
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: starPulse)
                .animation(.easeInOut(duration: 0.18), value: isPinned)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "Unpin note" : "Pin note")
    }

    /// The note's title — larger serif on the same paper, so the page
    /// reads as one cohesive document. Return glides into the body.
    @ViewBuilder
    private var titleField: some View {
        TextField("Add a title", text: $title)
            .focused($titleFocused)
            .font(.serif(23, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .submitLabel(.next)
            .onSubmit {
                editorController.focus()
            }
            .padding(.bottom, -6)
            .accessibilityLabel("Note title")
    }

    @ViewBuilder
    private var bodyField: some View {
        SmartNoteEditor(
            text: $noteText,
            placeholder: "What wants to be written?",
            controller: editorController,
            bodySize: 17,
            lineSpacing: 7,
            italic: true
        )
        .frame(minHeight: 140, alignment: .topLeading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var memoList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(voiceMemos) { memo in
                if let url = memo.url {
                    VoiceMemoStripView(
                        url: url,
                        duration: memo.duration,
                        onRemove: { removeMemo(memo) }
                    )
                }
            }
        }
    }

    // MARK: - Tool strip

    /// The quiet row of capture tools pinned above the keyboard. Small
    /// understated icons; the folder control grows into a chip showing
    /// the picked folder's dot + name.
    @ViewBuilder
    private var toolStrip: some View {
        HStack(spacing: 4) {
            // Camera-first — the designed proof camera is the default
            // capture; the library picker stays one tap away.
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showProofCamera = true
            }) {
                toolIcon("camera", active: photos.contains { $0.isProof })
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture a proof")
            .accessibilityHint("Opens the proof camera — post it, or just save it to this note")

            micTool

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
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showTagPicker = true
                }) {
                    toolIcon("number", active: !tags.isEmpty)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tags")
            }

            NoteFormatToggle(expanded: $formatExpanded)

            Spacer(minLength: 0)

            if recorder.isRecording {
                Text(recorder.elapsed.voiceMemoTimeString)
                    .font(.sans(12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.alertRed)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.sunWarm.opacity(0.35))
                .frame(height: 0.5)
        }
        .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
    }

    @ViewBuilder
    private var micTool: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Theme.alertRed : Color.clear)
                    .frame(width: 34, height: 34)
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(
                        recorder.isRecording ? Color.white : Theme.textPrimary.opacity(0.65)
                    )
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record voice memo")
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

    // MARK: - Derived

    private var currentFolder: NoteFolder? {
        guard let id = selectedFolderId else { return nil }
        return store.folders.first { $0.id == id }
    }

    private var hasContent: Bool {
        let hasText = !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || hasTitle || !voiceMemos.isEmpty || !photos.isEmpty
    }

    // MARK: - Actions

    private func toggleRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if recorder.isRecording {
            if let take = recorder.stop() {
                voiceMemos.append(NoteVoiceMemo(filename: take.filename, duration: take.duration))
            }
        } else {
            Task {
                do {
                    try await recorder.start()
                } catch {
                    // Permission denied or session failed — the dedicated
                    // voice-memo form carries the settings hint.
                }
            }
        }
    }

    private func togglePinned() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isPinned.toggle()
        starPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            starPulse = false
        }
    }

    // MARK: - Undo

    /// Push the pre-edit text state onto the undo stack, coalescing
    /// rapid keystrokes into comfortable chunks. Mirrors the editor.
    private func recordUndoSnapshot(previousBody: String, previousTitle: String) {
        guard !isUndoing else { return }
        let now = Date()
        if now.timeIntervalSince(lastSnapshotAt) < 1.2,
           let last = undoStack.last,
           last.body == previousBody, last.title == previousTitle {
            return
        }
        if now.timeIntervalSince(lastSnapshotAt) >= 1.2 || undoStack.isEmpty {
            undoStack.append(NewNoteTextSnapshot(body: previousBody, title: previousTitle))
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
            title = snapshot.title
        }
        lastSnapshotAt = .distantPast
        DispatchQueue.main.async {
            isUndoing = false
        }
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
    }

    private func removePhoto(_ photo: NotePhoto) {
        NotePhotoStore.delete(photo)
        withAnimation(.easeInOut(duration: 0.18)) {
            photos.removeAll { $0.id == photo.id }
        }
    }

    private func removeMemo(_ memo: NoteVoiceMemo) {
        if let url = memo.url {
            try? FileManager.default.removeItem(at: url)
        }
        voiceMemos.removeAll { $0.id == memo.id }
    }

    private func cancel() {
        recorder.cancel()
        for memo in voiceMemos {
            if let url = memo.url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        for photo in photos {
            NotePhotoStore.delete(photo)
        }
        dismiss()
    }

    private func save() {
        guard hasContent else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // A take still rolling when Save is tapped is kept, not lost.
        if recorder.isRecording, let take = recorder.stop() {
            voiceMemos.append(NoteVoiceMemo(filename: take.filename, duration: take.duration))
        }

        let trimmedBody = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let note = Note(
            createdAt: Date(),
            body: trimmedBody.isEmpty ? nil : trimmedBody,
            voiceMemos: voiceMemos,
            photos: photos,
            tags: store.noteTagsEnabled ? tags : [],
            folderId: selectedFolderId,
            label: trimmedTitle.isEmpty ? nil : trimmedTitle,
            isPinned: isPinned
        )
        store.addNote(note)

        dismiss()
        onSave()
    }
}

/// A captured title + body pair for the composer's undo stack.
private struct NewNoteTextSnapshot {
    let body: String
    let title: String
}

#Preview {
    NewNoteFormView { }
        .environment(Store())
}
