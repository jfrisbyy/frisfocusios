//
//  NoteTagChipsView.swift
//  FrisFocus
//
//  Small "#tag" chips rendered on note entries and inside the editor.
//  Quiet by design — a charcoal wash capsule with sans 11 text, so
//  tags whisper rather than shout on the paper.
//

import SwiftUI

struct NoteTagChipsView: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 60, maximum: 200), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(tags, id: \.self) { tag in
                    NoteTagChip(tag: tag)
                }
            }
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
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
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
