//
//  SeasonSetupViewModel.swift
//  FrisFocus
//
//  State machine for the season-setup flow (S1):
//  begin → conversation → review → naming → begins.
//
//  Owns the conversation history (user turns + the server-echoed raw
//  assistant turns), the orb-arc progress, the live thread chips, the
//  editable rubric draft, and the optional text-to-speech of the AI's
//  replies. Voice input lives in `SpeechCaptureService`; this type only
//  ever sees text.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class SeasonSetupViewModel {
    enum Stage: Equatable {
        case begin
        case conversation
        case review
        case naming
        case begins
    }

    var stage: Stage = .begin

    // MARK: Conversation state

    /// The AI's current question/turn, rendered large in the serif voice.
    private(set) var currentMessage: String = ""
    /// Bumped each time a fresh reply arrives so the view types it out.
    /// Stays 0 for resumed conversations, which show the last turn in full.
    private(set) var messageRevealID: Int = 0
    /// The user's most recent answer (warm dark bubble under the question).
    private(set) var lastAnswer: String?
    /// The previous AI question, faded above for one-exchange context.
    private(set) var priorMessage: String?
    /// Recognized focus areas — live chips + arc ticks.
    private(set) var threads: [SetupThread] = []
    /// Gentle inline teaching note for this turn, if any.
    private(set) var teaching: String?
    /// True while a backend call is in flight.
    private(set) var isThinking: Bool = false
    /// Set when the backend/model call fails; the view offers retry/skip.
    private(set) var errorMessage: String?
    /// The text whose send failed, preserved so retry doesn't lose words.
    private(set) var pendingText: String?
    /// Flips when the model emits the final rubric; the orb crests, then
    /// the view advances to review.
    private(set) var conversationDone: Bool = false

    /// Orb position along the arc, 0…1. Climbs a step per exchange and
    /// crests on `done`.
    private(set) var arcProgress: Double = 0.06

    /// Optional spoken replies — never forced; off by default.
    var speakReplies: Bool = false

    // MARK: Outputs carried forward

    private(set) var draft: RubricDraft?
    private(set) var suggestedName: String?
    private(set) var suggestedLengthDays: Int?
    /// True when the user skipped the conversation into the starter board.
    private(set) var usedStarter: Bool = false

    private var history: [AIMessage] = []
    private var userTurns: Int = 0
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Flow

    /// Begin → conversation. Fetches the model's opening question.
    /// Starting fresh replaces any saved in-progress conversation.
    func begin() {
        SeasonSetupResumeStore.clear()
        stage = .conversation
        guard history.isEmpty, currentMessage.isEmpty else { return }
        Task { await requestTurn(appending: nil) }
    }

    /// Resume a previously saved conversation, dropping straight back into
    /// the exact spot the user left off.
    func resume() {
        guard let snapshot = SeasonSetupResumeStore.load() else {
            begin()
            return
        }
        history = snapshot.history
        currentMessage = snapshot.currentMessage
        lastAnswer = snapshot.lastAnswer
        priorMessage = snapshot.priorMessage
        threads = snapshot.threads
        teaching = snapshot.teaching
        arcProgress = snapshot.arcProgress
        userTurns = snapshot.userTurns
        stage = .conversation
    }

    /// Send a user answer (typed or transcribed — same pipeline).
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        Task { await requestTurn(appending: trimmed) }
    }

    /// Retry the failed call (re-sends `pendingText` if a send failed,
    /// or re-fetches the opener).
    func retry() {
        let text = pendingText
        pendingText = nil
        errorMessage = nil
        Task { await requestTurn(appending: text) }
    }

    /// Discard the saved in-progress conversation (the "Discard" exit).
    func discardSavedProgress() {
        SeasonSetupResumeStore.clear()
    }

    /// Persist the current in-progress conversation so it can be resumed.
    /// No-op once the rubric is produced (the flow advances to review).
    func saveProgress() {
        guard !conversationDone, stage == .conversation else { return }
        guard !history.isEmpty else { return }
        let snapshot = SetupConversationSnapshot(
            history: history,
            currentMessage: currentMessage,
            lastAnswer: lastAnswer,
            priorMessage: priorMessage,
            threads: threads,
            teaching: teaching,
            arcProgress: arcProgress,
            userTurns: userTurns,
            savedAt: Date()
        )
        SeasonSetupResumeStore.save(snapshot)
    }

    /// Skip the conversation — sensible starter board, straight to review.
    func skipToStarter() {
        SeasonSetupResumeStore.clear()
        synthesizer.stopSpeaking(at: .immediate)
        draft = RubricDraft.starter()
        usedStarter = true
        suggestedName = nil
        suggestedLengthDays = 90
        stage = .review
    }

    /// Return to the guided conversation after landing on the starter board
    /// (e.g. the user skipped by accident). Drops the starter draft and
    /// restores the conversation — resuming the in-progress thread if one
    /// was underway, or opening a fresh one otherwise.
    func returnToGuidedSetup() {
        guard usedStarter else { return }
        synthesizer.stopSpeaking(at: .immediate)
        usedStarter = false
        draft = nil
        suggestedName = nil
        suggestedLengthDays = nil
        stage = .conversation
        if history.isEmpty && currentMessage.isEmpty && !isThinking {
            Task { await requestTurn(appending: nil) }
        }
    }

    /// Called by the conversation view after the crest animation lands.
    func advanceToReview() {
        guard conversationDone, draft != nil else { return }
        synthesizer.stopSpeaking(at: .immediate)
        stage = .review
    }

    /// Review → naming.
    func advanceToNaming() {
        stage = .naming
    }

    /// Naming → back to review (the back chevron).
    func backToReview() {
        stage = .review
    }

    /// Freeze the rubric into the Store and land on the closing screen.
    /// After this, daily scoring is local math — no further AI calls.
    func lockIn(store: Store, name: String, lengthDays: Int) {
        guard let draft else { return }
        store.startSeason(from: draft, name: name, lengthDays: lengthDays)
        SeasonSetupResumeStore.clear()
        stage = .begins
    }

    /// Mutable access for the review screen's edits.
    func updateDraft(_ transform: (inout RubricDraft) -> Void) {
        guard var current = draft else { return }
        transform(&current)
        draft = current
    }

    var draftBinding: RubricDraft {
        get { draft ?? RubricDraft.starter() }
        set { draft = newValue }
    }

    // MARK: - Backend turn

    private func requestTurn(appending userText: String?) async {
        errorMessage = nil
        isThinking = true

        var attempt = history
        if let userText {
            attempt.append(.user(userText))
        }

        do {
            let envelope = try await SeasonSetupAI.send(history: attempt)
            // Commit history only on success so a retry replays cleanly.
            history = attempt
            history.append(.assistant(envelope.raw))

            if let userText {
                userTurns += 1
                lastAnswer = userText
                priorMessage = currentMessage.isEmpty ? nil : currentMessage
            }

            let reply = envelope.reply
            currentMessage = reply.message
            messageRevealID += 1
            teaching = reply.teaching

            // Threads are cumulative from the server; keep first-seen arc
            // positions so ticks stay planted while the orb climbs.
            let incoming = reply.threads ?? []
            var merged = threads
            for wire in incoming {
                let key = wire.name.lowercased()
                if !merged.contains(where: { $0.id == key }) {
                    merged.append(
                        SetupThread(
                            name: wire.name,
                            colorHex: wire.colorHint ?? "#7F77DD",
                            arcPosition: min(0.92, arcProgress + 0.05)
                        )
                    )
                }
            }
            threads = merged

            if reply.done == true, let wireRubric = reply.rubric {
                draft = RubricDraft(wire: wireRubric)
                suggestedName = reply.suggestedName
                suggestedLengthDays = reply.suggestedLengthDays ?? 90
                conversationDone = true
                arcProgress = 1.0
                // The rubric exists now — the conversation is no longer a
                // resumable thing; the flow advances to review.
                SeasonSetupResumeStore.clear()
            } else {
                // Glide up a step per exchange; never quite crest early.
                arcProgress = min(0.92, 0.06 + Double(userTurns + 1) * 0.085)
                // Quietly keep progress after every successful exchange.
                saveProgress()
            }

            if speakReplies {
                speak(reply.message)
            }
        } catch {
            pendingText = userText
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Something interrupted the conversation."
            print("[SeasonSetup] turn failed: \(error)")
        }

        isThinking = false
    }

    // MARK: - Optional TTS

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.95
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
