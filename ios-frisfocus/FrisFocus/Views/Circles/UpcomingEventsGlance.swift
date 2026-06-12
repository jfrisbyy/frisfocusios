//
//  UpcomingEventsGlance.swift
//  FrisFocus
//
//  A compact homescreen card surfacing the user's next circle event
//  across every circle they're in — the soonest thing they've RSVP'd
//  to, always one glance away. Tapping it opens the event.
//

import SwiftUI
import UIKit

struct UpcomingEventsGlance: View {
    @Environment(Store.self) private var store
    /// Called with the event to open when the card is tapped.
    let onOpen: (CircleEvent) -> Void

    private let amber = Color(red: 216.0 / 255, green: 125.0 / 255, blue: 68.0 / 255)

    var body: some View {
        let events = store.myUpcomingEvents(limit: 1)
        if let next = events.first {
            card(for: next)
        }
    }

    private func card(for event: CircleEvent) -> some View {
        let circleName = store.circle(by: event.circleId)?.name ?? "Circle"
        let live = event.isHappeningNow()
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen(event)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(amber.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: live ? "dot.radiowaves.left.and.right" : "calendar")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(amber)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(live ? "Happening now · \(circleName)" : "Upcoming · \(circleName)")
                        .font(.sans(10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    Text(event.title)
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(whenLine(event: event, live: live))
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.paperCream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(amber.opacity(live ? 0.55 : 0.22), lineWidth: live ? 1.2 : 0.6)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(whenLine(event: event, live: live))")
    }

    private func whenLine(event: CircleEvent, live: Bool) -> String {
        if live { return "Tap to check in & post a proof" }
        let cal = Calendar.current
        let timeStr = event.startAt.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(event.startAt) { return "Today · \(timeStr)" }
        if cal.isDateInTomorrow(event.startAt) { return "Tomorrow · \(timeStr)" }
        let dayStr = event.startAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(dayStr) · \(timeStr)"
    }
}
