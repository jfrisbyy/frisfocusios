//
//  AppMode.swift
//  FrisFocus
//
//  The lifecycle state of a fresh install. On the very first launch the
//  Store no longer silently seeds a fake life — instead it sits in
//  `.uninitialized` until the welcome intro resolves into either a clean
//  personal start (`.clean`) or a fully-seeded sample sandbox (`.demo`).
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

    /// The user is exploring the fully-populated sample sandbox. A
    /// persistent marker stays visible, and "Exit demo" wipes it back
    /// to a clean start.
    case demo
}
