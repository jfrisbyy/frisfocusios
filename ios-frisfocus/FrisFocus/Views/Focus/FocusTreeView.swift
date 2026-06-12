//
//  FocusTreeView.swift
//  FrisFocus
//
//  The centerpiece tree for Focus Mode (F0 art direction). Each tree is
//  generated from a per-person seed: a unique silhouette (round / tall /
//  wide / leaning), trunk lean + thickness, branch skeleton, and a dense
//  layered canopy of several hundred small leaves drawn in two Canvas
//  passes (shaded back layer, sunlit front layer) with a golden
//  sun-catch glow on the upper-right rim. Greens shift subtly per tree
//  inside the FrisFocus warm-forest palette so a grove reads as a real
//  mixed stand rather than copies.
//
//  Leaves remain addressable by index: callers (F1/F2) drive
//  `fallenLeaves` to drop specific hero leaves on a real "left the app"
//  event. Each fallen leaf tumbles down and settles on the ground band
//  in a warm golden tone, and the dense canopy thins proportionally.
//

import SwiftUI

// MARK: - Leaf data

/// A single addressable leaf's identity within the canopy. The unit
/// position is interpreted as an offset inside one of the tree's
/// foliage clusters so hero leaves always sit on real foliage.
struct CanopyLeaf: Identifiable, Equatable {
    let id: Int
    /// Unit position inside its host cluster's bounding box (0...1).
    let unit: CGPoint
    let rotation: Double
    let size: CGFloat
    /// 0 = darker base, 1 = mid, 2 = sun-catch highlight.
    let toneIndex: Int
}

/// Tiny linear-congruential generator so tree generation stays
/// deterministic across launches / canvas sizes without a heavy RNG.
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

/// Stable per-person tree seed — the same friend always grows the same
/// recognizable tree, distinct from everyone else's.
func treeSeed(for id: UUID) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in id.uuidString.utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x100000001b3
    }
    return hash == 0 ? 17 : hash
}

/// Build the addressable hero-leaf layout. Positions are unit offsets
/// later mapped into the tree's foliage clusters.
func buildCanopyLeaves(count: Int = 26, seed: UInt64 = 17) -> [CanopyLeaf] {
    var rng = SeededRNG(seed: seed)
    var leaves: [CanopyLeaf] = []
    leaves.reserveCapacity(count)

    for i in 0..<count {
        // Sample inside an ellipse so the offset reads as foliage mass.
        var x: Double = 0
        var y: Double = 0
        for _ in 0..<8 {
            let candidateX = rng.range(-1, 1)
            let candidateY = rng.range(-1, 1)
            if (candidateX * candidateX) + (candidateY * candidateY * 1.15) <= 1.0 {
                x = candidateX
                y = candidateY
                break
            }
        }
        y = y * 0.92 - 0.04
        x = x * (x > 0 ? 1.05 : 0.95)

        let ux = (x + 1) * 0.5
        let uy = (y + 1) * 0.5
        let size = CGFloat(rng.range(16, 26))
        let rotation = rng.range(-55, 55)
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

// MARK: - Tree character

/// One foliage mass within the canopy. Unit-space center within the
/// canopy rect; radius as a fraction of canopy width.
struct FoliageCluster {
    let center: CGPoint
    let radius: CGFloat
    /// Vertical squash — clusters are wider than tall.
    let squash: CGFloat
    /// 0 = shaded back, 1 = mid, 2 = sunlit front.
    let depth: Int
    /// Per-cluster RNG seed for its leaf scatter.
    let seed: UInt64
}

/// Deterministic per-seed tree identity: silhouette, trunk geometry,
/// foliage cluster layout, and a subtly shifted warm-forest palette.
struct TreeCharacter {
    enum Silhouette { case round, tall, wide, leaning }

    let seed: UInt64
    let silhouette: Silhouette
    let canopyWidthFraction: CGFloat
    let canopyHeightFraction: CGFloat
    let trunkWidthFactor: CGFloat
    /// Top-of-trunk x offset, in fractions of trunk width (-1...1).
    let trunkLean: CGFloat
    let trunkTopWidthFactor: CGFloat
    /// Overall foliage fullness multiplier (0.85...1.18).
    let density: CGFloat
    let clusters: [FoliageCluster]

    // Palette — darkest shade → sunlit highlight.
    let leafTones: [Color]
    let blobBack: Color
    let blobMid: Color
    let blobFront: Color
    let barkLight: Color
    let barkMid: Color
    let barkDark: Color
    let sunGlow: Color

    init(seed: UInt64) {
        self.seed = seed
        var rng = SeededRNG(seed: seed)

        let silhouetteRoll = rng.unit()
        let shape: Silhouette
        if silhouetteRoll < 0.32 {
            shape = .round
        } else if silhouetteRoll < 0.56 {
            shape = .tall
        } else if silhouetteRoll < 0.80 {
            shape = .wide
        } else {
            shape = .leaning
        }
        silhouette = shape

        let leanDirection: CGFloat = rng.unit() < 0.5 ? -1 : 1

        switch shape {
        case .round:
            canopyWidthFraction = CGFloat(rng.range(0.84, 0.94))
            canopyHeightFraction = CGFloat(rng.range(0.56, 0.62))
            trunkLean = CGFloat(rng.range(-0.25, 0.25))
        case .tall:
            canopyWidthFraction = CGFloat(rng.range(0.68, 0.78))
            canopyHeightFraction = CGFloat(rng.range(0.62, 0.68))
            trunkLean = CGFloat(rng.range(-0.20, 0.20))
        case .wide:
            canopyWidthFraction = CGFloat(rng.range(0.94, 1.00))
            canopyHeightFraction = CGFloat(rng.range(0.50, 0.56))
            trunkLean = CGFloat(rng.range(-0.30, 0.30))
        case .leaning:
            canopyWidthFraction = CGFloat(rng.range(0.84, 0.94))
            canopyHeightFraction = CGFloat(rng.range(0.54, 0.62))
            trunkLean = leanDirection * CGFloat(rng.range(0.50, 0.90))
        }
        trunkWidthFactor = CGFloat(rng.range(0.85, 1.20))
        trunkTopWidthFactor = CGFloat(rng.range(0.36, 0.50))
        density = CGFloat(rng.range(0.85, 1.18))

        // Leaning trees shift their whole canopy toward the lean.
        let xBias: CGFloat = shape == .leaning ? leanDirection * 0.07 : 0

        // Foliage clusters: a crown plus 5–8 masses arranged per
        // silhouette, split into back / mid / front depth bands.
        var built: [FoliageCluster] = []
        let clusterCount = 6 + Int(rng.range(0, 2.99))
        built.append(FoliageCluster(
            center: CGPoint(
                x: 0.5 + xBias + CGFloat(rng.range(-0.05, 0.05)),
                y: CGFloat(rng.range(0.16, 0.24))
            ),
            radius: CGFloat(rng.range(0.20, 0.26)),
            squash: CGFloat(rng.range(0.72, 0.86)),
            depth: 1,
            seed: rng.next()
        ))
        for i in 1..<clusterCount {
            let xRange: (Double, Double)
            let yRange: (Double, Double)
            switch shape {
            case .tall:
                xRange = (0.28, 0.72)
                yRange = (0.22, 0.78)
            case .wide:
                xRange = (0.10, 0.90)
                yRange = (0.30, 0.68)
            default:
                xRange = (0.16, 0.84)
                yRange = (0.26, 0.72)
            }
            let depth = i < clusterCount / 2 ? 0 : (i < clusterCount - 2 ? 1 : 2)
            let radiusScale: CGFloat = depth == 0 ? 1.12 : (depth == 1 ? 1.0 : 0.85)
            built.append(FoliageCluster(
                center: CGPoint(
                    x: CGFloat(rng.range(xRange.0, xRange.1)) + xBias,
                    y: CGFloat(rng.range(yRange.0, yRange.1))
                ),
                radius: CGFloat(rng.range(0.16, 0.27)) * radiusScale,
                squash: CGFloat(rng.range(0.70, 0.88)),
                depth: depth,
                seed: rng.next()
            ))
        }
        clusters = built

        // Palette — warm-forest greens with a per-tree hue / lightness
        // drift so each tree leans a touch warmer, cooler, or deeper.
        let hueShift = rng.range(-0.022, 0.022)
        let lightShift = rng.range(-0.020, 0.020)
        func tone(_ h: Double, _ s: Double, _ l: Double) -> Color {
            Color(hsl: (h: h + hueShift, s: s, l: l + lightShift, a: 1.0))
        }
        leafTones = [
            tone(0.262, 0.62, 0.185),
            tone(0.255, 0.58, 0.245),
            tone(0.245, 0.55, 0.315),
            tone(0.225, 0.52, 0.400),
            tone(0.185, 0.56, 0.500),
        ]
        blobBack = tone(0.265, 0.60, 0.165)
        blobMid = tone(0.255, 0.57, 0.225)
        blobFront = tone(0.245, 0.54, 0.285)
        barkDark = tone(0.075, 0.42, 0.235)
        barkMid = tone(0.082, 0.38, 0.335)
        barkLight = tone(0.090, 0.36, 0.435)
        sunGlow = Color(hsl: (h: 0.118 + hueShift, s: 0.78, l: 0.60, a: 1.0))
    }
}

// MARK: - Shapes

/// Organic teardrop leaf for the addressable hero leaves. Tip points to
/// the right at 0° rotation.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let midY = rect.midY
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

/// Tapered trunk — wider at the ground, narrower at the canopy split,
/// with a per-tree lean and top width so each trunk reads differently.
struct TrunkShape: Shape {
    var lean: CGFloat = 0
    var topWidthFactor: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let topWidth = w * topWidthFactor
        let topCenter = w / 2 + lean * w
        let leftTop = CGPoint(x: topCenter - topWidth / 2, y: 0)
        let rightTop = CGPoint(x: topCenter + topWidth / 2, y: 0)
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
            control: CGPoint(x: topCenter, y: -2)
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
    /// Optional override of hero-leaf data. Pass `nil` to use the seeded
    /// layout derived from `seed`.
    let leaves: [CanopyLeaf]
    /// IDs of leaves that have fallen this session; rendered on the
    /// ground in golden-brown. The dense canopy thins alongside.
    let fallenLeafIDs: Set<Int>
    /// Coarse thinning tier for friends' trees: `nil` leaf data stays
    /// privacy-safe — the canopy just reads fuller or sparser.
    let thinningTier: ThinningTier
    /// Scale factor for grove perspective (1.0 = hero tree).
    let scale: CGFloat
    /// Whether to animate ambient canopy sway. Off for distant grove
    /// trees so the scene stays calm.
    let animatesSway: Bool
    /// Foliage detail budget (1.0 = hero tree, lower for distant grove
    /// trees so the scene stays cheap to draw).
    let detail: CGFloat

    private let character: TreeCharacter

    init(
        leaves: [CanopyLeaf]? = nil,
        fallenLeafIDs: Set<Int> = [],
        thinningTier: ThinningTier = .full,
        scale: CGFloat = 1.0,
        animatesSway: Bool = true,
        seed: UInt64 = 17,
        detail: CGFloat = 1.0
    ) {
        self.leaves = leaves ?? buildCanopyLeaves(seed: seed)
        self.fallenLeafIDs = fallenLeafIDs
        self.thinningTier = thinningTier
        self.scale = scale
        self.animatesSway = animatesSway
        self.detail = detail
        self.character = TreeCharacter(seed: seed)
    }

    enum ThinningTier { case full, thinning, sparse }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            // Canopy anchored near the top; trunk fills from under the
            // canopy down to the ground line (~0.92 of the frame).
            let canopyWidth = size.width * character.canopyWidthFraction
            let canopyHeight = size.height * character.canopyHeightFraction
            let trunkWidth = size.width * 0.13 * character.trunkWidthFactor
            let leanOffset = character.trunkLean * trunkWidth

            let canopyX = (size.width - canopyWidth) / 2 + leanOffset
            let canopyY = size.height * 0.02
            let canopyRect = CGRect(x: canopyX, y: canopyY, width: canopyWidth, height: canopyHeight)

            let trunkTopY = canopyY + canopyHeight * 0.72
            let trunkHeight = size.height * 0.92 - trunkTopY
            let trunkX = (size.width - trunkWidth) / 2
            let trunkRect = CGRect(x: trunkX, y: trunkTopY, width: trunkWidth, height: max(trunkHeight, 10))

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
                    .frame(width: canopyWidth * 0.72, height: size.height * 0.10)
                    .position(x: size.width / 2 + leanOffset * 0.5, y: size.height * 0.93)

                // Trunk shadow layer (slightly offset for depth).
                TrunkShape(lean: character.trunkLean * 0.13, topWidthFactor: character.trunkTopWidthFactor)
                    .fill(character.barkDark)
                    .frame(width: trunkRect.width, height: trunkRect.height)
                    .position(x: trunkRect.midX + 1.5, y: trunkRect.midY)

                // Trunk body — gradient bark.
                TrunkShape(lean: character.trunkLean * 0.13, topWidthFactor: character.trunkTopWidthFactor)
                    .fill(
                        LinearGradient(
                            colors: [character.barkLight, character.barkMid, character.barkDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        TrunkShape(lean: character.trunkLean * 0.13, topWidthFactor: character.trunkTopWidthFactor)
                            .stroke(
                                character.barkDark.opacity(0.30),
                                style: StrokeStyle(lineWidth: 0.6, lineCap: .round)
                            )
                    )
                    .frame(width: trunkRect.width, height: trunkRect.height)
                    .position(x: trunkRect.midX, y: trunkRect.midY)

                // Branch skeleton reaching into the foliage clusters.
                ForEach(Array(branches(trunkRect: trunkRect, canopyRect: canopyRect).enumerated()), id: \.offset) { _, branch in
                    BranchShape(start: branch.start, control: branch.control, end: branch.end)
                        .stroke(
                            character.barkDark,
                            style: StrokeStyle(lineWidth: branch.thickness, lineCap: .round)
                        )
                }

                // Dense foliage — shaded back layer.
                Canvas { ctx, _ in
                    drawFoliage(ctx, canopyRect: canopyRect, depths: [0, 1])
                }
                .frame(width: size.width, height: size.height)
                .modifier(SwayModifier(enabled: animatesSway, amplitude: 1.4, duration: 10.5))

                // Dense foliage — sunlit front layer + golden rim glow.
                Canvas { ctx, _ in
                    drawFoliage(ctx, canopyRect: canopyRect, depths: [2])
                    drawSunCatch(ctx, canopyRect: canopyRect)
                }
                .frame(width: size.width, height: size.height)
                .modifier(SwayModifier(enabled: animatesSway, amplitude: 2.2, duration: 8.0))

                // Hero leaves — individually shaped, addressable, varied
                // tones / rotations. These are the ones that fall.
                ZStack {
                    ForEach(visibleLeaves) { leaf in
                        leafView(leaf, in: canopyRect)
                    }
                }
                .modifier(SwayModifier(enabled: animatesSway, amplitude: 2.6, duration: 9.0))

                // Fallen leaves resting on the ground band.
                ForEach(fallenLeavesArray) { leaf in
                    fallenLeafView(leaf, canopyRect: canopyRect, in: size)
                }
            }
            .scaleEffect(scale, anchor: .bottom)
        }
    }

    // MARK: - Dense foliage drawing

    /// Combined canopy fullness: coarse tier × exact fallen-leaf
    /// fraction, so the dense foliage thins as hero leaves drop.
    private var foliageDensityFactor: CGFloat {
        let tierFactor: CGFloat
        switch thinningTier {
        case .full: tierFactor = 1.0
        case .thinning: tierFactor = 0.55
        case .sparse: tierFactor = 0.28
        }
        let fallenFraction = leaves.isEmpty
            ? 0
            : CGFloat(fallenLeafIDs.count) / CGFloat(leaves.count)
        return tierFactor * (1 - 0.55 * fallenFraction)
    }

    private func drawFoliage(_ ctx: GraphicsContext, canopyRect: CGRect, depths: Set<Int>) {
        let densityFactor = foliageDensityFactor
        guard densityFactor > 0.02 else { return }

        let selected = character.clusters
            .filter { depths.contains($0.depth) }
            .sorted { $0.depth < $1.depth }
        guard !selected.isEmpty else { return }

        let totalWeight = character.clusters.reduce(CGFloat(0)) { $0 + $1.radius * $1.radius }
        let budget = 300 * detail * character.density * densityFactor

        // Sparser trees let more light through their base masses so the
        // skeleton shows and the thinning is unmistakable.
        let blobAlpha: Double
        switch thinningTier {
        case .full: blobAlpha = 0.92
        case .thinning: blobAlpha = 0.70
        case .sparse: blobAlpha = 0.42
        }

        for cluster in selected {
            let cx = canopyRect.minX + cluster.center.x * canopyRect.width
            let cy = canopyRect.minY + cluster.center.y * canopyRect.height
            let r = cluster.radius * canopyRect.width
            let ry = r * cluster.squash

            let blobColor: Color
            switch cluster.depth {
            case 0: blobColor = character.blobBack
            case 1: blobColor = character.blobMid
            default: blobColor = character.blobFront
            }

            // Irregular base mass: three offset sub-blobs per cluster so
            // the silhouette clumps instead of reading as one oval.
            var blobRNG = SeededRNG(seed: cluster.seed)
            for _ in 0..<3 {
                let ox = CGFloat(blobRNG.range(-0.25, 0.25)) * r
                let oy = CGFloat(blobRNG.range(-0.22, 0.22)) * ry
                let sw = r * CGFloat(blobRNG.range(0.72, 1.0))
                let sh = ry * CGFloat(blobRNG.range(0.72, 1.0))
                let blobRect = CGRect(x: cx + ox - sw, y: cy + oy - sh, width: sw * 2, height: sh * 2)
                ctx.fill(Path(ellipseIn: blobRect), with: .color(blobColor.opacity(blobAlpha)))
            }

            // Soft sun-side inner glow on mid/front clusters.
            if cluster.depth >= 1 {
                let gx = cx + r * 0.38
                let gy = cy - ry * 0.42
                let glowRect = CGRect(x: gx - r * 0.7, y: gy - ry * 0.7, width: r * 1.4, height: ry * 1.4)
                ctx.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [character.sunGlow.opacity(0.16), .clear]),
                        center: CGPoint(x: gx, y: gy),
                        startRadius: 0,
                        endRadius: r * 0.8
                    )
                )
            }

            // Individual small leaves scattered across the cluster,
            // brighter toward the upper-right where the light falls.
            let weight = (cluster.radius * cluster.radius) / max(totalWeight, 0.0001)
            let depthBoost: CGFloat = cluster.depth == 0 ? 0.7 : (cluster.depth == 1 ? 1.0 : 1.25)
            let leafCount = max(6, Int(budget * weight * depthBoost))
            let maxTone = cluster.depth == 0 ? 2 : (cluster.depth == 1 ? 3 : 4)
            let baseLeaf = canopyRect.width * 0.034

            var rng = SeededRNG(seed: cluster.seed ^ 0x9E3779B97F4A7C15)
            for _ in 0..<leafCount {
                let angle = rng.range(0, Double.pi * 2)
                let rad = CGFloat(sqrt(rng.unit())) * CGFloat(rng.range(0.92, 1.12))
                let px = cx + CGFloat(cos(angle)) * rad * r
                let py = cy + CGFloat(sin(angle)) * rad * ry

                let nx = Double((px - cx) / max(r, 1))
                let ny = Double((py - cy) / max(ry, 1))
                let sun = 0.5 + 0.45 * nx - 0.5 * ny + rng.range(-0.22, 0.22)
                let toneIndex = min(maxTone, max(0, Int(sun * Double(maxTone + 1))))

                let w = baseLeaf * CGFloat(rng.range(0.62, 1.35))
                let h = w * CGFloat(rng.range(0.50, 0.66))
                let rot = CGFloat(angle + rng.range(-0.6, 0.6))

                let leafPath = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                    .applying(
                        CGAffineTransform(rotationAngle: rot)
                            .concatenating(CGAffineTransform(translationX: px, y: py))
                    )
                ctx.fill(leafPath, with: .color(character.leafTones[toneIndex]))
            }
        }
    }

    /// Golden sun-catch along the canopy's upper-right rim.
    private func drawSunCatch(_ ctx: GraphicsContext, canopyRect: CGRect) {
        guard thinningTier == .full else { return }
        let gx = canopyRect.minX + canopyRect.width * 0.68
        let gy = canopyRect.minY + canopyRect.height * 0.24
        let radius = canopyRect.width * 0.30
        let glowRect = CGRect(x: gx - radius, y: gy - radius * 0.8, width: radius * 2, height: radius * 1.6)
        ctx.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [character.sunGlow.opacity(0.14), .clear]),
                center: CGPoint(x: gx, y: gy),
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    // MARK: - Hero leaves

    /// Leaves currently still on the tree — fallen IDs removed, plus the
    /// thinning tier strips a fraction for distant grove trees.
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

    /// Hero leaves live on the mid/front clusters so they're visible.
    private var heroClusters: [FoliageCluster] {
        let fronts = character.clusters.filter { $0.depth >= 1 }
        return fronts.isEmpty ? character.clusters : fronts
    }

    /// Map an addressable leaf's unit offset into its host cluster.
    private func heroLeafPosition(_ leaf: CanopyLeaf, in canopyRect: CGRect) -> CGPoint {
        let hosts = heroClusters
        let cluster = hosts[leaf.id % hosts.count]
        let cx = canopyRect.minX + cluster.center.x * canopyRect.width
        let cy = canopyRect.minY + cluster.center.y * canopyRect.height
        let r = cluster.radius * canopyRect.width
        let dx = (CGFloat(leaf.unit.x) - 0.5) * 2 * r * 0.85
        let dy = (CGFloat(leaf.unit.y) - 0.5) * 2 * r * cluster.squash * 0.85
        return CGPoint(x: cx + dx, y: cy + dy)
    }

    private func heroLeafColor(_ toneIndex: Int) -> Color {
        switch toneIndex {
        case 0: return character.leafTones[1]
        case 2: return character.leafTones[4]
        default: return character.leafTones[3]
        }
    }

    @ViewBuilder
    private func leafView(_ leaf: CanopyLeaf, in canopyRect: CGRect) -> some View {
        let base = heroLeafColor(leaf.toneIndex)
        let highlight = base.opacity(0.55)
        let position = heroLeafPosition(leaf, in: canopyRect)
        let sizeFactor = max(0.5, min(1.0, canopyRect.width / 300))

        LeafShape()
            .fill(
                LinearGradient(
                    colors: [base, highlight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                LeafShape()
                    .stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: 0.4))
            )
            .frame(width: leaf.size * 1.4 * sizeFactor, height: leaf.size * 0.78 * sizeFactor)
            .rotationEffect(.degrees(leaf.rotation))
            .position(position)
    }

    @ViewBuilder
    private func fallenLeafView(_ leaf: CanopyLeaf, canopyRect: CGRect, in size: CGSize) -> some View {
        // Deterministic resting position derived from the leaf's id so
        // a leaf always lands in roughly the same spot each session.
        var rng = SeededRNG(seed: UInt64(leaf.id) &* 2654435761)
        let restingX = CGFloat(rng.range(-0.32, 0.32)) * size.width + size.width / 2
        let restingY = size.height * (0.90 + CGFloat(rng.range(0, 0.05)))
        let restingRotation = rng.range(-30, 30)

        let startPosition = heroLeafPosition(leaf, in: canopyRect)
        let startOffset = CGSize(
            width: startPosition.x - restingX,
            height: startPosition.y - restingY
        )

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
                        active: FallTransitionModifier(progress: 0, startOffset: startOffset),
                        identity: FallTransitionModifier(progress: 1, startOffset: startOffset)
                    ),
                    removal: .opacity
                )
            )
    }

    // MARK: - Branch skeleton

    private struct Branch {
        var start: CGPoint
        var control: CGPoint
        var end: CGPoint
        var thickness: CGFloat
    }

    /// Limbs reach from the trunk top toward the mid/front cluster
    /// centers, so leaves feel attached to a real skeleton. Deterministic
    /// per seed.
    private func branches(trunkRect: CGRect, canopyRect: CGRect) -> [Branch] {
        var rng = SeededRNG(seed: character.seed ^ 0xB7E15162)
        let topCenter = CGPoint(
            x: trunkRect.midX + character.trunkLean * 0.13 * trunkRect.width,
            y: trunkRect.minY + 4
        )
        let thicknessBase = max(2.5, canopyRect.width * 0.022)
        let targets = character.clusters.filter { $0.depth >= 1 }.prefix(4)

        var out: [Branch] = []
        for (i, cluster) in targets.enumerated() {
            let end = CGPoint(
                x: canopyRect.minX + cluster.center.x * canopyRect.width + CGFloat(rng.range(-6, 6)),
                y: canopyRect.minY + cluster.center.y * canopyRect.height + cluster.radius * canopyRect.width * 0.15
            )
            let pull = CGFloat(rng.range(0.10, 0.32))
            let control = CGPoint(
                x: topCenter.x + (end.x - topCenter.x) * pull,
                y: min(topCenter.y, end.y) - canopyRect.height * CGFloat(rng.range(0.05, 0.15))
            )
            let start = CGPoint(
                x: topCenter.x + (i % 2 == 0 ? -3 : 3),
                y: topCenter.y + CGFloat(rng.range(2, 14))
            )
            out.append(Branch(
                start: start,
                control: control,
                end: end,
                thickness: thicknessBase * CGFloat(rng.range(0.70, 1.15))
            ))
        }
        return out
    }
}

// MARK: - Sway

/// Gentle low-amplitude canopy sway. A repeat-forever offset animation
/// composited by Core Animation — no per-frame body evaluation. Layers
/// use different durations so foliage drifts a touch independently.
private struct SwayModifier: ViewModifier {
    let enabled: Bool
    let amplitude: CGFloat
    var duration: Double = 9.0

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
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
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
    /// Vector from the resting position back up to the leaf's canopy
    /// origin — computed by the tree so the fall starts on real foliage.
    let startOffset: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = max(0, min(1, progress))
        // Eased fall — quick-ish start, soft settle.
        let fall = 1 - pow(1 - p, 2.2)
        let sway = CGFloat(sin(Double(p) * .pi * 2.6)) * 14 * (1 - p)
        let rotation = (1 - p) * 220 + Double(sin(Double(p) * .pi * 3.2)) * 30

        content
            .offset(
                x: startOffset.width * (1 - fall) + sway,
                y: startOffset.height * (1 - fall)
            )
            .rotationEffect(.degrees(rotation))
            .opacity(Double(0.55 + 0.45 * p))
    }
}

#Preview("Unique trees") {
    HStack(spacing: 0) {
        FocusTreeView(seed: treeSeed(for: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()))
            .frame(width: 180, height: 240)
        FocusTreeView(seed: treeSeed(for: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()))
            .frame(width: 180, height: 240)
    }
    .background(Color(hex: 0xFAF2E0))
}
