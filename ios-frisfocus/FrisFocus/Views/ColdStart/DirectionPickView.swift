//
//  DirectionPickView.swift
//  FrisFocus
//
//  Screen 1 of the cold start — pick what you're focused on. A grid of
//  focus-area tiles (multi-select, no limit) plus a "+ Something else"
//  free-text route. Springy, haptic, line-icons only. No account, no
//  network — Continue appears once at least one direction is chosen.
//

import SwiftUI

struct DirectionPickView: View {
    @Bindable var viewModel: ColdStartViewModel
    let onBack: () -> Void
    let onContinue: () -> Void
    /// Secondary, quieter route: hand the chosen directions to the season
    /// conversation instead of building the board by hand.
    let onTalkItThrough: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false
    @State private var showFreeText: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(StarterLibrary.focusAreas.enumerated()), id: \.element.id) { idx, area in
                        DirectionTile(
                            area: area,
                            selected: viewModel.isSelected(area.id),
                            onTap: { toggle(area.id) }
                        )
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown ? 0 : 16)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82).delay(Double(idx) * 0.03),
                            value: shown
                        )

                        if idx == StarterLibrary.focusAreas.count - 1 {
                            SomethingElseTile(
                                count: viewModel.customIntents.count,
                                onTap: { showFreeText = true }
                            )
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 16)
                            .animation(
                                reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82).delay(Double(idx + 1) * 0.03),
                                value: shown
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }

            footer
                .padding(.horizontal, 24)
        }
        .padding(.top, 4)
        .onAppear {
            withAnimation { shown = true }
        }
        .sheet(isPresented: $showFreeText) {
            FreeTextSheet(viewModel: viewModel)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .top) {
            backRow.padding(.horizontal, 16).padding(.top, 6)
        }
    }

    // MARK: Pieces

    private var backRow: some View {
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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "LET'S BEGIN", opacity: 0.75, color: Theme.textCream)

            Text("What are you\nfocused on right now?")
                .font(.serif(30, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text("Pick a few. You can change it later.")
                .font(.serifItalic(16, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            // Live count
            Text(countLine)
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.8))
                .contentTransition(.numericText(value: Double(viewModel.selectionCount)))
                .animation(.easeOut(duration: 0.3), value: viewModel.selectionCount)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onContinue()
            } label: {
                HStack(spacing: 10) {
                    Text("Continue")
                        .font(.sans(17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(viewModel.canContinue ? Theme.textPrimary : Theme.textCream.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(viewModel.canContinue ? Theme.textCream : Color.white.opacity(0.14))
                )
                .shadow(color: viewModel.canContinue ? .black.opacity(0.18) : .clear, radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canContinue)
            .animation(.easeInOut(duration: 0.25), value: viewModel.canContinue)

            // The fork — quieter, secondary, only once something's chosen.
            // The board path above stays visually primary.
            if viewModel.canContinue {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTalkItThrough()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 13, weight: .medium))
                        Text("Rather talk it through?")
                            .font(.sans(14, weight: .medium))
                    }
                    .foregroundStyle(Theme.textCream.opacity(0.72))
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.bottom, 8)
    }

    private var countLine: String {
        let n = viewModel.selectionCount
        if n == 0 { return "Choose at least one to continue" }
        return "\(n) selected"
    }

    private func toggle(_ areaId: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            viewModel.toggleArea(areaId)
        }
    }
}

// MARK: - Focus-area tile

private struct DirectionTile: View {
    let area: StarterFocusArea
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 46, height: 46)
                    Image(systemName: area.symbol)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 14)

                Spacer(minLength: 0)

                Text(area.title)
                    .font(.sans(15.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Text(area.subtitle)
                    .font(.sans(11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(height: 150, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [area.tint, area.tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Theme.sunCore : .white.opacity(0.1), lineWidth: selected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.sunCore, area.tint.opacity(0.9))
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: selected ? Theme.sunOuter.opacity(0.45) : .black.opacity(0.12), radius: selected ? 12 : 6, y: 4)
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(area.title). \(area.subtitle)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

// MARK: - "+ Something else" tile

private struct SomethingElseTile: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
                .padding(.bottom, 14)

                Spacer(minLength: 0)

                Text("Something else")
                    .font(.sans(15.5, weight: .semibold))
                    .foregroundStyle(Theme.textCream)

                Text(count > 0 ? "\(count) added" : "Tell us in your words")
                    .font(.sans(11.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.7))
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(height: 150, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Theme.textCream.opacity(count > 0 ? 0.5 : 0.22),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Something else. Type what you're focused on.")
    }
}

// MARK: - Free-text sheet

private struct FreeTextSheet: View {
    @Bindable var viewModel: ColdStartViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var note: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What are you working on?")
                    .font(.serif(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("A few words is plenty — we'll find the right starting tasks.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }

            TextField("e.g. training for a half-marathon", text: $text, axis: .vertical)
                .font(.sans(16, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...3)
                .focused($focused)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.warmWheat)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1)
                )
                .onSubmit(add)

            if let note {
                Text(note)
                    .font(.sans(12.5, weight: .medium))
                    .foregroundStyle(Theme.alertGreen)
                    .transition(.opacity)
            }

            Button(action: add) {
                Text("Add")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(text.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textPrimary.opacity(0.3) : Theme.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Theme.paperCream)
        .onAppear { focused = true }
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let matched = viewModel.submitFreeText(trimmed)
        withAnimation {
            note = matched ? "Added to a matching focus area." : "Added — we'll build a board for it."
        }
        text = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
    }
}
