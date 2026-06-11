//
//  ProofAttachPickerSheet.swift
//  FrisFocus
//
//  The compact destination picker for attaching a composed proof card:
//  active milestones up top (flag marks + progress), recent notes
//  below, and a search field for older notes. One tap picks; the
//  caller writes the attachment and confirms.
//

import SwiftUI
import UIKit

struct ProofAttachPickerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Offered first — the capture's own milestone when there is one.
    var suggestedMilestoneId: UUID? = nil
    let onPick: (ProofAttachTarget) -> Void

    @State private var search: String = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    /// Milestones in pick order — the suggested one first, then
    /// in-motion in week order, landed ones after.
    private var orderedMilestones: [Milestone] {
        let base = store.attachableMilestones
        guard let suggestedMilestoneId,
              let suggested = base.first(where: { $0.id == suggestedMilestoneId })
        else { return base }
        return [suggested] + base.filter { $0.id != suggestedMilestoneId }
    }

    private var filteredNotes: [Note] {
        let all = store.attachableNotes
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return Array(all.prefix(12)) }
        return all.filter { note in
            let haystacks = [note.body, note.label].compactMap { $0 }
            return haystacks.contains { $0.localizedStandardContains(term) }
        }
    }

    var body: some View {
        ZStack {
            Theme.paperCream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if !orderedMilestones.isEmpty {
                        sectionLabel("MILESTONES")
                        VStack(spacing: 6) {
                            ForEach(orderedMilestones) { milestone in
                                milestoneRow(milestone)
                            }
                        }
                    }

                    sectionLabel("NOTES")
                    searchField

                    if filteredNotes.isEmpty {
                        Text(search.isEmpty
                             ? "No notes yet — write one from the journal first."
                             : "No notes match “\(search)”.")
                            .font(.serifItalic(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                            .padding(.top, 2)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(filteredNotes) { note in
                                noteRow(note)
                            }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 20)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keep this proof")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Pin the designed card to a journey or a note — it outlives the 24h story.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
    }

    // MARK: - Rows

    private func milestoneRow(_ milestone: Milestone) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick(.milestone(milestone.id))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((milestone.isCompleted ? Theme.alertGreen : Theme.sunWarm).opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: milestone.isCompleted ? "flag.checkered" : "flag")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(milestone.isCompleted ? Theme.alertGreen : Theme.sunShadow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.title.isEmpty ? "Untitled milestone" : milestone.title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(milestoneSubtitle(milestone))
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if milestone.id == suggestedMilestoneId {
                    Text("THIS ONE")
                        .font(.sans(8.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.sunShadow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.sunWarm.opacity(0.22)))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        milestone.id == suggestedMilestoneId
                            ? Theme.sunWarm.opacity(0.55)
                            : Theme.textPrimary.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to \(milestone.title)")
    }

    private func milestoneSubtitle(_ milestone: Milestone) -> String {
        if milestone.isCompleted { return "Landed · the journey keeps growing" }
        let done = milestone.steps.filter(\.isCompleted).count
        if milestone.steps.isEmpty { return "Week \(milestone.weekNumber) · in motion" }
        return "Week \(milestone.weekNumber) · \(done) of \(milestone.steps.count) steps"
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick(.note(note.id))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.textPrimary.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(noteTitle(note))
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(Self.dateFormatter.string(from: note.createdAt))
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to note from \(Self.dateFormatter.string(from: note.createdAt))")
    }

    private func noteTitle(_ note: Note) -> String {
        if let label = note.label, !label.isEmpty { return label }
        if let body = note.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }
        if !note.voiceMemos.isEmpty { return "Voice memo" }
        if !note.photos.isEmpty { return "Media note" }
        return "Untitled note"
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            TextField("Search older notes…", text: $search)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
