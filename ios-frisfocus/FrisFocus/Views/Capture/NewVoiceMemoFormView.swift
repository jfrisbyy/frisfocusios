//
//  NewVoiceMemoFormView.swift
//  FrisFocus
//
//  Full-height sheet for capturing a brand-new voice memo Note. Opens
//  in "idle" mode with a large red record button; after the user stops
//  recording the same screen transitions to a preview with play /
//  pause, a scrubber, a re-record link, and optional folder + label
//  fields. Save creates a Note in the Store with the recording attached.
//
//  Cancel always cleans up the on-disk audio file so the Documents
//  directory doesn't accumulate orphan clips.
//

import SwiftUI
import AVFoundation
import UIKit

struct NewVoiceMemoFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    @State private var recorder = AudioRecorderService()
    @State private var player = AudioPlayerService()
    @State private var completed: AudioRecorderService.Completed?
    @State private var label: String = ""
    @State private var selectedFolderId: UUID?
    @State private var showFolderPicker: Bool = false
    @State private var permissionDenied: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paperCream.ignoresSafeArea()

                if let completed {
                    previewState(completed: completed)
                } else {
                    recordingState
                }
            }
            .navigationTitle("Voice memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: cancel)
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if completed != nil {
                        Button("Save", action: save)
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.alertGreen)
                    }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerSheetView(selectedFolderId: $selectedFolderId)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Recording state

    @ViewBuilder
    private var recordingState: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 36)

            recordRing

            Text(recorder.elapsed.voiceMemoTimeString)
                .font(.system(size: 42, weight: .light, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.1), value: recorder.elapsed)

            Text(recorder.isRecording ? "Tap to stop" : "Tap to start recording")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))

            if permissionDenied {
                permissionHint
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private var recordRing: some View {
        ZStack {
            // Static engraved ring
            Circle()
                .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 1)
                .frame(width: 220, height: 220)

            // Live meter ring — only visible while recording
            if recorder.isRecording {
                Circle()
                    .strokeBorder(
                        Theme.alertRed.opacity(0.35 + Double(recorder.meterLevel) * 0.45),
                        lineWidth: 2
                    )
                    .frame(
                        width: 220 + CGFloat(recorder.meterLevel) * 28,
                        height: 220 + CGFloat(recorder.meterLevel) * 28
                    )
                    .animation(.easeInOut(duration: 0.12), value: recorder.meterLevel)
            }

            // Inner subtle pulse glow
            if recorder.isRecording {
                Circle()
                    .fill(Theme.alertRed.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .blur(radius: 10)
            }

            // The record button itself
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(Theme.alertRed)
                        .frame(width: 116, height: 116)
                        .shadow(
                            color: Theme.alertRed.opacity(recorder.isRecording ? 0.35 : 0.18),
                            radius: recorder.isRecording ? 14 : 8,
                            y: 4
                        )

                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 34, height: 34)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
        }
    }

    // MARK: - Preview state

    @ViewBuilder
    private func previewState(completed: AudioRecorderService.Completed) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 12)

                playerCard(completed: completed)

                reRecordButton

                VStack(spacing: 12) {
                    folderRow
                    labelField
                }
                .padding(.top, 8)

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 22)
        }
        .onAppear {
            player.load(url: completed.url)
        }
        .onDisappear {
            player.stop()
        }
    }

    @ViewBuilder
    private func playerCard(completed: AudioRecorderService.Completed) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text("Voice memo · \(completed.duration.voiceMemoTimeString)")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                Spacer()
            }

            HStack(spacing: 16) {
                Button(action: { player.toggle() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle().strokeBorder(Theme.textPrimary.opacity(0.15), lineWidth: 0.5)
                            )
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.textPrimary.opacity(0.1))
                                .frame(height: 4)
                            Capsule()
                                .fill(Theme.sunOuter)
                                .frame(width: proxy.size.width * player.progress, height: 4)
                            Circle()
                                .fill(Theme.sunOuter)
                                .frame(width: 11, height: 11)
                                .offset(x: proxy.size.width * player.progress - 5.5)
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text(player.currentTime.voiceMemoTimeString)
                            .font(.sans(11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        Spacer()
                        Text(completed.duration.voiceMemoTimeString)
                            .font(.sans(11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var reRecordButton: some View {
        Button(action: reRecord) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .regular))
                Text("Re-record")
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(
                Capsule()
                    .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var folderRow: some View {
        Button(action: { showFolderPicker = true }) {
            HStack(spacing: 12) {
                if let folder = currentFolder {
                    Circle()
                        .fill(folder.colorKey.dotColor)
                        .frame(width: 10, height: 10)
                    Text(folder.name)
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    Text("Pick a folder")
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var labelField: some View {
        TextField("Label · e.g. on the walk", text: $label)
            .font(.sans(15, weight: .regular))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var permissionHint: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                Text("Microphone access needed")
                    .font(.sans(13, weight: .medium))
            }
            .foregroundStyle(Theme.alertAmber)
            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.alertAmber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().strokeBorder(Theme.alertAmber.opacity(0.4), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Derived

    private var currentFolder: NoteFolder? {
        guard let id = selectedFolderId else { return nil }
        return store.folders.first { $0.id == id }
    }

    // MARK: - Actions

    private func toggleRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if recorder.isRecording {
            if let take = recorder.stop() {
                completed = take
            }
        } else {
            permissionDenied = false
            Task {
                do {
                    try await recorder.start()
                } catch AudioRecorderService.RecorderError.permissionDenied {
                    permissionDenied = true
                } catch {
                    // Silent — user can try again.
                }
            }
        }
    }

    private func reRecord() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        player.stop()
        if let completed {
            try? FileManager.default.removeItem(at: completed.url)
        }
        completed = nil
    }

    private func cancel() {
        recorder.cancel()
        player.stop()
        if let completed {
            try? FileManager.default.removeItem(at: completed.url)
        }
        dismiss()
    }

    private func save() {
        guard let completed else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Note(
            createdAt: Date(),
            body: nil,
            voiceMemos: [
                NoteVoiceMemo(filename: completed.filename, duration: completed.duration)
            ],
            folderId: selectedFolderId,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel
        )
        store.addNote(note)

        dismiss()
        onSave()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    NewVoiceMemoFormView { }
        .environment(Store())
}
