//
//  FocusTogetherSheet.swift
//  FrisFocus
//
//  F2 — entry sheet for a shared focus block. Pick 1–3 friends, a
//  duration, and an optional label, then hand off to
//  `SharedFocusModeView` via `onStart`. The grove is intimate by
//  design: a hard cap of 3 invited friends (4 trees incl. you) so
//  the scene never crowds into a forest.
//

import SwiftUI
import UIKit

struct FocusTogetherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    /// Hand-off to the host: (selected friend ids, duration in seconds, optional label).
    let onStart: ([UUID], TimeInterval, String?) -> Void

    @State private var selectedFriendIds: Set<UUID> = []
    @State private var selectedMinutes: Int = 45
    @State private var customMinutes: Int = 30
    @State private var useCustom: Bool = false
    @State private var label: String = ""

    private let presets: [Int] = [25, 45, 60]
    private let friendCap: Int = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro

                    sectionHeader("Friends (up to \(friendCap))")
                    if store.sharedFocusInviteCandidates.isEmpty {
                        Text("Add a friend first to focus together.")
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
                    TextField("Deep work, study hall…", text: $label)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.warmWheat)
                        )

                    Button(action: start) {
                        Text("Start the grove")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.warmWheat)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canStart ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart)
                    .padding(.top, 4)

                    Text("Each tree is one of you. Sleep doesn't cost a leaf — leaving the app does.")
                        .font(.serifItalic(12))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Focus together")
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

    // MARK: - Sections

    @ViewBuilder
    private var intro: some View {
        Text("A small grove — you and a few friends in one shared focus window.")
            .font(.serifItalic(14))
            .foregroundStyle(Theme.textPrimary.opacity(0.65))
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
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
                ZStack {
                    Circle()
                        .fill(Color(hex: friend.accentColorHex) ?? Theme.textPrimary)
                        .frame(width: 30, height: 30)
                    Text(friend.initials)
                        .font(.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.warmWheat)
                }
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

    // MARK: - Logic

    private var canStart: Bool {
        !selectedFriendIds.isEmpty
    }

    private func toggleFriend(_ friend: Friend) {
        if selectedFriendIds.contains(friend.id) {
            selectedFriendIds.remove(friend.id)
        } else if selectedFriendIds.count < friendCap {
            selectedFriendIds.insert(friend.id)
        }
    }

    private func start() {
        guard canStart else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let minutes = useCustom ? customMinutes : selectedMinutes
        let duration = TimeInterval(max(1, minutes) * 60)
        // Preserve the friend-row order rather than Set's iteration order.
        let ordered = store.sharedFocusInviteCandidates
            .map(\.id)
            .filter { selectedFriendIds.contains($0) }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        onStart(ordered, duration, trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}
