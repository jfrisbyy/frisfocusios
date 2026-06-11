//
//  UnderlineTabSwitcher.swift
//  FrisFocus
//
//  A quiet, premium segment control for the deep-sky surfaces: plain
//  text labels with a thin underline that slides between them. No
//  capsule, no fill — the inactive labels sit dimmed and the active
//  one brightens softly. Used for the Tasks · Stats tab switcher and
//  the Week · Month · Season scope switcher.
//

import SwiftUI
import UIKit

struct UnderlineTabSwitcher: View {
    let items: [String]
    let selectedIndex: Int
    /// Optional VoiceOver labels, one per item; falls back to the
    /// visible text when absent.
    var accessibilityLabels: [String]? = nil
    var onSelect: (Int) -> Void

    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: 30) {
            ForEach(items.indices, id: \.self) { index in
                tabButton(index)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedIndex)
    }

    @ViewBuilder
    private func tabButton(_ index: Int) -> some View {
        let isSelected = index == selectedIndex

        Button {
            guard !isSelected else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(index)
        } label: {
            Text(items[index])
                .font(.sans(13, weight: isSelected ? .semibold : .regular))
                .tracking(0.5)
                .foregroundStyle(Theme.textCream.opacity(isSelected ? 0.95 : 0.45))
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(Theme.textCream.opacity(0.85))
                            .frame(height: 1.5)
                            .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabels?[safe: index] ?? items[index])
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    UnderlineTabSwitcher(items: ["Tasks", "Stats"], selectedIndex: 0) { _ in }
        .padding(40)
        .background(Theme.skyDeep)
}
