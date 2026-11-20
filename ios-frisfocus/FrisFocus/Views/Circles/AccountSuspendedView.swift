//
//  AccountSuspendedView.swift
//  FrisFocus
//
//  What a suspended account sees in place of the social room.
//
//  The server is what enforces a suspension: row-level security refuses
//  a suspended account's posts, messages, requests and uploads, and
//  stops serving what it already shared. Without this screen all of
//  that would simply look like an app where nothing works — every send
//  failing, no reason given. This says what happened, what still works,
//  and where to write.
//
//  Deliberately plain. It is not a place for an appeal form or a
//  countdown; a person reads the appeal, so it goes to support.
//

import SwiftUI

struct AccountSuspendedView: View {
    /// The reason a moderator chose to show, if any.
    var reason: String?

    private var shownReason: String? {
        guard let text = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Theme.alertRed)

                Text("Your account is suspended")
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Friends, circles, stories and messages are unavailable while a suspension is in place. Your own tasks, notes and season are untouched.")
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                if let shownReason {
                    Text(shownReason)
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.paperCream)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("If you think this is a mistake, contact support and a person will review it.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                if let mailto = LegalContact.mailtoURL(subject: "Account suspension") {
                    Link(destination: mailto) {
                        Text("Contact support")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.textCream)
                            .padding(.horizontal, 22)
                            .frame(height: 46)
                            .background(Theme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 4)
                }

                Text(LegalContact.supportEmail)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
        }
    }
}

#Preview {
    AccountSuspendedView(reason: "Repeated harassment in a public circle.")
}
