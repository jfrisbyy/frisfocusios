//
//  ColdStartFlowView.swift
//  FrisFocus
//
//  The 60-second cold start: pick a direction (Screen 1), then walk one
//  rich board page per chosen direction (Screen 2). On finish it hands
//  the de-duplicated board to the Store, which lands the person on their
//  real home with the sun low — ready for the first check (Screen 3).
//
//  No account wall, no network on the tile path, no loading spinners.
//

import SwiftUI

struct ColdStartFlowView: View {
    /// Commit the final board → the parent lands on home.
    let onComplete: (_ board: [ColdStartFinalTask], _ directionTitles: [String]) -> Void
    /// Back out to the welcome panel.
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = ColdStartViewModel()
    @State private var phase: Phase = .pick

    private enum Phase { case pick, board }

    var body: some View {
        ZStack {
            // The sky warms from pre-dawn violet (Screen 1) toward a warm
            // horizon as the person walks the direction pages.
            DawnBackdrop(progress: skyProgress)
                .ignoresSafeArea()

            switch phase {
            case .pick:
                DirectionPickView(
                    viewModel: viewModel,
                    onBack: onBack,
                    onContinue: {
                        viewModel.build()
                        advance(to: .board)
                    }
                )
                .transition(stageTransition)

            case .board:
                DirectionBoardContainer(
                    viewModel: viewModel,
                    onBackToPick: { advance(to: .pick) },
                    onFinish: {
                        onComplete(viewModel.finalBoard(), viewModel.directionTitles)
                    }
                )
                .transition(stageTransition)
            }
        }
    }

    /// 0 at the pick screen → ramps toward 1 across the direction pages.
    private var skyProgress: Double {
        switch phase {
        case .pick:
            return 0
        case .board:
            let total = max(1, viewModel.directions.count)
            return 0.35 + 0.65 * (Double(viewModel.index) / Double(total))
        }
    }

    private func advance(to next: Phase) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            phase = next
        }
    }

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99))
    }
}

// MARK: - Dawn backdrop

/// A pre-dawn → dawn sky that warms with `progress` (0…1), with a low
/// sun barely cresting a hairline horizon. The sun rises a little as the
/// person moves through onboarding — a promise of Screen 3's payoff.
struct DawnBackdrop: View {
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = max(0, min(1, progress))

        ZStack {
            LinearGradient(
                colors: [
                    Color.lerpHSL(Color(hex: 0x241B3A), Color(hex: 0x3A2A4E), t: p),
                    Color.lerpHSL(Color(hex: 0x4A3357), Color(hex: 0x8E5A4E), t: p),
                    Color.lerpHSL(Color(hex: 0x8E5A4E), Theme.sunOuter, t: p)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Low sun glow cresting the horizon, rising with progress.
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                RadialGradient(
                    colors: [
                        Theme.sunCore.opacity(0.55 + 0.35 * p),
                        Theme.sunWarm.opacity(0.18),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: 260
                )
                .frame(width: 520, height: 520)
                .position(x: w / 2, y: h * (0.92 - 0.12 * p))
                .blur(radius: 8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: p)
            }
        }
    }
}

#Preview {
    ColdStartFlowView(onComplete: { _, _ in }, onBack: {})
}
