//
//  GoldenHourHostView.swift
//  FrisFocus
//
//  The single full-screen entry into one circle's Golden Hour. Routes by
//  the moment's live phase, re-evaluated every half-second:
//
//   • live + I haven't posted  → the countdown camera.
//   • live + I posted          → the wall (others stream in live).
//   • viewing                  → the wall (blurred forever if I missed).
//   • upcoming / over / off    → the residue card — attendance + streak,
//                                never media. "Nowhere after" by design.
//
//  Presented from the golden orb, the circle detail, and tapped
//  Golden Hour notifications (the `golden` deep-link route).
//

import SwiftUI

struct GoldenHourHostView: View {
    let circleId: UUID

    @Environment(GoldenHourService.self) private var service
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var didLoad = false

    private var myUserId: String { auth.user?.id ?? "" }

    var body: some View {
        @Bindable var service = service

        ZStack {
            GoldenTheme.ink.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                content(now: context.date)
            }
        }
        .task {
            // Cold open from a tapped notification: the service may not
            // have loaded yet.
            if service.settingsByCircle[circleId] == nil, !myUserId.isEmpty, !didLoad {
                didLoad = true
                await service.load(myUserId: myUserId)
            }
        }
        .alert("Something went wrong", isPresented: $service.showError) {
            Button("OK") { }
        } message: {
            Text(service.errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let moment = service.currentMoment(for: circleId, now: now) {
            switch moment.phase(at: now) {
            case .live:
                if service.post(circleId: circleId, day: moment.day, userId: myUserId) != nil {
                    GoldenHourWallView(moment: moment)
                } else {
                    GoldenHourCameraView(moment: moment)
                }
            case .viewing:
                GoldenHourWallView(moment: moment)
            case .upcoming, .over:
                GoldenHourResidueView(circleId: circleId, moment: moment, now: now)
            }
        } else if service.isLoading {
            ProgressView().tint(GoldenTheme.gold)
        } else {
            GoldenHourResidueView(circleId: circleId, moment: nil, now: now)
        }
    }
}

// MARK: - Residue (after the hour / before the moment)

/// What remains when there is nothing to capture or view: the attendance
/// record and the streak. Never media — the media is gone for real.
struct GoldenHourResidueView: View {
    let circleId: UUID
    let moment: GoldenHourMoment?
    let now: Date

    @Environment(GoldenHourService.self) private var service
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private var myUserId: String { auth.user?.id ?? "" }
    private var circleName: String { service.circle(circleId)?.name ?? "Your circle" }

    private var isOver: Bool {
        guard let moment else { return false }
        return moment.phase(at: now) == .over
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(GoldenTheme.inkRaised)
                        .frame(width: 96, height: 96)
                    Image(systemName: isOver ? "sun.haze.fill" : "sun.horizon.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(GoldenTheme.gold.opacity(0.85))
                }

                if isOver, let moment {
                    let attendance = service.attendance(circleId: circleId, day: moment.day)
                    Text("\(attendance.made) of \(attendance.total) made it")
                        .font(.serif(24, weight: .medium))
                        .foregroundStyle(GoldenTheme.cream)
                    Text("Today's Golden Hour is gone — the wall and every capture have been deleted. What's left is the record.")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(GoldenTheme.cream.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                } else {
                    Text("Nothing here yet")
                        .font(.serif(24, weight: .medium))
                        .foregroundStyle(GoldenTheme.cream)
                    Text(upcomingBlurb)
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(GoldenTheme.cream.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                }

                streakChip
            }

            Spacer()
            Spacer()
        }
    }

    private var upcomingBlurb: String {
        guard let settings = service.settingsByCircle[circleId], settings.enabled else {
            return "Golden Hour isn't turned on for \(circleName) yet. An owner or admin can enable it in the circle's settings."
        }
        switch settings.mode {
        case .fixed:
            if let moment {
                let f = DateFormatter()
                f.timeStyle = .short
                f.dateStyle = .none
                return "Today's moment fires at \(f.string(from: moment.fireAt)). Be ready — you'll get 5 minutes."
            }
            return "Today's moment hasn't fired yet. Be ready — you'll get 5 minutes."
        case .turns:
            let picker = service.todaysPicker(for: circleId, now: now)
            return "\(picker?.displayName ?? "Someone") secretly picks today's moment. Nobody else knows when it fires."
        case .surprise:
            return "Today's moment fires sometime between 9 AM and 6 PM. Nobody knows when."
        }
    }

    @ViewBuilder
    private var streakChip: some View {
        let streak = service.streak(circleId: circleId, userId: myUserId, now: now)
        if streak > 0 {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Your streak: \(streak)")
                    .font(.sans(13, weight: .semibold))
            }
            .foregroundStyle(GoldenTheme.gold)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(GoldenTheme.gold.opacity(0.14)))
            .overlay(Capsule().strokeBorder(GoldenTheme.gold.opacity(0.35), lineWidth: 0.5))
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOLDEN HOUR")
                    .font(.sans(10, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(GoldenTheme.gold)
                Text(circleName)
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(GoldenTheme.cream)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GoldenTheme.cream)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(GoldenTheme.inkRaised))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Golden Hour")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
