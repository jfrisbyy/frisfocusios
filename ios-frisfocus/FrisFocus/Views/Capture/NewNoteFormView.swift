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
    @State private var label: String = ""
    @State private var selectedFolderId: UUID?
    @State private var tags: [String] = []
    @State private var photos: [NotePhoto] = []
    @State private var voiceMemos: [NoteVoiceMemo] = []

    @State private var showFolderPicker: Bool = false
    @State private var showTagPicker: Bool = false
    @State private var showLabelField: Bool = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showProofCamera: Bool = false

    @State private var recorder = AudioRecorderService()

    @FocusState private var bodyFocused: Bool
    @FocusState private var labelFocused: Bool

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

                        if showLabelField {
                            labelField
                        }

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                }
                .scrollDismissesKeyboard(.never)
            }
        }
        .safeAreaInset(edge: .bottom) {
            toolStrip
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
        .onAppear {
            // Land the cursor in the page once the sheet settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                bodyFocused = true
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

    @ViewBuilder
    private var bodyField: some View {
        TextField(
            "What wants to be written?",
            text: $noteText,
            axis: .vertical
        )
        .focused($bodyFocused)
        .font(.serifItalic(17, weight: .regular))
        .lineSpacing(7)
        .foregroundStyle(Theme.textPrimary)
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

            Button(action: toggleLabelField) {
                toolIcon("bookmark", active: showLabelField || !label.isEmpty)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Label")

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
        return hasText || !voiceMemos.isEmpty || !photos.isEmpty
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
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)

        let note = Note(
            createdAt: Date(),
            body: trimmedBody.isEmpty ? nil : trimmedBody,
            voiceMemos: voiceMemos,
            photos: photos,
            tags: store.noteTagsEnabled ? tags : [],
            folderId: selectedFolderId,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel
        )
        store.addNote(note)

        dismiss()
        onSave()
    }
}

#Preview {
    NewNoteFormView { }
        .environment(Store())
}
