//
//  SetupConversationView.swift
//  FrisFocus
//
//  Screen 2 — the voice-first season conversation. Deliberately NOT a
//  chat log: the orb-arc sunrise tracks progress, the AI's current
//  question renders large in the serif app-voice, the prior exchange
//  fades above, and recognized focus areas populate live thread chips.
//
//  Voice is a pure UI layer: speech-to-text produces an EDITABLE
//  transcript that enters the same pipeline as typed input. A keyboard
//  fallback is always one tap away, and the app's replies are text with
//  optional spoken delivery — never forced audio.
//

import SwiftUI
import UIKit

struct SetupConversationView: View {
    @Bindable var viewModel: SeasonSetupViewModel
    let onClose: () -> Void
    /// The way out when the conversation can't run at all. This door needs
    /// a connection and a server round-trip; the quick path needs neither,
    /// so a failure hands the person back to the fork where that door is
    /// waiting. Nil when the flow was opened as a sheet — there's no fork
    /// behind it, and the starter board stays the fallback there.
    var onBuildInAMinute: (() -> Void)? = nil

    @State private var speech = SpeechCaptureService()
    @State private var useKeyboard: Bool = false
    @State private var typedText: String = ""
    /// A finished voice take, editable before sending.
    @State private var transcriptDraft: String = ""
    @State private var showTranscriptEditor: Bool = false
    @State private var confirmExit: Bool = false
    @FocusState private var keyboardFocused: Bool
    @FocusState private var transcriptFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The closing recap and teaching-heavy turns flow as a calm
    /// scrollable thread instead of cramming the one-exchange layout.
    private var isLongReply: Bool {
        viewModel.currentMessage.count > 300
    }

    var body: some View {
        ZStack {
            Theme.paperCream.ignoresSafeArea()
            LinearGradient(
                colors: [Theme.warmWheat, Theme.paperCream],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLongReply {
                    longReplyBody
                } else {
                    standardBody
                }

                if let error = viewModel.errorMessage {
                    failureBanner(error)
                }

                inputBar
            }
        }
        .onChange(of: viewModel.conversationDone) { _, done in
            guard done else { return }
            // Let the orb crest, then advance.
            speech.cancel()
            Task {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : 1.6))
                viewModel.advanceToReview()
            }
        }
        .onDisappear {
            speech.cancel()
            viewModel.stopSpeaking()
        }
        .confirmationDialog(
            "Leave season setup?",
            isPresented: $confirmExit,
            titleVisibility: .visible
        ) {
            Button("Save & exit") {
                viewModel.saveProgress()
                onClose()
            }
            Button("Discard", role: .destructive) {
                viewModel.discardSavedProgress()
                onClose()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Save & exit keeps this conversation so you can pick it back up later.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if speech.isListening { speech.cancel() }
                confirmExit = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .background(Theme.textPrimary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            EyebrowText(text: "Setting your season", opacity: 0.55)

            Spacer()

            HStack(spacing: 4) {
                Button {
                    viewModel.speakReplies.toggle()
                    if !viewModel.speakReplies { viewModel.stopSpeaking() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: viewModel.speakReplies ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(viewModel.speakReplies ? 0.85 : 0.45))
                        .frame(width: 34, height: 38)
                }
                .buttonStyle(.plain)

                Button("Skip") {
                    speech.cancel()
                    viewModel.skipToStarter()
                }
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Standard one-exchange layout

    private var standardBody: some View {
        VStack(spacing: 0) {
            SetupOrbArc(
                progress: viewModel.arcProgress,
                threads: viewModel.threads,
                isThinking: viewModel.isThinking
            )
            .frame(height: 130)
            .padding(.horizontal, 28)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 18) {
                    // Prior exchange, faded above.
                    if let prior = viewModel.priorMessage {
                        Text(prior)
                            .font(.serif(14, weight: .regular))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textPrimary.opacity(0.32))
                            .lineLimit(2)
                            .padding(.horizontal, 40)
                    }

                    if let answer = viewModel.lastAnswer {
                        Text(answer)
                            .font(.sans(14, weight: .regular))
                            .foregroundStyle(Theme.textCream)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.textPrimary.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 40)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // The AI's current question — large, serif, app-voice.
                    if viewModel.currentMessage.isEmpty && viewModel.isThinking {
                        thinkingIndicator
                            .padding(.top, 20)
                    } else {
                        TypewriterText(
                            fullText: viewModel.currentMessage,
                            revealID: viewModel.messageRevealID,
                            font: .serif(23, weight: .medium),
                            color: Theme.textPrimary,
                            alignment: .center,
                            reduceMotion: reduceMotion
                        )
                        .padding(.horizontal, 32)
                    }

                    if viewModel.isThinking && !viewModel.currentMessage.isEmpty {
                        thinkingIndicator
                    }

                    if let teaching = viewModel.teaching {
                        teachingCard(teaching)
                            .padding(.horizontal, 32)
                    }

                    threadChips
                        .padding(.top, 6)
                }
                .padding(.top, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Long-reply scrollable state

    private var longReplyBody: some View {
        VStack(spacing: 0) {
            // Compacted slim bar with the small orb.
            HStack(spacing: 10) {
                SetupMiniOrb()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x7F77DD).opacity(0.5), Theme.sunOuter.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .frame(maxWidth: 90 * viewModel.arcProgress + 20)
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let answer = viewModel.lastAnswer {
                        Text(answer)
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                            .padding(.horizontal, 4)
                    }

                    TypewriterText(
                        fullText: viewModel.currentMessage,
                        revealID: viewModel.messageRevealID,
                        font: .serif(17, weight: .regular),
                        color: Theme.textPrimary.opacity(0.92),
                        alignment: .leading,
                        lineSpacing: 5,
                        reduceMotion: reduceMotion
                    )

                    if let teaching = viewModel.teaching {
                        teachingCard(teaching)
                    }

                    if viewModel.isThinking {
                        thinkingIndicator
                    }

                    threadChips
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Pieces

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.textPrimary.opacity(0.4))
            Text("FrisFocus is listening…")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
    }

    private func teachingCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.sunShadow)
                .padding(.top, 2)
            Text(text)
                .font(.sans(12.5, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.sunWarm.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var threadChips: some View {
        if !viewModel.threads.isEmpty {
            VStack(spacing: 10) {
                EyebrowText(text: "Your season so far", opacity: 0.4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(viewModel.threads) { thread in
                        Text(thread.name)
                            .font(.sans(12, weight: .medium))
                            .foregroundStyle(Color(hex: thread.colorHex).opacity(0.95))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: thread.colorHex).opacity(0.13))
                            .clipShape(Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 40)
                .animation(.spring(duration: 0.4), value: viewModel.threads)
            }
        }
    }

    private func failureBanner(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.sans(12.5, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.alertRed)

            if onBuildInAMinute != nil {
                Text("This door needs a connection. You can build your season in about a minute instead, and talk it through any time later.")
                    .font(.serifItalic(13, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.retry()
                } label: {
                    Text("Try again")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Theme.textPrimary.opacity(0.88))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Offered instead of the generic starter board when there's
                // a fork to go back to: the one-minute build is the same
                // season, made by hand, and it doesn't need the network.
                if let onBuildInAMinute {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onBuildInAMinute()
                    } label: {
                        Text("Build it in about a minute")
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.65))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().strokeBorder(Theme.textPrimary.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        viewModel.skipToStarter()
                    } label: {
                        Text("Start from a simple board")
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.65))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().strokeBorder(Theme.textPrimary.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Input bar

    @ViewBuilder
    private var inputBar: some View {
        VStack(spacing: 10) {
            if !viewModel.answerOptions.isEmpty
                && !viewModel.isThinking
                && !showTranscriptEditor
                && !speech.isListening {
                answerOptionsBar
            }

            if showTranscriptEditor {
                transcriptEditor
            }

            if let speechFailure = speech.failureMessage, !useKeyboard {
                Text(speechFailure)
                    .font(.sans(11.5, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .padding(.horizontal, 32)
            }

            if useKeyboard {
                keyboardRow
            } else {
                voiceRow
            }
        }
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Theme.paperCream.opacity(0), Theme.paperCream],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Tappable short answers for yes/no & confirmation turns. Soft pills
    /// on the parchment; the mic/keyboard stay available beneath them.
    private var answerOptionsBar: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
            alignment: .center,
            spacing: 8
        ) {
            ForEach(viewModel.answerOptions, id: \.self) { option in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if speech.isListening { speech.cancel() }
                    viewModel.send(option)
                } label: {
                    Text(option)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(Theme.sunShadow.opacity(0.3), lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isThinking)
            }
        }
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.spring(duration: 0.35), value: viewModel.answerOptions)
    }

    /// A finished take — live, editable before it's sent so mangled
    /// proper nouns get fixed first.
    private var transcriptEditor: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("tap to edit · send when ready")
                .font(.sans(10.5, weight: .regular))
                .tracking(0.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))

            TextField("Your answer", text: $transcriptDraft, axis: .vertical)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textCream)
                .focused($transcriptFocused)
                .lineLimit(1...6)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.textPrimary.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                Button {
                    transcriptDraft = ""
                    showTranscriptEditor = false
                } label: {
                    Text("Discard")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                .buttonStyle(.plain)

                Button {
                    sendTranscript()
                } label: {
                    HStack(spacing: 6) {
                        Text("Send")
                        Image(systemName: "arrow.up")
                    }
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Theme.sunShadow)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 24)
    }

    private var voiceRow: some View {
        HStack(spacing: 12) {
            // Keyboard fallback — always present, never forced voice.
            Button {
                if speech.isListening { speech.cancel() }
                useKeyboard = true
                keyboardFocused = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    .frame(width: 50, height: 50)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Type instead")

            // The mic — primary, large, inviting.
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if speech.isListening {
                    speech.stop()
                    let text = speech.consumeTranscript()
                    if !text.isEmpty {
                        transcriptDraft = text
                        showTranscriptEditor = true
                    }
                } else {
                    showTranscriptEditor = false
                    transcriptDraft = ""
                    Task { await speech.start() }
                }
            } label: {
                HStack(spacing: 10) {
                    if speech.isListening {
                        waveform
                        Text("Tap to stop")
                            .font(.sans(15, weight: .medium))
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .medium))
                        Text("Tap to speak")
                            .font(.sans(15, weight: .medium))
                    }
                }
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule().fill(
                        speech.isListening
                            ? AnyShapeStyle(Theme.alertRed.opacity(0.92))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Theme.sunOuter, Theme.sunShadow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isThinking || viewModel.conversationDone)
            .opacity(viewModel.isThinking || viewModel.conversationDone ? 0.55 : 1)
            .accessibilityLabel(speech.isListening ? "Stop listening" : "Speak your answer")
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .top) {
            if speech.isListening && !speech.transcript.isEmpty {
                liveTranscript
                    .offset(y: -56)
            }
        }
    }

    /// Live transcript floating above the mic while listening.
    private var liveTranscript: some View {
        Text(speech.transcript)
            .font(.sans(13, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.75))
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Theme.textPrimary.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, 24)
            .transition(.opacity)
    }

    private var waveform: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { index in
                let base: CGFloat = [0.45, 0.8, 1.0, 0.7, 0.5][index]
                Capsule()
                    .fill(Theme.textCream)
                    .frame(width: 3, height: 6 + 16 * base * CGFloat(max(0.15, speech.meterLevel)))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.12), value: speech.meterLevel)
        .accessibilityHidden(true)
    }

    private var keyboardRow: some View {
        HStack(spacing: 10) {
            Button {
                useKeyboard = false
                keyboardFocused = false
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    .frame(width: 50, height: 50)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speak instead")

            TextField("Type your answer…", text: $typedText, axis: .vertical)
                .font(.sans(15, weight: .regular))
                .focused($keyboardFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
                )

            Button {
                sendTyped()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 50, height: 50)
                    .background(Theme.sunShadow)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isThinking)
            .opacity(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isThinking ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Sending

    private func sendTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        typedText = ""
        viewModel.send(text)
    }

    private func sendTranscript() {
        let text = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        transcriptDraft = ""
        showTranscriptEditor = false
        viewModel.send(text)
    }
}
