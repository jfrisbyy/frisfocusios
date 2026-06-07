//
//  SeasonCheerCard.swift
//  FrisFocus
//
//  The frosted-glass card that lands inbound cheers on the homepage
//  Sun zone. Shows up to two cheers stacked per page; if more than
//  two are active today the card becomes a horizontally-swipeable
//  pager with small dots beneath. Each cheer reads as `{message}`
//  with a small avatar of the sender and a `{name} cheered you on`
//  attribution beneath. Tapping any cheer marks it read but it stays
//  visible for the rest of the day — `Cheer.isActiveToday` is the
//  fade contract, not the read stamp.
//

import SwiftUI
import UIKit

struct SeasonCheerCard: View {
    @Environment(Store.self) private var store

    let cheers: [Cheer]

    @State private var pageIndex: Int = 0
    /// Per-row horizontal drag offset, keyed by cheer id. Lets us
    /// animate the row out before persisting the dismiss.
    @State private var dragOffsets: [UUID: CGFloat] = [:]
    /// Cheer the user tapped — opens the composer so they can send
    /// one back to the original sender.
    @State private var replyTarget: Friend?

    /// Cheers chunked into pages of two so the card can keep the
    /// "up to two visible at once" rule even when there are 5+
    /// active today.
    private var pages: [[Cheer]] {
        guard !cheers.isEmpty else { return [] }
        var result: [[Cheer]] = []
        var idx = 0
        while idx < cheers.count {
            let end = min(idx + 2, cheers.count)
            result.append(Array(cheers[idx..<end]))
            idx = end
        }
        return result
    }

    var body: some View {
        content
            .sheet(item: $replyTarget) { friend in
                CheerComposerView(friend: friend)
            }
    }

    @ViewBuilder
    private var content: some View {
        if pages.isEmpty {
            EmptyView()
        } else if pages.count == 1 {
            cheerPage(pages[0])
                .padding(.horizontal, Theme.pageHorizontalPadding)
        } else {
            VStack(spacing: 8) {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        cheerPage(page)
                            .padding(.horizontal, Theme.pageHorizontalPadding)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: estimatedPageHeight)

                pageDots
            }
        }
    }

    /// The card itself — one page of up to two cheers. The frosted
    /// treatment (cream wash + ultraThinMaterial blur + cream hairline)
    /// is what makes it read as part of the sky rather than a feed
    /// row dropped over it.
    private func cheerPage(_ page: [Cheer]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(page) { cheer in
                cheerRow(cheer)
                if cheer.id != page.last?.id {
                    Rectangle()
                        .fill(Theme.textCream.opacity(0.18))
                        .frame(height: 0.5)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.textCream.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func cheerRow(_ cheer: Cheer) -> some View {
        let offset = dragOffsets[cheer.id] ?? 0
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.markCheerRead(cheer.id)
            if let sender = store.friend(forCheer: cheer) {
                replyTarget = sender
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: cheer.fromColorHex))
                    Text(cheer.fromInitials)
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().strokeBorder(Theme.textCream.opacity(0.35), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("\u{201C}\(cheer.message)\u{201D}")
                        .font(.serifItalic(14, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(cheer.fromName) cheered you on \u{00B7} tap to reply")
                        .font(.sans(10, weight: .regular))
                        .tracking(0.3)
                        .foregroundStyle(Theme.textCream.opacity(0.65))
                }

                Spacer(minLength: 0)

                if cheer.readAt == nil {
                    Circle()
                        .fill(Color(hex: 0xED93B1))
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: offset)
        .opacity(1 - min(abs(offset) / 240, 0.7))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    // Only horizontal drags drive the swipe; vertical
                    // motion is ignored so the parent pager can still
                    // be scrolled.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffsets[cheer.id] = value.translation.width
                }
                .onEnded { value in
                    let width = value.translation.width
                    if abs(width) > 110 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffsets[cheer.id] = width > 0 ? 600 : -600
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            store.dismissCheer(cheer.id)
                            dragOffsets[cheer.id] = nil
                        }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            dragOffsets[cheer.id] = 0
                        }
                    }
                }
        )
        .accessibilityLabel("Cheer from \(cheer.fromName): \(cheer.message)")
        .accessibilityHint("Tap to send one back. Swipe to dismiss.")
        .accessibilityAction(named: "Dismiss") {
            store.dismissCheer(cheer.id)
        }
        .accessibilityAction(named: "Send cheer back") {
            if let sender = store.friend(forCheer: cheer) {
                replyTarget = sender
            }
        }
    }

    /// Page dots beneath the pager. Filled cream for the active
    /// page, half-opacity for the rest. We render our own rather
    /// than relying on `.page(indexDisplayMode: .always)` so the
    /// dots can sit outside the card and read against the night
    /// sky in cream rather than the iOS default tint.
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages.count, id: \.self) { i in
                Circle()
                    .fill(Theme.textCream.opacity(i == pageIndex ? 0.85 : 0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: pageIndex)
    }

    /// Reserved height for the pager so TabView doesn't snap to its
    /// default tall layout. Two-cheer pages stretch a little taller
    /// than single-cheer pages, so we size to the larger value to
    /// avoid a layout jump when the user swipes.
    private var estimatedPageHeight: CGFloat {
        let maxCount = pages.map(\.count).max() ?? 1
        return maxCount >= 2 ? 132 : 76
    }
}

#Preview {
    let store = Store()
    return ZStack {
        LinearGradient(colors: [Color(hex: 0x1A1830), Color(hex: 0x5A4868)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        SeasonCheerCard(cheers: store.activeCheersToday)
            .environment(store)
    }
}
