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
    /// day-1 fork), so the parent can advance its own sequence.
    var onFinished: (() -> Void)? = nil

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
                    onClose: { dismiss() }
                )
                .transition(stageTransition)

            case .conversation:
                SetupConversationView(
                    viewModel: viewModel,
                    onClose: { dismiss() }
                )
                .transition(stageTransition)

            case .review:
                RubricReviewView(viewModel: viewModel)
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

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }
}

#Preview {
    SeasonSetupFlowView()
        .environment(Store())
}
