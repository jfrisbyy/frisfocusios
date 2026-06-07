//
//  NotesGroupedSections.swift
//  FrisFocus
//
//  Two reusable journal sections shared by the Notes library and the
//  Folder detail page:
//
//  • `PinnedNotesSectionView` — small gold star + PINNED eyebrow, then
//    each pinned note rendered with the standard `NoteEntryView`.
//  • `NoteDayGroupView` — refined serif day header ("Today",
//    "Yesterday", "Tue · Mar 12") with a thin warm-gold rule beneath
//    and a quiet count on the right, then each note in the day.
//
//  Both sections use a soft hairline divider between entries so the
//  page reads like a thoughtfully kept journal rather than a list.
//

import SwiftUI

// MARK: - Pinned section

/// "Pinned" block — eyebrow with a filled gold star, then the entries.
/// Shown above the day-grouped flow when at least one pinned note
/// matches the current selection.
struct PinnedNotesSectionView: View {
    let notes: [Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Theme.sunWarm)
                Text("PINNED")
                    .font(.sans(10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                Spacer(minLength: 0)
                Text(countLabel)
                    .font(.sans(10, weight: .regular))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }

            Rectangle()
                .fill(Theme.sunWarm.opacity(0.6))
                .frame(height: 0.5)

            NotesList(notes: notes)
        }
    }

    private var countLabel: String {
        let n = notes.count
        return "\(n) note\(n == 1 ? "" : "s")"
    }
}

// MARK: - Day group

/// Single day section. Header uses serif and gains a thin warm-gold
/// rule beneath. The day text uses friendly relative phrasing when
/// possible, otherwise an editorial `Tue · Mar 12` format.
struct NoteDayGroupView: View {
    let date: Date
    let notes: [Note]

    private static let weekdayMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerLabel)
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(countLabel)
                    .font(.sans(11, weight: .regular))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }

            Rectangle()
                .fill(Theme.sunWarm.opacity(0.5))
                .frame(height: 0.5)

            NotesList(notes: notes)
        }
    }

    private var headerLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return Self.weekdayMonthDayFormatter.string(from: date)
    }

    private var countLabel: String {
        let n = notes.count
        return "\(n) note\(n == 1 ? "" : "s")"
    }
}

// MARK: - Shared entry list

/// Renders the entries with a soft hairline divider between them.
/// Extracted so the Pinned and Day-Group sections look identical.
private struct NotesList: View {
    let notes: [Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(notes) { note in
                NoteEntryView(note: note)
                if note.id != notes.last?.id {
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.05))
                        .frame(height: 0.5)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        let store = Store()
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PinnedNotesSectionView(notes: store.notes)
                NoteDayGroupView(date: Date(), notes: store.notes)
            }
            .padding(Theme.pageHorizontalPadding)
        }
        .background(Theme.paperCream)
        .environment(store)
    }
}
