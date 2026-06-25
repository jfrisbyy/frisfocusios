//
//  DirectionBoardPage.swift
//  FrisFocus
//
//  Screen 2 of the cold start — one rich page per chosen direction,
//  walked one at a time. Everything happens on this single page: keep /
//  drop, drag-to-rank, swipe-to-remove, press-and-hold to edit, add your
//  own, and browse the deeper bench. Native List gives long-press
//  drag-to-rank and swipe-to-remove with springy reflow for free.
//

import SwiftUI

// MARK: - Container (paging across directions)

struct DirectionBoardContainer: View {
    @Bindable var viewModel: ColdStartViewModel
    let onBackToPick: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)

            if viewModel.current != nil {
                DirectionBoardPage(viewModel: viewModel)
                    .id(viewModel.index)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            footer
                .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .top) { topBar.padding(.horizontal, 16).padding(.top, 6) }
    }

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if viewModel.index == 0 {
                    onBackToPick()
                } else {
                    step(to: viewModel.index - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textCream.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            Spacer()
            ProgressDots(count: viewModel.directions.count, index: viewModel.index)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let dir = viewModel.current {
                    ZStack {
                        Circle().fill(.white.opacity(0.2)).frame(width: 40, height: 40)
                        Image(systemName: dir.symbol)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(
                        text: "DIRECTION \(viewModel.index + 1) OF \(viewModel.directions.count)",
                        opacity: 0.8,
                        color: Theme.textCream
                    )
                    Text(viewModel.current?.title ?? "")
                        .font(.serif(24, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Text("Keep what fits. Drag to rank what matters most.")
                .font(.serifItalic(14.5, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text("\(viewModel.keptCountCurrent) task\(viewModel.keptCountCurrent == 1 ? "" : "s") kept · ranked")
                .font(.sans(12.5, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.78))

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    advance()
                } label: {
                    Text("Skip")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textCream.opacity(0.85))
                        .frame(width: 84)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    advance()
                } label: {
                    HStack(spacing: 8) {
                        Text(viewModel.isLastDirection ? "Start tracking" : nextLabel)
                            .font(.sans(16.5, weight: .semibold))
                        Image(systemName: viewModel.isLastDirection ? "sun.and.horizon.fill" : "arrow.right")
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
        .padding(.bottom, 8)
    }

    private var nextLabel: String {
        let next = viewModel.index + 1
        if viewModel.directions.indices.contains(next) {
            return "Next"
        }
        return "Next"
    }

    private func advance() {
        if viewModel.isLastDirection {
            onFinish()
        } else {
            step(to: viewModel.index + 1)
        }
    }

    private func step(to newIndex: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            viewModel.index = max(0, min(viewModel.directions.count - 1, newIndex))
        }
    }
}

// MARK: - Progress dots

private struct ProgressDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.textCream : Theme.textCream.opacity(0.3))
                    .frame(width: i == index ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
            }
        }
    }
}

// MARK: - One direction's page

struct DirectionBoardPage: View {
    @Bindable var viewModel: ColdStartViewModel

    @State private var editingItem: ColdStartViewModel.Item?
    @State private var showBrowseMore: Bool = false
    @State private var showAddField: Bool = false
    @State private var newTaskText: String = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(currentItems) { item in
                    StarterTaskRow(
                        item: item,
                        rank: rank(of: item),
                        onToggleKeep: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.toggleKeep(item.id)
                            }
                        },
                        onEdit: { editingItem = item }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .onMove { source, dest in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.move(from: source, to: dest)
                }
                .onDelete { offsets in
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.remove(at: offsets)
                    }
                }
            } footer: {
                actionRows
                    .padding(.top, 6)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .sheet(item: $editingItem) { item in
            StarterTaskEditSheet(viewModel: viewModel, item: item)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBrowseMore) {
            BrowseMoreSheet(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var currentItems: [ColdStartViewModel.Item] {
        viewModel.current?.items ?? []
    }

    private func rank(of item: ColdStartViewModel.Item) -> Int {
        (currentItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
    }

    // MARK: Add + Browse rows

    private var actionRows: some View {
        VStack(spacing: 10) {
            if showAddField {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.9))
                    TextField("", text: $newTaskText, prompt: Text("Add your own task").foregroundColor(Theme.textCream.opacity(0.5)))
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(commitAdd)
                    Button("Add", action: commitAdd)
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.textCream))
                        .buttonStyle(.plain)
                        .disabled(newTaskText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                actionButton(icon: "plus", label: "Add your own") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showAddField = true }
                    addFocused = true
                }
            }

            actionButton(icon: "square.grid.2x2", label: "Browse more") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showBrowseMore = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.sans(15, weight: .medium))
                Spacer()
            }
            .foregroundStyle(Theme.textCream.opacity(0.92))
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.textCream.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func commitAdd() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let area = viewModel.current?.area
        // Best-effort default grouping from the area's first task.
        let lifeArea = StarterLibrary.tier1(for: area?.id ?? "").first?.lifeArea ?? .work
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.addCustom(label: trimmed, lifeArea: lifeArea)
        }
        newTaskText = ""
        showAddField = false
    }
}

// MARK: - Task row

private struct StarterTaskRow: View {
    let item: ColdStartViewModel.Item
    let rank: Int
    let onToggleKeep: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Keep / drop toggle
            Button(action: onToggleKeep) {
                Image(systemName: item.kept ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(item.kept ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.sans(15.5, weight: .semibold))
                    .foregroundStyle(item.kept ? Theme.textPrimary : Theme.textTertiary)
                    .strikethrough(!item.kept, color: Theme.textTertiary)
                    .lineLimit(1)
                if !item.blurb.isEmpty {
                    Text(item.blurb)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Circle().fill(item.lifeArea.tint).frame(width: 6, height: 6)
                    Text(item.lifeArea.displayName)
                        .font(.sans(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 4)

            // Weight rail — order = importance. Subtle grip hint.
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.18))
                        .frame(width: 14, height: 2)
                }
            }
            .padding(.leading, 2)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.warmWheat.opacity(item.kept ? 0.96 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label). \(item.lifeArea.displayName). Rank \(rank).")
        .accessibilityHint("Double-tap to edit. Swipe to remove.")
    }
}
