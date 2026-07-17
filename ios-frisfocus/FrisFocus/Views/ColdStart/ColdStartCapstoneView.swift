//
//  ColdStartCapstoneView.swift
//  FrisFocus
//
//  Screen A of the cold start's closing beat — the capstone. One free-
//  text field where the person names, in their own words, what would
//  make this season a win. Milestones are never pre-selected from a
//  library: no chips, no suggestion list. A rotating ghost placeholder
//  teaches the SHAPE (not the content), flavored by chosen directions.
//  "+ another" stacks more; skip is always available. Each line saves
//  later as a north star at a hidden default value — no user-visible
//  pricing here.
//

import SwiftUI
import Combine

struct ColdStartCapstoneView: View {
    @Bindable var viewModel: ColdStartViewModel
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedIndex: Int?
    @State private var ghostIndex: Int = 0
    @State private var shown: Bool = false

    private let ghostTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    prompt
                    fields
                    addAnotherButton
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
        .onAppear {
            if viewModel.milestones.isEmpty { viewModel.milestones = [""] }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { shown = true }
        }
        .onReceive(ghostTimer) { _ in
            guard !reduceMotion else { return }
            let count = max(1, viewModel.milestoneGhostExamples.count)
            withAnimation(.easeInOut(duration: 0.35)) {
                ghostIndex = (ghostIndex + 1) % count
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textCream.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onContinue()
            } label: {
                Text("Skip")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textCream.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Prompt

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would make this\nseason a win?")
                .font(.serif(28, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .fixedSize(horizontal: false, vertical: true)
            Text("Name it in your own words. You can add more than one — or skip this.")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 10)
    }

    // MARK: Fields

    private var fields: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.milestones.indices, id: \.self) { i in
                milestoneField(index: i)
            }
        }
    }

    private func milestoneField(index i: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "flag")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.sunCore.opacity(0.9))

            TextField(
                "",
                text: Binding(
                    get: { viewModel.milestones.indices.contains(i) ? viewModel.milestones[i] : "" },
                    set: { if viewModel.milestones.indices.contains(i) { viewModel.milestones[i] = $0 } }
                ),
                prompt: Text(placeholder).foregroundColor(Theme.textCream.opacity(0.42))
            )
            .font(.serif(18, weight: .regular))
            .foregroundStyle(Theme.textCream)
            .focused($focusedIndex, equals: i)
            .submitLabel(.done)

            if viewModel.milestones.count > 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.milestones.remove(at: i)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textCream.opacity(0.55))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textCream.opacity(focusedIndex == i ? 0.32 : 0.14), lineWidth: 1)
        )
    }

    private var placeholder: String {
        let examples = viewModel.milestoneGhostExamples
        guard !examples.isEmpty else { return "name a win…" }
        return examples[ghostIndex % examples.count]
    }

    private var addAnotherButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                viewModel.milestones.append("")
            }
            focusedIndex = viewModel.milestones.count - 1
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("another")
                    .font(.sans(14.5, weight: .semibold))
            }
            .foregroundStyle(Theme.textCream.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            focusedIndex = nil
            onContinue()
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.hasMilestones ? "Continue" : "Skip for now")
                    .font(.sans(16.5, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.textCream)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        DawnBackdrop(progress: 0.8).ignoresSafeArea()
        ColdStartCapstoneView(viewModel: ColdStartViewModel(), onBack: {}, onContinue: {})
    }
}
