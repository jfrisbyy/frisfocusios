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
    /// Short tappable answers for yes/no or confirmation turns. Empty for
    /// open-ended questions and cleared while a call is in flight.
    private(set) var answerOptions: [String] = []
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

    /// The warm-start envelope, set by the flow before `begin()`. Sent on
    /// the OPENING turn only (the running history carries the context
    /// forward after that), so the conversation never starts cold.
    var coldStartContext: ColdStartContext?

    // MARK: Outputs carried forward

    private(set) var draft: RubricDraft?
    private(set) var suggestedName: String?
    private(set) var suggestedLengthDays: Int?
    /// A concrete end date the user mentioned during setup ("end on Oct
    /// 12"), if any — pre-selects the date-ending mode on the final screen.
    private(set) var suggestedEndDate: Date?
    /// True when the user signalled an open-ended season ("no end date",
    /// "until I'm done") — pre-selects open-ended on the final screen.
    private(set) var suggestedOpenEnded: Bool = false
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

        // If the saved conversation had already reached its rubric, the
        // person was somewhere on the review or naming screens when they
        // left. Rebuild the season from the assistant's own last turn —
        // `content` is the canonical JSON the server returned — and put
        // them back in front of it rather than in front of a finished
        // conversation with no way forward.
        guard let last = history.last(where: { $0.role == "assistant" }),
              let data = last.content.data(using: .utf8),
              let reply = try? JSONDecoder().decode(SetupWireReply.self, from: data),
              reply.done == true, let wireRubric = reply.rubric else { return }
        draft = RubricDraft(wire: wireRubric)
        suggestedName = reply.suggestedName
        suggestedLengthDays = reply.suggestedLengthDays ?? 90
        suggestedOpenEnded = reply.suggestedOpenEnded ?? false
        suggestedEndDate = Self.parseEndDate(reply.suggestedEndDate)
        conversationDone = true
        arcProgress = 1.0
        stage = .review
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
        guard stage == .conversation || stage == .review || stage == .naming else { return }
        // A conversation the person has not spoken in is not a
        // conversation. This used to require only a non-empty history,
        // which is true the moment the OPENER lands — so tapping Begin,
        // reading one sentence and leaving created a "saved conversation"
        // holding nothing, and the next visit hid the Begin button behind
        // a destructive "Start fresh?" confirmation to protect it.
        guard userTurns > 0 else { return }
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
    ///
    /// This used to clear the saved conversation on its way past, so a
    /// button labelled just "Skip", sitting in the header at 50% opacity
    /// next to the speaker toggle, destroyed ten minutes of conversation
    /// with one tap and no confirmation — while the exit button two
    /// inches away carefully asked first. `returnToGuidedSetup` exists
    /// precisely so skipping can be undone, and it cannot undo anything
    /// that has been erased.
    func skipToStarter() {
        synthesizer.stopSpeaking(at: .immediate)
        draft = RubricDraft.starter()
        usedStarter = true
        suggestedName = nil
        suggestedLengthDays = 90
        suggestedEndDate = nil
        suggestedOpenEnded = true
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
        suggestedEndDate = nil
        suggestedOpenEnded = false
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
        saveProgress()
    }

    /// Review → naming.
    func advanceToNaming() {
        stage = .naming
        saveProgress()
    }

    /// Naming → back to review (the back chevron).
    func backToReview() {
        stage = .review
    }

    /// Freeze the rubric into the Store and land on the closing screen.
    /// After this, daily scoring is local math — no further AI calls.
    func lockIn(store: Store, name: String, endMode: SeasonEndMode, endDate: Date?) {
        guard let draft else { return }
        // One-season rule: a cold-start user's provisional season is edited
        // IN PLACE (same id, dates, and log history) rather than replaced,
        // so the conversation never spawns a parallel first season.
        // Everyone else freezes a brand-new season as before.
        if store.currentSeason.isProvisional {
            store.editProvisionalSeason(from: draft, name: name, endMode: endMode, endDate: endDate)
        } else {
            store.startSeason(from: draft, name: name, endMode: endMode, endDate: endDate)
        }
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
        // Options belong to the turn just answered — drop them while the
        // next turn is being fetched so stale cards never linger.
        answerOptions = []

        var attempt = history
        if let userText {
            attempt.append(.user(userText))
        }

        // The envelope rides only on the opener; once the model's first
        // (context-aware) turn is in history, replaying it keeps context.
        let contextForTurn = attempt.isEmpty ? coldStartContext : nil

        do {
            let envelope = try await SeasonSetupAI.send(history: attempt, coldStartContext: contextForTurn)
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
            // Offer tappable answers only for genuine yes/no / confirmation
            // turns, and never once the conversation has produced a rubric.
            answerOptions = reply.done == true
                ? []
                : (reply.answerOptions ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(3)
                    .map { $0 }

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
                suggestedOpenEnded = reply.suggestedOpenEnded ?? false
                suggestedEndDate = Self.parseEndDate(reply.suggestedEndDate)
                conversationDone = true
                arcProgress = 1.0
                // The snapshot used to be cleared right here, the moment
                // the rubric arrived — while the draft existed only in
                // memory and `saveProgress` had already stopped writing.
                // A crash, an OS memory kill, or a force-quit anywhere on
                // the review or naming screens destroyed the entire
                // conversation AND the finished season, with nothing on
                // disk and no resume offered anywhere. That is the most
                // invested moment in the whole flow. It is kept until
                // lock-in now, and `resume()` rebuilds the draft from
                // this same turn.
                saveProgress()
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
            Log.seasonSetup.error("turn failed: \(error)")
        }

        isThinking = false
    }

    /// Parse an ISO `yyyy-MM-dd` end date from the setup guide into a
    /// local `Date` at start of day. Returns nil for missing / unparseable
    /// values or dates already in the past.
    private static func parseEndDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: raw) else { return nil }
        let day = Calendar.current.startOfDay(for: parsed)
        return day > Calendar.current.startOfDay(for: Date()) ? day : nil
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
