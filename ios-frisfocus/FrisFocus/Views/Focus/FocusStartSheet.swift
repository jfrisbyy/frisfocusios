//
//  FocusStartSheet.swift
//  FrisFocus
//
//  The single, unified focus setup. Pick a duration, an optional label,
//  optionally invite a few friends (which turns the block into a shared
//  grove), choose which apps to silence, and attach any mix of pinned
//  Tasks and dated To-dos to check off during the session. Submitting
//  hands control to the host via `onStart`, which routes to the solo
//  focus scene or the grove depending on whether any friends were added.
//

import SwiftUI
import UIKit

struct FocusStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(FocusBlockingService.self) private var blocking

    /// Hand-off to the host: (duration, optional label, invited friend
    /// ids, attached items). An empty friend list means a solo block.
    let onStart: (TimeInterval, String?, [UUID], [FocusTaskAttachment]) -> Void

    @State private var selectedMinutes: Int = 45
    @State private var customMinutes: Int = 30
    @State private var useCustom: Bool = false
    @State private var label: String = ""
    /// Invited friend ids (order preserved by the candidate list).
    @State private var selectedFriendIds: Set<UUID> = []
    /// Ordered attached item ids — preserves tap order in the running
    /// screen's task tray.
    @State private var selectedItemIds: [UUID] = []
    /// Which attached ids are shared with the grove (only meaningful when
    /// friends are invited).
    @State private var sharedItemIds: Set<UUID> = []
    @State private var showBlockList = false
    @State private var showSchedule = false
    @State private var showHistory = false
    @State private var showAuthFailure = false

    private let presets: [Int] = [25, 45, 60]
    private let friendCap: Int = 3

    private var isShared: Bool { !selectedFriendIds.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionHeader("Duration")
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { m in
                            durationChip(m, selected: !useCustom && selectedMinutes == m) {
                                useCustom = false
                                selectedMinutes = m
                            }
                        }
                        customChip
                    }
                    if useCustom {
                        Stepper(value: $customMinutes, in: 5...180, step: 5) {
                            Text("\(customMinutes) min")
                                .font(.serif(18, weight: .regular))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.top, 2)
                    }

                    sectionHeader("Label (optional)")
                    TextField("Writing, reading, deep work…", text: $label)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.warmWheat)
                        )

                    inviteSection

                    sectionHeader("Silence apps")
                    if blocking.authStatus == .notDetermined {
                        permissionCard
                    } else {
                        silenceRow
                        if blocking.authStatus == .denied {
                            deniedNote
                        }
                    }

                    if !attachableItems.isEmpty {
                        sectionHeader("Attach tasks & to-dos (optional)")
                        Text(isShared
                             ? "Check them off during the session. Tap the share toggle to let the grove see one."
                             : "Check them off yourself during the session — they count toward your day.")
                            .font(.serifItalic(13))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        VStack(spacing: 6) {
                            ForEach(attachableItems) { item in
                                itemRow(item)
                            }
                        }
                    }

                    Button(action: start) {
                        Text(isShared ? "Start the grove" : "Start focus")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.warmWheat)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.textPrimary)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    if !store.sharedFocusInviteCandidates.isEmpty {
                        scheduleRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showBlockList) {
                FocusBlockListView()
            }
            .sheet(isPresented: $showSchedule) {
                ScheduleGroveSheet()
            }
            .sheet(isPresented: $showHistory) {
                GroveHistoryView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.sans(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
            .onAppear { blocking.refreshAuthStatus() }
            .alert("Screen Time approval failed", isPresented: $showAuthFailure) {
                authFailureActions
            } message: {
                Text(authFailureText)
            }
        }
    }

    @ViewBuilder
    private var authFailureActions: some View {
        let failure: FocusBlockingService.AuthFailure? = blocking.lastFailure
        if failure?.canRetry ?? true {
            Button("Try Again") { allowBlocking() }
        }
        if failure?.suggestsSettings ?? false {
            Button("Open Settings") { openSettings() }
        }
        Button("Not Now", role: .cancel) {}
    }

    private var authFailureText: String {
        guard let failure = blocking.lastFailure else {
            return "Apple refused the Screen Time request. Please try again."
        }
        return "\(failure.message)\n\nApple's error: \(failure.rawCode)"
    }

    // MARK: - Attachable items

    /// A pinned Task or dated To-do offered up to attach.
    private struct AttachItem: Identifiable {
        let id: UUID
        let title: String
        let dotColor: Color
        let kind: FocusItemKind
    }

    private var attachableItems: [AttachItem] {
        let taskItems = store.tasks.map { task in
            AttachItem(
                id: task.id,
                title: task.title,
                dotColor: Color(hex: task.category.hexColor) ?? Theme.textPrimary,
                kind: .task
            )
        }
        let todoItems = store.todos
            .filter { !$0.isCompleted }
            .map { todo in
                AttachItem(
                    id: todo.id,
                    title: todo.title,
                    dotColor: Color(hex: 0x9E7E40) ?? Theme.textPrimary,
                    kind: .todo
                )
            }
        return taskItems + todoItems
    }

    // MARK: - Invite section

    @ViewBuilder
    private var inviteSection: some View {
        let candidates = store.sharedFocusInviteCandidates
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Invite friends (up to \(friendCap))")
                Text("Add friends and your tree blossoms into a shared grove.")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                VStack(spacing: 6) {
                    ForEach(candidates) { friend in
                        friendRow(friend)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func friendRow(_ friend: Friend) -> some View {
        let isSelected = selectedFriendIds.contains(friend.id)
        let isCapped = !isSelected && selectedFriendIds.count >= friendCap
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toggleFriend(friend)
        } label: {
            HStack(spacing: 12) {
                FriendAvatarView(friend: friend, size: 30)
                Text(friend.displayName)
                    .font(.serif(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(isCapped ? 0.45 : 0.95))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.alertGreen.opacity(0.10) : Theme.warmWheat)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCapped)
    }

    private func toggleFriend(_ friend: Friend) {
        if selectedFriendIds.contains(friend.id) {
            selectedFriendIds.remove(friend.id)
        } else if selectedFriendIds.count < friendCap {
            selectedFriendIds.insert(friend.id)
        }
    }

    // MARK: - Permission card

    @ViewBuilder
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.alertGreen)
                Text("Silence distracting apps")
                    .font(.serif(17, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("FrisFocus can block the apps that pull you away while a focus block runs. Allow Screen Time access to turn it on.")
                .font(.serifItalic(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
            Button(action: allowBlocking) {
                Text("Allow app blocking")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.warmWheat)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.textPrimary)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.alertGreen.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.alertGreen.opacity(0.25), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var deniedNote: some View {
        Button(action: openSettings) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x9E7E40))
                Text("Screen Time access is off — turn it on in Settings to silence apps.")
                    .font(.sans(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func allowBlocking() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let granted = await blocking.requestAuthorization()
            // On a real iPhone a refusal raises a clear, retryable alert
            // instead of silently hiding the card.
            if !granted && blocking.lastFailure != nil {
                showAuthFailure = true
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Silence row

    @ViewBuilder
    private var silenceRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showBlockList = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: blocking.isEnabled && blocking.hasSelection ? "hand.raised.fill" : "hand.raised")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(blocking.isEnabled && blocking.hasSelection ? Theme.alertGreen : Theme.textPrimary.opacity(0.45))
                Text(blocking.isEnabled ? blocking.summaryLine : "Off")
                    .font(.serif(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.warmWheat)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule / history row

    @ViewBuilder
    private var scheduleRow: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSchedule = true
            } label: {
                Label("Schedule for later", systemImage: "calendar")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.textPrimary.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if !store.recentGroves.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showHistory = true
                } label: {
                    Label("Past groves", systemImage: "clock.arrow.circlepath")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.textPrimary.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }

    @ViewBuilder
    private func durationChip(_ m: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text("\(m)m")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.textPrimary : Theme.warmWheat)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var customChip: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            useCustom = true
        } label: {
            Text("Custom")
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(useCustom ? Theme.warmWheat : Theme.textPrimary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(useCustom ? Theme.textPrimary : Theme.warmWheat)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func itemRow(_ item: AttachItem) -> some View {
        let isSelected = selectedItemIds.contains(item.id)
        let shared = sharedItemIds.contains(item.id)
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                selectedItemIds.removeAll { $0 == item.id }
                sharedItemIds.remove(item.id)
            } else {
                selectedItemIds.append(item.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                Circle()
                    .fill(item.dotColor)
                    .frame(width: 7, height: 7)
                Text(item.title)
                    .font(.serif(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if item.kind == .todo {
                    Text("To-do")
                        .font(.sans(9, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                Spacer()
                if isSelected && isShared {
                    sharePill(isShared: shared, itemId: item.id)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.alertGreen.opacity(0.10) : Theme.warmWheat)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sharePill(isShared: Bool, itemId: UUID) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isShared { sharedItemIds.remove(itemId) } else { sharedItemIds.insert(itemId) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isShared ? "person.2.fill" : "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(isShared ? "Shared" : "Private")
                    .font(.sans(10, weight: .semibold))
            }
            .foregroundStyle(isShared ? Theme.warmWheat : Theme.textPrimary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isShared ? Theme.textPrimary : Theme.textPrimary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action

    private func start() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let minutes = useCustom ? customMinutes : selectedMinutes
        let duration = TimeInterval(max(1, minutes) * 60)
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)

        // Preserve the friend-row order rather than Set's iteration order.
        let orderedFriends = store.sharedFocusInviteCandidates
            .map(\.id)
            .filter { selectedFriendIds.contains($0) }

        // Build attachments in tap order, resolving each id's kind.
        let kinds = Dictionary(uniqueKeysWithValues: attachableItems.map { ($0.id, $0.kind) })
        let attachments = selectedItemIds.compactMap { id -> FocusTaskAttachment? in
            guard let kind = kinds[id] else { return nil }
            return FocusTaskAttachment(
                taskId: id,
                shared: isShared && sharedItemIds.contains(id),
                kind: kind
            )
        }

        Task {
            await blocking.ensureAuthorizedForSessionStart()
            onStart(duration, trimmed.isEmpty ? nil : trimmed, orderedFriends, attachments)
            dismiss()
        }
    }
}
