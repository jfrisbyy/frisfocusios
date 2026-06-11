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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What's being shared — a day (or week), or a milestone.
    let subject: ShareCardSubject

    @State private var camera = CameraService()
    @State private var options = ShareOverlayOptions()
    /// Milestone disclosure choices — loaded from (and saved back to)
    /// the user's last share so curation sticks.
    @State private var milestoneOptions: MilestoneShareOptions = MilestoneShareOptions.load()
    @State private var result: CaptureResult?
    @State private var showLayers: Bool = false

    init(subject: ShareCardSubject) {
        self.subject = subject
    }

    /// Convenience for the existing day/week entry points.
    init(context: ShareDayContext) {
        self.subject = .day(context)
    }

    // Recording state
    @State private var isRecording: Bool = false
    @State private var recordStart: Date?
    @State private var recordElapsed: Double = 0
    /// Arms the hold-to-record after a short press; a quick release
    /// before it fires is a photo instead.
    @State private var pressTimerTask: Task<Void, Never>?

    // Visual effects
    @State private var flashOpacity: Double = 0

    @AppStorage("share.chipHint.seen") private var chipHintSeen: Bool = false
    @AppStorage("share.shutterHint.seen") private var shutterHintSeen: Bool = false

    private let maxRecordSeconds: Double = 30
    private let recordTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var username: String {
        profileStore.myProfile?.username
            ?? profileStore.myProfile?.name
            ?? "me"
    }

    /// The subject frozen together with the current overlay options —
    /// what the preview and the renderer will draw.
    private var composition: ShareCardComposition {
        switch subject {
        case .day(let context): return .day(context, options)
        case .milestone(let context): return .milestone(context, milestoneOptions)
        }
    }

    private var isDaySubject: Bool {
        if case .day = subject { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraProxyView(camera: camera)
                .ignoresSafeArea()
                .simultaneousGesture(doubleTapFlipGesture)

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
        .statusBarHidden()
        .onAppear {
            Task { await camera.requestAccessAndStart() }
        }
        .onDisappear {
            pressTimerTask?.cancel()
            camera.stop()
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
        switch subject {
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
        }
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
            .disabled(!camera.hasCamera)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 14) {
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
    /// press held past 220 ms arms a recording that stops on release.
    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressTimerTask == nil, !isRecording, camera.hasCamera else { return }
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

    /// Double-tap anywhere on the viewfinder flips the camera — the
    /// top-bar flip button stays as the discoverable affordance.
    private var doubleTapFlipGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard camera.hasCamera else { return }
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
        guard camera.hasCamera, !isRecording else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        recordStart = Date()
        recordElapsed = 0
        withAnimation(.easeOut(duration: 0.2)) { isRecording = true }
        camera.startRecording()
        if !shutterHintSeen { shutterHintSeen = true }
    }

    private func stopRecording() {
        guard isRecording else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let duration = recordElapsed
        withAnimation(.easeOut(duration: 0.2)) { isRecording = false }
        recordStart = nil
        camera.stopRecording { url in
            if let url {
                result = .video(url: url, thumbnail: nil, duration: duration)
            }
        }
    }

    private func tickRecording() {
        guard isRecording, let start = recordStart else { return }
        recordElapsed = Date().timeIntervalSince(start)
        if recordElapsed >= maxRecordSeconds {
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
