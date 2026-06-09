//
//  ReportSheet.swift
//  FrisFocus
//
//  A calm reporting flow reused anywhere a person or a proof can be
//  flagged. Pick a reason, optionally add a note, and submit — the
//  report is filed for review. Pass a `messageId` to report a specific
//  proof, or just a `reportedUserId` to report the person.
//

import SwiftUI
import UIKit

/// A pending report target, wrapped so it can drive a `.sheet(item:)`
/// from any surface with a "..." menu.
struct ReportTarget: Identifiable {
    let id = UUID()
    let reportedUserId: String?
    let messageId: UUID?
    let subjectName: String
}

struct ReportSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(\.dismiss) private var dismiss

    let reportedUserId: String?
    let messageId: UUID?
    let subjectName: String

    @State private var reason: String?
    @State private var details: String = ""
    @State private var isSubmitting: Bool = false

    private let reasons = [
        "Spam",
        "Harassment or bullying",
        "Inappropriate or explicit content",
        "Impersonation",
        "Something else",
    ]

    private var subtitle: String {
        messageId != nil ? "Report this proof from \(subjectName)" : "Report \(subjectName)"
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        reasonsSection
                        detailsSection
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                submitButton
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("REPORT")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text(subtitle)
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT'S WRONG?")
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            ForEach(reasons, id: \.self) { option in
                reasonRow(option)
            }
        }
    }

    private func reasonRow(_ option: String) -> some View {
        let isSelected = reason == option
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reason = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.3))
                Text(option)
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.textPrimary.opacity(0.3) : Theme.textPrimary.opacity(0.08), lineWidth: isSelected ? 1.2 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANYTHING TO ADD? (OPTIONAL)")
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            TextField("A short note for whoever reviews this…", text: $details, axis: .vertical)
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3...6)
                .padding(12)
                .background(Theme.paperCream)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView().tint(Theme.textCream)
                } else {
                    Text("Submit report")
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(reason == nil ? Theme.textPrimary.opacity(0.35) : Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(reason == nil || isSubmitting)
    }

    private func submit() async {
        guard let reason, let myId = auth.user?.id else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await moderation.report(
            reportedUserId: reportedUserId,
            messageId: messageId,
            reason: reason,
            details: details,
            myUserId: myId
        )
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            ReportSheet(reportedUserId: "usr_x", messageId: nil, subjectName: "Alex")
                .environment(AuthManager())
                .environment(ModerationService())
        }
}
