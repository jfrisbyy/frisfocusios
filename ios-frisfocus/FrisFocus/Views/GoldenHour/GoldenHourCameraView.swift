//
//  GoldenHourCameraView.swift
//  FrisFocus
//
//  The strict 5-minute capture flow. No editor, no filters, no drafts —
//  Golden Hour is about showing up, not composing. Tap for a photo,
//  hold for a clip (max 10 s), confirm, post. The countdown never
//  stops ticking, goes urgent under a minute, and when it hits zero the
//  shutter locks for good — the host flips to the (blurred) wall.
//
//  Reuses the app's `CameraService` + `CameraProxyView`, so the cloud
//  simulator gets the same calm placeholder as the main capture flow.
//

import AVKit
import Combine
import SwiftUI
import UIKit

struct GoldenHourCameraView: View {
    let moment: GoldenHourMoment

    @Environment(GoldenHourService.self) private var service
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var camera = CameraService()
    @State private var captured: CaptureResult?
    @State private var isPosting = false

    // Recording state
    @State private var isRecording = false
    @State private var recordStart: Date?
    @State private var recordElapsed: Double = 0
    @State private var pressTimerTask: Task<Void, Never>?

    private let maxRecordSeconds: Double = 10
    private let recordTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var myUserId: String { auth.user?.id ?? "" }
    private var circleName: String { service.circle(moment.circleId)?.name ?? "Your circle" }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraProxyView(camera: camera)
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.65), .clear, .clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                chrome(now: context.date)
            }

            if let captured {
                previewOverlay(captured)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task {
            await camera.requestAccessAndStart()
        }
        .onReceive(recordTimer) { _ in
            guard isRecording, let start = recordStart else { return }
            let elapsed = Date().timeIntervalSince(start)
            recordElapsed = min(elapsed, maxRecordSeconds)
            if elapsed >= maxRecordSeconds {
                stopRecording()
            }
        }
        .onDisappear {
            pressTimerTask?.cancel()
            camera.stop()
        }
    }

    // MARK: - Chrome (countdown + shutter)

    @ViewBuilder
    private func chrome(now: Date) -> some View {
        let remaining = moment.captureClosesAt.timeIntervalSince(now)
        let urgent = remaining <= 60

        VStack(spacing: 0) {
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Golden Hour camera")

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    camera.flipCamera()
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Flip camera")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            // The golden countdown — the heart of the screen.
            VStack(spacing: 6) {
                Text("GOLDEN HOUR · \(circleName.uppercased())")
                    .font(.sans(10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(GoldenTheme.goldBright)
                    .lineLimit(1)

                Text(GoldenHourSchedule.countdownString(until: moment.captureClosesAt, from: now))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(urgent ? Color(hex: 0xF06A52) : GoldenTheme.gold)
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(color: (urgent ? Color(hex: 0xF06A52) : GoldenTheme.gold).opacity(0.45), radius: 14)

                Text("show what you're working on")
                    .font(.serif(14, weight: .regular))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .padding(.top, 14)

            Spacer()

            if isRecording {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xE0454C)).frame(width: 7, height: 7)
                    Text(String(format: "0:%02d / 0:%02d", Int(recordElapsed.rounded()), Int(maxRecordSeconds)))
                        .font(.sans(13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.bottom, 12)
            } else if camera.hasCamera {
                Text("tap for photo · hold for a clip")
                    .font(.sans(12, weight: .regular))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .padding(.bottom, 12)
            }

            shutterButton(remaining: remaining)
                .padding(.bottom, 44)
        }
    }

    // MARK: - Shutter

    private func shutterButton(remaining: TimeInterval) -> some View {
        let captureRemaining = remaining / GoldenHourSchedule.captureWindow
        return ZStack {
            // Golden draining ring — the window itself, always visible.
            GoldenDrainRing(remaining: captureRemaining, lineWidth: 4)
                .frame(width: 92, height: 92)

            // Recording progress (red) rides inside.
            Circle()
                .trim(from: 0, to: isRecording ? recordElapsed / maxRecordSeconds : 0)
                .stroke(Color(hex: 0xE0454C), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 78, height: 78)

            Circle()
                .fill(isRecording ? Color(hex: 0xE0454C) : GoldenTheme.gold)
                .frame(width: isRecording ? 34 : 62, height: isRecording ? 34 : 62)
                .animation(.easeInOut(duration: 0.18), value: isRecording)
        }
        .contentShape(Circle())
        .gesture(shutterGesture)
        .opacity(camera.isReady && remaining > 0 ? 1.0 : 0.45)
        .accessibilityLabel(isRecording ? "Recording. Release to stop." : "Tap to photograph, hold to record")
    }

    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressTimerTask == nil, !isRecording, camera.isReady, captured == nil else { return }
                pressTimerTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    if !Task.isCancelled {
                        startRecording()
                    }
                }
            }
            .onEnded { _ in
                if isRecording {
                    stopRecording()
                } else {
                    pressTimerTask?.cancel()
                    pressTimerTask = nil
                    takePhoto()
                }
                pressTimerTask = nil
            }
    }

    private func takePhoto() {
        guard camera.isReady, captured == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            if let image = await camera.capturePhoto() {
                captured = .photo(image)
            }
        }
    }

    private func startRecording() {
        guard camera.isReady, !isRecording, captured == nil else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        recordElapsed = 0
        recordStart = Date()
        isRecording = true
        camera.startRecording()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let duration = recordElapsed
        camera.stopRecording { url in
            guard let url else { return }
            Task { @MainActor in
                captured = .video(url: url, thumbnail: nil, duration: duration)
            }
        }
    }

    // MARK: - Preview + post

    @ViewBuilder
    private func previewOverlay(_ result: CaptureResult) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch result {
            case .photo(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            case .video(let url, _, _):
                GoldenLoopingPlayer(url: url)
                    .ignoresSafeArea()
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                previewChrome(now: context.date)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func previewChrome(now: Date) -> some View {
        VStack {
            HStack {
                Button {
                    guard !isPosting else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    captured = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Retake")
                            .font(.sans(13, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .disabled(isPosting)

                Spacer()

                Text(GoldenHourSchedule.countdownString(until: moment.captureClosesAt, from: now))
                    .font(.sans(17, weight: .bold).monospacedDigit())
                    .foregroundStyle(GoldenTheme.gold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer()

            if let progress = service.uploadProgress {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(GoldenTheme.gold)
                        .frame(maxWidth: 220)
                    Text("Posting…")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(.bottom, 18)
            }

            Button {
                post()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(isPosting ? "Posting…" : "Post to the wall")
                        .font(.sans(16, weight: .bold))
                }
                .foregroundStyle(GoldenTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .fill(GoldenTheme.goldGradient)
                        .shadow(color: GoldenTheme.gold.opacity(0.4), radius: 12, y: 4)
                )
            }
            .buttonStyle(.plain)
            .disabled(isPosting)
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
            .accessibilityLabel("Post to the Golden Hour wall")
        }
    }

    private func post() {
        guard let result = captured, !isPosting, !myUserId.isEmpty else { return }
        isPosting = true
        Task { @MainActor in
            defer { isPosting = false }
            switch result {
            case .photo(let image):
                guard let data = image.jpegData(compressionQuality: 0.85) else { return }
                let ok = await service.postCapture(
                    circleId: moment.circleId,
                    data: data,
                    mediaKind: .photo,
                    durationSeconds: nil,
                    myUserId: myUserId
                )
                if ok {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    captured = nil
                }
            case .video(let url, _, let duration):
                let compressed = await VideoTranscoder.compressForUpload(sourceURL: url) ?? url
                guard let data = try? Data(contentsOf: compressed) else { return }
                let ok = await service.postCapture(
                    circleId: moment.circleId,
                    data: data,
                    mediaKind: .video,
                    durationSeconds: duration,
                    myUserId: myUserId
                )
                if ok {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    captured = nil
                }
            }
        }
    }
}

// MARK: - Looping preview player

/// An unmuted looping player for the capture preview and full-screen
/// wall viewing — plays a local or signed URL on repeat, holding the
/// playback audio-session claim so sound carries even on silent.
struct GoldenLoopingPlayer: View {
    let url: URL

    @State private var player: AVPlayer?
    @State private var looper: Any?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.black
            }
        }
        .onAppear {
            VideoPlaybackAudio.activate()
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(playerItem: item)
            queue.isMuted = false
            looper = AVPlayerLooper(player: queue, templateItem: item)
            queue.play()
            player = queue
        }
        .onDisappear {
            player?.pause()
            player = nil
            looper = nil
            VideoPlaybackAudio.release()
        }
    }
}
