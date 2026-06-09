//
//  CircleStoryView.swift
//  FrisFocus
//
//  "Our story" — a warm, scrollable lookback on everything a circle has
//  done together. Each stretch the group ran as a Witness room, a shared
//  list, a shared number, or both becomes a chapter on a vertical
//  timeline: when it ran, how it ended, and the proofs from that stretch.
//
//  This is the group's shared memory, mirroring the per-friend "since you
//  connected" warmth at the group level. Finished goals are proud
//  chapters, not deleted data — never a scoreboard or a ranking.
//

import SwiftUI

struct CircleStoryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let circleId: UUID

    private var circle: FFCircle? { store.circles.first { $0.id == circleId } }

    /// The whole timeline, oldest first — read like a story from the
    /// beginning, the current chapter waiting at the end.
    private var chapters: [CircleChapter] {
        (circle?.chapters ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let circle {
                    content(for: circle)
                } else {
                    Text("This circle is no longer available.")
                        .font(.serifItalic(15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.warmWheat)
                }
            }
            .navigationTitle("Our story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    private func content(for circle: FFCircle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                intro(for: circle)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 22)

                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    chapterRow(
                        chapter,
                        circleId: circle.id,
                        isFirst: index == 0,
                        isLast: index == chapters.count - 1
                    )
                    .padding(.horizontal, 22)
                }

                footer(for: circle)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
            }
        }
        .background(Theme.warmWheat)
    }

    // MARK: - Intro

    private func intro(for circle: FFCircle) -> some View {
        let chapterCount = chapters.count
        let finished = chapters.filter { $0.outcome == .completed }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(circle.name.uppercased())
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text("What we\u{2019}ve done together")
                .font(.serif(26, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(summaryLine(chapterCount: chapterCount, finished: finished))
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryLine(chapterCount: Int, finished: Int) -> String {
        if chapterCount <= 1 { return "The beginning of something." }
        if finished == 0 { return "\(chapterCount) chapters, and still going." }
        if finished == 1 { return "\(chapterCount) chapters \u{00b7} 1 goal finished together." }
        return "\(chapterCount) chapters \u{00b7} \(finished) goals finished together."
    }

    // MARK: - Chapter row

    private func chapterRow(_ chapter: CircleChapter, circleId: UUID, isFirst: Bool, isLast: Bool) -> some View {
        let tint = chapter.type.tint
        let moments = store.storyPosts(forCircleId: circleId, in: chapter).count

        return HStack(alignment: .top, spacing: 14) {
            // Timeline rail: connecting line + node.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Theme.textPrimary.opacity(0.12))
                    .frame(width: 1.5, height: 14)
                ZStack {
                    Circle()
                        .fill(chapter.isCurrent ? tint : Theme.warmWheat)
                        .frame(width: 14, height: 14)
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                        .frame(width: 14, height: 14)
                    Image(systemName: chapterIcon(chapter))
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(chapter.isCurrent ? Theme.textCream : tint)
                }
                Rectangle()
                    .fill(isLast ? Color.clear : Theme.textPrimary.opacity(0.12))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 16)

            card(chapter, tint: tint, moments: moments)
                .padding(.bottom, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ chapter: CircleChapter, tint: Color, moments: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(chapterEyebrow(chapter))
                    .font(.sans(9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(tint)
                Spacer()
                outcomeChip(chapter, tint: tint)
            }

            Text(chapter.title)
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            if let detail = chapter.detail, !detail.isEmpty {
                Text(detail)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Label(dateRange(chapter), systemImage: "calendar")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .labelStyle(.titleAndIcon)
                if moments > 0 {
                    Label(moments == 1 ? "1 moment" : "\(moments) moments", systemImage: "photo.on.rectangle.angled")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.top, 2)

            if let actor = chapter.actorName, !actor.isEmpty {
                Text(actorLine(chapter, actor: actor))
                    .font(.serifItalic(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(chapter.isCurrent ? tint.opacity(0.1) : Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(chapter.isCurrent ? tint.opacity(0.3) : Theme.textPrimary.opacity(0.08), lineWidth: chapter.isCurrent ? 1 : 0.5)
        )
    }

    @ViewBuilder
    private func outcomeChip(_ chapter: CircleChapter, tint: Color) -> some View {
        switch chapter.outcome {
        case .ongoing:
            chip("NOW", color: tint, filled: true)
        case .completed:
            chip("FINISHED", color: Theme.alertGreen, filled: false)
        case .setAside:
            chip("SET ASIDE", color: Theme.textPrimary.opacity(0.45), filled: false)
        case .returned:
            EmptyView()
        }
    }

    private func chip(_ text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.sans(9, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(filled ? Theme.textCream : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? color : color.opacity(0.14))
            )
    }

    // MARK: - Footer

    private func footer(for circle: FFCircle) -> some View {
        Text("Nothing here is ever deleted \u{2014} a goal set aside is only sleeping, ready to pick back up whenever you like.")
            .font(.serifItalic(12, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.45))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
    }

    // MARK: - Derived copy

    private func chapterEyebrow(_ chapter: CircleChapter) -> String {
        switch chapter.type {
        case .witness: return "PRESENCE"
        case .parallel: return "SHARED LIST"
        case .collective: return "SHARED NUMBER"
        case .hybrid: return "TWO GOALS"
        }
    }

    private func chapterIcon(_ chapter: CircleChapter) -> String {
        switch chapter.type {
        case .witness: return "moon.stars.fill"
        case .parallel: return "checklist"
        case .collective: return "number"
        case .hybrid: return "square.on.square"
        }
    }

    private func actorLine(_ chapter: CircleChapter, actor: String) -> String {
        let what: String
        switch chapter.type {
        case .witness: return "\(actor) set the goal aside"
        case .parallel: what = "a shared list"
        case .collective: what = "a shared number"
        case .hybrid: what = "a second goal"
        }
        return "\(actor) switched the circle to \(what)"
    }

    private func dateRange(_ chapter: CircleChapter) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        let start = f.string(from: chapter.startedAt)
        if let end = chapter.endedAt {
            return "\(start) \u{2013} \(f.string(from: end)) \u{00b7} \(durationText(chapter.startedAt, end))"
        }
        return "\(start) \u{2013} now \u{00b7} \(durationText(chapter.startedAt, Date()))"
    }

    private func durationText(_ start: Date, _ end: Date) -> String {
        let days = max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
        if days < 14 { return days == 1 ? "1 day" : "\(days) days" }
        if days < 60 { return "\(days / 7) weeks" }
        let months = max(1, days / 30)
        return months == 1 ? "1 month" : "\(months) months"
    }
}
