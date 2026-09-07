//
//  SeasonSetupFlowView.swift
//  FrisFocus
//
//  Host for the season-setup journey: begin → conversation → review →
//  name & frame → the season begins. Owns the view model, advances the
//  stages with gentle cross-fades, and performs the freeze (the rubric
//  lands in the Store; daily scoring is local math thereafter).
//

import SwiftUI

struct SeasonSetupFlowView: View {
    /// When true, the flow drops straight into the saved conversation
    /// instead of showing the begin screen (used by the settings resume).
    var startInResume: Bool = false
    /// The warm-start envelope. When present the conversation opens with
    /// context (directions, board, north stars, logs) instead of cold.
    var coldStartContext: ColdStartContext? = nil
    /// Called instead of `dismiss()` when the flow is hosted inline (the
    /// fork's deep path), so the parent can advance its own sequence.
    var onFinished: (() -> Void)? = nil
    /// Called when the person leaves the flow while hosted inline —
    /// returns to the fork instead of dismissing a sheet that isn't there.
    /// The conversation saves itself, so leaving is always safe.
    var onExit: (() -> Void)? = nil

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel = SeasonSetupViewModel()
    @State private var frozenName: String = ""
    @State private var didStart: Bool = false

    var body: some View {
        ZStack {
            switch viewModel.stage {
            case .begin:
                SetupBeginView(
                    onBegin: { viewModel.begin() },
                    onResume: { viewModel.resume() },
                    onClose: { if let onExit { onExit() } else { dismiss() } }
                )
                .transition(stageTransition)

            case .conversation:
                SetupConversationView(
                    viewModel: viewModel,
                    onClose: { if let onExit { onExit() } else { dismiss() } },
                    onBuildInAMinute: quickPathEscape
                )
                .transition(stageTransition)

            case .review:
                RubricReviewView(viewModel: viewModel)
                    .transition(stageTransition)

            case .shape:
                ShapeYourWeekView(viewModel: viewModel)
                    .transition(stageTransition)

            case .naming:
                SetupNameView(viewModel: viewModel) { name, endMode, endDate in
                    frozenName = name
                    viewModel.lockIn(store: store, name: name, endMode: endMode, endDate: endDate)
                }
                .transition(stageTransition)

            case .begins:
                SetupBeginsView(
                    seasonName: frozenName.isEmpty ? store.currentSeason.name : frozenName,
                    taskCount: store.tasks.count,
                    categoryCount: store.currentSeason.categories.count,
                    milestoneCount: store.currentSeason.milestones.count,
                    onSeeToday: {
                        if let onFinished {
                            onFinished()
                        } else {
                            dismiss()
                        }
                    }
                )
                .transition(stageTransition)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: viewModel.stage)
        .interactiveDismissDisabled(viewModel.stage != .begin)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            viewModel.coldStartContext = coldStartContext
            if startInResume, SeasonSetupResumeStore.hasSaved {
                viewModel.resume()
            }
        }
    }

    /// The escape offered when the conversation can't run: save whatever
    /// was said and go back out through the existing exit, which lands on
    /// the fork and its one-minute door. Only exists when the flow is
    /// hosted inline — a sheet has no fork behind it to fall back to.
    /// Saving means "talk it through any time later" is literally true:
    /// the fork then offers to pick the conversation back up.
    private var quickPathEscape: (() -> Void)? {
        guard let onExit else { return nil }
        return {
            viewModel.saveProgress()
            onExit()
        }
    }

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }
}

#Preview {
    SeasonSetupFlowView()
        .environment(Store())
}
