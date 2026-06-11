//
//  ShareCameraView.swift
//  FrisFocus
//
//  The share camera — the user takes a photo or records a clip THROUGH
//  the day-overlay. The overlay (sun-state mark, season name, task
//  chips, attribution) is live on the viewfinder and reflows as the
//  user curates; what you see is exactly what exports.
//
//   • PHOTO / VIDEO segmented modes, large shutter, flip, close.
//   • Tap any task chip on the viewfinder to hide/show it.
//   • "Layers" opens the disclosure sheet (season / tasks / numbers).
//   • Video caps at 30 s with a progress ring.
//
//  Reuses the proven `CameraService` + `CameraProxyView` from the
//  capture module — on the cloud simulator the proxy shows its calm
//  placeholder and the shutter is disabled.
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

enum ShareCaptureMode: String, CaseIterable {
    case photo = "PHOTO"
    case video = "VIDEO"
}

struct ShareCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The day (or week) being shared — today from the home button,
    /// retroactive from a past day's detail, the week from the recap.
    let context: ShareDayContext

    @State private var camera = CameraService()
    @State private var options = ShareOverlayOptions()
    @State private var captureMode: ShareCaptureMode = .photo
    @State private var result: CaptureResult?
    @State private var showLayers: Bool = false

    // Recording state
    @State private var isRecording: Bool = false
    @State private var recordStart: Date?
    @State private var recordElapsed: Double = 0

    // Visual effects
    @State private var flashOpacity: Double = 0

    @AppStorage("share.chipHint.seen") private var chipHintSeen: Bool = false

    private let maxRecordSeconds: Double = 30
    private let recordTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var username: String {
        profileStore.myProfile?.username
            ?? profileStore.myProfile?.name
            ?? "me"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraProxyView(camera: camera)
                .ignoresSafeArea()

            // The live overlay — WYSIWYG with the export. Chips are the
            // only interactive part; everything else passes touches to
            // the camera layer.
            ShareOverlayView(
                context: context,
                options: options,
                mode: .composing,
                username: username,
                showChipHint: !chipHintSeen,
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
            camera.stop()
        }
        .onReceive(recordTimer) { _ in
            tickRecording()
        }
        .sheet(isPresented: $showLayers) {
            ShareLayersSheet(options: $options)
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .fullScreenCover(item: $result, onDismiss: {
            // Retake — bring the session back.
            Task { await camera.requestAccessAndStart() }
        }) { captured in
            SharePreviewView(
                result: captured,
                context: context,
                options: options,
                username: username,
                onFinished: {
                    result = nil
                    dismiss()
                }
            )
            .environment(store)
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

            // Mode toggle — PHOTO / VIDEO.
            HStack(spacing: 26) {
                ForEach(ShareCaptureMode.allCases, id: \.self) { mode in
                    Button {
                        guard !isRecording else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.2)) {
                            captureMode = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.sans(13, weight: captureMode == mode ? .bold : .medium))
                            .tracking(1.6)
                            .foregroundStyle(
                                captureMode == mode
                                    ? Color.white
                                    : Color.white.opacity(0.55)
                            )
                    }
                    .accessibilityLabel("\(mode == .photo ? "Photo" : "Video") mode")
                    .accessibilityAddTraits(captureMode == mode ? .isSelected : [])
                }
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

            Button {
                handleShutterTap()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 78, height: 78)

                    if captureMode == .video {
                        if isRecording {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 24, height: 24)
                        }
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                    }

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
            }
            .buttonStyle(.plain)
            .disabled(!camera.hasCamera)
            .opacity(camera.hasCamera ? 1 : 0.4)
            .accessibilityLabel(shutterAccessibilityLabel)
        }
    }

    private var shutterAccessibilityLabel: String {
        if captureMode == .photo { return "Take photo" }
        return isRecording ? "Stop recording" : "Start recording"
    }

    // MARK: - Capture

    private func handleShutterTap() {
        switch captureMode {
        case .photo:
            takePhoto()
        case .video:
            isRecording ? stopRecording() : startRecording()
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
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        recordStart = Date()
        recordElapsed = 0
        withAnimation(.easeOut(duration: 0.2)) { isRecording = true }
        camera.startRecording()
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
