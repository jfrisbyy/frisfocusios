//
//  AlertCardView.swift
//  FrisFocus
//
//  White card with severity-tinted border. Icon on the left, plain
//  English title and sub-line on the right.
//

import SwiftUI

struct AlertCardView: View {
    let alert: AlertItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity.iconName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(alert.severity.color)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(alert.subtitle)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(alert.severity.color.opacity(0.22), lineWidth: 0.5)
        )
    }
}

#Preview {
    VStack(spacing: 10) {
        AlertCardView(alert: SampleData.alerts[0])
        AlertCardView(alert: SampleData.alerts[1])
    }
    .padding()
    .background(Theme.warmWheat)
}
