//
//  FocusModeView.swift
//  FrisFocus
//
//  F1 — Focus Block (solo) behavior. Hosts the F0 art-directed scene
//  (scenery + tree + leaves) and wires it to the real "left the app"
//  trigger. The timer is wall-clock; locking the device costs nothing,
//  app-switch / home drops a leaf and records a `FocusLeave`.
//
//  Lifecycle classification:
//   - Scene goes to `.inactive` paired with `protectedDataWillBecomeUnavailable`
//     within a short window  → lock / screen sleep (NOT a leave).
//   - Scene goes to `.background` without that signal → real leave.
//   - Return to `.active`  → close the open leave and surface the
//     "while you were gone" return-from-leave screen.
//

import SwiftUI
import UIKit

struct FocusModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Store.self) private var store
    @Environment(FocusBlockingService.self) private var blocking

    // MARK: - Inputs

    /// Total session length in seconds. Defaults to 45 minutes.
    let sessionLength: TimeInterval
    /// Optional label shown in the eyebrow ("FOCUS · {label}").
    let label: String?
    /// Personal tasks attached to this session, checked off manually.
    let attachments: [FocusTaskAttachment]

    init(
        sessionLength: TimeInterval = 45 * 60,
        label: String? = nil,
        attachments: [FocusTaskAttachment] = []
    ) {
        self.sessionLength = sessionLength
        self.label = label
        self.attachments = attachments
    }

    // MARK: - State

    /// Wall-clock anchor. `now - startedAt` is the elapsed time; lock
    /// / sleep never pauses it.
    @State private var startedAt: Date = Date()
    @State private var leaves: [CanopyLeaf] = buildCanopyLeaves()
    @State private var fallenLeafIDs: Set<Int> = []

    /// True while the device is locking — set by the
    /// `protectedDataWillBecomeUnavailable` notification, cleared on
    /// return to `.active`. While true, a `.background` transition is
    /// classified as a lock, not a real leave.
    @State private var isLocking: Bool = false
    /// True when the most recent return needs the "while you were
    /// gone" overlay (i.e. came from a real leave, not a lock).
    @State private var showReturnOverlay: Bool = false
    /// Snapshot of the leave details to display in the return overlay
    /// — captured at return time so dismissing doesn't blank the copy.
    @State private var returnLeaveCount: Int = 0
    @State private var returnAwaySeconds: TimeInterval = 0
    /// Completion overlay — fires when the timer hits zero or the
    /// user ends early.
    @State private var showCompletionSheet: Bool = false
    @State private var completedClean: Bool = false
    @State private var completedLeafCount: Int = 0

    /// True from the moment `endFocusSession` is called so lifecycle
    /// observers don't keep recording leaves while the completion
    /// overlay is on screen.
    @State private var sessionEnded: Bool = false

    var body: some View {
        ZStack {
            FocusSceneryView()
                .ignoresSafeArea()

            GeometryReader { geo in
                let size = geo.size
                let treeWidth = min(size.width * 0.78, 380)
                let treeHeight = size.height * 0.58

                FocusTreeView(
                    leaves: leaves,
                    fallenLeafIDs: fallenLeafIDs,
                    thinningTier: .full,
                    scale: 1.0,
                    animatesSway: true
                )
                .frame(width: treeWidth, height: treeHeight)
                .position(x: size.width / 2, y: size.height * 0.50)
                .accessibilityLabel(accessibilityLabel)
            }

            VStack {
                // Top bar — close (ends the block) + state chip.
                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        endEarly()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("End focus")
                    Spacer()
                    stateChip
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Spacer()

                // Timer + label band sit quietly under the tree.
                VStack(spacing: 6) {
                    if let label, !label.isEmpty {
                        Text("FOCUS · \(label.uppercased())")
                            .font(.sans(10, weight: .semibold))
                            .tracking(2.0)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    } else {
                        Text("FOCUS")
                            .font(.sans(10, weight: .semibold))
                            .tracking(2.0)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let remaining = secondsRemaining
                        Text(timerString(remaining))
                            .font(.serif(46, weight: .light))
                            .tracking(-1)
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                            .onChange(of: remaining) { _, newValue in
                                if newValue <= 0 && !sessionEnded {
                                    finish()
                                }
                            }
                    }
                    Text("of \(Int(sessionLength / 60)) minutes")
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))

                    if !attachments.isEmpty {
                        FocusTaskTrayView(attachments: attachments, friendTasks: [])
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                    }
                }
                .padding(.bottom, 36)
            }

            if showReturnOverlay {
                returnFromLeaveOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if showCompletionSheet {
                completionOverlay
                    .transition(.opacity)
            }
        }
        .background(Color(hex: 0xFAF2E0).ignoresSafeArea())
        .onAppear(perform: beginIfNeeded)
        .onChange(of: scenePhase, handleScenePhase)
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.protectedDataWillBecomeUnavailableNotification
            )
        ) { _ in
            // A pending lock — flag it so the upcoming `.background`
            // transition (if it arrives) is classified as a lock,
            // not a leave.
            isLocking = true
        }
    }

    // MARK: - State chip

    @ViewBuilder
    private var stateChip: some View {
        let count = fallenLeafIDs.count
        HStack(spacing: 6) {
            Circle()
                .fill(count == 0 ? Theme.alertGreen : Color(hex: 0xC4A86A))
                .frame(width: 6, height: 6)
            Text(stateChipText(count: count))
                .font(.sans(11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.55)))
    }

    private func stateChipText(count: Int) -> String {
        if count == 0 { return "rooted · every leaf still on" }
        return "\(count) leaf\(count == 1 ? "" : "ves") fell · still standing"
    }

    // MARK: - Return-from-leave overlay

    @ViewBuilder
    private var returnFromLeaveOverlay: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome back")
                            .font(.serif(26, weight: .regular))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(minutesLeftDisplay) left")
                            .font(.serifItalic(15))
                            .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHILE YOU WERE GONE")
                            .font(.sans(10, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(Color(hex: 0x9E7E40))
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(returnLeaveCount)")
                                    .font(.serif(22, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(returnLeaveCount == 1 ? "leaf fell" : "leaves fell")
                                    .font(.sans(11))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            }
                            Rectangle()
                                .fill(Theme.textPrimary.opacity(0.12))
                                .frame(width: 0.5, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(awayString(returnAwaySeconds))
                                    .font(.serif(22, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("away")
                                    .font(.sans(11))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: 0xC4A86A).opacity(0.14))
                    )

                    Text("Stay to the end and keep what's left.")
                        .font(.serifItalic(14))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))

                    HStack(spacing: 10) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeOut(duration: 0.22)) {
                                showReturnOverlay = false
                            }
                        } label: {
                            Text("Back to it")
                                .font(.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.warmWheat)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.textPrimary)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            endEarly()
                        } label: {
                            Text("End here")
                                .font(.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Theme.textPrimary.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.warmWheat)
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Completion overlay

    @ViewBuilder
    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.20).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(completedClean ? "FULL CANOPY" : "BLOCK CLOSED")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(
                        completedClean ? Theme.alertGreen : Color(hex: 0x9E7E40)
                    )
                Text(completedClean
                     ? "You stayed the whole time."
                     : "You showed up.")
                    .font(.serif(26, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                Text(completedClean
                     ? "Every leaf stayed on the tree."
                     : "\(completedLeafCount) leaf\(completedLeafCount == 1 ? "" : "ves") fell — the tree's still standing."
                )
                .font(.serifItalic(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.warmWheat)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.textPrimary)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.warmWheat)
            )
            .padding(.horizontal, 22)
        }
    }

    // MARK: - Lifecycle

    private func beginIfNeeded() {
        // Reuse an existing active session if one is already running
        // (e.g. the user re-entered the screen after a brief detour);
        // otherwise start a fresh one.
        if let active = store.activeFocusSession,
           active.endedAt == nil,
           active.startedAt.addingTimeInterval(active.plannedDuration) > Date() {
            startedAt = active.startedAt
            // Resync visual fallen leaves with the recorded leaf
            // count so a relaunch mid-session lands on the right
            // canopy state.
            let count = min(active.leaves.count, leaves.count)
            fallenLeafIDs = Set(leaves.prefix(count).map(\.id))
            // Re-publish the activity in case it was torn down with
            // the app; ActivityKit ignores starts when one is already
            // running, so this is safe.
            FocusActivityManager.shared.start(
                startedAt: active.startedAt,
                plannedDuration: active.plannedDuration,
                label: active.label,
                canopyTotal: leaves.count
            )
            FocusActivityManager.shared.update(
                startedAt: active.startedAt,
                plannedDuration: active.plannedDuration,
                leavesFallen: active.leaves.count,
                canopyTotal: leaves.count
            )
        } else {
            let started = store.startFocusSession(
                plannedDuration: sessionLength,
                label: label,
                attachments: attachments
            )
            startedAt = started.startedAt
            FocusActivityManager.shared.start(
                startedAt: started.startedAt,
                plannedDuration: started.plannedDuration,
                label: started.label,
                canopyTotal: leaves.count
            )
        }
        // Shield the chosen apps for the duration of the block.
        blocking.beginShielding()
    }

    private func handleScenePhase(_ old: ScenePhase, _ new: ScenePhase) {
        guard !sessionEnded else { return }

        switch new {
        case .background:
            // A `.background` transition with the lock flag set is a
            // screen lock, not a leave. Without the lock flag, it's
            // a real leave: drop a leaf and record it.
            if isLocking { return }
            recordLeave()
        case .active:
            // Return path: clear the lock flag, close any open leave,
            // and — if there was a real leave — surface the return
            // overlay. Returning from a lock skips the overlay.
            let hadOpenLeave = store.activeFocusSession?.leaves.last?.awaySeconds == nil
            store.closeOpenFocusLeave()
            if isLocking {
                isLocking = false
            } else if hadOpenLeave, let last = store.activeFocusSession?.leaves.last {
                returnLeaveCount = store.activeFocusSession?.leaves.count ?? 0
                returnAwaySeconds = last.awaySeconds ?? 0
                withAnimation(.easeOut(duration: 0.25)) {
                    showReturnOverlay = true
                }
            }
        case .inactive:
            // Don't classify yet — `protectedDataWillBecomeUnavailable`
            // may arrive after `.inactive` but before `.background`.
            break
        @unknown default:
            break
        }
    }

    private func recordLeave() {
        store.recordFocusLeave()
        // Push the new leaf count to the Live Activity so the lock-
        // screen tree thins in sync with the in-app one.
        if let active = store.activeFocusSession {
            FocusActivityManager.shared.update(
                startedAt: active.startedAt,
                plannedDuration: active.plannedDuration,
                leavesFallen: active.leaves.count,
                canopyTotal: leaves.count
            )
        }
        guard let next = leaves.first(where: { !fallenLeafIDs.contains($0.id) }) else { return }
        withAnimation(.timingCurve(0.22, 0.72, 0.30, 1.0, duration: 2.1)) {
            _ = fallenLeafIDs.insert(next.id)
        }
    }

    private func endEarly() {
        guard !sessionEnded else { return }
        finish()
    }

    private func finish() {
        guard !sessionEnded else { return }
        sessionEnded = true
        let leafCount = store.activeFocusSession?.leaves.count ?? 0
        let clean = leafCount == 0
        store.endFocusSession()
        FocusActivityManager.shared.end()
        blocking.endShielding()
        completedLeafCount = leafCount
        completedClean = clean
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeOut(duration: 0.28)) {
            showReturnOverlay = false
            showCompletionSheet = true
        }
    }

    // MARK: - Helpers

    private var secondsRemaining: TimeInterval {
        max(0, sessionLength - Date().timeIntervalSince(startedAt))
    }

    private var minutesLeftDisplay: String {
        let m = Int(secondsRemaining / 60)
        if m <= 0 { return "Less than a minute" }
        return "\(m) minute\(m == 1 ? "" : "s")"
    }

    private func timerString(_ s: TimeInterval) -> String {
        let total = Int(s.rounded(.down))
        let m = total / 60
        let r = total % 60
        return String(format: "%02d:%02d", m, r)
    }

    private func awayString(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60
        let r = total % 60
        if m < 60 {
            return r == 0 ? "\(m)m" : "\(m)m \(r)s"
        }
        let h = m / 60
        let rm = m % 60
        return rm == 0 ? "\(h)h" : "\(h)h \(rm)m"
    }

    private var accessibilityLabel: String {
        let count = fallenLeafIDs.count
        if count == 0 { return "Focus tree — full canopy" }
        return "Focus tree — \(count) leaf\(count == 1 ? "" : "ves") fallen this session"
    }
}

#Preview {
    FocusModeView()
        .environment(Store())
}
