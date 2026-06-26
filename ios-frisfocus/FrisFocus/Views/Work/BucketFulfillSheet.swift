//
//  BucketFulfillSheet.swift
//  FrisFocus
//
//  The calm sheet that opens when a bucket is tapped. A bucket protects
//  a stretch of time for an intention; honoring the block is what counts
//  toward the day (it carries its own value). Logging a specific inside
//  just records *what* — it never double-counts. Three paths: pick a
//  fitting specific, free-log "something else," or just mark the block
//  done.
//

import SwiftUI
import UIKit

struct BucketFulfillSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bucket: Bucket

    @State private var customText: String = ""
    @FocusState private var customFocused: Bool

    private var alreadyHonored: Bool { store.hasLogEntryToday(forBucketId: bucket.id) }
    private var loggedSpecific: String? { store.loggedSpecificToday(forBucketId: bucket.id) }
    private var tint: Color { Color(hex: store.categoryColorHex(bucket.category)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if alreadyHonored {
                    honoredState
                } else {
                    intentionLine
                    candidatesSection
                    customSection
                    markDoneButton
                }
            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .background(Theme.warmWheat)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("BUCKET")
                    .font(.sans(9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.14)))
                if let window = bucket.timeWindow {
                    Text(window.displayText)
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                } else if bucket.partOfDay != .anytime {
                    Text(bucket.partOfDay.softLabel)
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }
            Text(bucket.title)
                .font(.serif(24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(store.categoryDisplayName(bucket.category)) · worth \(bucket.pointValue)")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }

    private var intentionLine: some View {
        Text("You protected this time for \(bucket.title.lowercased()). Do whatever fits today — pick one, or just log what you did.")
            .font(.serifItalic(15))
            .foregroundStyle(Theme.textPrimary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Honored state

    @ViewBuilder
    private var honoredState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.alertGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block honored")
                        .font(.serif(17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let loggedSpecific, loggedSpecific != bucket.title {
                        Text(loggedSpecific)
                            .font(.sans(12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.alertGreen.opacity(0.10))
            )

            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.unhonorBucket(bucket)
                dismiss()
            } label: {
                Text("Undo")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.alertRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.alertRed.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Candidates

    @ViewBuilder
    private var candidatesSection: some View {
        if !bucket.candidateTitles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowText(text: "What fits", opacity: 0.5)
                ForEach(bucket.candidateTitles, id: \.self) { candidate in
                    Button {
                        honor(with: candidate)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(tint).frame(width: 7, height: 7)
                            Text(candidate)
                                .font(.sans(15, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 17))
                                .foregroundStyle(tint.opacity(0.7))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Custom log

    @ViewBuilder
    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "Something else I did", opacity: 0.5)
            HStack(spacing: 10) {
                TextField("What you actually did", text: $customText)
                    .font(.sans(15, weight: .medium))
                    .focused($customFocused)
                    .submitLabel(.done)
                    .onSubmit { if !trimmedCustom.isEmpty { honor(with: trimmedCustom) } }
                if !trimmedCustom.isEmpty {
                    Button {
                        honor(with: trimmedCustom)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.6)
            )
        }
    }

    private var markDoneButton: some View {
        Button {
            honor(with: nil)
        } label: {
            Text("Mark the block done")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.warmWheat)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.textPrimary)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var trimmedCustom: String {
        customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func honor(with specific: String?) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.honorBucket(bucket, specific: specific)
        dismiss()
    }
}
