//
//  ShareCameraView.swift
//  FrisFocus
//
//  The share camera — the user takes a photo or records a clip THROUGH
//  the card overlay. Two subjects share the one camera: the day card
//  (sun-state mark, season name, task chips) and the milestone card
//  (flag mark, serif title, progress, journey strip). The overlay is
//  live on the viewfinder and reflows as the user curates; what you
//  see is exactly what exports.
//
//   • One shutter, camera ergonomics: tap → photo, press-and-hold →
//     video (30 s cap with a progress ring), double-tap the
//     viewfinder to flip cameras.
//   • Tap any task chip on the viewfinder to hide/show it.
//   • "Layers" opens the disclosure sheet (season / tasks / numbers).
//
//  Reuses the proven `CameraService` + `CameraProxyView` from the
//  capture module — on the cloud simulator the proxy shows its calm
//  placeholder and the shutter is disabled.
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

struct ShareCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(ProfileStore.self) private var profileStore
    @Environment(WalkthroughManager.self) private var walkthrough
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What's being shared — a day (or week), a milestone, or a
    /// journal capture.
    let subject: ShareCardSubject
    /// Where the composed card can attach afterwards — a milestone's
    /// journey, the note composer, or the free-standing picker.
    let attachContext: ProofAttachContext
    /// Note-composer flow: saved media returns here instead of
    /// mutating the Store (the note doesn't exist yet).
    let onSavedToNoteComposer: ((NotePhoto) -> Void)?

    /// The shared, pre-warmable app camera — same instance the proof
    /// camera uses, so both surfaces get the same gestures and warm-up.
    private var camera: CameraService { .shared }
    @State private var options = ShareOverlayOptions()
    /// Milestone disclosure choices — loaded from (and saved back to)
    /// the user's last share so curation sticks.
    @State private var milestoneOptions: MilestoneShareOptions = MilestoneShareOptions.load()
    @State private var result: CaptureResult?
    @State private var showLayers: Bool = false

    /// The swipeable overlay carousel — built once on appear: nothing →
    /// the season day card → one card per milestone (→ the journal card
    /// when that's how the camera was opened). The entry subject is
    /// always one of the pages and starts selected.
    @State private var pages: [ShareCardSubject] = []
    @State private var pageIndex: Int = 0

    init(
        subject: ShareCardSubject,
        attachContext: ProofAttachContext = .none,
        onSavedToNoteComposer: ((NotePhoto) -> Void)? = nil
    ) {
        self.subject = subject
        self.attachContext = attachContext
        self.onSavedToNoteComposer = onSavedToNoteComposer
    }

    /// Convenience for the existing day/week entry points.
    init(context: ShareDayContext) {
        self.subject = .day(context)
        self.attachContext = .none
        self.onSavedToNoteComposer = nil
    }

    // Recording state
    @State private var isRecording: Bool = false
    @State private var recordStart: Date?
    @State private var recordElapsed: Double = 0
    /// Arms the hold-to-record after a short press; a quick release
    /// before it fires is a photo instead.
    @State private var pressTimerTask: Task<Void, Never>?
    /// The 30 s cap ended the recording while the finger was still
    /// down. Whatever release follows closes THAT recording — it is not
    /// a request for a photo. Without this the cap silently replaced a
    /// full-length video with a still the moment the finger lifted.
    @State private var suppressPhotoOnRelease: Bool = false

    // Visual effects
    @State private var flashOpacity: Double = 0
    /// Tap-to-focus reticle state — parity with the proof camera.
    @State private var focusPoint: CGPoint?
    @State private var focusVisible: Bool = false
    /// Pinch-zoom anchor; recording slide-zoom ramps from `recordZoomBase`.
    @State private var pinchBase: CGFloat = 1.0
    @State private var recordZoomBase: CGFloat = 1.0
    /// The share-attribution concept lesson, fired once on first reach.
    @State private var attributionLesson: WalkthroughLesson?

    @AppStorage("share.chipHint.seen") private var chipHintSeen: Bool = false
    @AppStorage("share.shutterHint.seen") private var shutterHintSeen: Bool = false

    private let maxRecordSeconds: Double = 30
    private let recordTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var username: String {
        profileStore.myProfile?.username
            ?? profileStore.myProfile?.name
            ?? "me"
    }

    /// The overlay the viewfinder is currently showing — the selected
    /// carousel page (falling back to the entry subject pre-build).
    private var currentSubject: ShareCardSubject {
        guard pages.indices.contains(pageIndex) else { return subject }
        return pages[pageIndex]
    }

    /// The subject frozen together with the current overlay options —
    /// what the preview and the renderer will draw.
    private var composition: ShareCardComposition {
        switch currentSubject {
        case .blank: return .blank
        case .day(let context): return .day(context, options)
        case .milestone(let context): return .milestone(context, milestoneOptions)
        case .note(let context): return .note(context)
        }
    }

    private var isDaySubject: Bool {
        if case .day = currentSubject { return true }
        return false
    }

    /// Only the day and milestone cards have disclosure layers.
    private var hasLayers: Bool {
        switch currentSubject {
        case .day, .milestone: return true
        case .blank, .note: return false
        }
    }

    /// Short name for the active overlay, shown beside the dots.
    private var overlayLabel: String {
        switch currentSubject {
        case .blank: return "No overlay"
        case .day(let context):
            if case .week = context.sun { return "Your week" }
            return "Season"
        case .milestone(let context): return context.title
        case .note: return "Journal"
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                CameraProxyView(camera: camera)
                    .ignoresSafeArea()
                    .gesture(pinchGesture)
                    .simultaneousGesture(tapToFocusGesture(in: geo.size))
                    .simultaneousGesture(doubleTapFlipGesture)

                // Yellow focus reticle — parity with the proof camera.
                if let pt = focusPoint, focusVisible {
                    focusReticle
                        .position(pt)
                        .allowsHitTesting(false)
                }

                // The live overlay — WYSIWYG with the export. Day-card
                // chips are the only interactive part; everything else
                // passes touches to the camera layer.
                ShareCompositionOverlayView(
                    composition: composition,
                    mode: .composing,
                    username: username,
                    showChipHint: isDaySubject && !chipHintSeen,
                    onToggleChip: { chipId in
                        toggleChip(chipId)
                    },
                    bottomPadding: 168
                )
                .id(pageIndex)
                .transition(.opacity)
                .ignoresSafeArea(edges: .bottom)

                // Photo flash.
                Color.white.opacity(flashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomControls
                }
            }
        }
        .statusBarHidden()
        .simultaneousGesture(overlayCarouselGesture)
        .onAppear {
            buildPages()
            Task { await camera.requestAccessAndStart() }
            // Attribution — taught the first time the share surface is
            // reached, after a beat so it doesn't fight the camera open.
            // The floor is claimed AFTER the beat, never across it: a
            // lesson that holds the slot through a wait the user may walk
            // out of would silence every other surface for the session.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard attributionLesson == nil,
                      walkthrough.claim(.shareAttribution) else { return }
                attributionLesson = .shareAttribution
            }
        }
        .walkthroughLessonSheet($attributionLesson) { walkthrough.markSeen($0); walkthrough.release($0) }
        .onDisappear {
            pressTimerTask?.cancel()
            camera.stop()
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
            withAnimation(.easeOut(duration: 0.2)) { isRecording = false }
            recordStart = nil
            recordElapsed = 0
            suppressPhotoOnRelease = true
            pinchBase = camera.currentZoom
        }
        .onReceive(recordTimer) { _ in
            tickRecording()
        }
        .sheet(isPresented: $showLayers) {
            layersSheet
        }
        .onChange(of: milestoneOptions) { _, newOptions in
            newOptions.save()
        }
        .fullScreenCover(item: $result, onDismiss: {
            // Retake — bring the session back.
            Task { await camera.requestAccessAndStart() }
        }) { captured in
            SharePreviewView(
                result: captured,
                composition: composition,
                username: username,
                attachContext: attachContext,
                onSavedToNoteComposer: onSavedToNoteComposer,
                onFinished: {
                    result = nil
                    dismiss()
                }
            )
            .environment(store)
        }
    }

    // MARK: - Layers sheet

    @ViewBuilder
    private var layersSheet: some View {
        switch currentSubject {
        case .day:
            ShareLayersSheet(options: $options)
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        case .milestone:
            MilestoneShareLayersSheet(options: $milestoneOptions)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        case .blank, .note:
            EmptyView()
        }
    }

    // MARK: - Overlay carousel

    /// Builds the carousel once: nothing → the day card → every
    /// milestone of the season (→ the journal card for note captures).
    /// The entry subject's exact context is reused so deep entry points
    /// (a past day, the week, a specific milestone) keep their data.
    private func buildPages() {
        guard pages.isEmpty else { return }
        var built: [ShareCardSubject] = [.blank]

        if case .day(let context) = subject {
            built.append(.day(context))
        } else {
            built.append(.day(store.dayShareContext()))
        }

        var milestonePages = store.currentSeason.milestones
            .sorted { $0.weekNumber < $1.weekNumber }
            .prefix(8)
            .map { ShareCardSubject.milestone(store.milestoneShareContext(for: $0)) }
        if case .milestone(let context) = subject,
           !milestonePages.contains(.milestone(context)) {
            milestonePages.insert(.milestone(context), at: 0)
        }
        built.append(contentsOf: milestonePages)

        if case .note(let context) = subject {
            built.append(.note(context))
        }

        pages = built
        pageIndex = built.firstIndex(of: subject) ?? 0
    }

    /// Horizontal swipe anywhere on the viewfinder steps through the
    /// overlay pages (wrapping at the ends). Never fires mid-recording
    /// or while a shutter press is armed, and vertical drags pass.
    private var overlayCarouselGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard pages.count > 1, !isRecording, pressTimerTask == nil, result == nil else { return }
                let width = value.translation.width
                guard abs(width) > 48, abs(width) > abs(value.translation.height) else { return }
                let step = width < 0 ? 1 : -1
                let next = (pageIndex + step + pages.count) % pages.count
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeInOut(duration: 0.22)) {
                    pageIndex = next
                }
            }
    }

    /// Dots + the active overlay's name, floating above the shutter.
    private var overlayIndicator: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                ForEach(pages.indices, id: \.self) { idx in
                    Circle()
                        .fill(Color.white.opacity(idx == pageIndex ? 0.95 : 0.35))
                        .frame(width: idx == pageIndex ? 6 : 5, height: idx == pageIndex ? 6 : 5)
                }
            }
            Text(overlayLabel)
                .font(.sans(12, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        }
        .animation(.easeInOut(duration: 0.2), value: pageIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overlay: \(overlayLabel)")
        .accessibilityHint("Swipe left or right on the viewfinder to change the overlay")
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .accessibilityLabel("Close share camera")

            Spacer()

            if hasLayers {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showLayers = true
                } label: {
                    Text("Layers")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                }
                .accessibilityLabel("Overlay layers")
                .accessibilityHint("Choose what appears on the share")
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                camera.toggleFlash()
            } label: {
                Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .accessibilityLabel(camera.isFlashOn ? "Flash on" : "Flash off")
            .disabled(!camera.hasCamera)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                camera.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .accessibilityLabel("Flip camera")
            .disabled(!camera.canFlipCamera)
            .opacity(camera.canFlipCamera ? 1 : 0)
            .allowsHitTesting(camera.canFlipCamera)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if pages.count > 1 && !isRecording {
                overlayIndicator
                    .transition(.opacity)
            }

            shutterRow

            // First-use gesture hint — replaces the old mode toggle.
            if !shutterHintSeen && !isRecording && camera.hasCamera {
                Text("tap for photo · hold for video")
                    .font(.sans(12, weight: .regular))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .transition(.opacity)
            } else {
                // Keep the shutter's vertical position stable.
                Color.clear.frame(height: 28)
            }
        }
        .padding(.bottom, 30)
    }

    private var shutterRow: some View {
        ZStack {
            // Recording timer, floating above the shutter.
            if isRecording {
                Text(timeString(recordElapsed))
                    .font(.sans(13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .offset(y: -64)
                    .transition(.opacity)
            }

            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 78, height: 78)

                Circle()
                    .fill(isRecording ? Color.red : Color.white)
                    .frame(width: isRecording ? 32 : 62, height: isRecording ? 32 : 62)
                    .clipShape(
                        isRecording
                            ? AnyShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            : AnyShape(Circle())
                    )
                    .animation(.easeInOut(duration: 0.18), value: isRecording)

                // Recording progress ring toward the 30 s cap.
                if isRecording {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(1, recordElapsed / maxRecordSeconds)))
                        .stroke(
                            Color.red,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 78, height: 78)
                        .rotationEffect(.degrees(-90))
                }
            }
            .scaleEffect(isRecording && !reduceMotion ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isRecording)
            .contentShape(Circle())
            .gesture(shutterGesture)
            .disabled(!camera.hasCamera)
            .opacity(camera.hasCamera ? 1 : 0.4)
            .accessibilityLabel(isRecording ? "Recording. Release to stop." : "Tap to photograph, hold to record")
        }
    }

    // MARK: - Capture gestures

    /// Camera ergonomics on one shutter: a quick tap fires a photo; a
    /// press held past 220 ms arms a recording that stops on release —
    /// and once recording, the held finger slides up to zoom.
    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isRecording {
                    let rise = -value.translation.height
                    camera.setZoom(recordZoomBase + rise / 110)
                    return
                }
                guard pressTimerTask == nil, camera.isReady else { return }
                pressTimerTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    // Clear the slot from inside the task too. It used
                    // to be cleared only in onEnded, so any gesture that
                    // never delivered one — a system interruption, a
                    // cancelled touch — left the slot occupied and
                    // hold-to-record dead for the rest of the session.
                    pressTimerTask = nil
                    startRecording()
                }
            }
            .onEnded { _ in
                pressTimerTask?.cancel()
                pressTimerTask = nil
                if isRecording {
                    stopRecording()
                } else if suppressPhotoOnRelease {
                    suppressPhotoOnRelease = false
                } else {
                    takePhoto()
                }
            }
    }

    /// Pinch anywhere on the viewfinder to zoom — parity with the proof
    /// camera. Caption pinches don't exist here, so the whole canvas is
    /// fair game.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                camera.setZoom(pinchBase * value.magnification)
            }
            .onEnded { _ in
                pinchBase = camera.currentZoom
            }
    }

    /// Tap the viewfinder to focus + meter there, with the yellow
    /// reticle pulse. Chip taps live on the overlay above and never
    /// reach this gesture.
    private func tapToFocusGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                guard camera.hasCamera else { return }
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

    /// Double-tap anywhere on the viewfinder flips the camera — the
    /// top-bar flip button stays as the discoverable affordance.
    private var doubleTapFlipGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard camera.canFlipCamera else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                camera.flipCamera()
            }
    }

    private func takePhoto() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.08)) { flashOpacity = 0.85 }
        Task {
            let image = await camera.capturePhoto()
            withAnimation(.easeOut(duration: 0.3)) { flashOpacity = 0 }
            if let image {
                result = .photo(image)
            }
        }
    }

    private func startRecording() {
        guard camera.isReady, !isRecording else { return }
        // Only show a recording UI for a recording the service actually
        // accepted. This used to flip `isRecording` first and never ask,
        // so a refused start left a progress ring spinning over nothing
        // and a release that produced no clip and no explanation.
        guard camera.startRecording() else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        recordStart = Date()
        recordElapsed = 0
        recordZoomBase = camera.currentZoom
        withAnimation(.easeOut(duration: 0.2)) { isRecording = true }
        if !shutterHintSeen { shutterHintSeen = true }
    }

    private func stopRecording() {
        guard isRecording else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let polled = recordElapsed
        withAnimation(.easeOut(duration: 0.2)) { isRecording = false }
        recordStart = nil
        pinchBase = camera.currentZoom
        camera.stopRecording { url in
            guard let url else { return }
            Task { @MainActor in
                let seconds = await CameraService.duration(of: url, fallback: polled)
                result = .video(url: url, thumbnail: nil, duration: seconds)
            }
        }
    }

    private func tickRecording() {
        guard isRecording, let start = recordStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        recordElapsed = min(elapsed, maxRecordSeconds)
        if elapsed >= maxRecordSeconds {
            // The finger is still down. Whatever release follows is the
            // end of THIS recording, not a new photo.
            suppressPhotoOnRelease = true
            stopRecording()
        }
    }

    private func toggleChip(_ chipId: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        if options.hiddenChipIds.contains(chipId) {
            options.hiddenChipIds.remove(chipId)
        } else {
            options.hiddenChipIds.insert(chipId)
        }
        if !chipHintSeen {
            chipHintSeen = true
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "0:%02d", total)
    }
}
