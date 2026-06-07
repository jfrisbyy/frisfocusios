//
//  VoiceMemoCard.swift
//  FrisFocus
//
//  Tinted-white card: waveform icon, title + italic sub, play button.
//

import SwiftUI

struct VoiceMemoCard: View {
    let memo: VoiceMemo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("Voice memo · \(memo.duration)")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Text(memo.subtitle)
                    .font(.serifItalic(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

#Preview {
    VoiceMemoCard(memo: SampleData.voiceMemo)
        .padding()
        .background(Theme.paperCream)
}
