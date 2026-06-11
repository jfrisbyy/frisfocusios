//
//  CircleSharingSheet.swift
//  FrisFocus
//
//  Owner-side sharing editor for a real shared circle. Flip the circle
//  between private (invite only, the default) and public (listed in
//  Discover), choose the join rule for public circles — open or
//  approval — and write the short blurb shown in the directory.
//

import SwiftUI
import UIKit

struct CircleSharingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let circle: SharedCircle
    /// (visibility, joinRule, description)
    let onSave: (String, String, String?) -> Void

    @State private var isPublic: Bool
    @State private var requiresApproval: Bool
    @State private var descriptionText: String

    init(circle: SharedCircle, onSave: @escaping (String, String, String?) -> Void) {
        self.circle = circle
        self.onSave = onSave
        _isPublic = State(initialValue: circle.isPublic)
        _requiresApproval = State(initialValue: circle.joinRule == "approval")
        _descriptionText = State(initialValue: circle.descriptionText ?? "")
    }

    private var hasChanges: Bool {
        isPublic != circle.isPublic
            || (isPublic && requiresApproval != (circle.joinRule == "approval"))
            || (isPublic && descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    != (circle.descriptionText ?? ""))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(spacing: 8) {
                    choiceRow(
                        isPublicChoice: false,
                        icon: "lock.fill",
                        title: "Private",
                        blurb: "Invite only — the circle never appears in Discover."
                    )
                    choiceRow(
                        isPublicChoice: true,
                        icon: "globe",
                        title: "Public",
                        blurb: "Listed in Discover — anyone can find and join it."
                    )
                }

                if isPublic {
                    VStack(alignment: .leading, spacing: 12) {
                        eyebrow("HOW PEOPLE JOIN")
                        HStack(spacing: 10) {
                            ruleChip(approval: false, label: "Open — anyone joins")
                            ruleChip(approval: true, label: "Approval — ask first")
                        }

                        eyebrow("SHOWN IN DISCOVER")
                            .padding(.top, 4)
                        TextField("A line about the circle…", text: $descriptionText, axis: .vertical)
                            .font(.sans(14, weight: .regular))
                            .foregroundStyle(Theme.textPrimary)
                            .tint(Theme.textPrimary)
                            .lineLimit(2...4)
                            .padding(.vertical, 13)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                                    .fill(Color.white.opacity(0.75))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                                    .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                saveButton
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(Theme.warmWheat)
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.2), value: isPublic)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .medium))
            .tracking(2)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow("WHO CAN FIND IT")
            Text(circle.name)
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
    }

    private func choiceRow(isPublicChoice: Bool, icon: String, title: String, blurb: String) -> some View {
        let isSelected = isPublic == isPublicChoice
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) { isPublic = isPublicChoice }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .strokeBorder(
                        isSelected ? Theme.sunShadow : Theme.textPrimary.opacity(0.3),
                        lineWidth: isSelected ? 6 : 1.6
                    )
                    .frame(width: 22, height: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.sunShadow : Theme.textPrimary.opacity(0.45))
                        Text(title)
                            .font(.sans(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(blurb)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.sunShadow.opacity(0.5) : Theme.textPrimary.opacity(0.08),
                        lineWidth: isSelected ? 1.4 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func ruleChip(approval: Bool, label: String) -> some View {
        let isSelected = requiresApproval == approval
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) { requiresApproval = approval }
        } label: {
            Text(label)
                .font(.sans(12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.06))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var saveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSave(
                isPublic ? "public" : "private",
                (isPublic && requiresApproval) ? "approval" : "open",
                isPublic ? descriptionText : nil
            )
            dismiss()
        } label: {
            Text("Save")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(hasChanges ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges)
        .accessibilityLabel("Save sharing settings")
    }
}
