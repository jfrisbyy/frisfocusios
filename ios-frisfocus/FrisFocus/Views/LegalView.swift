//
//  LegalView.swift
//  FrisFocus
//
//  The in-app Privacy Policy and Terms of Use — reachable from the
//  sign-in step (before an account exists) and from the account hub.
//  Written to match what the app actually does: private by default,
//  friends see only what you choose, delete everything in-app.
//

import SwiftUI

/// Where FrisFocus can be reached, and where these documents live on the
/// web.
///
/// App Store Connect requires a support URL and a PUBLICLY HOSTED privacy
/// policy — text living only inside the binary does not satisfy either.
/// The copy below is the source of truth for what gets published there, so
/// keeping the addresses beside it is what stops the two drifting apart.
enum LegalContact {
    static let supportEmail = "support@frisfocus.app"
    static let privacyURL = URL(string: "https://frisfocus.app/privacy")!
    static let termsURL = URL(string: "https://frisfocus.app/terms")!

    /// Prefilled so a report arrives with something to act on rather than
    /// an empty message.
    static func mailtoURL(subject: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url
    }
}

/// One of the two legal documents, driving both the pushed rows in the
/// account hub and the sheet links under the sign-in buttons.
enum LegalDocument: String, Identifiable, CaseIterable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Use"
        }
    }

    var updated: String {
        "Last updated August 2026"
    }

    var sections: [LegalSection] {
        switch self {
        case .privacy: return Self.privacySections
        case .terms: return Self.termsSections
        }
    }

    static let privacySections: [LegalSection] = [
        LegalSection(
            heading: "The short version",
            body: "FrisFocus is private by default. Your points, your plan, and your notes belong to you. Friends see only what you explicitly choose to share — the shape of your day, never the numbers. We don't run ads, we don't sell data, and we don't use third-party trackers."
        ),
        LegalSection(
            heading: "What we store",
            body: "When you sign in with Apple or Google we receive your name and email address to create your account. Your email is stored privately — it is never shown to other members and never leaves our servers. You can add a display name, @username, photo, and header image; those are visible to people who find you."
        ),
        LegalSection(
            heading: "Your season and notes",
            body: "Your season plan, daily check-ins, points, milestones, and journal notes sync to your account so they follow you across devices. They are private: no other member can read them. If you publish a season card or share with a friend, only the fields you chose for that person are visible to them."
        ),
        LegalSection(
            heading: "What friends can see",
            body: "Sharing is per-friend and tiered. At the quietest tier a friend sees almost nothing; at the fullest tier they see your day's shape and shared activities. Exact points are never shown to anyone. Stories, proofs, messages, and Golden Hour captures are visible only to the friends or circle members they were shared with, and media is served through short-lived private links."
        ),
        LegalSection(
            heading: "Contacts (optional)",
            body: "If you choose to find friends from your contacts, your contacts' email addresses and one-way hashes of their phone numbers are checked against existing accounts in the moment. Your contact list is never stored on our servers."
        ),
        LegalSection(
            heading: "Near you (optional)",
            body: "If you turn on Near you, we store a coarse area (roughly a 50 km grid cell) — never your precise location. Turn it off any time and the area is removed."
        ),
        LegalSection(
            heading: "Notifications",
            body: "Push notifications are person-to-person only — a friend request, a cheer, a proof. Daily reminders are built on your device and never leave it. Both can be switched off any time."
        ),
        LegalSection(
            heading: "Deleting your account",
            body: "You can delete your account in the app (You → Delete account). This permanently erases your profile, seasons, notes, messages, stories, circles, and friendships. There is no grace period and no backup copy."
        ),
        LegalSection(
            heading: "Questions or concerns",
            body: "Use the report flows inside the app to flag a specific person or piece of content — reports are reviewed by a person. For anything else, including a question about your data or a request to have it removed, write to \(LegalContact.supportEmail)."
        ),
    ]

    static let termsSections: [LegalSection] = [
        LegalSection(
            heading: "The agreement",
            body: "By creating an account you agree to these terms. If you don't agree, please don't use FrisFocus. You must be at least 13 years old (or the minimum age in your country) to use the app."
        ),
        LegalSection(
            heading: "Your content",
            body: "Everything you create — seasons, notes, stories, proofs, captures — remains yours. You give us only the permission needed to store it and show it to the people you chose to share it with. We never publish your content anywhere else."
        ),
        LegalSection(
            heading: "Being a good witness",
            body: "FrisFocus is built on quiet, mutual witness. Don't harass, bully, impersonate, or spam other members. Don't post unlawful, hateful, or sexually explicit content. Content shared with you by friends is theirs — don't redistribute it."
        ),
        LegalSection(
            heading: "Moderation",
            body: "You can report any member or piece of shared content, hide content from your view, and block people. We may remove content or suspend accounts that break these terms, and we may act on reports without prior notice when safety requires it."
        ),
        LegalSection(
            heading: "The service",
            body: "We work hard to keep FrisFocus available and your data safe, but the app is provided as-is, without warranties. Features may change or be discontinued as the product evolves. We are not liable for indirect damages to the extent the law allows."
        ),
        LegalSection(
            heading: "Ending things",
            body: "You can stop using FrisFocus and delete your account at any time, in the app. We may suspend or end accounts that violate these terms."
        ),
        LegalSection(
            heading: "Changes",
            body: "If these terms change in a meaningful way, we'll surface the update in the app. Continuing to use FrisFocus after a change means you accept the new terms."
        ),
    ]
}

struct LegalSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

/// A calm, readable legal page in the app's own voice and paper. Works
/// pushed inside a NavigationStack (account hub) or wrapped in one as a
/// sheet (sign-in step).
struct LegalView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(document.title)
                    .font(.serif(28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 18)

                Text(document.updated)
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 6)

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(section.heading)
                            .font(.serif(17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(section.body)
                            .font(.sans(14, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 22)
                }

                contactRow
                    .padding(.top, 26)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.warmWheat.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
    }

    /// A tappable address rather than one more sentence about writing to
    /// us. Rendered as a Link so it works in the pre-account sheet too,
    /// where there is no navigation stack to lean on.
    @ViewBuilder
    private var contactRow: some View {
        if let mailto = LegalContact.mailtoURL(subject: "FrisFocus — \(document.title)") {
            VStack(alignment: .leading, spacing: 7) {
                Text("Reach a person")
                    .font(.serif(17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Link(destination: mailto) {
                    HStack(spacing: 7) {
                        Image(systemName: "envelope")
                            .font(.system(size: 13, weight: .regular))
                        Text(LegalContact.supportEmail)
                            .font(.sans(14, weight: .medium))
                    }
                    .foregroundStyle(Theme.sunOuter)
                }
                .accessibilityLabel("Email \(LegalContact.supportEmail)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        LegalView(document: .privacy)
    }
}
