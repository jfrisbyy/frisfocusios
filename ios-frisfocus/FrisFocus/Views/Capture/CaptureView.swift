//
//  CaptureView.swift
//  FrisFocus
//
//  Snapchat / Instagram-style story capture.
//
//   - Tap the shutter → photo (quick flash-of-white + soft haptic).
//   - Press and hold the shutter → video, up to 30 s, with a glowing
//     red progress ring and a live timer.
//   - Double-tap anywhere to flip the camera.
//   - Pinch to zoom.
//   - Tap to set focus (yellow square pulse).
//
//  On real hardware this drives an `AVCaptureSession` with both
//  `AVCapturePhotoOutput` and `AVCaptureMovieFileOutput`. In the cloud
//  simulator there is no physical camera; `CameraProxyView` falls back
//  to a calm placeholder and the shutter is disabled so nothing
//  crashes.
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - Mode

enum CaptureMode {
    case generalPost
    /// A moment posted into a circle's story. `task` is the optional
    /// "earned" badge — set when launched from a finished task (or a
    /// held task), `nil` for a general circle moment opened from the
    /// always-available "Add to story" button.
    case circleClip(circle: FFCircle, task: CircleTask?)
    /// A proof posted to a circle event. Behaves like a circle clip
    /// (posts into the circle's story) but also files under the event
    /// and carries the event tag.
    case eventProof(circle: FFCircle, event: CircleEvent, task: CircleTask?)

    var contextChip: (task: String?, circle: String)? {
        switch self {
        case .generalPost:
            return nil
        case .circleClip(let circle, let task):
            return (task?.title, circle.name)
        case .eventProof(let circle, let event, _):
            return (event.title, circle.name)
        }
    }
}

// MARK: - Capture result

/// What a successful capture produces. The editor branches on this to
/// either show the still + filters or the first-frame thumbnail of the
/// recorded video + a tinted overlay.
enum CaptureResult: Equatable, Identifiable {
    case photo(UIImage)
    case video(url: URL, thumbnail: UIImage?, duration: Double)

    /// Stable per-instance id so `.fullScreenCover(item:)` treats each
    /// new capture as a fresh presentation. We don't want SwiftUI to
    /// reuse the old cover body for a different photo.
    var id: String {
        switch self {
        case .photo(let image):
            return "photo-\(ObjectIdentifier(image).hashValue)"
        case .video(let url, _, _):
            return "video-\(url.absoluteString)"
        }
    }
}

// MARK: - CaptureView

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    let mode: CaptureMode
    /// When the camera is launched from a task / to-do card, this is the
    /// sticker that should already be placed on the shot — seeded into
    /// the review editor's canvas the moment a capture lands. `nil` for a
    /// blank capture (the user can still add stickers via "Add task").
    var initialTaskSticker: TaskStickerBlock? = nil
    /// When launched from a friend's hub via "Send a proof," this
    /// friend is preselected as the private recipient in the review's
    /// destination picker.
    var initialDirectFriendId: UUID? = nil
    /// Live Proofs path: when set, the finished proof is sent to exactly
    /// one real account through this async closure (and the audience
    /// chooser is hidden) instead of writing to the local store.
    /// `liveProofRecipientName` labels the fixed destination chip.
    var liveProofRecipientName: String? = nil
    /// Returns whether the proof reached the thread. It used to return
    /// `Void`, so the review sheet announced "Proof sent" unconditionally
    /// — including for a send the service had refused outright.
    var onSendLiveProof: ((_ data: Data, _ isVideo: Bool, _ duration: Double?, _ caption: String?) async -> Bool)? = nil

    /// The app-wide shared camera — pre-warmed by hosts the moment the
    /// open-camera gesture begins, so the viewfinder is live (not
    /// warming) by the time this view lands on screen.
    private var camera: CameraService { .shared }
    @State private var captureResult: CaptureResult?
    @State private var showPermissionDenied: Bool = false

    // Draft state — a saved editor session the user can resume. The chip
    // sits in the shutter row; tapping it restores the whole composition.
    @State private var hasDraft: Bool = false
    @State private var draftThumb: UIImage?
    @State private var restoredDraft: CaptureEditorDraft?

    // Shutter / gesture state
    @State private var isRecording: Bool = false
    @State private var recordStart: Date?
    @State private var recordElapsed: Double = 0
    @State private var pressTimerTask: Task<Void, Never>?
    /// A recording that continues with no finger on the shutter. Set by
    /// dragging up past the lock threshold; cleared when the recording
    /// ends.
    @State private var isLocked: Bool = false
    /// 0…1 travel toward the lock, for the affordance above the shutter.
    @State private var lockProgress: CGFloat = 0
    /// The finger is still down after the recording already ended (the
    /// 30 s cap fired, or a locked recording was stopped). Without this,
    /// `onEnded` took its not-recording branch and fired a PHOTO that
    /// overwrote the video the person had just finished recording.
    @State private var suppressPhotoOnRelease: Bool = false
    @State private var showHint: Bool = true

    // Visual effects
    @State private var flashOpacity: Double = 0
    @State private var focusPoint: CGPoint?
    @State private var focusVisible: Bool = false
    @State private var pinchBase: CGFloat = 1.0
    /// Zoom at the moment recording began — the anchor the hold-and-slide
    /// zoom ramps from, Snapchat-style.
    @State private var recordZoomBase: CGFloat = 1.0

    private let maxRecordSeconds: Double = 30
    private let recordTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                CameraProxyView(camera: camera)
                    .ignoresSafeArea()
                    .gesture(pinchGesture)
                    .simultaneousGesture(tapToFocusGesture(in: geo.size))
                    .simultaneousGesture(doubleTapGesture)

                // Yellow focus reticle.
                if let pt = focusPoint, focusVisible {
                    focusReticle
                        .position(pt)
                        .allowsHitTesting(false)
                }

                // Vignette behind chrome.
                LinearGradient(
                    colors: [Color.black.opacity(0.55), .clear, .clear, Color.black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // Photo flash.
                Color.white.opacity(flashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 18)
                        .padding(.top, 8)

                    if let chip = mode.contextChip {
                        contextChip(task: chip.task, circle: chip.circle)
                            .padding(.top, 16)
                    }

                    Spacer()

                    if isRecording {
                        recordingTimer
                            .padding(.bottom, 12)
                    } else if showHint && camera.hasCamera {
                        hint
                            .padding(.bottom, 12)
                    }

                    shutterRow
                        .padding(.horizontal, 24)
                        .padding(.bottom, 38)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            refreshDraftState()
            await camera.requestAccessAndStart()
            if camera.authorization == .denied {
                showPermissionDenied = true
            }
            // Get the microphone question answered while nothing is
            // recording. It used to be asked inside startRecording,
            // which put a system alert in the middle of the start
            // sequence and made the first-ever clip unrecoverable.
            await camera.primeMicrophonePermission()

            // Fade the gesture hint after a beat.
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.5)) { showHint = false }
        }
        .onReceive(recordTimer) { _ in
            guard isRecording, let start = recordStart else { return }
            let elapsed = Date().timeIntervalSince(start)
            recordElapsed = min(elapsed, maxRecordSeconds)
            if elapsed >= maxRecordSeconds {
                // The finger is still down. Whatever release follows is
                // the end of THIS recording, not a new photo.
                suppressPhotoOnRelease = true
                stopRecording()
            }
        }
        .onChange(of: camera.recordingState) { _, state in
            guard state == .idle, isRecording else { return }
                // A recording can end without anyone asking: a phone
                // call or another app seizes the camera, the session
                // hits a runtime error, or the app leaves the
                // foreground. AVFoundation finalizes the file and goes
                // idle, but nothing told this view — so the ring kept
                // sweeping to the cap over a session that had stopped,
                // and the release fired a photo instead. `stopRecording`
                // clears `isRecording` before the delegate lands, so
                // reaching here with it still set means the end was not
                // ours.
            isRecording = false
            isLocked = false
            lockProgress = 0
            recordStart = nil
            recordElapsed = 0
            suppressPhotoOnRelease = true
            pinchBase = camera.currentZoom
        }
        .onDisappear {
            pressTimerTask?.cancel()
            camera.stop()
        }
        .alert("Camera access needed", isPresented: $showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) { dismiss() }
        } message: {
            Text("FrisFocus uses the camera to share a moment from your day. You can turn it on in Settings.")
        }
        .fullScreenCover(item: $captureResult) { result in
            CaptureReviewView(
                result: result,
                mode: mode,
                onPosted: {
                    captureResult = nil
                    restoredDraft = nil
                    dismiss()
                },
                onRetake: {
                    captureResult = nil
                    restoredDraft = nil
                    refreshDraftState()
                },
                initialTaskSticker: initialTaskSticker,
                initialDirectFriendId: initialDirectFriendId,
                liveProofRecipientName: liveProofRecipientName,
                onSendLiveProof: onSendLiveProof,
                initialDraftState: restoredDraft
            )
            .environment(store)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            chromeButton(systemName: "xmark") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }
            .accessibilityLabel("Close capture")

            Spacer()

            HStack(spacing: 10) {
                chromeButton(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    camera.toggleFlash()
                }
                .accessibilityLabel(camera.isFlashOn ? "Flash on" : "Flash off")

                chromeButton(systemName: "camera.rotate") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    camera.flipCamera()
                }
                .accessibilityLabel("Flip camera")
            }
        }
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context chip

    private func contextChip(task: String?, circle: String) -> some View {
        HStack(spacing: 8) {
            if let task {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                Text(task)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("·")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(circle)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.78))
            } else {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC59A5C))
                Text(circle)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.45)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.map { "Earned \($0) in \(circle)" } ?? "Adding to \(circle)")
    }

    // MARK: - Hint / timer

    private var hint: some View {
        Text("hold to record · tap for photo")
            .font(.sans(12, weight: .regular))
            .tracking(0.6)
            .foregroundStyle(Color.white.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .transition(.opacity)
    }

    private var recordingTimer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: 0xE0454C))
                .frame(width: 7, height: 7)
            Text(formatTime(recordElapsed) + " / " + formatTime(maxRecordSeconds))
                .font(.sans(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "0:%02d", total)
    }

    // MARK: - Shutter row

    private var shutterRow: some View {
        HStack {
            if hasDraft {
                draftChip
            } else {
                Color.clear.frame(width: 54, height: 54)
            }
            Spacer()
            shutterButton
            Spacer()
            Color.clear.frame(width: 54, height: 54)
        }
    }

    /// A small thumbnail of the saved draft — tap to resume the edit
    /// exactly where it was left, captions / filter / stickers intact.
    private var draftChip: some View {
        Button(action: openDraft) {
            VStack(spacing: 4) {
                ZStack {
                    if let draftThumb {
                        Image(uiImage: draftThumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.15)
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 1.4)
                )

                Text("Draft")
                    .font(.sans(10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.4), radius: 2, y: 1)
            }
            .frame(width: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel("Resume draft")
    }

    // MARK: - Draft actions

    private func refreshDraftState() {
        hasDraft = CaptureDraftStore.hasDraft
        draftThumb = hasDraft ? CaptureDraftStore.thumbnail() : nil
    }

    /// Restore the saved draft into the editor.
    private func openDraft() {
        guard let draft = CaptureDraftStore.load() else {
            hasDraft = false
            draftThumb = nil
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        restoredDraft = draft
        captureResult = draft.result
    }

    private var shutterButton: some View {
        ZStack {
            // Progress ring while recording.
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 4)
                .frame(width: 86, height: 86)

            Circle()
                .trim(from: 0, to: isRecording ? recordElapsed / maxRecordSeconds : 0)
                .stroke(
                    Color(hex: 0xE0454C),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 86, height: 86)
                .animation(.linear(duration: 0.05), value: recordElapsed)

            // Outer ring (cream)
            Circle()
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 4)
                .frame(width: 78, height: 78)
                .scaleEffect(isRecording ? 1.10 : 1.0)
                .animation(.easeInOut(duration: 0.18), value: isRecording)

            // Inner disc (turns red while recording).
            Circle()
                .fill(isRecording ? Color(hex: 0xE0454C) : Color.white)
                .frame(width: isRecording ? 36 : 64, height: isRecording ? 36 : 64)
                .clipShape(isRecording ? AnyShape(RoundedRectangle(cornerRadius: 8)) : AnyShape(Circle()))
                .animation(.easeInOut(duration: 0.18), value: isRecording)
        }
        .contentShape(Circle())
        .gesture(shutterGesture)
        // A locked recording has no finger on it, so it needs an
        // ordinary tap target to stop.
        .onTapGesture { if isLocked { stopRecording() } }
        .overlay(alignment: .top) { lockAffordance }
        .accessibilityLabel(accessibilityShutterLabel)
        // Hold-to-record was unreachable with VoiceOver: a drag gesture
        // is not something the rotor can perform. These name both video
        // actions explicitly.
        .accessibilityAction(named: isRecording ? "Stop recording" : "Record video") {
            if isRecording { stopRecording() } else { startRecording() }
        }
        .opacity(camera.isReady ? 1.0 : 0.45)
    }

    private var accessibilityShutterLabel: String {
        if isLocked { return "Recording hands-free. Tap to stop." }
        if isRecording { return "Recording. Release to stop, or slide up to lock." }
        return "Tap to photograph, hold to record"
    }

    /// The lock target that rises above the shutter while recording.
    ///
    /// Drawn above the shutter rather than in the HUD, because it has to
    /// appear exactly where the finger is already travelling — the whole
    /// gesture is "keep going up".
    @ViewBuilder
    private var lockAffordance: some View {
        if isRecording {
            VStack(spacing: 4) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: isLocked ? 15 : 13, weight: .semibold))
                    .foregroundStyle(
                        isLocked ? Color(hex: 0xE0454C) : Color.white.opacity(0.55 + 0.45 * lockProgress)
                    )
                    .scaleEffect(1 + 0.25 * lockProgress)
                if !isLocked {
                    Text("Slide up to lock")
                        .font(.sans(10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35 + 0.5 * lockProgress))
                        .fixedSize()
                }
            }
            .padding(.bottom, 10)
            .offset(y: -(lockTravel * 0.62) - 34 * lockProgress)
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.15), value: lockProgress)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isLocked)
        }
    }

    /// How far up the finger must travel to lock a recording hands-free.
    /// Comfortably past a stray drift, comfortably short of a stretch.
    private var lockTravel: CGFloat { 90 }

    private var shutterGesture: some Gesture {
        // Use a DragGesture with minimumDistance 0 so we get reliable
        // onChanged-on-press and onEnded-on-release without UIKit-level
        // long-press timing quirks. We arm the recording start after a
        // 220 ms hold so a quick tap fires a photo instead.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isRecording {
                    let rise = -value.translation.height

                    // The first `lockTravel` points of upward travel now
                    // mean "lock", not "zoom". Both gestures want the
                    // same axis, and hands-free recording is the one
                    // people reach for — zoom simply starts once the
                    // lock threshold is passed, so nothing is lost.
                    if !isLocked {
                        lockProgress = max(0, min(1, rise / lockTravel))
                        if rise >= lockTravel {
                            lockRecording()
                        }
                        return
                    }

                    // Once locked the finger is gone, so any drag that
                    // arrives is a NEW touch starting at zero travel —
                    // including the tap that stops the recording. Feeding
                    // that to the zoom would yank it to
                    // `recordZoomBase - lockTravel/110` on every stop.
                    // Zoom during a locked recording is the pinch
                    // gesture's job, which starts from the live value.
                    return
                }
                guard pressTimerTask == nil, camera.isReady else { return }
                pressTimerTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    // Clear the slot from inside the task as well. It
                    // used to be cleared only in onEnded, so any gesture
                    // sequence that never delivered one (a system
                    // interruption, a cancelled touch) left the slot
                    // occupied and hold-to-record dead for the rest of
                    // the session.
                    pressTimerTask = nil
                    startRecording()
                }
            }
            .onEnded { _ in
                pressTimerTask?.cancel()
                pressTimerTask = nil
                lockProgress = 0

                // A locked recording outlives the finger. Releasing is
                // not a stop and certainly not a photo.
                if isLocked { return }

                if isRecording {
                    stopRecording()
                } else if suppressPhotoOnRelease {
                    // The recording already ended under the finger (the
                    // 30 s cap). This release closes that recording; it
                    // is not a request for a photo.
                    suppressPhotoOnRelease = false
                } else {
                    takePhoto()
                }
            }
    }

    /// Hand the recording over to the lock: it keeps running with no
    /// finger on the shutter, and a tap stops it.
    private func lockRecording() {
        guard isRecording, !isLocked else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Hand the current zoom to pinch, which takes over from here.
        pinchBase = camera.currentZoom
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            isLocked = true
            lockProgress = 1
        }
    }

    // MARK: - Gestures (canvas)

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = pinchBase * value.magnification
                camera.setZoom(next)
            }
            .onEnded { _ in
                pinchBase = camera.currentZoom
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                camera.flipCamera()
            }
    }

    private func tapToFocusGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                let pt = value.location
                focusPoint = pt
                focusVisible = true
                let normalized = CGPoint(
                    x: max(0, min(1, pt.x / size.width)),
                    y: max(0, min(1, pt.y / size.height))
                )
                camera.focus(at: normalized)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    withAnimation(.easeOut(duration: 0.25)) {
                        focusVisible = false
                    }
                }
            }
    }

    private var focusReticle: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1.2)
            .frame(width: 64, height: 64)
            .scaleEffect(focusVisible ? 1.0 : 1.4)
            .opacity(focusVisible ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.22), value: focusVisible)
    }

    // MARK: - Actions

    private func takePhoto() {
        guard camera.isReady else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.06)) { flashOpacity = 0.85 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.easeIn(duration: 0.18)) { flashOpacity = 0 }
        }

        Task { @MainActor in
            if let image = await camera.capturePhoto() {
                captureResult = .photo(image)
            }
        }
    }

    private func startRecording() {
        guard camera.isReady, !isRecording else { return }
        // Only show a recording UI for a recording the service actually
        // accepted. It used to flip isRecording first and ask never —
        // so a refused start left a ring spinning over nothing.
        guard camera.startRecording() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        recordElapsed = 0
        recordStart = Date()
        recordZoomBase = camera.currentZoom
        isRecording = true
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isLocked = false
        lockProgress = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // The slide-zoom sticks: future pinches continue from here.
        pinchBase = camera.currentZoom
        let polled = recordElapsed
        camera.stopRecording { url in
            guard let url else { return }
            Task { @MainActor in
                async let thumb = Self.generateThumbnail(for: url)
                async let seconds = CameraService.duration(of: url, fallback: polled)
                captureResult = .video(url: url, thumbnail: await thumb, duration: await seconds)
            }
        }
    }

    private static func generateThumbnail(for url: URL) async -> UIImage? {
        await Task.detached {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            do {
                let cg = try gen.copyCGImage(at: CMTime(seconds: 0.0, preferredTimescale: 600), actualTime: nil)
                return UIImage(cgImage: cg)
            } catch {
                return nil
            }
        }.value
    }
}

// MARK: - AnyShape (small helper)

private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        self.pathBuilder = { rect in shape.path(in: rect) }
    }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

// MARK: - Camera proxy

struct CameraProxyView: View {
    @Bindable var camera: CameraService

    var body: some View {
        switch camera.viewState {
        case .running:
            ZStack {
                ActualCameraView(camera: camera)
                if camera.isInterrupted {
                    statusCard(
                        icon: "pause.circle",
                        title: "Camera paused",
                        message: "Another app is using the camera. It will resume automatically."
                    )
                }
            }
        case .warmingUp:
            ZStack {
                Color.black
                ProgressView()
                    .tint(Color.white.opacity(0.7))
            }
        case .denied:
            statusCard(
                icon: "video.slash",
                title: "Camera access is off",
                message: "Enable camera access in Settings to capture a moment from your day.",
                buttonTitle: "Open Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        case .failed:
            statusCard(
                icon: "exclamationmark.triangle",
                title: "The camera couldn't start",
                message: "Something interrupted the camera. Try again.",
                buttonTitle: "Retry"
            ) {
                Task { await camera.retry() }
            }
        case .unavailable:
            placeholder
        }
    }

    private func statusCard(
        icon: String,
        title: String,
        message: String,
        buttonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            Color.black.opacity(0.92)
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.65))
                Text(title)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(message)
                    .font(.serif(14, weight: .regular))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 40)

                if let buttonTitle, let action {
                    Button(action: action) {
                        Text(buttonTitle)
                            .font(.sans(14, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1830),
                    Color(hex: 0x2A2438),
                    Color(hex: 0x3A2F48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text("Camera preview")
                    .font(.sans(13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("Install this app on your device via the Rork App to use the camera.")
                    .font(.serif(15, weight: .regular))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .padding(.horizontal, 36)
            }
        }
    }
}

// MARK: - Actual camera view

struct ActualCameraView: UIViewRepresentable {
    @Bindable var camera: CameraService

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.backgroundColor = .black
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        Self.applyMirrorPolicy(to: view.previewLayer, isFront: camera.position == .front)
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if uiView.previewLayer.session !== camera.session {
            uiView.previewLayer.session = camera.session
        }
        // Reading these ties this update to session bring-up and camera
        // flips, so the policy re-applies on each fresh connection.
        _ = camera.position
        _ = camera.hasCamera
        Self.applyMirrorPolicy(to: uiView.previewLayer, isFront: camera.position == .front)
    }

    /// Mirror-consistent viewfinder: the front camera previews mirrored
    /// (like looking in a mirror) and the saved photo/video is flipped
    /// to match it exactly — what you compose is what you keep. The
    /// back camera is never mirrored.
    private static func applyMirrorPolicy(to layer: AVCaptureVideoPreviewLayer, isFront: Bool) {
        guard let connection = layer.connection, connection.isVideoMirroringSupported else { return }
        if connection.automaticallyAdjustsVideoMirroring {
            connection.automaticallyAdjustsVideoMirroring = false
        }
        if connection.isVideoMirrored != isFront {
            connection.isVideoMirrored = isFront
        }
    }

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Camera service

@MainActor
@Observable
final class CameraService: NSObject {
    /// One camera for the whole app. Hosts call `prewarm()` the moment
    /// an open-camera gesture begins, so by the time the capture UI is
    /// on screen the session is already delivering frames — no warming
    /// beat between the swipe and a live viewfinder.
    static let shared = CameraService()

    /// Kick the session into life ahead of presentation. Only runs when
    /// camera permission is already granted — a half-finished swipe must
    /// never summon the system permission dialog.
    func prewarm() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        Task { await requestAccessAndStart() }
    }

    enum AuthState: Equatable {
        case unknown, granted, denied, restricted
    }

    /// What the proxy view should show. Keeps the four failure surfaces
    /// (permission, hardware-missing, startup failure, interruption)
    /// from collapsing into one silent black screen.
    enum ViewState: Equatable {
        case warmingUp, running, denied, failed, unavailable
    }

    let session = AVCaptureSession()
    private(set) var authorization: AuthState = .unknown
    private(set) var isReady: Bool = false
    private(set) var hasCamera: Bool = false
    private(set) var startupFailed: Bool = false
    private(set) var isInterrupted: Bool = false
    private(set) var isFlashOn: Bool = false
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var currentZoom: CGFloat = 1.0

    private let sessionQueue = DispatchQueue(label: "frisfocus.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var pendingCapture: CheckedContinuation<UIImage?, Never>?
    private var pendingRecording: ((URL?) -> Void)?
    private var pendingRecordingURL: URL?

    /// Where the recorder actually is, as opposed to where the UI thinks
    /// it is.
    ///
    /// `movieOutput.isRecording` cannot answer this. It is mutated on
    /// `sessionQueue` and read on the main actor, and — the part that
    /// broke every recording — it stays FALSE for the whole window
    /// between asking to record and AVFoundation actually opening the
    /// file. Releasing the shutter inside that window made
    /// `stopRecording(completion:)` take its `else` branch, hand back
    /// nil, and the view drop the clip on the floor. `.starting` is the
    /// state that window needed a name for.
    enum RecordingState: Equatable {
        case idle
        /// Asked to record; AVFoundation has not opened the file yet.
        case starting
        case recording
        case stopping
    }
    private(set) var recordingState: RecordingState = .idle
    /// A stop that arrived while still `.starting`. Honoured the instant
    /// the recording actually begins, so a quick hold yields a short clip
    /// instead of nothing — and never leaves a recording nobody can stop.
    private var stopRequestedWhileStarting = false
    private var observersRegistered: Bool = false

    var viewState: ViewState {
        if hasCamera { return .running }
        if authorization == .denied || authorization == .restricted { return .denied }
        if startupFailed { return .failed }
        if authorization == .granted, !Self.cameraDeviceExists { return .unavailable }
        return .warmingUp
    }

    /// Whether the hardware has any camera at all — distinguishes the
    /// cloud simulator's placeholder from a real-device startup failure.
    nonisolated private static var cameraDeviceExists: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    func requestAccessAndStart() async {
        // Idempotent: if we've already set the session up successfully,
        // just ensure it's running so re-entries (post-capture retake)
        // don't get stuck on a frozen frame.
        if hasCamera {
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
            return
        }

        startupFailed = false

        // Video permission only — the microphone is deliberately NOT
        // requested or attached here. Holding an audio input while the
        // app's voice/audio features own the audio session can silently
        // interrupt the capture session and leave the viewfinder black.
        // Audio attaches just-in-time when a recording actually starts.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: authorization = .granted
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            authorization = ok ? .granted : .denied
        case .denied: authorization = .denied
        case .restricted: authorization = .restricted
        @unknown default: authorization = .denied
        }

        guard authorization == .granted else {
            hasCamera = false
            return
        }

        registerSessionObservers()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                self?.configureSession()
                continuation.resume()
            }
        }
    }

    /// Clears a failed startup and tries the whole bring-up again.
    func retry() async {
        startupFailed = false
        await requestAccessAndStart()
    }

    // MARK: - Interruption recovery

    private func registerSessionObservers() {
        guard !observersRegistered else { return }
        observersRegistered = true
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        nc.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        nc.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    @objc nonisolated private func sessionWasInterrupted() {
        Task { @MainActor in self.isInterrupted = true }
    }

    @objc nonisolated private func sessionInterruptionEnded() {
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        Task { @MainActor in self.isInterrupted = false }
    }

    @objc nonisolated private func sessionRuntimeError() {
        // Bounce the session back the moment the system lets us.
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        // Readiness has to fall with the session. Leaving `isReady` true
        // over a stopped session let the next `startRecording` sail past
        // its guard and record into nothing.
        isReady = false
        recordingState = .idle
        stopRequestedWhileStarting = false
        pendingRecording?(nil)
        pendingRecording = nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func toggleFlash() { isFlashOn.toggle() }

    func flipCamera() {
        let next: AVCaptureDevice.Position = (position == .back) ? .front : .back
        sessionQueue.async { [weak self] in
            self?.switchCamera(to: next)
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentInput?.device else { return }
        let clamped = max(1.0, min(factor, min(device.activeFormat.videoMaxZoomFactor, 6.0)))
        currentZoom = clamped
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                // Non-fatal — zoom just won't change this frame.
            }
        }
    }

    func focus(at normalized: CGPoint) {
        guard let device = currentInput?.device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = normalized
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = normalized
                }
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // Best-effort focus.
            }
        }
    }

    func capturePhoto() async -> UIImage? {
        guard hasCamera, isReady else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            self.pendingCapture = continuation
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                // Mirror front-camera stills so the saved photo matches
                // the mirrored viewfinder exactly; back camera stays true.
                let isFront = self.currentInput?.device.position == .front
                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = isFront
                }
                let settings = AVCapturePhotoSettings()
                if let device = self.currentInput?.device,
                   device.hasFlash,
                   self.photoOutput.supportedFlashModes.contains(.on) {
                    settings.flashMode = self.isFlashOn ? .on : .off
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    /// Ask for the microphone ahead of any recording.
    ///
    /// This used to live INSIDE `startRecording`, which meant the very
    /// first video anyone ever recorded put a system permission alert in
    /// the middle of the start sequence. The user answered it seconds
    /// after releasing the shutter, by which point the clip had already
    /// been discarded — so the first recording was not merely racy, it
    /// was guaranteed to be lost. Asking here costs nothing (the sheet
    /// is open, no recording is in flight) and takes the alert off the
    /// critical path for good.
    ///
    /// A denied mic is fine and deliberately not surfaced: the recording
    /// simply has no audio track.
    func primeMicrophonePermission() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Begin recording. Returns false when the recorder refused, so the
    /// caller never shows a recording UI for a recording that is not
    /// happening.
    @discardableResult
    func startRecording() -> Bool {
        guard hasCamera, isReady, recordingState == .idle else { return false }
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("frisfocus-clip-\(UUID().uuidString).mov")
        pendingRecordingURL = url
        recordingState = .starting
        stopRequestedWhileStarting = false

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.attachAudioInput()
            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                // Mirror front-camera clips so the recording matches
                // the mirrored viewfinder and the saved front-camera
                // photos; back camera stays true.
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = self.currentInput?.device.position == .front
                }
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)

            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.recordingState == .starting else { return }
                self.recordingState = .recording
                // The release that arrived before the file was open. Now
                // that it is, honour it — the person gets the short clip
                // they actually recorded rather than silence.
                if self.stopRequestedWhileStarting {
                    self.stopRequestedWhileStarting = false
                    self.performStop()
                }
            }
        }
        return true
    }

    /// Adds the microphone input if authorized and not already attached.
    /// Runs on the session queue.
    nonisolated private func attachAudioInput() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let alreadyAttached = session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .contains { $0.device.hasMediaType(.audio) }
        guard !alreadyAttached,
              let audioDevice = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: audioDevice) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
    }

    /// Releases the microphone after a recording so the camera never
    /// holds the audio device while idle. Runs on the session queue.
    nonisolated private func detachAudioInput() {
        let audioInputs = session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.audio) }
        guard !audioInputs.isEmpty else { return }
        session.beginConfiguration()
        for input in audioInputs {
            session.removeInput(input)
        }
        session.commitConfiguration()
    }

    /// The real duration of a finished recording.
    ///
    /// Every camera surface reported the value from its own 0.05 s UI
    /// stopwatch, which is a display number: it drifts whenever the main
    /// thread stalls, it's clamped at the cap, and it starts before
    /// AVFoundation has opened the file. Recipients then saw a length
    /// that didn't match the clip they were watching. The asset knows.
    nonisolated static func duration(of url: URL, fallback: Double) async -> Double {
        guard let time = try? await AVURLAsset(url: url).load(.duration),
              time.isNumeric else { return fallback }
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0 else { return fallback }
        return seconds
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        switch recordingState {
        case .idle:
            // Genuinely nothing running.
            completion(nil)

        case .starting:
            // THE BUG THIS REPLACES. The old code asked
            // `movieOutput.isRecording`, which is still false here, took
            // the else branch and handed back nil — and the view's
            // `guard let url else { return }` dropped the clip without a
            // word. Worse, the start already in flight then began a
            // recording nobody was left to stop.
            //
            // Hold the completion and let the start land; it stops
            // itself the moment the file is open.
            pendingRecording = completion
            recordingState = .stopping
            stopRequestedWhileStarting = true

        case .recording:
            pendingRecording = completion
            performStop()

        case .stopping:
            // A second release for one recording. Never overwrite the
            // outstanding completion — doing so orphaned the first one
            // forever and paired the finished file with the wrong
            // caller.
            completion(nil)
        }
    }

    /// Issue the actual stop. Only ever called once per recording.
    private func performStop() {
        recordingState = .stopping
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    // MARK: - Session config (off-main)

    nonisolated private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = Self.defaultDevice(position: .back) ?? Self.defaultDevice(position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            // A device exists but couldn't be wired up → a real failure
            // worth a Retry. No device at all → the simulator placeholder.
            let failed = Self.cameraDeviceExists
            Task { @MainActor in
                self.hasCamera = false
                self.isReady = false
                self.startupFailed = failed
            }
            return
        }
        session.addInput(input)

        // NOTE: no audio input here — the mic attaches just-in-time in
        // startRecording() so an idle viewfinder never owns the audio
        // device (which can silently interrupt the session → black).

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        session.commitConfiguration()
        session.startRunning()

        let running = session.isRunning
        let devicePosition = device.position
        Task { @MainActor in
            self.currentInput = input
            self.position = devicePosition
            self.hasCamera = running
            self.isReady = running
            self.startupFailed = !running
        }
    }

    nonisolated private func switchCamera(to next: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let videoInputs = session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.video) }
        for input in videoInputs {
            session.removeInput(input)
        }

        guard let device = Self.defaultDevice(position: next),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            for input in videoInputs where session.canAddInput(input) {
                session.addInput(input)
            }
            return
        }

        session.addInput(input)
        Task { @MainActor in
            self.currentInput = input
            self.position = next
            self.currentZoom = 1.0
        }
    }

    nonisolated private static func defaultDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

// MARK: - Photo capture delegate

extension CameraService: @preconcurrency AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage? = {
            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let img = UIImage(data: data) else { return nil }
            return img
        }()
        Task { @MainActor in
            self.pendingCapture?.resume(returning: image)
            self.pendingCapture = nil
        }
    }
}

// MARK: - Movie file output delegate

extension CameraService: @preconcurrency AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Release the mic as soon as the clip is finalized.
        sessionQueue.async { [weak self] in
            self?.detachAudioInput()
        }
        Task { @MainActor in
            // A non-nil error does NOT mean the file is unusable.
            // AVFoundation reports a "successfully finished" error for
            // ordinary stops — discarding on `error != nil` alone threw
            // away perfectly good recordings.
            let finishedFine = (error as NSError?)?
                .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
            let usable = error == nil || finishedFine
            let finalURL: URL? = usable ? outputFileURL : nil

            self.recordingState = .idle
            self.stopRequestedWhileStarting = false
            let completion = self.pendingRecording
            self.pendingRecording = nil
            self.pendingRecordingURL = nil

            if completion == nil, usable {
                // Nobody was waiting — an orphaned recording (a stop that
                // never reached us, a session interruption). Do not leave
                // the bytes lying in tmp forever.
                try? FileManager.default.removeItem(at: outputFileURL)
                return
            }
            completion?(finalURL)
        }
    }
}
