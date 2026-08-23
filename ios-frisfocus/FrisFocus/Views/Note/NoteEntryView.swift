//
//  NoteEntryView.swift
//  FrisFocus
//
//  A single journal entry, rendered on the paper background. Shows
//  the created-at time, the folder dot + label (if either is set),
//  the serif italic body, photo thumbnails, tag chips, and a quiet
//  read-only voice-memo badge if an audio clip is attached. The whole
//  row is wrapped in a `NavigationLink` so tapping anywhere on it
//  pushes the `NoteDetailEditView`.
//

import SwiftUI

struct NoteEntryView: View {
    let note: Note
    /// When provided, tapping the row calls this instead of pushing the
    /// full editor — the homepage uses it to open the inline composer.
    var onTap: ((Note) -> Void)? = nil
    @Environment(Store.self) private var store

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        if let onTap {
            Button {
                onTap(note)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                NoteDetailEditView(note: note)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow

            // The note's title leads the entry — same paper, larger serif
            // — so lists read title-first while the document stays whole.
            if let title = note.label, !title.isEmpty {
                Text(title)
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let body = note.body, !body.isEmpty {
                NoteBodyText(text: body, size: 16, lineSpacing: 6)
            }

            if !note.photos.isEmpty {
                photoRow
                    .padding(.top, 2)
            }

            if note.voiceMemoFilename != nil {
                VoiceMemoLabelView(duration: note.voiceMemoDuration ?? 0)
                    .padding(.top, 2)
            }

            if store.noteTagsEnabled && !note.tags.isEmpty {
                CollapsibleNoteTagsView(tags: note.tags)
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 8) {
            // Tiny warm-gold star when the note is pinned — mirrors the
            // PINNED eyebrow in the library so the indicator reads the
            // same way across surfaces.
            if note.isPinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Theme.sunWarm)
            }

            Text(Self.timeFormatter.string(from: note.createdAt).uppercased())
                .font(.sans(10, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))

            if let folder = store.folder(for: note) {
                dotSeparator
                HStack(spacing: 4) {
                    Circle()
                        .fill(folder.colorKey.dotColor)
                        .frame(width: 5, height: 5)
                    Text(folder.name)
                        .font(.sans(10, weight: .regular))
                        .foregroundStyle(folder.colorKey.pillText.opacity(0.85))
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Compact read-only photo strip — up to three small rounded
    /// thumbnails with a quiet "+n" overflow badge. Tapping the row
    /// still navigates to the editor where the full grid lives.
    @ViewBuilder
    private var photoRow: some View {
        HStack(spacing: 6) {
            ForEach(note.photos.prefix(3)) { photo in
                NotePhotoThumbView(photo: photo)
                    .frame(width: 72, height: 72)
                    .allowsHitTesting(false)
            }
            if note.photos.count > 3 {
                Text("+\(note.photos.count - 3)")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .frame(width: 36, height: 72)
                    .background(Color.white.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Spacer(minLength: 0)
        }
    }

    private var dotSeparator: some View {
        Circle()
            .fill(Theme.textPrimary.opacity(0.3))
            .frame(width: 4, height: 4)
    }
}

#Preview {
    NavigationStack {
        let store = Store()
        VStack(spacing: 20) {
            ForEach(store.notes) { note in
                NoteEntryView(note: note)
            }
        }
        .padding()
        .background(Theme.paperCream)
        .environment(store)
    }
}
