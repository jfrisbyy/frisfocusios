//
//  DirectionBoardPage.swift
//  FrisFocus
//
//  Screen 2 of the cold start — one page per chosen direction. Library
//  tasks start UNPLACED in a tray; three labeled bands sit below. Dragging
//  a card into a band is one gesture with two meanings: "this is on my
//  board" AND "this is what it costs me". Cards left in the tray stay off
//  the board. Within a band, top = takes the most out of you. A dim→bright
//  weight rail runs down the left. No numbers anywhere — the sun carries
//  the pricing.
//

import SwiftUI

// MARK: - Container (paging across directions)

struct DirectionBoardContainer: View {
    @Bindable var viewModel: ColdStartViewModel
    let onBackToPick: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFloorAsk: Bool = false

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
        .confirmationDialog(
            "Anything here you'd still do on a rough day?",
            isPresented: $showFloorAsk,
            titleVisibility: .visible
        ) {
            Button("Let me add one") { /* stays on the page */ }
            Button("Not this time", role: .cancel) { proceed() }
        } message: {
            Text("The \u{201C}\(ColdStartBand.floor.title)\u{201D} band keeps your sun above the horizon when everything else falls apart. Totally optional.")
        }
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(hintLine)
                .font(.sans(12.5, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.72))
                .animation(.easeInOut(duration: 0.25), value: viewModel.placedCountCurrent)

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
                    onNext()
                } label: {
                    HStack(spacing: 8) {
                        Text(viewModel.isLastDirection ? "Start tracking" : "Next")
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

    private var hintLine: String {
        viewModel.placedCountCurrent == 0
            ? "Tap a card to add it — drag to choose its band"
            : "Add more, or continue when it feels right"
    }

    /// Next with the single, non-repeating floor nudge.
    private func onNext() {
        if viewModel.shouldAskAboutFloor() {
            viewModel.markFloorAsked()
            showFloorAsk = true
            return
        }
        advance()
    }

    private func proceed() { advance() }

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
    @State private var dropTargetBand: ColdStartBand?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                subDirectionChips
                tray
                prompt
                bands
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .scrollDismissesKeyboard(.interactively)
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

    // MARK: Sub-direction chips

    @ViewBuilder
    private var subDirectionChips: some View {
        let subs = viewModel.availableSubDirections
        if !subs.isEmpty || viewModel.current?.area != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's your thing? Pick any — we'll swap in the real drills.")
                    .font(.sans(12.5, weight: .medium))
                    .foregroundStyle(Theme.textCream.opacity(0.78))

                ColdStartFlowLayout(spacing: 8) {
                    ForEach(subs, id: \.self) { sub in
                        chip(
                            label: sub,
                            selected: viewModel.isSubSelected(sub),
                            icon: viewModel.isSubSelected(sub) ? "checkmark" : nil
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.toggleSub(sub)
                            }
                        }
                    }
                    chip(label: "Something else", selected: false, icon: "plus") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showAddField = true }
                        addFocused = true
                    }
                }

                if showAddField { addField }
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18, weight: .regular))
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowText(text: "IN THE TRAY", opacity: 0.65, color: Theme.textCream)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showBrowseMore = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Browse more")
                            .font(.sans(12.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textCream.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            if viewModel.trayItems.isEmpty {
                Text("Everything's placed. Nice — continue when ready.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ColdStartFlowLayout(spacing: 8) {
                    ForEach(viewModel.trayItems) { item in
                        TrayCard(item: item)
                            .draggable(item.id) {
                                TrayCard(item: item).opacity(0.9)
                            }
                            // Tap-to-place: the fast path. One tap lands
                            // the card in the middle band; dragging stays
                            // for choosing the exact cost. Tap it again
                            // in the band to fine-tune or edit.
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.place(item.id, into: Self.tapPlacementBand)
                                }
                            }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.12), lineWidth: 1)
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.place(id, into: nil)
            }
            return true
        }
    }

    // MARK: Prompt

    /// Where a plain tap lands a tray card — the middle band, the
    /// most common answer. Drag remains the deliberate placement.
    static var tapPlacementBand: ColdStartBand {
        let all = ColdStartBand.allCases
        return all[all.count / 2]
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("When do you actually do these?")
                .font(.serif(22, weight: .semibold))
                .foregroundStyle(Theme.textCream)
            Text("Tap a card to add it — or drag it into the band that fits. What's left behind stays off your board.")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: Bands

    private var bands: some View {
        VStack(spacing: 12) {
            ForEach(ColdStartBand.allCases, id: \.self) { band in
                BandView(
                    band: band,
                    items: viewModel.items(in: band),
                    isTargeted: dropTargetBand == band,
                    onDropOnBand: { id in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            viewModel.place(id, into: band)
                        }
                    },
                    onDropOnCard: { id, beforeId in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            viewModel.place(id, into: band, before: beforeId)
                        }
                    },
                    onTapCard: { item in editingItem = item }
                )
            }
        }
    }

    // MARK: Chip helper

    private func chip(label: String, selected: Bool, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.sans(13.5, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textCream)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(selected ? Theme.textCream : Color.white.opacity(0.1))
            )
            .overlay(
                Capsule().strokeBorder(Theme.textCream.opacity(selected ? 0 : 0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func commitAdd() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let area = viewModel.current?.area
        let lifeArea = StarterLibrary.tier1(for: area?.id ?? "").first?.lifeArea ?? .work
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.addCustom(label: trimmed, lifeArea: lifeArea)
        }
        newTaskText = ""
        showAddField = false
    }
}

// MARK: - Band view

private struct BandView: View {
    let band: ColdStartBand
    let items: [ColdStartViewModel.Item]
    let isTargeted: Bool
    let onDropOnBand: (String) -> Void
    let onDropOnCard: (_ id: String, _ beforeId: String) -> Void
    let onTapCard: (ColdStartViewModel.Item) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Weight rail — dim (floor) → bright (ideal).
            Capsule()
                .fill(Theme.sunCore.opacity(band.railWeight))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(band.title)
                    .font(.sans(13, weight: .bold))
                    .foregroundStyle(Theme.textCream.opacity(0.9))

                if items.isEmpty {
                    Text("Drag a card here")
                        .font(.sans(12.5, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                } else {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            BandCard(item: item)
                                .draggable(item.id) { BandCard(item: item).opacity(0.9) }
                                .onTapGesture { onTapCard(item) }
                                .dropDestination(for: String.self) { ids, _ in
                                    guard let id = ids.first else { return false }
                                    onDropOnCard(id, item.id)
                                    return true
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isTargeted ? 0.16 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Theme.textCream.opacity(items.isEmpty ? 0.16 : 0.28),
                    style: StrokeStyle(lineWidth: 1.2, dash: items.isEmpty ? [6, 5] : [])
                )
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onDropOnBand(id)
            return true
        }
    }
}

// MARK: - Cards

private struct TrayCard: View {
    let item: ColdStartViewModel.Item

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(item.lifeArea.tint).frame(width: 7, height: 7)
            Text(item.label)
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.warmWheat)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct BandCard: View {
    let item: ColdStartViewModel.Item

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(item.lifeArea.tint).frame(width: 8, height: 8)
            Text(item.label)
                .font(.sans(14.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.warmWheat)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Flow layout

/// A simple wrapping flow layout for chips and tray cards.
struct ColdStartFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        var height: CGFloat = 0
        for row in rows {
            let rowHeight = row.map(\.height).max() ?? 0
            height += rowHeight
        }
        height += spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
