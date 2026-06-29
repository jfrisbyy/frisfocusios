//
//  NoteTagChipsView.swift
//  FrisFocus
//
//  Small "#tag" chips rendered on note entries and inside the editor.
//  Quiet by design — a charcoal wash capsule with sans 11 text, so
//  tags whisper rather than shout on the paper.
//

import SwiftUI
import UIKit

struct NoteTagChipsView: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    NoteTagChip(tag: tag)
                }
            }
        }
    }
}

/// Home-entry tag display: collapsed by default into a single quiet
/// "N tags" control, expanding inline to the full chip set on tap.
/// Keeps the paper calm while leaving tags one tap away.
struct CollapsibleNoteTagsView: View {
    let tags: [String]

    @State private var isExpanded: Bool = false

    var body: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: toggle) {
                    HStack(spacing: 5) {
                        Image(systemName: "tag")
                            .font(.system(size: 10, weight: .regular))
                        Text("\(tags.count) \(tags.count == 1 ? "tag" : "tags")")
                            .font(.sans(11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide tags" : "Show \(tags.count) tags")

                if isExpanded {
                    NoteTagChipsView(tags: tags)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.22)) {
            isExpanded.toggle()
        }
    }
}

struct NoteTagChip: View {
    let tag: String
    var isSelected: Bool = false

    var body: some View {
        Text("#\(tag)")
            .font(.sans(11, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.65))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Theme.sunWarm.opacity(0.7) : Theme.textPrimary.opacity(0.12),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
    }
}

#Preview {
    NoteTagChipsView(tags: ["idea", "gratitude", "morning pages"])
        .padding()
        .background(Theme.paperCream)
}
