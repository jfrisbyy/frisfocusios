//
//  NewNoteFormView.swift
//  FrisFocus
//
//  Full-height form sheet for jotting down a Note. The body is a serif
//  italic text field with a small mic button tucked into its
//  bottom-right corner — tap to attach a voice memo without leaving
//  the form. Folder and label fields live below; the folder picker
//  opens its own sheet so users can create folders on the fly.
//
//  Save is dimmed until the note has either text or audio. Cancel
//  cleans up any orphaned voice clip on disk.
//

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
    @State private var showFolderPicker: Bool = false

    @State private var recorder = AudioRecorderService()
    @State private var attachedMemo: AudioRecorderService.Completed?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        TextField(
                            "What wants to be written?",
                            text: $noteText,
                            axis: .vertical
                        )
                        .font(.serifItalic(16, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(6...20)
                        .frame(minHeight: 140, alignment: .topLeading)
                        .padding(.trailing, 44)

                        micButton
                            .padding(.bottom, 2)
                            .padding(.trailing, 0)
                    }
                } header: {
                    Text("Body")
                }

                if let memo = attachedMemo {
                    Section {
                        VoiceMemoStripView(
                            url: memo.url,
                            duration: memo.duration,
                            onRemove: removeAttachedMemo
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Voice memo")
                    }
                }

                Section {
                    folderPickerRow

                    TextField("Label (e.g. morning pages)", text: $label)
                        .font(.sans(15, weight: .regular))
                } header: {
                    Text("Optional")
                } footer: {
                    Text("Pick a folder and label to help group entries later.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paperCream)
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: cancel)
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerSheetView(selectedFolderId: $selectedFolderId)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Mic button

    @ViewBuilder
    private var micButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Theme.alertRed : Color.white)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(
                            recorder.isRecording ? Theme.alertRed.opacity(0.6) : Theme.textPrimary.opacity(0.15),
                            lineWidth: 0.5
                        )
                    )
                    .shadow(
                        color: recorder.isRecording ? Theme.alertRed.opacity(0.35) : .black.opacity(0.05),
                        radius: recorder.isRecording ? 6 : 2,
                        y: 1
                    )

                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(recorder.isRecording ? Color.white : Theme.textPrimary.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if recorder.isRecording {
                Text(recorder.elapsed.voiceMemoTimeString)
                    .font(.sans(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.alertRed)
                    .offset(y: 18)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record voice memo")
    }

    // MARK: - Folder picker

    @ViewBuilder
    private var folderPickerRow: some View {
        Button(action: { showFolderPicker = true }) {
            HStack(spacing: 10) {
                Text("Folder")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let folder = currentFolder {
                    Circle()
                        .fill(folder.colorKey.dotColor)
                        .frame(width: 8, height: 8)
                    Text(folder.name)
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                } else {
                    Text("None")
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
            .font(.sans(15, weight: .regular))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentFolder: NoteFolder? {
        guard let id = selectedFolderId else { return nil }
        return store.folders.first { $0.id == id }
    }

    // MARK: - Derived

    private var canSave: Bool {
        let hasText = !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || attachedMemo != nil
    }

    // MARK: - Actions

    private func toggleRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if recorder.isRecording {
            if let take = recorder.stop() {
                // Drop the previous take (if any) to avoid orphans.
                if let old = attachedMemo {
                    try? FileManager.default.removeItem(at: old.url)
                }
                attachedMemo = take
            }
        } else {
            Task {
                do {
                    try await recorder.start()
                } catch {
                    // Permission denied or session failed — silently
                    // ignore; the dedicated voice-memo form has the
                    // settings hint when the user wants more guidance.
                }
            }
        }
    }

    private func removeAttachedMemo() {
        if let memo = attachedMemo {
            try? FileManager.default.removeItem(at: memo.url)
        }
        attachedMemo = nil
    }

    private func cancel() {
        recorder.cancel()
        if let memo = attachedMemo {
            try? FileManager.default.removeItem(at: memo.url)
        }
        dismiss()
    }

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let trimmedBody = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)

        let note = Note(
            createdAt: Date(),
            body: trimmedBody.isEmpty ? nil : trimmedBody,
            voiceMemos: attachedMemo.map {
                [NoteVoiceMemo(filename: $0.filename, duration: $0.duration)]
            } ?? [],
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
