//
//  FocusTreeView.swift
//  FrisFocus
//
//  The centerpiece tree for Focus Mode (F0 art direction). Renders a
//  tapering trunk, organic branches, three layered canopy masses, and
//  ~26 individually shaped leaves with hue/size/rotation variation,
//  plus a soft elliptical ground shadow.
//
//  Leaves are addressable by index: callers (F1/F2) drive `fallenLeaves`
//  to drop specific leaves on a real "left the app" event. Each fallen
//  leaf tumbles down and settles on the ground band in a warm golden
//  tone where it stays for the session.
//

import SwiftUI

// MARK: - Leaf data

/// A single leaf's resting position + visual identity within the canopy.
/// Computed once via a small seeded RNG so the tree is deterministic
/// across renders.
struct CanopyLeaf: Identifiable, Equatable {
    let id: Int
    /// Unit position inside the canopy bounding box (0...1).
    let unit: CGPoint
    let rotation: Double
    let size: CGFloat
    /// 0 = darker base, 1 = mid, 2 = sun-catch highlight.
    let toneIndex: Int
}

/// Tiny linear-congruential generator so the leaf layout stays the
/// same across launches / canvas sizes without bringing in a heavy RNG.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed != 0 ? seed : 0x4d595df4d0f33173 }
    mutating func next() -> UInt64 {
        state &*= 6364136223846793005
        state &+= 1442695040888963407
        return state
    }
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + unit() * (upper - lower)
    }
}

/// Build the canopy leaf layout. Leaves are scattered across an
/// asymmetric blob (wider on the sunward side) so the tree looks
/// organic rather than spherical.
func buildCanopyLeaves(count: Int = 26, seed: UInt64 = 17) -> [CanopyLeaf] {
    var rng = SeededRNG(seed: seed)
    var leaves: [CanopyLeaf] = []
    leaves.reserveCapacity(count)

    for i in 0..<count {
        // Sample inside an ellipse with a slight sunward (right) bias.
        var x: Double = 0
        var y: Double = 0
        for _ in 0..<8 {
            let candidateX = rng.range(-1, 1)
            let candidateY = rng.range(-1, 1)
            // Reject samples outside the ellipse so the cluster reads
            // as a foliage mass instead of a square.
            if (candidateX * candidateX) + (candidateY * candidateY * 1.15) <= 1.0 {
                x = candidateX
                y = candidateY
                break
            }
        }
        // Bias upper-half slightly denser (foliage grows up).
        y = y * 0.92 - 0.04
        // Sunward (right) side leans a touch wider.
        x = x * (x > 0 ? 1.05 : 0.95)

        let ux = (x + 1) * 0.5
        let uy = (y + 1) * 0.5
        let size = CGFloat(rng.range(16, 26))
        let rotation = rng.range(-55, 55)
        // Mostly mid-tone with a sprinkle of dark/light leaves; light
        // leaves bias toward the sunward (right/upper) side.
        let toneRoll = rng.unit()
        let tone: Int
        if toneRoll < 0.28 {
            tone = 0
        } else if toneRoll > 0.78 && ux > 0.45 && uy < 0.7 {
            tone = 2
        } else {
            tone = 1
        }
        leaves.append(CanopyLeaf(
            id: i,
            unit: CGPoint(x: ux, y: uy),
            rotation: rotation,
            size: size,
            toneIndex: tone
        ))
    }
    return leaves
}

// MARK: - Shapes

/// Organic teardrop leaf. Tip points to the right at 0° rotation; the
/// view rotates this around its center per leaf.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let midY = rect.midY
        // Stem-end on the left, tip on the right.
        p.move(to: CGPoint(x: 0, y: midY))
        p.addCurve(
            to: CGPoint(x: w, y: midY),
            control1: CGPoint(x: w * 0.25, y: midY - h * 0.55),
            control2: CGPoint(x: w * 0.78, y: midY - h * 0.25)
        )
        p.addCurve(
            to: CGPoint(x: 0, y: midY),
            control1: CGPoint(x: w * 0.78, y: midY + h * 0.25),
            control2: CGPoint(x: w * 0.25, y: midY + h * 0.55)
        )
        p.closeSubpath()
        return p
    }
}

/// Tapered trunk — wider at the ground, narrower at the canopy split.
/// Lightly curved so the silhouette reads as a real tree rather than
/// a lollipop stick.
struct TrunkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let topWidth = w * 0.42
        let leftTop = CGPoint(x: (w - topWidth) / 2 - 1, y: 0)
        let rightTop = CGPoint(x: (w + topWidth) / 2 + 1, y: 0)
        let leftBase = CGPoint(x: -w * 0.05, y: h)
        let rightBase = CGPoint(x: w + w * 0.05, y: h)

        p.move(to: leftBase)
        p.addCurve(
            to: leftTop,
            control1: CGPoint(x: w * 0.08, y: h * 0.55),
            control2: CGPoint(x: leftTop.x - 4, y: h * 0.18)
        )
        p.addQuadCurve(
            to: rightTop,
            control: CGPoint(x: w / 2, y: -2)
        )
        p.addCurve(
            to: rightBase,
            control1: CGPoint(x: rightTop.x + 4, y: h * 0.18),
            control2: CGPoint(x: w * 0.92, y: h * 0.55)
        )
        // Soft root flare at the base.
        p.addQuadCurve(
            to: leftBase,
            control: CGPoint(x: w / 2, y: h + 4)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Branches

/// A single branch curve drawn from the trunk top into the canopy.
struct BranchShape: Shape {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start)
        p.addQuadCurve(to: end, control: control)
        return p
    }
}

// MARK: - Tree view

struct FocusTreeView: View {
    /// Optional override of leaf data. Pass `nil` to use the default
    /// seeded layout. Grove rendering uses different seeds per tree.
    let leaves: [CanopyLeaf]
    /// IDs of leaves that have fallen this session; rendered on the
    /// ground in golden-brown.
    let fallenLeafIDs: Set<Int>
    /// Optional thinning tier for distant grove trees: `nil` = full art,
    /// `.thinning` = ~⅓ leaves dimmed/missing, `.sparse` = ~⅔ missing.
    let thinningTier: ThinningTier
    /// Scale factor for grove perspective (1.0 = hero tree).
    let scale: CGFloat
    /// Whether to animate ambient canopy sway. Off for distant grove
    /// trees so the scene stays calm.
    let animatesSway: Bool

    init(
        leaves: [CanopyLeaf]? = nil,
        fallenLeafIDs: Set<Int> = [],
        thinningTier: ThinningTier = .full,
        scale: CGFloat = 1.0,
        animatesSway: Bool = true
    ) {
        self.leaves = leaves ?? buildCanopyLeaves()
        self.fallenLeafIDs = fallenLeafIDs
        self.thinningTier = thinningTier
        self.scale = scale
        self.animatesSway = animatesSway
    }

    enum ThinningTier { case full, thinning, sparse }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Trunk sits centered horizontally. Canopy occupies the
            // upper ~62 % of the frame; ground band the bottom ~10 %.
            let trunkWidth = size.width * 0.13
            let trunkHeight = size.height * 0.50
            let trunkX = (size.width - trunkWidth) / 2
            let trunkY = size.height * 0.40
            let trunkRect = CGRect(x: trunkX, y: trunkY, width: trunkWidth, height: trunkHeight)

            let canopyHeight = size.height * 0.58
            let canopyWidth = size.width * 0.92
            let canopyX = (size.width - canopyWidth) / 2
            let canopyY = size.height * 0.02
            let canopyRect = CGRect(x: canopyX, y: canopyY, width: canopyWidth, height: canopyHeight)

            ZStack {
                // Ground shadow under the tree — soft warm darkening.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: 0x7A6240).opacity(0.32),
                                Color(hex: 0x7A6240).opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: size.width * 0.34
                        )
                    )
                    .frame(width: size.width * 0.62, height: size.height * 0.10)
                    .position(x: size.width / 2, y: size.height * 0.93)

                // Trunk shadow layer (slightly offset for depth).
                TrunkShape()
                    .fill(Color(hex: 0x6E5232))
                    .frame(width: trunkRect.width, height: trunkRect.height)
                    .offset(x: -1, y: 0)
                    .position(x: trunkRect.midX + 1, y: trunkRect.midY)

                // Trunk body — gradient bark.
                TrunkShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x9C7A55),
                                Color(hex: 0x8A6A48),
                                Color(hex: 0x735030)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: trunkRect.width, height: trunkRect.height)
                    .position(x: trunkRect.midX, y: trunkRect.midY)
                    .overlay(
                        // Faint bark striations.
                        TrunkShape()
                            .stroke(
                                Color(hex: 0x5E4321).opacity(0.18),
                                style: StrokeStyle(lineWidth: 0.6, lineCap: .round)
                            )
                            .frame(width: trunkRect.width, height: trunkRect.height)
                            .position(x: trunkRect.midX, y: trunkRect.midY)
                    )

                // Branches: a few organic curves from trunk top up into
                // the canopy.
                ForEach(branches(trunkRect: trunkRect, canopyRect: canopyRect), id: \.self) { branch in
                    BranchShape(start: branch.start, control: branch.control, end: branch.end)
                        .stroke(
                            Color(hex: 0x6E5232),
                            style: StrokeStyle(lineWidth: branch.thickness, lineCap: .round)
                        )
                }

                // Canopy: three overlapping masses, dark back → light front.
                canopyMasses(in: canopyRect)
                    .modifier(SwayModifier(enabled: animatesSway, amplitude: 1.6))

                // Leaves — individually shaped, varied tones / rotations.
                ZStack {
                    ForEach(visibleLeaves) { leaf in
                        leafView(leaf, in: canopyRect, fallen: false)
                    }
                }
                .modifier(SwayModifier(enabled: animatesSway, amplitude: 2.4))

                // Fallen leaves resting on the ground band.
                ForEach(fallenLeavesArray) { leaf in
                    fallenLeafView(leaf, in: size)
                }
            }
            .scaleEffect(scale, anchor: .bottom)
        }
    }

    // MARK: - Canopy masses

    @ViewBuilder
    private func canopyMasses(in rect: CGRect) -> some View {
        let back = Color(hex: 0x365C18)
        let mid = Color(hex: 0x4E7F22)
        let light = Color(hex: 0x7BA537)

        ZStack {
            // Back layer — deepest, widest, set slightly back-left.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [back.opacity(0.95), back.opacity(0.75)],
                        center: UnitPoint(x: 0.4, y: 0.4),
                        startRadius: 4,
                        endRadius: rect.width * 0.55
                    )
                )
                .frame(width: rect.width * 0.95, height: rect.height * 0.86)
                .offset(x: -rect.width * 0.04, y: rect.height * 0.06)

            // Middle layer.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [mid.opacity(0.96), mid.opacity(0.78)],
                        center: UnitPoint(x: 0.55, y: 0.45),
                        startRadius: 6,
                        endRadius: rect.width * 0.5
                    )
                )
                .frame(width: rect.width * 0.86, height: rect.height * 0.76)
                .offset(x: rect.width * 0.03, y: rect.height * 0.01)

            // Front sun-catch — lighter, smaller, biased to the upper
            // right (sunward).
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [light.opacity(0.85), light.opacity(0.0)],
                        center: UnitPoint(x: 0.65, y: 0.4),
                        startRadius: 4,
                        endRadius: rect.width * 0.36
                    )
                )
                .frame(width: rect.width * 0.7, height: rect.height * 0.6)
                .offset(x: rect.width * 0.08, y: -rect.height * 0.04)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Leaves

    /// Leaves currently still on the tree — fallen IDs removed, and
    /// thinning tier strips an additional fraction for distant grove
    /// trees.
    private var visibleLeaves: [CanopyLeaf] {
        let baseRemaining = leaves.filter { !fallenLeafIDs.contains($0.id) }
        switch thinningTier {
        case .full:
            return baseRemaining
        case .thinning:
            return baseRemaining.filter { $0.id % 3 != 0 }
        case .sparse:
            return baseRemaining.filter { $0.id % 3 == 1 }
        }
    }

    private var fallenLeavesArray: [CanopyLeaf] {
        leaves.filter { fallenLeafIDs.contains($0.id) }
    }

    private func leafColor(_ toneIndex: Int) -> Color {
        switch toneIndex {
        case 0: return Color(hex: 0x365C18)
        case 2: return Color(hex: 0x8FBE3F)
        default: return Color(hex: 0x5C8E26)
        }
    }

    @ViewBuilder
    private func leafView(_ leaf: CanopyLeaf, in rect: CGRect, fallen: Bool) -> some View {
        let base = leafColor(leaf.toneIndex)
        let highlight = base.opacity(0.55)
        let x = rect.minX + CGFloat(leaf.unit.x) * rect.width
        let y = rect.minY + CGFloat(leaf.unit.y) * rect.height * 0.92

        LeafShape()
            .fill(
                LinearGradient(
                    colors: [base, highlight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                // Faint mid-vein.
                LeafShape()
                    .stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: 0.4))
            )
            .frame(width: leaf.size * 1.4, height: leaf.size * 0.78)
            .rotationEffect(.degrees(leaf.rotation))
            .position(x: x, y: y)
            .opacity(fallen ? 0 : 1)
    }

    @ViewBuilder
    private func fallenLeafView(_ leaf: CanopyLeaf, in size: CGSize) -> some View {
        // Deterministic resting position derived from the leaf's id so
        // a leaf always lands in roughly the same spot each session.
        var rng = SeededRNG(seed: UInt64(leaf.id) &* 2654435761)
        let restingX = CGFloat(rng.range(-0.32, 0.32)) * size.width + size.width / 2
        let restingY = size.height * (0.90 + CGFloat(rng.range(0, 0.05)))
        let restingRotation = rng.range(-30, 30)

        LeafShape()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xC4A86A), Color(hex: 0x9E7E40)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                LeafShape()
                    .stroke(Color(hex: 0x6B4D1F).opacity(0.30), style: StrokeStyle(lineWidth: 0.4))
            )
            .frame(width: leaf.size * 1.3, height: leaf.size * 0.72)
            .rotationEffect(.degrees(restingRotation))
            .position(x: restingX, y: restingY)
            .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
            .transition(
                .asymmetric(
                    insertion: .modifier(
                        active: FallTransitionModifier(progress: 0, leaf: leaf, size: size),
                        identity: FallTransitionModifier(progress: 1, leaf: leaf, size: size)
                    ),
                    removal: .opacity
                )
            )
    }

    // MARK: - Branches data

    private struct Branch: Hashable {
        var start: CGPoint
        var control: CGPoint
        var end: CGPoint
        var thickness: CGFloat
    }

    private func branches(trunkRect: CGRect, canopyRect: CGRect) -> [Branch] {
        let trunkTopX = trunkRect.midX
        let trunkTopY = trunkRect.minY + 4
        return [
            Branch(
                start: CGPoint(x: trunkTopX - 4, y: trunkTopY + 6),
                control: CGPoint(x: canopyRect.midX - canopyRect.width * 0.18, y: trunkTopY - canopyRect.height * 0.18),
                end: CGPoint(x: canopyRect.minX + canopyRect.width * 0.25, y: canopyRect.midY),
                thickness: 6
            ),
            Branch(
                start: CGPoint(x: trunkTopX + 4, y: trunkTopY + 6),
                control: CGPoint(x: canopyRect.midX + canopyRect.width * 0.18, y: trunkTopY - canopyRect.height * 0.18),
                end: CGPoint(x: canopyRect.maxX - canopyRect.width * 0.22, y: canopyRect.midY - 6),
                thickness: 6
            ),
            Branch(
                start: CGPoint(x: trunkTopX, y: trunkTopY),
                control: CGPoint(x: trunkTopX + 4, y: trunkTopY - canopyRect.height * 0.32),
                end: CGPoint(x: canopyRect.midX + 6, y: canopyRect.minY + canopyRect.height * 0.34),
                thickness: 5
            ),
            Branch(
                start: CGPoint(x: trunkTopX - 2, y: trunkTopY + 18),
                control: CGPoint(x: canopyRect.minX + canopyRect.width * 0.30, y: canopyRect.midY + 14),
                end: CGPoint(x: canopyRect.minX + canopyRect.width * 0.18, y: canopyRect.maxY - canopyRect.height * 0.10),
                thickness: 4
            ),
        ]
    }
}

// MARK: - Sway

/// Gentle low-amplitude canopy sway. A repeat-forever offset animation
/// composited by Core Animation — no per-frame body evaluation, so the
/// canopy isn't re-rendered 30× per second.
private struct SwayModifier: ViewModifier {
    let enabled: Bool
    let amplitude: CGFloat

    @State private var isSwaying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if !enabled || reduceMotion {
            content
        } else {
            content
                .offset(
                    x: isSwaying ? amplitude : -amplitude,
                    y: isSwaying ? amplitude * 0.3 : -amplitude * 0.3
                )
                .onAppear {
                    // Half-period of the old sin(t × 0.35) sway (~18 s cycle).
                    withAnimation(.easeInOut(duration: 9.0).repeatForever(autoreverses: true)) {
                        isSwaying = true
                    }
                }
        }
    }
}

// MARK: - Fall transition

/// Custom modifier that animates a leaf from its canopy spot down to
/// its resting position with a graceful tumble + sway, then settles.
/// Used as the insertion side of `.transition` for fallen leaves.
struct FallTransitionModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let leaf: CanopyLeaf
    let size: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // We move the leaf from its canopy origin to ground rest. The
        // resting view already positions it at rest, so we apply a
        // negative offset that interpolates back to zero.
        let canopyHeight = size.height * 0.58
        let canopyY = size.height * 0.02 + CGFloat(leaf.unit.y) * canopyHeight * 0.92
        let restingY = size.height * 0.92
        let startOffsetY = canopyY - restingY  // negative (above rest)

        let canopyWidth = size.width * 0.92
        let canopyX = (size.width - canopyWidth) / 2 + CGFloat(leaf.unit.x) * canopyWidth
        let restingX = size.width / 2
        let startOffsetX = canopyX - restingX

        let p = max(0, min(1, progress))
        // Eased fall — quick-ish start, soft settle.
        let fall = 1 - pow(1 - p, 2.2)
        let sway = CGFloat(sin(Double(p) * .pi * 2.6)) * 14 * (1 - p)
        let rotation = (1 - p) * 220 + Double(sin(Double(p) * .pi * 3.2)) * 30

        content
            .offset(
                x: startOffsetX * (1 - fall) + sway,
                y: startOffsetY * (1 - fall)
            )
            .rotationEffect(.degrees(rotation))
            .opacity(Double(0.55 + 0.45 * p))
    }
}
