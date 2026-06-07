//
//  FocusGroveView.swift
//  FrisFocus
//
//  Multi-tree grove for shared focus (F2). Renders the same scenery as
//  single-player focus, but with several trees arranged in depth: your
//  tree front-and-largest with full art, friends' trees nearby — set
//  back, slightly smaller, slightly desaturated for atmospheric
//  perspective — with their canopy fullness reflecting a coarse tier
//  (full / thinning / sparse), never a countable ledger.
//
//  This view is pure rendering. `SharedFocusModeView` owns the
//  lifecycle (timer, leave detection, presence publish, nudge) and
//  feeds participants in.
//

import SwiftUI

/// A single participant in the grove. `tier` is the coarse privacy-safe
/// state surface F2 maps real "leaves fallen" counts into.
struct GroveParticipant: Identifiable {
    let id: UUID
    let name: String
    let isYou: Bool
    let tier: FocusTreeView.ThinningTier
    /// In-block vs. stepped-away. Drives the calm "stepped away"
    /// label + the nudge affordance.
    let isSteppedAway: Bool
    /// Distance band: 0 = front (yours), 1 = mid, 2 = back. Drives
    /// scale + saturation + position.
    let depth: Int
    /// Horizontal position (0...1) within the scene.
    let xUnit: CGFloat
    /// Seeded leaf layout so each tree looks distinct from siblings.
    let leafSeed: UInt64
    /// Fallen leaf IDs for this participant. Usually empty for friends
    /// (coarse tier covers the visual), populated for your own tree.
    let fallenLeafIDs: Set<Int>
}

struct FocusGroveView: View {
    let participants: [GroveParticipant]
    let sessionLabel: String
    /// Tapped a friend tree → host opens the nudge / cheer flow.
    let onNudge: ((GroveParticipant) -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        participants: [GroveParticipant] = FocusGroveView.sampleParticipants,
        sessionLabel: String = "TOGETHER · 45 MIN",
        onNudge: ((GroveParticipant) -> Void)? = nil
    ) {
        self.participants = participants
        self.sessionLabel = sessionLabel
        self.onNudge = onNudge
    }

    var body: some View {
        ZStack {
            FocusSceneryView()
                .ignoresSafeArea()

            GeometryReader { geo in
                let size = geo.size
                // Render back depths first, so the front tree paints
                // over them.
                let sorted = participants.sorted { $0.depth > $1.depth }
                ForEach(sorted) { p in
                    treeNode(p, in: size)
                }
            }

            VStack {
                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(sessionLabel)
                        .font(.sans(10, weight: .medium))
                        .tracking(2.4)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.5)))
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                Spacer()
            }
        }
        .background(Color(hex: 0xFAF2E0).ignoresSafeArea())
    }

    // MARK: - Tree node

    private struct DepthLayout {
        let scale: CGFloat
        let yOffset: CGFloat
        let saturation: Double
        let opacity: Double
    }

    private func layout(forDepth depth: Int, sceneHeight: CGFloat) -> DepthLayout {
        switch depth {
        case 0:
            return DepthLayout(scale: 1.0, yOffset: 0, saturation: 1.0, opacity: 1.0)
        case 1:
            return DepthLayout(scale: 0.62, yOffset: -sceneHeight * 0.10, saturation: 0.78, opacity: 0.92)
        default:
            return DepthLayout(scale: 0.46, yOffset: -sceneHeight * 0.18, saturation: 0.6, opacity: 0.82)
        }
    }

    @ViewBuilder
    private func treeNode(_ p: GroveParticipant, in size: CGSize) -> some View {
        let baseHeight = size.height * 0.58
        let dl = layout(forDepth: p.depth, sceneHeight: size.height)
        let scale = dl.scale
        let yOffset = dl.yOffset
        let saturation = dl.saturation
        // Stepped-away friends fade a touch further so the grove
        // signals their absence without alarm.
        let opacity = dl.opacity * (p.isSteppedAway && !p.isYou ? 0.78 : 1.0)

        let treeW = min(size.width * 0.62, 320) * scale
        let treeH = baseHeight * scale
        let yCenter = size.height * 0.55 + yOffset

        let leaves = buildCanopyLeaves(seed: p.leafSeed)

        VStack(spacing: 6) {
            FocusTreeView(
                leaves: leaves,
                fallenLeafIDs: p.fallenLeafIDs,
                thinningTier: p.tier,
                scale: 1.0,
                animatesSway: p.depth == 0
            )
            .frame(width: treeW, height: treeH)
            .saturation(saturation)
            .opacity(opacity)

            VStack(spacing: 2) {
                Text(p.name)
                    .font(.serif(p.isYou ? 14 : 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(p.isYou ? 0.95 : 0.75))
                Text(stateLabel(for: p))
                    .font(.sans(9, weight: .medium))
                    .tracking(1.6)
                    .foregroundStyle(stateColor(for: p).opacity(0.78))
            }
            .opacity(opacity)
        }
        // Whole tree is tappable for friends — opens the nudge flow.
        .contentShape(Rectangle())
        .onTapGesture {
            guard !p.isYou, let onNudge else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onNudge(p)
        }
        .position(x: size.width * p.xUnit, y: yCenter)
    }

    private func stateLabel(for p: GroveParticipant) -> String {
        if p.isYou {
            switch p.tier {
            case .full: return "STILL IN"
            case .thinning: return "STILL IN · A FEW LEAVES"
            case .sparse: return "STILL IN · WINDED"
            }
        }
        if p.isSteppedAway { return "STEPPED AWAY · TAP TO NUDGE" }
        switch p.tier {
        case .full: return "STILL IN"
        case .thinning: return "STILL IN"
        case .sparse: return "STILL IN"
        }
    }

    private func stateColor(for p: GroveParticipant) -> Color {
        if !p.isYou && p.isSteppedAway { return Color(hex: 0x9E7E40) }
        return Theme.alertGreen
    }
}

// MARK: - Sample data

extension FocusGroveView {
    static var sampleParticipants: [GroveParticipant] {
        [
            GroveParticipant(
                id: UUID(),
                name: "You",
                isYou: true,
                tier: .full,
                isSteppedAway: false,
                depth: 0,
                xUnit: 0.50,
                leafSeed: 17,
                fallenLeafIDs: []
            ),
            GroveParticipant(
                id: UUID(),
                name: "Maya",
                isYou: false,
                tier: .full,
                isSteppedAway: false,
                depth: 1,
                xUnit: 0.18,
                leafSeed: 41,
                fallenLeafIDs: []
            ),
            GroveParticipant(
                id: UUID(),
                name: "Jonah",
                isYou: false,
                tier: .thinning,
                isSteppedAway: true,
                depth: 1,
                xUnit: 0.82,
                leafSeed: 73,
                fallenLeafIDs: []
            ),
            GroveParticipant(
                id: UUID(),
                name: "Ari",
                isYou: false,
                tier: .sparse,
                isSteppedAway: false,
                depth: 2,
                xUnit: 0.32,
                leafSeed: 109,
                fallenLeafIDs: []
            ),
        ]
    }
}

#Preview {
    FocusGroveView()
}
