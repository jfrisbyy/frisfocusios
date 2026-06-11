//
//  MilestoneShareLayersSheet.swift
//  FrisFocus
//
//  The compact disclosure control for the milestone share overlay —
//  the same quiet sheet language as the day card's. Governs the
//  SUPPORTING lines only: progress, points, season name, timeline,
//  and the journey-photo strip. The title and flag have no toggle
//  (they are the card), and attribution is identity, never a layer.
//

import SwiftUI

struct MilestoneShareLayersSheet: View {
    @Binding var options: MilestoneShareOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ON THE CARD")
                .font(.sans(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .padding(.top, 26)
                .padding(.bottom, 18)

            // The title + flag — always present.
            HStack {
                Text("The title")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("always")
                    .font(.serifItalic(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
            .padding(.vertical, 13)

            hairline

            Toggle(isOn: $options.showProgress) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progress")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Steps done — or the LANDED stamp")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .tint(Color(hex: 0xC2922F))
            .padding(.vertical, 11)

            hairline

            Toggle(isOn: $options.showPoints) {
                Text("Points")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Color(hex: 0xC2922F))
            .padding(.vertical, 11)

            hairline

            Toggle(isOn: $options.showSeasonName) {
                Text("Season name")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Color(hex: 0xC2922F))
            .padding(.vertical, 11)

            hairline

            Toggle(isOn: $options.showTimeline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timeline")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Target week and the landing date")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .tint(Color(hex: 0xC2922F))
            .padding(.vertical, 11)

            hairline

            Toggle(isOn: $options.showJourneyStrip) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Journey photos")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("A small strip of the documented process")
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
    MilestoneShareLayersSheet(options: .constant(MilestoneShareOptions()))
}
