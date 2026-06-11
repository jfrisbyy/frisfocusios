//
//  ShareLayersSheet.swift
//  FrisFocus
//
//  The compact disclosure control for the share overlay. Governs the
//  DAY'S CONTENT only — season name, tasks, numbers. The sun has no
//  toggle (it's the mark), and attribution is identity, never a layer.
//

import SwiftUI

struct ShareLayersSheet: View {
    @Binding var options: ShareOverlayOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ON THE CARD")
                .font(.sans(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .padding(.top, 26)
                .padding(.bottom, 18)

            // The sun — always present.
            HStack {
                Text("The sun")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("always")
                    .font(.serifItalic(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
            .padding(.vertical, 13)

            hairline

            Toggle(isOn: $options.showSeasonName) {
                Text("Season name")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Color(hex: 0xC2922F))
            .padding(.vertical, 11)

            hairline

            Toggle(isOn: $options.showTasks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Completed tasks")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Show what you did today")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .tint(Color(hex: 0xC2922F))
            .padding(.vertical, 11)

            hairline

            Toggle(isOn: $options.showNumbers) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("My numbers")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your percent · off by default")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .tint(Color(hex: 0xC2922F))
            .padding(.vertical, 11)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paperCream)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.08))
            .frame(height: 0.5)
    }
}

#Preview {
    ShareLayersSheet(options: .constant(ShareOverlayOptions()))
}
