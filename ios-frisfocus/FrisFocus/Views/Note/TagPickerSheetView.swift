//
//  TagPickerSheetView.swift
//  FrisFocus
//
//  Sheet for choosing a note's tags. Existing tags (from every note)
//  show as toggleable chips; a quiet field at the top creates new tags
//  on the fly. Multi-select — the binding updates live, so the parent
//  form reflects picks immediately.
//

import SwiftUI
import UIKit

struct TagPickerSheetView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The note's tags. Updated in place as the user toggles / creates.
    @Binding var selectedTags: [String]

    @State private var newTag: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paperCream.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        createField

                        if !selectedTags.isEmpty {
                            section(title: "On this note", tags: selectedTags)
                        }

                        let others = availableTags
                        if !others.isEmpty {
                            section(title: "All tags", tags: others)
                        }

                        if selectedTags.isEmpty && availableTags.isEmpty {
                            emptyHint
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
    }

    /// Every known tag not already on this note.
    private var availableTags: [String] {
        let selected = Set(selectedTags.map { $0.lowercased() })
        return store.allNoteTags.filter { !selected.contains($0.lowercased()) }
    }

    // MARK: - Create field

    @ViewBuilder
    private var createField: some View {
        HStack(spacing: 10) {
            Text("#")
                .font(.serif(16, weight: .medium))
                .foregroundStyle(Theme.sunShadow.opacity(0.8))

            TextField("new tag…", text: $newTag)
                .focused($fieldFocused)
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(addNewTag)

            if canAdd {
                Button(action: addNewTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.sunOuter)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Add tag")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    fieldFocused ? Theme.sunWarm.opacity(0.7) : Theme.textPrimary.opacity(0.1),
                    lineWidth: fieldFocused ? 1 : 0.5
                )
        )
        .animation(.easeInOut(duration: 0.15), value: canAdd)
    }

    private var canAdd: Bool {
        !cleanedNewTag.isEmpty
    }

    /// Tags are stored without the leading # and trimmed.
    private var cleanedNewTag: String {
        newTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
    }

    private func addNewTag() {
        let tag = cleanedNewTag
        guard !tag.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !selectedTags.contains(where: { $0.lowercased() == tag.lowercased() }) {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTags.append(tag)
            }
        }
        newTag = ""
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(title: String, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText(text: title, opacity: 0.5)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 70, maximum: 220), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(tags, id: \.self) { tag in
                    let isOn = selectedTags.contains { $0.lowercased() == tag.lowercased() }
                    Button(action: { toggle(tag) }) {
                        NoteTagChip(tag: tag, isSelected: isOn)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ tag: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.18)) {
            if let idx = selectedTags.firstIndex(where: { $0.lowercased() == tag.lowercased() }) {
                selectedTags.remove(at: idx)
            } else {
                selectedTags.append(tag)
            }
        }
    }

    @ViewBuilder
    private var emptyHint: some View {
        VStack(alignment: .center, spacing: 8) {
            EyebrowText(text: "No tags yet", opacity: 0.5)
            Text("Type one above — #idea, #gratitude, anything.")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

#Preview {
    @Previewable @State var tags: [String] = ["idea"]
    return Color.black.opacity(0.2)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TagPickerSheetView(selectedTags: $tags)
                .environment(Store())
        }
}
