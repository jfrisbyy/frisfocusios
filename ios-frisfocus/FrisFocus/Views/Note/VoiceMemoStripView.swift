//
//  VoiceMemoStripView.swift
//  FrisFocus
//
//  Compact inline player for an attached voice memo. Play / pause on
//  the left, "Voice memo · 0:42" label, a thin warm-amber progress bar
//  underneath, and an optional × to remove. Each instance spins up its
//  own `AudioPlayerService` so multiple strips on a page don't fight
//  for playback state.
//
//  The shape is the same as a quiet card — used inside note detail
//  screens, inside the new-note form (with × to detach), and inline
//  on the homepage entry summary (without ×).
//

import SwiftUI
import UIKit

struct VoiceMemoStripView: View {
    let url: URL
    let duration: TimeInterval
    /// Provide a closure to render the × remove button. Pass nil for
    /// read-only contexts (the homepage entry summary, for example).
    let onRemove: (() -> Void)?

    @State private var player = AudioPlayerService()
    @State private var loadFailed: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .fill(Theme.alertGreen.opacity(player.isPlaying ? 0.22 : 0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                        .offset(x: player.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(loadFailed)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    Text(displayLabel)
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    Spacer(minLength: 0)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.textPrimary.opacity(0.08))
                            .frame(height: 3)
                        Capsule()
                            .fill(Theme.sunOuter.opacity(0.75))
                            .frame(width: proxy.size.width * player.progress, height: 3)
                            .animation(.linear(duration: 0.08), value: player.progress)
                    }
                }
                .frame(height: 3)
            }

            if let onRemove {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRemove()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove voice memo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear { reload() }
        .onChange(of: url) { _, _ in reload() }
        .onDisappear { player.stop() }
    }

    private var displayLabel: String {
        let totalSeconds = duration > 0 ? duration : player.duration
        return "Voice memo · \(totalSeconds.voiceMemoTimeString)"
    }

    private func reload() {
        loadFailed = !player.load(url: url)
    }

    private func toggle() {
        guard !loadFailed else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        player.toggle()
    }
}

// MARK: - Read-only label

/// Non-interactive voice-memo label used in the homepage NoteEntryView
/// summary. Tapping the parent entry navigates to the detail screen
/// where playback is interactive.
struct VoiceMemoLabelView: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.alertGreen.opacity(0.14))
                    .frame(width: 26, height: 26)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                    .offset(x: 1)
            }
            Text("Voice memo · \(duration.voiceMemoTimeString)")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
