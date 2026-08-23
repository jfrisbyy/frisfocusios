//
//  AppMode.swift
//  FrisFocus
//
//  The lifecycle state of a fresh install. On the very first launch the
//  Store sits in `.uninitialized` until the welcome intro resolves into
//  a clean personal start (`.clean`) backed by a real signed-in account.
//  (The old `.demo` sample sandbox has been removed — a stored "demo"
//  marker is treated as uninitialized and its data purged.)
//

import Foundation

/// Whether this install has been introduced yet, and if so, which path
/// the user chose. Persisted as a raw string under its own key so it
/// survives model-version bumps independently of the data slices.
nonisolated enum AppMode: String, Codable, Equatable {
    /// Brand-new install that hasn't seen the welcome intro yet. No
    /// data is seeded; the intro carousel is shown over the home.
    case uninitialized

    /// The user chose to start their own season from a clean slate.
    /// Nothing is seeded; they go straight into guided season setup.
    case clean
}
