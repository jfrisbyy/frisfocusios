//
//  SharedCircleStoryView.swift
//  FrisFocus
//
//  "Our story" for a synced shared circle — the warm group-level lookback,
//  matching the labels and colors of the night-sky room. It shows where
//  the circle began and the chapter it's living now, with the same calm,
//  never-a-scoreboard tone. Switching modes is recorded here as the
//  circle's shape changes, and the safe-switching promise is front and
//  center: nothing is ever deleted.
//

import SwiftUI

struct SharedCircleStoryView: View {
    @Environment(\.dismiss) private var dismiss

    let circle: SharedCircle

    private var tint: Color { circle.kind.tint }
    private var tintDark: Color { circle.kind.tintDark }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    chapterCard
                    if let started = circle.createdAt {
                        foundingNote(started)
                    }
                    footerNote
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.warmWheat)
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(circle.name.uppercased())
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text("What we\u{2019}re doing together")
                .font(.serif(26, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chapterCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(tint).frame(width: 14, height: 14)
                    Image(systemName: chapterIcon)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Theme.textCream)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(chapterEyebrow)
                        .font(.sans(9, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(tint)
                    Spacer()
                    Text("NOW")
                        .font(.sans(9, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textCream)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(tint))
                }
                Text(chapterTitle)
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(chapterDetail)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(tint.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func foundingNote(_ started: Date) -> some View {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d, yyyy"
        return Label("Together since \(f.string(from: started))", systemImage: "sparkles")
            .font(.sans(12, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .labelStyle(.titleAndIcon)
    }

    private var footerNote: some View {
        Text("Switch modes anytime \u{2014} add a goal, set one aside, or run both. Nothing is ever deleted; a goal set aside is only sleeping, ready to pick back up.")
            .font(.serifItalic(12, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.45))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    // MARK: - Derived copy

    private var chapterEyebrow: String {
        switch circle.kind {
        case .witness: return "PRESENCE"
        case .parallel: return "SHARED LIST"
        case .collective: return "SHARED NUMBER"
        case .hybrid: return "TWO GOALS"
        }
    }

    private var chapterIcon: String {
        switch circle.kind {
        case .witness: return "moon.stars.fill"
        case .parallel: return "checklist"
        case .collective: return "number"
        case .hybrid: return "square.on.square"
        }
    }

    private var chapterTitle: String {
        switch circle.kind {
        case .witness: return "Just present"
        case .parallel: return "Shared list"
        case .collective: return "Shared number"
        case .hybrid: return "Two goals"
        }
    }

    private var chapterDetail: String {
        switch circle.kind {
        case .witness:
            return "Everyone keeps their own goals \u{2014} a calm room you're in together."
        case .parallel:
            return circle.tasks.isEmpty ? "A shared checklist, each on their own copy." : "\(circle.tasks.count) shared task\(circle.tasks.count == 1 ? "" : "s"), each on their own copy."
        case .collective:
            if let target = circle.collectiveTarget {
                return "Building toward \(circleNumber(target)) \(circle.collectiveUnit ?? "") together.".replacingOccurrences(of: "  ", with: " ")
            }
            return "One number you build toward together."
        case .hybrid:
            return "A shared list and a shared number, side by side."
        }
    }
}
