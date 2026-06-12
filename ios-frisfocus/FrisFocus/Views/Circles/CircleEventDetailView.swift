//
//  CircleEventDetailView.swift
//  FrisFocus
//
//  The full picture of a single circle event: a story strip of the
//  proofs posted to it right under the title (tap to play full-screen),
//  description, when & where, the linked task, RSVP buttons + tallies,
//  and the "I'm here" check-in — open from one hour before the start
//  through the end — with a live present-now row. Any member can RSVP
//  and check in; the creator (or a circle owner/admin) can delete it.
//

import Combine
import SwiftUI
import UIKit

struct CircleEventDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let eventId: UUID

    @State private var showProofCapture: Bool = false
    @State private var showProofStory: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var checkInFlourish: Bool = false
    /// Drives a 1s ticking clock so "happening now" / presence refresh
    /// without manual reloads while the screen is open.
    @State private var now: Date = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var event: CircleEvent? { store.event(by: eventId) }
    private var circle: FFCircle? { event.flatMap { store.circle(by: $0.circleId) } }

    var body: some View {
        Group {
            if let event, let circle {
                content(event: event, circle: circle)
            } else {
                missing
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    private var missing: some View {
        VStack(spacing: 12) {
            Text("This event is no longer available.")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
            Button("Close") { dismiss() }
                .font(.sans(14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.warmWheat)
    }

    @ViewBuilder
    private func content(event: CircleEvent, circle: FFCircle) -> some View {
        let tint = circle.type.tint
        let tintDark = circle.type.tintDark
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                headerBlock(event: event, tint: tint, tintDark: tintDark)
                proofStoryStrip(event: event, tint: tint, tintDark: tintDark)
                whenWhereBlock(event: event, tintDark: tintDark)
                if let taskTitle = linkedTaskTitle(event: event, circle: circle) {
                    linkedTaskBlock(title: taskTitle, tintDark: tintDark)
                }
                rsvpBlock(event: event, tint: tint, tintDark: tintDark)
                presenceBlock(event: event, tint: tint, tintDark: tintDark)
                if store.canManageEvent(event) {
                    deleteButton
                }
                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.top, 20)
        }
        .background(Theme.warmWheat)
        .safeAreaInset(edge: .bottom) {
            // Check-in opens an hour before the start and runs through
            // the event's end — the bar covers the whole window.
            if event.isCheckInOpen(at: now) {
                liveActionBar(event: event, circle: circle, tint: tint, tintDark: tintDark)
            }
        }
        .overlay(alignment: .topLeading) { closeButton }
        .fullScreenCover(isPresented: $showProofCapture) {
            if let liveEvent = store.event(by: eventId),
               let liveCircle = store.circle(by: liveEvent.circleId) {
                CaptureView(mode: .eventProof(
                    circle: liveCircle,
                    event: liveEvent,
                    task: linkedTask(event: liveEvent, circle: liveCircle)
                ))
                .environment(store)
            }
        }
        .fullScreenCover(isPresented: $showProofStory) {
            if let liveEvent = store.event(by: eventId) {
                StoryPlayerView(mode: .event(liveEvent))
                    .environment(store)
            }
        }
        .confirmationDialog("Delete this event?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete event", role: .destructive) {
                store.deleteEvent(eventId)
                dismiss()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("RSVPs and check-ins will be removed. Proofs already posted to the circle stay.")
        }
    }

    private var closeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .padding(.leading, Theme.pageHorizontalPadding)
        .padding(.top, 8)
        .accessibilityLabel("Close")
    }

    // MARK: - Header

    private func headerBlock(event: CircleEvent, tint: Color, tintDark: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("EVENT")
                    .font(.sans(10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(tintDark)
                if event.isHappeningNow(at: now) {
                    happeningNowTag(tint: tint, tintDark: tintDark)
                } else if event.isCheckInOpen(at: now) {
                    startingSoonTag(tint: tint, tintDark: tintDark)
                } else if event.repeatRule.repeats {
                    Text(event.repeatRule.summary.uppercased())
                        .font(.sans(10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
            }
            .padding(.top, 30)

            Text(event.title)
                .font(.serif(28, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            if let details = event.details, !details.isEmpty {
                Text(details)
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
            }
        }
    }

    private func happeningNowTag(tint: Color, tintDark: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tintDark).frame(width: 6, height: 6)
                .opacity(checkInFlourish ? 0.5 : 1)
            Text("HAPPENING NOW")
                .font(.sans(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(tintDark)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.18)))
    }

    private func startingSoonTag(tint: Color, tintDark: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.sans(8, weight: .bold))
                .foregroundStyle(tintDark)
            Text("STARTING SOON")
                .font(.sans(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(tintDark)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    // MARK: - Proof story strip

    /// The proofs posted to this event, as a story strip right under
    /// the title — glowing poster-frame bubbles that play full-screen
    /// like any other story. Replaces the old static grid.
    @ViewBuilder
    private func proofStoryStrip(event: CircleEvent, tint: Color, tintDark: Color) -> some View {
        let proofs = store.eventProofs(eventId: event.id).sorted { $0.createdAt < $1.createdAt }
        if proofs.isEmpty {
            if event.isCheckInOpen(at: now) {
                Text("Check in and post the first proof — it'll play here as a story.")
                    .font(.serifItalic(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(tintDark)
                    Text("Event story")
                        .font(.sans(11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(tintDark)
                    Spacer()
                    Text("\(proofs.count) proof\(proofs.count == 1 ? "" : "s")")
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(proofs) { post in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showProofStory = true
                            } label: {
                                EventProofBubble(post: post, tint: tint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play event story")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - When / where

    private func whenWhereBlock(event: CircleEvent, tintDark: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(icon: "calendar", text: dateLine(event: event))
            infoRow(icon: "clock", text: timeLine(event: event))
            if let location = event.location, !location.isEmpty {
                infoRow(icon: "mappin.and.ellipse", text: location)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(width: 18)
            Text(text)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
            Spacer(minLength: 0)
        }
    }

    private func dateLine(event: CircleEvent) -> String {
        event.startAt.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func timeLine(event: CircleEvent) -> String {
        let start = event.startAt.formatted(date: .omitted, time: .shortened)
        if let end = event.endAt {
            return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return start
    }

    // MARK: - Linked task

    private func linkedTask(event: CircleEvent, circle: FFCircle) -> CircleTask? {
        guard let id = event.linkedCircleTaskId else { return nil }
        return circle.tasks.first { $0.id == id }
    }

    private func linkedTaskTitle(event: CircleEvent, circle: FFCircle) -> String? {
        linkedTask(event: event, circle: circle)?.title
    }

    private func linkedTaskBlock(title: String, tintDark: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(tintDark)
            VStack(alignment: .leading, spacing: 1) {
                Text("Linked task")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                Text(title)
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
    }

    // MARK: - RSVP

    private func rsvpBlock(event: CircleEvent, tint: Color, tintDark: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Are you in?")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 8) {
                ForEach(EventRSVPStatus.allCases, id: \.self) { status in
                    rsvpButton(event: event, status: status, tint: tint, tintDark: tintDark)
                }
            }

            let going = store.rsvpMembers(eventId: event.id, status: .going)
            if !going.isEmpty {
                HStack(spacing: 8) {
                    EventMemberStack(memberIds: going, maxVisible: 6)
                    Text("\(going.count) going")
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
        }
    }

    private func rsvpButton(event: CircleEvent, status: EventRSVPStatus, tint: Color, tintDark: Color) -> some View {
        let selected = store.myRSVPStatus(forEventId: event.id) == status
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.setRSVP(eventId: event.id, status: status)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: status.symbolName)
                    .font(.sans(16, weight: .semibold))
                Text(status.displayName)
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.textCream : Theme.textPrimary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? tintDark : Color.white.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Theme.textPrimary.opacity(0.1), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Presence

    private func presenceBlock(event: CircleEvent, tint: Color, tintDark: Color) -> some View {
        let present = store.presentMembers(eventId: event.id, now: now)
        let title = event.isPast(at: now) ? "Who showed up" : "Here now"
        let people = event.isPast(at: now) ? store.attendees(eventId: event.id) : present
        return Group {
            if !people.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(title)
                            .font(.serif(18, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if !event.isPast(at: now) {
                            Text("\(people.count) here now")
                                .font(.sans(12, weight: .medium))
                                .foregroundStyle(tintDark)
                        }
                    }
                    EventMemberStack(memberIds: people, maxVisible: 8)
                }
            }
        }
    }

    // MARK: - Live action bar

    private func liveActionBar(event: CircleEvent, circle: FFCircle, tint: Color, tintDark: Color) -> some View {
        let checkedIn = store.isCheckedIn(eventId: event.id, now: now)
        return HStack(spacing: 10) {
            if checkedIn {
                Label("You're here", systemImage: "checkmark.circle.fill")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.7))
                    )

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showProofCapture = true
                } label: {
                    Label("Post proof", systemImage: "camera.fill")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tintDark))
                }
                .buttonStyle(.plain)
            } else {
                let early = event.isUpcoming(at: now)
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { checkInFlourish = true }
                    store.checkIn(eventId: event.id)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        checkInFlourish = false
                    }
                } label: {
                    VStack(spacing: 2) {
                        Label(early ? "Check in early" : "I'm here", systemImage: "hand.wave.fill")
                            .font(.sans(15, weight: .bold))
                        if early {
                            Text("starts \(event.startAt.formatted(date: .omitted, time: .shortened))")
                                .font(.sans(11, weight: .medium))
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, early ? 11 : 15)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tintDark))
                    .scaleEffect(checkInFlourish ? 1.03 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showDeleteConfirm = true
        } label: {
            Text("Delete event")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(Color(hex: 0xB23B3B))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hex: 0xB23B3B).opacity(0.3), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

// MARK: - Member stack

/// Overlapping member discs for an event — friends get their avatar,
/// the current user a gold ring, unknown circle-only members a grey
/// disc. Compact, non-interactive (presence read-out only).
struct EventMemberStack: View {
    @Environment(Store.self) private var store
    let memberIds: [UUID]
    var maxVisible: Int = 6
    var diameter: CGFloat = 30

    var body: some View {
        let visible = Array(memberIds.prefix(maxVisible))
        let remainder = max(0, memberIds.count - visible.count)
        HStack(spacing: -8) {
            ForEach(Array(visible.enumerated()), id: \.element) { _, id in
                avatar(for: id)
            }
            if remainder > 0 {
                ZStack {
                    Circle().fill(Theme.textPrimary.opacity(0.12))
                    Text("+\(remainder)")
                        .font(.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.4))
            }
        }
    }

    @ViewBuilder
    private func avatar(for id: UUID) -> some View {
        if id == store.currentUserId {
            MyAvatarDisc(size: diameter)
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [Theme.sunWarm, Theme.sunOuter], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.6
                    )
                )
        } else if let friend = store.friend(by: id) {
            FriendAvatarView(friend: friend, size: diameter)
                .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.4))
        } else {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.4))
        }
    }
}

// MARK: - Proof story bubble

/// One glowing story bubble in the event's proof strip. Shows the
/// proof's poster frame ringed in the circle's warm tint; falls back
/// to a caption disc when the media bytes are gone.
struct EventProofBubble: View {
    @Environment(Store.self) private var store
    let post: StoryPost
    let tint: Color

    private let size: CGFloat = 62

    var body: some View {
        let asset = post.mediaId.flatMap { store.media(by: $0) }
        let url = asset?.resolvedThumbnailURL ?? asset?.resolvedLocalURL
        Circle()
            .fill(Theme.textPrimary.opacity(0.08))
            .frame(width: size, height: size)
            .overlay {
                if let url, asset?.type != .video || asset?.resolvedThumbnailURL != nil {
                    CachedImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .allowsHitTesting(false)
                } else if let caption = post.caption {
                    Text(caption)
                        .font(.serifItalic(9, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(6)
                }
            }
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(
                    AngularGradient(
                        colors: [tint, Theme.sunWarm, tint.opacity(0.6), Theme.sunWarm, tint],
                        center: .center
                    ),
                    lineWidth: 2.2
                )
                .padding(-3)
            )
            .overlay(alignment: .bottomTrailing) {
                if asset?.type == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Color.white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .offset(x: 1, y: 1)
                }
            }
            .shadow(color: Theme.sunWarm.opacity(0.35), radius: 6, y: 2)
            .padding(3)
    }
}
