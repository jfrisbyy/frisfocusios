//
//  ReminderSettingsView.swift
//  FrisFocus
//
//  Everything the app is allowed to interrupt you with, in one place —
//  two halves, because they come from two different directions.
//
//  The first four switches are on-device nudges built from the day's
//  plan; changes reschedule the pending notification set immediately and
//  nothing goes through a server. The second half is what other people
//  can send you: the social push kinds, gathered into the handful of
//  shapes a person actually thinks in and stored on the account, so
//  `send-push` can honour them before anything leaves the server.
//
//  The OS permission is the roof over both. With notifications denied
//  every switch here is decoration, so the whole screen dims and freezes
//  behind the banner that offers the way out.
//

import SwiftUI
import UserNotifications
import UIKit

/// One switch on the social side, and the push kinds it covers.
///
/// A toggle per kind would be a wall of nouns nobody reads, and most of
/// the distinctions inside it aren't ones people hold — nobody wants
/// circle check-offs but not circle invites. These six are the shapes
/// that do get held: someone wrote to me, someone wants to be friends,
/// my circle is moving, someone reacted to what I made, the hour is
/// happening, someone asked me to do something together. Every kind sits
/// in exactly one of them, so nothing is left unswitchable.
private struct PushKindGroup: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let kinds: [PushKind]

    static let all: [PushKindGroup] = [
        PushKindGroup(
            id: "messages",
            icon: "paperplane.fill",
            title: "Proofs and notes",
            subtitle: "When a friend sends you one",
            kinds: [.proof, .note]
        ),
        PushKindGroup(
            id: "friends",
            icon: "person.badge.plus",
            title: "Friend requests",
            subtitle: "New requests, and when yours is accepted",
            kinds: [.friendRequest, .friendAccept]
        ),
        PushKindGroup(
            id: "circles",
            icon: "circle.hexagongrid.fill",
            title: "Circle activity",
            subtitle: "Invites, check-offs, and what changes in a circle",
            kinds: [.circleInvite, .circleTask, .circleProgress, .circleMode, .circleEvent]
        ),
        PushKindGroup(
            id: "reactions",
            icon: "hands.clap.fill",
            title: "Cheers and reactions",
            subtitle: "Cheers sent your way, and likes or comments on your story",
            kinds: [.cheer, .cheerReaction, .storyLike, .storyComment]
        ),
        PushKindGroup(
            id: "golden",
            icon: "sun.horizon.fill",
            title: "Golden Hour",
            subtitle: "When a friend posts during the hour",
            kinds: [.goldenPost]
        ),
        PushKindGroup(
            id: "together",
            icon: "person.2.fill",
            title: "Pacts and shared focus",
            subtitle: "Pact proposals, and invitations to focus together",
            kinds: [.pactInvite, .pactAccept, .focusInvite]
        )
    ]

    #if DEBUG
    /// Every kind belongs to exactly one group. Checked at runtime in
    /// debug builds because getting it wrong fails silently: a kind added
    /// later with no group is one nobody can ever switch off.
    static let coversEveryKind: Bool = {
        let listed = all.flatMap(\.kinds).map(\.rawValue)
        return Set(listed).count == listed.count
            && Set(listed) == Set(PushKind.allCases.map(\.rawValue))
    }()
    #endif
}

struct ReminderSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(NotificationManager.self) private var notifications

    @State private var prefs: PlanReminderPrefs = PlanReminderPrefs.load()
    @State private var permissionDenied: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if permissionDenied {
                    deniedBanner
                }

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("FROM YOUR PLAN")
                    card {
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
                }

                Text("Reminders are built from your plan on this device and update the moment it changes. Finishing a task quietly cancels its reminders.")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .padding(.horizontal, 6)

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("FROM FRIENDS")
                    card {
                        ForEach(Array(PushKindGroup.all.enumerated()), id: \.element.id) { index, group in
                            if index > 0 {
                                divider
                            }
                            toggleRow(
                                icon: group.icon,
                                title: group.title,
                                subtitle: group.subtitle,
                                isOn: groupBinding(group)
                            )
                        }
                    }
                }

                Text("These come from other people, so they arrive when the moment does. Switching a group off stops it before it is sent — nobody is told, and everything still waits for you in the app.")
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
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            #if DEBUG
            assert(
                PushKindGroup.coversEveryKind,
                "Every PushKind needs exactly one group here, or it can never be switched off."
            )
            #endif
            await refreshPermissionState()
            // The cached set already drew the switches; this reconciles a
            // change made on another device.
            await notifications.refreshPushPreferences()
        }
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

    /// A group reads as on only while every kind under it is on. A partial
    /// state can only arrive from another build with a different grouping;
    /// showing it as off — and letting one tap clear the whole group — is
    /// the reading that resolves it rather than hiding it.
    private func groupBinding(_ group: PushKindGroup) -> Binding<Bool> {
        Binding(
            get: { group.kinds.allSatisfy { notifications.isPushEnabled($0) } },
            set: { newValue in
                notifications.setPushKinds(group.kinds, enabled: newValue)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        )
    }

    /// The card chrome both halves share — and the single place the OS
    /// permission is honoured, so a denied permission dims and freezes
    /// every switch on the screen instead of letting people arrange
    /// notifications that cannot arrive.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
            .opacity(permissionDenied ? 0.45 : 1)
            .disabled(permissionDenied)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sans(11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
            .padding(.horizontal, 6)
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
                    Text("Allow notifications in Settings so these can reach you. Your choices below are kept.")
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
            .environment(NotificationManager())
    }
}
