//
//  VoiceMemoRecorderSheet.swift
//  FrisFocus
//
//  Lightweight recording sheet used by the note detail screen's
//  "Re-record" action. Walks through the same idle → recording →
//  preview states as `NewVoiceMemoFormView` but returns the
//  completed take via callback instead of creating a Note. The
//  caller then attaches the take to whatever note it's editing.
//
//  Cancelling cleans up the on-disk file so we never leak audio.
//

import SwiftUI
import AVFoundation
import UIKit

struct VoiceMemoRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Fired once the user confirms a take with "Use this".
    let onComplete: (AudioRecorderService.Completed) -> Void

    @State private var recorder = AudioRecorderService()
    @State private var player = AudioPlayerService()
    @State private var completed: AudioRecorderService.Completed?
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
                        Button("Use", action: use)
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.alertGreen)
                    }
                }
            }
        }
    }

    // MARK: - Recording

    @ViewBuilder
    private var recordingState: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 36)

            ZStack {
                Circle()
                    .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 1)
                    .frame(width: 220, height: 220)

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

                    Circle()
                        .fill(Theme.alertRed.opacity(0.12))
                        .frame(width: 160, height: 160)
                        .blur(radius: 10)
                }

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

            Text(recorder.elapsed.voiceMemoTimeString)
                .font(.system(size: 42, weight: .light, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)

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

    // MARK: - Preview

    @ViewBuilder
    private func previewState(completed: AudioRecorderService.Completed) -> some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 12)

            VStack(spacing: 18) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
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

            Button(action: reRecord) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
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

            Spacer()
        }
        .padding(.horizontal, 22)
        .onAppear {
            player.load(url: completed.url)
        }
        .onDisappear {
            player.stop()
        }
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

    private func use() {
        guard let completed else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        player.stop()
        onComplete(completed)
        dismiss()
    }

    private func cancel() {
        recorder.cancel()
        player.stop()
        if let completed {
            try? FileManager.default.removeItem(at: completed.url)
        }
        dismiss()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
