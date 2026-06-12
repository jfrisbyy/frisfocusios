//
//  ScheduleGroveSheet.swift
//  FrisFocus
//
//  Plan a grove for later — pick friends, a length, a start time, and an
//  optional repeat. Saving arms a local reminder (5 min before) and
//  sends each invited friend a heads-up push, so everyone shows up
//  together. Same warm paper aesthetic as the live grove.
//

import SwiftUI
import UIKit

struct ScheduleGroveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    @State private var selectedFriendIds: Set<UUID> = []
    @State private var selectedMinutes: Int = 45
    @State private var startAt: Date = ScheduleGroveSheet.defaultStart()
    @State private var recurrence: GroveRecurrence = .once
    @State private var label: String = ""

    private let presets: [Int] = [25, 45, 60]
    private let friendCap: Int = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Set a time and invite a few friends. Everyone gets a reminder before it starts.")
                        .font(.serifItalic(14))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))

                    sectionHeader("When")
                    DatePicker("", selection: $startAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    sectionHeader("Repeat")
                    HStack(spacing: 8) {
                        ForEach(GroveRecurrence.allCases, id: \.self) { r in
                            recurrenceChip(r)
                        }
                    }

                    sectionHeader("Friends (up to \(friendCap))")
                    if store.sharedFocusInviteCandidates.isEmpty {
                        Text("Add a friend first to schedule a grove.")
                            .font(.serifItalic(14))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    } else {
                        VStack(spacing: 6) {
                            ForEach(store.sharedFocusInviteCandidates) { friend in
                                friendRow(friend)
                            }
                        }
                    }

                    sectionHeader("Duration")
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { m in
                            durationChip(m)
                        }
                    }

                    sectionHeader("Label (optional)")
                    TextField("Study hall, deep work…", text: $label)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.warmWheat)
                        )

                    Button(action: save) {
                        Text("Schedule grove")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.warmWheat)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canSave ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Schedule a grove")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.sans(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }

    @ViewBuilder
    private func recurrenceChip(_ r: GroveRecurrence) -> some View {
        let selected = recurrence == r
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            recurrence = r
        } label: {
            Text(r.label)
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(selected ? Theme.textPrimary : Theme.warmWheat)
                )
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    private func durationChip(_ m: Int) -> some View {
        let selected = selectedMinutes == m
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedMinutes = m
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

    // MARK: - Logic

    private var canSave: Bool { !selectedFriendIds.isEmpty }

    private func toggleFriend(_ friend: Friend) {
        if selectedFriendIds.contains(friend.id) {
            selectedFriendIds.remove(friend.id)
        } else if selectedFriendIds.count < friendCap {
            selectedFriendIds.insert(friend.id)
        }
    }

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ordered = store.sharedFocusInviteCandidates
            .map(\.id)
            .filter { selectedFriendIds.contains($0) }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addScheduledGrove(
            friendIds: ordered,
            plannedDuration: TimeInterval(selectedMinutes * 60),
            startAt: startAt,
            recurrence: recurrence,
            label: trimmed.isEmpty ? nil : trimmed
        )
        dismiss()
    }

    /// Default to the next round half-hour, at least 10 minutes out.
    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let base = Date().addingTimeInterval(30 * 60)
        let minute = cal.component(.minute, from: base)
        let rounded = minute < 30 ? 30 : 60
        return cal.date(bySetting: .minute, value: rounded % 60, of: base) ?? base
    }
}
