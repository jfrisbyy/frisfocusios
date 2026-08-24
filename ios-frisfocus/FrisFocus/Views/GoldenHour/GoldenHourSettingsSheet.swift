//
//  GoldenHourSettingsSheet.swift
//  FrisFocus
//
//  The per-circle Golden Hour configuration, opened from the shared
//  circle detail. Owners/admins flip it on and choose the scheduling
//  mode (fixed time / members take turns / surprise); members see a
//  read-only summary. Turns mode adds the daily-picker flow: when it's
//  your day and you haven't locked a time in yet, you secretly pick the
//  moment right here.
//

import SwiftUI
import UIKit

struct GoldenHourSettingsSheet: View {
    let circleId: UUID
    let circleName: String
    let myUserId: String
    let canManage: Bool

    @Environment(GoldenHourService.self) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = false
    @State private var mode: GoldenHourMode = .surprise
    @State private var fireTime = Date()
    @State private var pickTime = Date()
    @State private var didSeed = false
    @State private var isSaving = false

    private var settings: GoldenHourSettings {
        service.settingsByCircle[circleId] ?? .defaults(circleId: circleId)
    }

    private var isDirty: Bool {
        enabled != settings.enabled || mode != settings.mode ||
        (mode == .fixed && Self.minute(of: fireTime) != settings.fireMinute)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                heroCard

                if canManage {
                    enableRow
                    if enabled {
                        modePicker
                        if mode == .fixed {
                            fixedTimeRow
                        }
                    }
                } else {
                    readOnlySummary
                }

                if enabled || settings.enabled {
                    todayCard
                }

                if canManage, isDirty {
                    saveButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(GoldenTheme.ink)
        .presentationDragIndicator(.visible)
        .onAppear { seedIfNeeded() }
        .task {
            if service.settingsByCircle[circleId] == nil, !myUserId.isEmpty {
                await service.load(myUserId: myUserId)
                seedIfNeeded(force: true)
            }
        }
    }

    private func seedIfNeeded(force: Bool = false) {
        guard !didSeed || force else { return }
        didSeed = true
        let s = settings
        enabled = s.enabled
        mode = s.mode
        fireTime = Self.date(fromMinute: s.fireMinute)
        pickTime = Date().addingTimeInterval(30 * 60)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(GoldenTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(GoldenTheme.goldGradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Golden Hour")
                        .font(.serif(21, weight: .medium))
                        .foregroundStyle(GoldenTheme.cream)
                    Text(circleName)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(GoldenTheme.cream.opacity(0.6))
                }
            }
            Text("Once a day, everyone in this circle gets pinged at the exact same instant. 5 minutes to capture what you're working on, 1 hour to see the wall — then it's deleted forever. Only streaks survive.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(GoldenTheme.cream.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(GoldenTheme.inkRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(GoldenTheme.gold.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Enable

    private var enableRow: some View {
        Toggle(isOn: $enabled.animation(.snappy)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Golden Hour")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(GoldenTheme.cream)
                Text(enabled ? "Fires every day — no skipping" : "Off for this circle")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(GoldenTheme.cream.opacity(0.55))
            }
        }
        .tint(GoldenTheme.gold)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GoldenTheme.inkRaised))
    }

    // MARK: - Mode

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHEN IT FIRES")
                .font(.sans(10, weight: .bold))
                .tracking(2)
                .foregroundStyle(GoldenTheme.gold)

            ForEach(GoldenHourMode.allCases, id: \.self) { candidate in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy) { mode = candidate }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: candidate.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(mode == candidate ? GoldenTheme.ink : GoldenTheme.gold)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(mode == candidate ? AnyShapeStyle(GoldenTheme.goldGradient) : AnyShapeStyle(GoldenTheme.gold.opacity(0.12)))
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title)
                                .font(.sans(14, weight: .semibold))
                                .foregroundStyle(GoldenTheme.cream)
                            Text(candidate.blurb)
                                .font(.sans(11, weight: .regular))
                                .foregroundStyle(GoldenTheme.cream.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: mode == candidate ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(mode == candidate ? GoldenTheme.gold : GoldenTheme.cream.opacity(0.25))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(GoldenTheme.inkRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(mode == candidate ? GoldenTheme.gold.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fixedTimeRow: some View {
        HStack {
            Text("Fires daily at")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(GoldenTheme.cream)
            Spacer()
            DatePicker("", selection: $fireTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .colorScheme(.dark)
                .tint(GoldenTheme.gold)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GoldenTheme.inkRaised))
    }

    // MARK: - Read-only summary

    private var readOnlySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.enabled ? "Golden Hour is on" : "Golden Hour is off")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(GoldenTheme.cream)
            Text(settings.enabled
                 ? settings.mode.blurb
                 : "Only the circle's owner or an admin can turn it on.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(GoldenTheme.cream.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GoldenTheme.inkRaised))
    }

    // MARK: - Today

    @ViewBuilder
    private var todayCard: some View {
        let now = Date()
        let liveSettings = settings
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY")
                .font(.sans(10, weight: .bold))
                .tracking(2)
                .foregroundStyle(GoldenTheme.gold)

            if let moment = service.currentMoment(for: circleId, now: now) {
                switch moment.phase(at: now) {
                case .live:
                    statusRow(icon: "dot.radiowaves.left.and.right", text: "Live right now — \(GoldenHourSchedule.countdownString(until: moment.captureClosesAt, from: now)) left to capture", highlight: true)
                case .viewing:
                    statusRow(icon: "eye.fill", text: "Wall is open — closes in \(GoldenHourSchedule.wallCountdownString(until: moment.wallClosesAt, from: now))", highlight: true)
                case .over:
                    let attendance = service.attendance(circleId: circleId, day: moment.day)
                    statusRow(icon: "checkmark.seal.fill", text: "Done for today — \(attendance.made == 1 ? "1 made it" : "\(attendance.made) made it")", highlight: false)
                case .upcoming:
                    upcomingRow(moment: moment, settings: liveSettings)
                }
            } else if liveSettings.enabled {
                statusRow(icon: "hourglass", text: "Today's moment is being computed…", highlight: false)
            } else {
                statusRow(icon: "moon.zzz.fill", text: "Nothing fires until Golden Hour is turned on.", highlight: false)
            }

            pickerFlow(now: now, settings: liveSettings)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GoldenTheme.inkRaised))
    }

    @ViewBuilder
    private func upcomingRow(moment: GoldenHourMoment, settings: GoldenHourSettings) -> some View {
        switch settings.mode {
        case .fixed:
            let f: DateFormatter = {
                let f = DateFormatter()
                f.timeStyle = .short
                return f
            }()
            statusRow(icon: "clock.fill", text: "Fires today at \(f.string(from: moment.fireAt))", highlight: false)
        case .surprise:
            statusRow(icon: "sparkles", text: "Fires sometime between 9 AM and 6 PM — nobody knows when.", highlight: false)
        case .turns:
            let picker = service.todaysPicker(for: circleId)
            if service.hasPickToday(for: circleId) {
                statusRow(icon: "lock.fill", text: "\(picker?.id == myUserId ? "You" : (picker?.displayName ?? "Someone")) locked in today's secret time.", highlight: false)
            } else {
                statusRow(icon: "person.fill.questionmark", text: "\(picker?.id == myUserId ? "Your" : "\(picker?.displayName ?? "Someone")'s") turn to secretly pick today's moment.", highlight: picker?.id == myUserId)
            }
        }
    }

    /// Turns mode, my day, no pick yet → the secret time picker.
    @ViewBuilder
    private func pickerFlow(now: Date, settings: GoldenHourSettings) -> some View {
        if settings.enabled,
           settings.mode == .turns,
           service.todaysPicker(for: circleId, now: now)?.id == myUserId,
           !service.hasPickToday(for: circleId, now: now),
           let moment = service.currentMoment(for: circleId, now: now),
           moment.phase(at: now) == .upcoming {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(GoldenTheme.gold.opacity(0.2))
                HStack {
                    Text("Today's secret time")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(GoldenTheme.cream)
                    Spacer()
                    DatePicker("", selection: $pickTime, in: now.addingTimeInterval(5 * 60)..., displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .tint(GoldenTheme.gold)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        let ok = await service.submitPick(
                            circleId: circleId,
                            fireMinute: Self.minute(of: pickTime),
                            myUserId: myUserId
                        )
                        if ok {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                } label: {
                    Text(service.isWorking ? "Locking in…" : "Lock in today's time")
                        .font(.sans(14, weight: .bold))
                        .foregroundStyle(GoldenTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(GoldenTheme.goldGradient))
                }
                .buttonStyle(.plain)
                .disabled(service.isWorking)
                Text("Nobody else will see the time — they'll just get pinged.")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(GoldenTheme.cream.opacity(0.5))
            }
        }
    }

    private func statusRow(icon: String, text: String, highlight: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlight ? GoldenTheme.gold : GoldenTheme.cream.opacity(0.6))
            Text(text)
                .font(.sans(13, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? GoldenTheme.cream : GoldenTheme.cream.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isSaving = true
            Task {
                let ok = await service.updateSettings(
                    circleId: circleId,
                    enabled: enabled,
                    mode: mode,
                    fireMinute: Self.minute(of: fireTime),
                    myUserId: myUserId
                )
                isSaving = false
                if ok {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            }
        } label: {
            Text(isSaving ? "Saving…" : "Save Golden Hour")
                .font(.sans(15, weight: .bold))
                .foregroundStyle(GoldenTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(GoldenTheme.goldGradient))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    // MARK: - Time helpers

    private static func minute(of date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func date(fromMinute minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: (minute / 60) % 24,
            minute: minute % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}
