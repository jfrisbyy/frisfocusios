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

    /// Horizontal swipe offset while the user drags the card away.
    @State private var dragX: CGFloat = 0

    private let amber = Color(red: 216.0 / 255, green: 125.0 / 255, blue: 68.0 / 255)

    /// The next event worth surfacing. Skips occurrences the user
    /// swiped away, and — the key rule — anything they've already
    /// checked into: once you're checked in, the nag is done.
    private var nextEvent: CircleEvent? {
        store.myUpcomingEvents(limit: 5).first { event in
            guard !store.isEventGlanceDismissed(event.id) else { return false }
            guard !store.hasEverCheckedIn(eventId: event.id) else { return false }
            return true
        }
    }

    var body: some View {
        if let next = nextEvent {
            card(for: next)
                .offset(x: dragX)
                .opacity(1 - min(0.9, abs(dragX) / 220))
                .simultaneousGesture(swipeAway(for: next))
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: dragX)
        }
    }

    /// Horizontal swipe-to-dismiss. Only claims horizontal-dominant
    /// drags so the page's vertical scroll keeps working over the card.
    private func swipeAway(for event: CircleEvent) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                let flungFar = abs(value.translation.width) > 90
                let flungFast = abs(value.predictedEndTranslation.width) > 220
                if (flungFar || flungFast), abs(value.translation.width) > abs(value.translation.height) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.22)) {
                        dragX = value.translation.width < 0 ? -500 : 500
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        store.dismissEventGlance(event.id)
                        dragX = 0
                    }
                } else {
                    dragX = 0
                }
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
        if event.isCheckInOpen() { return "Starting soon · check in early" }
        let cal = Calendar.current
        let timeStr = event.startAt.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(event.startAt) { return "Today · \(timeStr)" }
        if cal.isDateInTomorrow(event.startAt) { return "Tomorrow · \(timeStr)" }
        let dayStr = event.startAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(dayStr) · \(timeStr)"
    }
}
