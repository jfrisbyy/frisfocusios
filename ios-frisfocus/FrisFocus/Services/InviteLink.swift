//
//  InviteLink.swift
//  FrisFocus
//
//  The personal invite link people share to add each other. Two forms:
//
//   • The shareable HTTPS link — a hosted landing page that works in
//     Messages previews, browsers, and on phones without the app; its
//     "Open FrisFocus" button hops into the app via the custom scheme.
//   • The custom scheme (`frisfocus://add-friend?u=<id>`) registered in
//     Info.plist — what actually opens the app to the inviter's profile.
//
//  `userId(from:)` accepts both, so a pasted web link or a scanned QR
//  lands identically whether the app was cold-launched or foregrounded.
//  Pure value helpers — safe to call from anywhere.
//
//  The link is not the whole invite. The landing page is served from
//  the project's default Supabase domain, which does not reliably
//  render HTML (it can arrive as plain text), and a recipient without
//  the app cannot follow the custom scheme at all. So the words that
//  travel with the link have to work on their own: `addMeLine` puts the
//  sender's @username in the message itself, which is the one thing a
//  recipient can always act on — install, open Friends, search it.
//

import Foundation

enum InviteLink {
    static let scheme = "frisfocus"
    static let host = "add-friend"

    /// Base for the hosted landing page. Falls back to the project's
    /// live URL if the build-time config value is absent.
    private nonisolated static var functionsBase: String {
        let configured = Config.EXPO_PUBLIC_SUPABASE_URL
        return configured.isEmpty ? "https://pgrsrgctuclcmbhqnlqo.supabase.co" : configured
    }

    /// The custom-scheme URL that opens the app directly. Used by the
    /// landing page's button; not shared directly anymore.
    nonisolated static func url(forUserId userId: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "u", value: userId)]
        return components.url
    }

    /// The shareable invite URL for a given account id — an HTTPS
    /// landing page that survives previews, browsers, and phones
    /// without the app installed. Share sheet, copy-link, and the QR
    /// code all use this same durable form.
    nonisolated static func webURL(forUserId userId: String) -> URL? {
        var components = URLComponents(string: "\(functionsBase)/functions/v1/invite")
        components?.queryItems = [URLQueryItem(name: "u", value: userId)]
        return components?.url
    }

    /// "Add me on FrisFocus: @username" — the line of an invite that
    /// still works when the link does not. Accepts the handle with or
    /// without its "@". With no username claimed yet there is nothing
    /// to search for, so it falls back to the bare ask and the link
    /// carries the invite alone.
    nonisolated static func addMeLine(handle: String?) -> String {
        let trimmed = (handle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "@" else { return "Add me on FrisFocus" }
        let tagged = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        return "Add me on FrisFocus: \(tagged)"
    }

    /// The complete invite as text — the add-me line, then the link —
    /// for surfaces that compose the whole message themselves (a text
    /// message body, copy-to-clipboard). Share sheets that already
    /// attach the URL as their item should send `addMeLine` alone.
    nonisolated static func shareText(handle: String?, userId: String) -> String {
        let line = addMeLine(handle: handle)
        guard let link = webURL(forUserId: userId)?.absoluteString else { return line }
        return "\(line)\n\(link)"
    }

    /// Extract the invited account id from an incoming URL, or nil when
    /// the URL isn't one of our invite links. Accepts both the custom
    /// scheme and the hosted HTTPS form.
    nonisolated static func userId(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let id = components?.queryItems?.first(where: { $0.name == "u" })?.value

        if url.scheme?.lowercased() == scheme, url.host?.lowercased() == host {
            guard let id, !id.isEmpty else { return nil }
            return id
        }

        // Hosted landing-page form: https://…/functions/v1/invite?u=<id>
        if let httpScheme = url.scheme?.lowercased(),
           httpScheme == "https" || httpScheme == "http",
           url.path.hasSuffix("/functions/v1/invite") {
            guard let id, !id.isEmpty else { return nil }
            return id
        }

        return nil
    }
}
