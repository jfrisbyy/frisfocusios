//
//  ZoneHeaderView.swift
//  FrisFocus
//
//  Shared header used at the top of Work, Note, and Signal zones.
//  Editorial: big serif title, small uppercase eyebrow on the right,
//  italic subline below.
//

import SwiftUI

struct ZoneHeaderView: View {
    let title: String
    /// Optional uppercase eyebrow on the right — omitted entirely when
    /// empty so headers with trailing controls don't collide with it.
    var eyebrowRight: String = ""
    let subline: String
    var textColor: Color = Theme.textPrimary
    var dim: Double = 0.55

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(textColor)

                Spacer()

                if !eyebrowRight.isEmpty {
                    Text(eyebrowRight.uppercased())
                        .font(.sans(10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(textColor.opacity(dim))
                }
            }

            Text(subline)
                .font(.serifItalic(12, weight: .regular))
                .foregroundStyle(textColor.opacity(0.6))
        }
    }
}
