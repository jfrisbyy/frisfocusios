//
//  NotesSearchField.swift
//  FrisFocus
//
//  Inline paper-tone search field used at the top of the Notes library.
//  Magnifying glass on the left, serif italic placeholder, optional ×
//  to clear, and a warm-gold border tint when the field is focused.
//
//  Used by `NotesLibraryView`; can be lifted into other pages later if
//  the user wants in-folder search.
//

import SwiftUI
import UIKit

struct NotesSearchField: View {
    @Binding var query: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(isFocused ? 0.75 : 0.45))

            TextField("search notes, folders, tags…", text: $query)
                .focused($isFocused)
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !query.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? Theme.sunWarm.opacity(0.7)
                        : Theme.textPrimary.opacity(0.1),
                    lineWidth: isFocused ? 1 : 0.5
                )
        )
        .shadow(
            color: isFocused ? Theme.sunWarm.opacity(0.18) : .clear,
            radius: isFocused ? 6 : 0,
            y: 1
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: query.isEmpty)
    }

    private func clear() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        query = ""
    }
}

#Preview {
    @Previewable @State var q = ""
    return VStack(spacing: 16) {
        NotesSearchField(query: $q)
        NotesSearchField(query: .constant("morning"))
    }
    .padding()
    .background(Theme.paperCream)
}
