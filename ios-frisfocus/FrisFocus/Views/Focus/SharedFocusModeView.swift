//
//  SharedFocusModeView.swift
//  FrisFocus
//
//  F2 — the running shared focus block. Wraps `FocusGroveView` with the
//  F1 lifecycle (wall-clock timer, lock-vs-leave classifier, leaf-fall
//  on real leaves) for the local user, plus a coarse `FocusPresence`
//  publish to the Store and the "nudge {name} back in" cheer flow for
//  any friend whose tree is in the stepped-away state.
//
//  Friends' trees render from the seeded / simulated presences in the
//  Store; the real backend relay slots in later without touching this
//  view.
//

import SwiftUI
import UIKit

struct SharedFocusModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Store.self) private var store
    @Environment(FocusBlockingService.self) private var blocking

    let sessionLength: TimeInterval
    let label: String?
    let participantFriendIds: [UUID]

    init(
        sessionLength: TimeInterval,
        label: String? = nil,
        participantFriendIds: [UUID]
    ) {
        self.sessionLength = sessionLength
        self.label = label
        self.participantFriendIds = participantFriendIds
    }

    // MARK: - State

    @State private var startedAt: Date = Date()
    @State private var leaves: [CanopyLeaf] = buildCanopyLeaves()
    @State private var fallenLeafIDs: Set<Int> = []
    @State private var isLocking: Bool = false
    @State private var showReturnOverlay: Bool = false
    @State private var returnLeaveCount: Int = 0
    @State private var returnAwaySeconds: TimeInterval = 0
    @State private var showCompletionSheet: Bool = false
    @State private var sessionEnded: Bool = false

    /// The friend the user tapped to nudge — drives the cheer composer
    /// sheet.
    @State private var nudgeTarget: Friend? = nil
    /// Per-participant cheer counters; bumping one floats a reaction
    /// over that friend's tree.
    @State private var reactionPings: [UUID: Int] = [:]
    /// Tracks whether we've already started this view's local F1
    /// session so a re-render doesn't start a second one.
    @State private var didStart: Bool = false

    var body: some View {
        ZStack {
            FocusGroveView(
                participants: groveParticipants,
                sessionLabel: sessionLabelText,
                reactionPings: reactionPings,
                onNudge: handleNudge(_:)
            )

            VStack {
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
                    .accessibilityLabel("End grove")
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Spacer()

                // Timer + label band sit quietly under the grove.
                VStack(spacing: 6) {
                    Text(eyebrowText)
                        .font(.sans(10, weight: .semibold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
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
                    Text("of \(Int(sessionLength / 60)) minutes · together")
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
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
            isLocking = true
        }
        .sheet(item: $nudgeTarget) { friend in
            CheerComposerView(friend: friend)
        }
    }

    // MARK: - Grove projection

    private var eyebrowText: String {
        if let label, !label.isEmpty {
            return "TOGETHER · \(label.uppercased())"
        }
        return "TOGETHER"
    }

    private var sessionLabelText: String {
        let minutes = Int(sessionLength / 60)
        if let label, !label.isEmpty {
            return "TOGETHER · \(label.uppercased()) · \(minutes) MIN"
        }
        return "TOGETHER · \(minutes) MIN"
    }

    /// Build the list of grove participants from the active shared
    /// block + presence array. Me first (depth 0, centered); friends
    /// fanned out by depth — first friend mid-left, second mid-right,
    /// third back.
    private var groveParticipants: [GroveParticipant] {
        var out: [GroveParticipant] = []

        let myTier = LeafTier.bucket(leavesFallen: fallenLeafIDs.count)
        let myThinning: FocusTreeView.ThinningTier = {
            switch myTier {
            case .full: return .full
            case .thinning: return .thinning
            case .sparse: return .sparse
            }
        }()
        out.append(
            GroveParticipant(
                id: store.currentUserId,
                name: "You",
                isYou: true,
                tier: myThinning,
                isSteppedAway: false,
                depth: 0,
                xUnit: 0.50,
                leafSeed: 17,
                fallenLeafIDs: fallenLeafIDs
            )
        )

        // Friend slots — limited to 3.
        let slots: [(depth: Int, x: CGFloat, seed: UInt64)] = [
            (1, 0.18, 41),
            (1, 0.82, 73),
            (2, 0.50, 109)
        ]
        for (i, fid) in participantFriendIds.prefix(3).enumerated() {
            guard let friend = store.friends.first(where: { $0.id == fid }) else { continue }
            let presence = store.focusPresences.first(where: { $0.userId == fid })
            let tier = presence?.leafTier ?? .full
            let mapped: FocusTreeView.ThinningTier = {
                switch tier {
                case .full: return .full
                case .thinning: return .thinning
                case .sparse: return .sparse
                }
            }()
            // No presence row yet, or an explicit `.invited` row, means
            // they haven't dropped into the grove — show the waiting tree
            // until their device publishes `inBlock`.
            let isWaiting = presence == nil || presence?.state == .invited
            let slot = slots[i]
            out.append(
                GroveParticipant(
                    id: fid,
                    name: friend.displayName,
                    isYou: false,
                    tier: mapped,
                    isSteppedAway: presence?.state == .steppedAway,
                    isWaiting: isWaiting,
                    depth: slot.depth,
                    xUnit: slot.x,
                    leafSeed: slot.seed,
                    fallenLeafIDs: []
                )
            )
        }
        return out
    }

    // MARK: - Lifecycle

    private func beginIfNeeded() {
        guard !didStart else { return }
        didStart = true

        // Local F1 session for my tree's exact leaf record.
        if let active = store.activeFocusSession,
           active.endedAt == nil,
           active.startedAt.addingTimeInterval(active.plannedDuration) > Date() {
            startedAt = active.startedAt
            let count = min(active.leaves.count, leaves.count)
            fallenLeafIDs = Set(leaves.prefix(count).map(\.id))
        } else {
            let started = store.startFocusSession(
                plannedDuration: sessionLength,
                label: label,
                linkedTaskId: nil
            )
            startedAt = started.startedAt
        }

        // Shared block — start a fresh one if there isn't already an
        // active one (e.g. resumed after backgrounding).
        if store.activeSharedFocusBlock == nil {
            store.startSharedFocusBlock(
                friendIds: participantFriendIds,
                plannedDuration: sessionLength,
                label: label
            )
        }
        publishMyPresence()
        blocking.beginShielding()
    }

    private func handleScenePhase(_ old: ScenePhase, _ new: ScenePhase) {
        guard !sessionEnded else { return }
        switch new {
        case .background:
            if isLocking { return }
            recordLeave()
        case .active:
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
            publishMyPresence()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func recordLeave() {
        store.recordFocusLeave()
        // Also broadcast my coarse presence to the grove.
        store.publishMyFocusPresence(
            state: .steppedAway,
            leafTier: LeafTier.bucket(leavesFallen: fallenLeafIDs.count + 1)
        )
        guard let next = leaves.first(where: { !fallenLeafIDs.contains($0.id) }) else { return }
        withAnimation(.timingCurve(0.22, 0.72, 0.30, 1.0, duration: 2.1)) {
            _ = fallenLeafIDs.insert(next.id)
        }
    }

    private func publishMyPresence() {
        store.publishMyFocusPresence(
            state: .inBlock,
            leafTier: LeafTier.bucket(leavesFallen: fallenLeafIDs.count)
        )
    }

    private func handleNudge(_ participant: GroveParticipant) {
        guard let friend = store.friends.first(where: { $0.id == participant.id }) else { return }
        // Stepped-away friends get the nudge composer ("come back in").
        // Everyone else gets a quick, silent cheer that floats over
        // their tree — keeping the grove alive without words.
        if participant.isSteppedAway {
            nudgeTarget = friend
        } else {
            sendQuickCheer(to: friend)
        }
    }

    private func sendQuickCheer(to friend: Friend) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reactionPings[friend.id, default: 0] += 1
        store.sendQuickCheer(to: friend.id)
    }

    private func endEarly() {
        guard !sessionEnded else { return }
        finish()
    }

    private func finish() {
        guard !sessionEnded else { return }
        sessionEnded = true
        store.endFocusSession()
        store.endSharedFocusBlock()
        blocking.endShielding()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeOut(duration: 0.28)) {
            showReturnOverlay = false
            showCompletionSheet = true
        }
    }

    // MARK: - Return overlay

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
                        Text("\(minutesLeftDisplay) left in the grove")
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

                    Text("The grove's still here. Stay to the end and keep what's left.")
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
                Text("THE GROVE")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Color(hex: 0x9E7E40))
                Text("You focused together.")
                    .font(.serif(26, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                Text(completionBody)
                    .font(.serifItalic(14))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))

                if let streakLine {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xC97B4B))
                        Text(streakLine)
                            .font(.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: 0xC97B4B).opacity(0.12))
                    )
                }

                Text("\(store.totalGroveMinutes) minutes in the grove, all time")
                    .font(.sans(11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))

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

    /// "You and Maya — 4 days in a row" for the first invited friend who
    /// has a live streak after this block.
    private var streakLine: String? {
        guard let fid = participantFriendIds.first,
              let friend = store.friends.first(where: { $0.id == fid }) else { return nil }
        let streak = store.coFocusStreak(with: fid)
        guard streak >= 2 else { return nil }
        return "You and \(friend.displayName) — \(streak) days in a row"
    }

    private var completionBody: String {
        let myLeaves = fallenLeafIDs.count
        if myLeaves == 0 {
            return "Your tree kept every leaf. Each of you finished your own block."
        }
        return "\(myLeaves) leaf\(myLeaves == 1 ? "" : "ves") fell on your side — the grove's still standing."
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
}
