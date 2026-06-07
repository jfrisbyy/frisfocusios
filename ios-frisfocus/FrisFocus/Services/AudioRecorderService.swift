//
//  AudioRecorderService.swift
//  FrisFocus
//
//  Local voice-memo capture. Wraps `AVAudioRecorder` so the views can
//  drive it with a couple of @MainActor calls and observe the live
//  state — elapsed seconds, the normalised meter level, whether we're
//  currently recording — without touching AVFoundation themselves.
//
//  Recordings live in the app's Documents directory as `<UUID>.m4a`.
//  The Note model stores just the filename so the absolute path can
//  change between app updates without breaking links.
//

import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
    /// True while a recording is in flight.
    private(set) var isRecording: Bool = false

    /// Elapsed seconds since the current take started. Updated 10×/s.
    private(set) var elapsed: TimeInterval = 0

    /// Normalised 0…1 meter level. Drives the small mic-button pulse
    /// and the recording-screen ring.
    private(set) var meterLevel: Float = 0

    /// Filename + duration of the last completed take. Cleared by
    /// `cancel()` or after the caller takes ownership.
    private(set) var lastRecording: Completed?

    /// What was returned by `stop()` — the filename to persist on the
    /// Note plus the take's final duration.
    struct Completed: Equatable {
        let filename: String
        let url: URL
        let duration: TimeInterval
    }

    enum RecorderError: Error, LocalizedError {
        case permissionDenied
        case sessionFailed
        case recorderFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone access is needed to record voice memos."
            case .sessionFailed: return "Couldn't start the audio session."
            case .recorderFailed: return "Couldn't start the recorder."
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?

    // MARK: - Permission

    /// Ask for microphone access if we haven't already. Returns whether
    /// recording is allowed. Idempotent — already-granted permissions
    /// short-circuit without prompting.
    func requestPermission() async -> Bool {
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

    // MARK: - Recording

    func start() async throws {
        let granted = await requestPermission()
        guard granted else { throw RecorderError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            throw RecorderError.sessionFailed
        }

        let filename = "\(UUID().uuidString).m4a"
        let url = Self.documentsDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.isMeteringEnabled = true
            r.prepareToRecord()
            r.record()
            recorder = r
            startedAt = Date()
            elapsed = 0
            meterLevel = 0
            isRecording = true
            lastRecording = Completed(filename: filename, url: url, duration: 0)
            startTimer()
        } catch {
            throw RecorderError.recorderFailed
        }
    }

    /// Stop the current take. Returns the completed recording so the
    /// caller can attach it to a Note. Returns nil if no take was
    /// in progress.
    @discardableResult
    func stop() -> Completed? {
        guard let recorder, isRecording else { return nil }
        recorder.stop()
        stopTimer()

        let duration = elapsed
        let url = recorder.url
        let filename = url.lastPathComponent
        let completed = Completed(filename: filename, url: url, duration: duration)
        isRecording = false
        lastRecording = completed
        self.recorder = nil
        startedAt = nil
        return completed
    }

    /// Stop and discard the current take. Removes the on-disk file so
    /// the Documents directory doesn't accumulate cancelled clips.
    func cancel() {
        if let recorder {
            recorder.stop()
            recorder.deleteRecording()
        }
        stopTimer()
        isRecording = false
        elapsed = 0
        meterLevel = 0
        if let last = lastRecording {
            try? FileManager.default.removeItem(at: last.url)
        }
        lastRecording = nil
        recorder = nil
        startedAt = nil
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
        }
        if let recorder, recorder.isRecording {
            recorder.updateMeters()
            let db = recorder.averagePower(forChannel: 0)
            // -60 dB → 0, 0 dB → 1, clamped.
            let normalized = max(0, min(1, (db + 60) / 60))
            meterLevel = normalized
        }
    }

    // MARK: - Helpers

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Delegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Stop is called explicitly from `stop()` so we don't need to
        // mutate UI state here. Keeping the delegate so AVAudioRecorder
        // won't keep a strong reference to a deallocated proxy.
    }
}
