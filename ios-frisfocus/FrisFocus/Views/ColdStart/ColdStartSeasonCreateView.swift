//
//  ColdStartSeasonCreateView.swift
//  FrisFocus
//
//  Screen B of the cold start's closing beat — create the season. The
//  person names this stretch of life and chooses how it ends. Name is
//  free-text with a rotating, locally-flavored ghost example (zero LLM).
//  Three quiet option cards frame the ending: open-ended (default), a
//  set date (their exact date, never rounded), or "when my milestones
//  land" — shown only when north stars exist. Skip = "Season One",
//  open-ended. Never blocks.
//

import SwiftUI
import Combine

struct ColdStartSeasonCreateView: View {
    @Bindable var viewModel: ColdStartViewModel
    let onBack: () -> Void
    let onCreate: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var nameFocused: Bool
    @State private var ghostIndex: Int = 0
    @State private var shown: Bool = false

    private let ghostTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    prompt
                    nameField
                    endOptions
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { shown = true }
        }
        .onReceive(ghostTimer) { _ in
            guard !reduceMotion else { return }
            let count = max(1, viewModel.seasonNameGhostExamples.count)
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
                skipWithDefaults()
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
            Text("Name this season.")
                .font(.serif(28, weight: .semibold))
                .foregroundStyle(Theme.textCream)
            Text("A season is a stretch of your life with a shape. Give it a name you'd want to look back on.")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 10)
    }

    // MARK: Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "",
                text: $viewModel.seasonName,
                prompt: Text(nameGhost).foregroundColor(Theme.textCream.opacity(0.42))
            )
            .font(.serif(26, weight: .medium))
            .foregroundStyle(Theme.textCream)
            .focused($nameFocused)
            .submitLabel(.done)

            Rectangle()
                .fill(Theme.textCream.opacity(nameFocused ? 0.4 : 0.22))
                .frame(height: 1)
        }
    }

    private var nameGhost: String {
        let examples = viewModel.seasonNameGhostExamples
        guard !examples.isEmpty else { return "Season One" }
        return examples[ghostIndex % examples.count]
    }

    // MARK: End options

    private var endOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW IT ENDS")
                .font(.sans(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textCream.opacity(0.6))

            endCard(
                mode: .openEnded,
                title: "Open-ended",
                subtitle: "until you decide it's done."
            )

            endCard(
                mode: .date,
                title: "A set date",
                subtitle: "choose the day it wraps."
            )

            if viewModel.seasonEndMode == .date {
                DatePicker(
                    "",
                    selection: $viewModel.seasonEndDate,
                    in: tomorrow...,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(Theme.sunCore)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if viewModel.hasMilestones {
                endCard(
                    mode: .milestones,
                    title: "When my milestones land",
                    subtitle: "the season ends when you've done what you named."
                )
            }
        }
    }

    private func endCard(mode: SeasonEndMode, title: String, subtitle: String) -> some View {
        let selected = viewModel.seasonEndMode == mode
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                viewModel.seasonEndMode = mode
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(selected ? Theme.sunCore : Theme.textCream.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sans(15.5, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                    Text(subtitle)
                        .font(.serifItalic(13.5, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.13 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.textCream.opacity(selected ? 0.3 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            nameFocused = false
            onCreate()
        } label: {
            HStack(spacing: 8) {
                Text("Begin the season")
                    .font(.sans(16.5, weight: .semibold))
                Image(systemName: "sun.and.horizon.fill")
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

    // MARK: Helpers

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private func skipWithDefaults() {
        viewModel.seasonName = ""
        viewModel.seasonEndMode = .openEnded
        onCreate()
    }
}

#Preview {
    ZStack {
        DawnBackdrop(progress: 1).ignoresSafeArea()
        ColdStartSeasonCreateView(viewModel: ColdStartViewModel(), onBack: {}, onCreate: {})
    }
}
