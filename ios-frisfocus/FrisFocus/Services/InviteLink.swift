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
