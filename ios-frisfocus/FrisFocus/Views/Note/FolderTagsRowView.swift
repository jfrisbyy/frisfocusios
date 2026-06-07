//
//  FolderTagsRowView.swift
//  FrisFocus
//
//  Pill row showing the user's folders along the bottom of the Note
//  zone. Each pill uses its folder's `colorKey` for tint, falling
//  through to a quiet grey when the colour can't be resolved. The
//  right-aligned "all folders →" link is tappable too — it dismisses
//  the row's selection callback with `nil`, which the parent uses to
//  navigate to the full notes library.
//

import SwiftUI

struct FolderTagsRowView: View {
    let folders: [NoteFolder]
    /// Called when the user taps a folder pill. Pass `nil` for the
    /// "all folders" link. The parent decides what to do — typically
    /// navigates to NotesLibraryView pre-filtered to that folder.
    var onSelect: ((NoteFolder?) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(folders) { folder in
                pill(for: folder)
            }

            Spacer(minLength: 0)

            Button(action: { onSelect?(nil) }) {
                HStack(spacing: 4) {
                    Text("all folders")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func pill(for folder: NoteFolder) -> some View {
        Button(action: { onSelect?(folder) }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(folder.colorKey.dotColor)
                    .frame(width: 5, height: 5)
                Text(folder.name)
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(folder.colorKey.pillText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(folder.colorKey.pillBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        FolderTagsRowView(
            folders: [
                NoteFolder(name: "Songs", colorKey: .purple),
                NoteFolder(name: "Prayer", colorKey: .green),
                NoteFolder(name: "Work", colorKey: .blue)
            ]
        )
        FolderTagsRowView(
            folders: [
                NoteFolder(name: "Ideas", colorKey: .pink),
                NoteFolder(name: "Letters", colorKey: .dusk)
            ]
        )
        FolderTagsRowView(folders: [])
    }
    .padding()
    .background(Theme.paperCream)
}
