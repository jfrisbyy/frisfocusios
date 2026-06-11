//
//  SpeechCaptureService.swift
//  FrisFocus
//
//  On-device speech-to-text for the season-setup conversation. Voice is
//  a pure UI layer: this service produces text that enters the same
//  pipeline as typed input — it never touches the AI contract.
//
//  Wraps `SFSpeechRecognizer` + `AVAudioEngine` for live partial
//  transcripts and a normalized meter level (drives the waveform).
//  Recognition is requested on-device when supported so nothing leaves
//  the phone during dictation.
//

import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechCaptureService {
    /// True while the engine is running and partial results are flowing.
    private(set) var isListening: Bool = false

    /// The live transcript, updated as partial results arrive. The view
    /// hands this to an editable field on stop — mangled proper nouns get
    /// fixed before sending.
    private(set) var transcript: String = ""

    /// Normalized 0…1 input level for the waveform bars.
    private(set) var meterLevel: Double = 0

    /// Set when speech recognition can't run here (no permission, no
    /// recognizer, simulator without audio input). The UI falls back to
    /// the keyboard, which is always present anyway.
    private(set) var failureMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.preferredLanguages.first ?? "en-US"))
        ?? SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Ask for speech + microphone permission. Idempotent.
    func requestPermission() async -> Bool {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    /// Begin live transcription. Clears the previous transcript.
    func start() async {
        failureMessage = nil
        guard await requestPermission() else {
            failureMessage = "Voice needs microphone and speech permission — you can type instead."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            failureMessage = "Speech recognition isn't available right now — type your answer instead."
            return
        }

        stopEngineOnly()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            failureMessage = "Couldn't open the microphone — type your answer instead."
            return
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        request = recognitionRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            failureMessage = "No audio input is available here — type your answer instead."
            return
        }

        transcript = ""
        meterLevel = 0

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            // Compute a quick RMS for the waveform.
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for i in 0..<frames { sum += channel[i] * channel[i] }
            let rms = sqrt(sum / Float(frames))
            let level = Double(min(1, max(0, rms * 14)))
            Task { @MainActor in
                self?.meterLevel = level
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            failureMessage = "Couldn't start listening — type your answer instead."
            return
        }

        isListening = true

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopEngineOnly()
                    self.isListening = false
                }
            }
        }
    }

    /// Stop listening, keeping the transcript for the editable bubble.
    func stop() {
        request?.endAudio()
        stopEngineOnly()
        isListening = false
    }

    /// Stop and throw the transcript away.
    func cancel() {
        stop()
        transcript = ""
        meterLevel = 0
    }

    /// The view takes ownership of the transcript (it moves into the
    /// editable bubble); clear our copy so a new take starts clean.
    func consumeTranscript() -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        meterLevel = 0
        return text
    }

    private func stopEngineOnly() {
        task?.cancel()
        task = nil
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        meterLevel = 0
    }
}
