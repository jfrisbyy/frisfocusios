//
//  CircleEventsSection.swift
//  FrisFocus
//
//  The "Events" block inside a circle's detail page. Splits the
//  circle's gatherings into Upcoming (soonest first, with a live
//  "happening now" highlight) and Past (finished, with proof counts).
//  Any member can add an event from the header "+".
//

import SwiftUI
import UIKit

struct CircleEventsSection: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    let onCreate: () -> Void
    let onOpenEvent: (CircleEvent) -> Void

    private var upcoming: [CircleEvent] { store.upcomingEvents(forCircleId: circle.id) }
    private var past: [CircleEvent] { store.pastEvents(forCircleId: circle.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if upcoming.isEmpty && past.isEmpty {
                emptyState
            } else {
                if !upcoming.isEmpty {
                    ForEach(upcoming) { event in
                        EventRowCard(event: event, isPast: false) { onOpenEvent(event) }
                    }
                }
                if !past.isEmpty {
                    Text("PAST")
                        .font(.sans(10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                        .padding(.top, 4)
                    ForEach(past.prefix(6)) { event in
                        EventRowCard(event: event, isPast: true) { onOpenEvent(event) }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Events")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onCreate()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.sans(11, weight: .semibold))
                    Text("New")
                        .font(.sans(12, weight: .semibold))
                }
                .foregroundStyle(circle.type.tintDark)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(circle.type.tint.opacity(0.14)))
                .overlay(Capsule(style: .continuous).strokeBorder(circle.type.tint.opacity(0.3), lineWidth: 0.6))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New event")
        }
    }

    private var emptyState: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCreate()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.sans(20, weight: .regular))
                    .foregroundStyle(circle.type.tintDark.opacity(0.8))
                Text("No events yet")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                Text("Plan a run, a meetup, anything — everyone can RSVP and show up together.")
                    .font(.serifItalic(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.textPrimary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event row card

struct EventRowCard: View {
    @Environment(Store.self) private var store
    let event: CircleEvent
    let isPast: Bool
    let onTap: () -> Void

    private var tint: Color {
        store.circle(by: event.circleId)?.type.tint ?? Theme.categorySpiritual
    }
    private var tintDark: Color {
        store.circle(by: event.circleId)?.type.tintDark ?? Theme.categorySpiritual
    }
    private var live: Bool { event.isHappeningNow() }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(spacing: 12) {
                dateBadge
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.serif(16, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if live {
                            liveTag
                        }
                    }
                    Text(metaLine)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .lineLimit(1)
                    footerLine
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(live ? tint.opacity(0.12) : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(live ? tint.opacity(0.5) : Theme.textPrimary.opacity(0.08), lineWidth: live ? 1 : 0.5)
            )
            .contentShape(Rectangle())
            .opacity(isPast ? 0.82 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(metaLine)")
    }

    private var dateBadge: some View {
        VStack(spacing: 1) {
            Text(event.startAt, format: .dateTime.month(.abbreviated)).textCase(.uppercase)
                .font(.sans(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(tintDark)
            Text(event.startAt, format: .dateTime.day())
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 46, height: 46)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.6)
        )
    }

    private var liveTag: some View {
        HStack(spacing: 4) {
            Circle().fill(tintDark).frame(width: 5, height: 5)
            Text("NOW")
                .font(.sans(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(tintDark)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.2)))
    }

    private var metaLine: String {
        var parts: [String] = [event.startAt.formatted(date: .omitted, time: .shortened)]
        if let location = event.location, !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var footerLine: some View {
        if isPast {
            let count = store.eventProofCount(eventId: event.id)
            Text(count == 0 ? "No proofs" : "\(count) proof\(count == 1 ? "" : "s")")
                .font(.sans(11, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        } else {
            let going = store.rsvpCount(eventId: event.id, status: .going)
            let maybe = store.rsvpCount(eventId: event.id, status: .maybe)
            HStack(spacing: 8) {
                if going > 0 {
                    Label("\(going) going", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.alertGreen)
                }
                if maybe > 0 {
                    Text("\(maybe) maybe")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                if going == 0 && maybe == 0 {
                    Text(event.repeatRule.repeats ? event.repeatRule.summary : "Tap to RSVP")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
            }
        }
    }
}
