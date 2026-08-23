//
//  ReminderSettingsView.swift
//  FrisFocus
//
//  The Reminders section of settings: four on-device nudge kinds, each
//  individually switchable. Changes reschedule the pending notification
//  set immediately. All reminders come from the day's plan on this
//  device — nothing goes through a server.
//

import SwiftUI
import UserNotifications
import UIKit

struct ReminderSettingsView: View {
    @Environment(Store.self) private var store

    @State private var prefs: PlanReminderPrefs = PlanReminderPrefs.load()
    @State private var permissionDenied: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if permissionDenied {
                    deniedBanner
                }

                VStack(spacing: 0) {
                    toggleRow(
                        icon: "sunrise.fill",
                        title: "Morning preview",
                        subtitle: "One note with the day's plan, around 8:15",
                        isOn: binding(\.morningDigest)
                    )
                    divider
                    toggleRow(
                        icon: "clock.fill",
                        title: "Timed windows",
                        subtitle: "When a task's scheduled window opens",
                        isOn: binding(\.timedWindows)
                    )
                    divider
                    toggleRow(
                        icon: "sun.max.fill",
                        title: "Part-of-day nudges",
                        subtitle: "As morning, afternoon, and evening begin",
                        isOn: binding(\.partOfDayNudge)
                    )
                    divider
                    toggleRow(
                        icon: "sunset.fill",
                        title: "Evening check-in",
                        subtitle: "Only if something's still open, around 7:30",
                        isOn: binding(\.eveningCheckIn)
                    )
                }
                .background(Theme.paperCream)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
                )

                Text("Reminders are built from your plan on this device and update the moment it changes. Finishing a task quietly cancels its reminders.")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.warmWheat.ignoresSafeArea())
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await refreshPermissionState() }
    }

    // MARK: - Pieces

    private func binding(_ keyPath: WritableKeyPath<PlanReminderPrefs, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { newValue in
                prefs[keyPath: keyPath] = newValue
                store.planReminderPrefs = prefs
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        )
    }

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Theme.textPrimary.opacity(0.06))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 63)
    }

    private var deniedBanner: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.alertRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Allow notifications in Settings so these reminders can reach you.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.alertRed.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func refreshPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionDenied = settings.authorizationStatus == .denied
    }
}

#Preview {
    NavigationStack {
        ReminderSettingsView()
            .environment(Store())
    }
}
