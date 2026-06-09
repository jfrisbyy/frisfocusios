//
//  InviteLink.swift
//  FrisFocus
//
//  The personal invite link people share to add each other. A custom
//  scheme (`frisfocus://add-friend?u=<id>`) registered in Info.plist, so
//  tapping it (or scanning the QR) opens the app straight to the
//  inviter's profile with an Add control. Pure value helpers — safe to
//  call from anywhere.
//

import Foundation

enum InviteLink {
    static let scheme = "frisfocus"
    static let host = "add-friend"

    /// The shareable invite URL for a given account id.
    nonisolated static func url(forUserId userId: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "u", value: userId)]
        return components.url
    }

    /// Extract the invited account id from an incoming URL, or nil when
    /// the URL isn't one of our invite links.
    nonisolated static func userId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let id = components?.queryItems?.first(where: { $0.name == "u" })?.value
        guard let id, !id.isEmpty else { return nil }
        return id
    }
}
