//
//  AppMode.swift
//  FrisFocus
//
//  The lifecycle state of a fresh install. On the very first launch the
//  Store sits in `.uninitialized` until the welcome intro resolves into
//  either the pre-auth sample sandbox (`.demo`) or a clean personal
//  start (`.clean`) backed by a real signed-in account.
//

import Foundation

/// Whether this install has been introduced yet, and if so, which path
/// the user chose. Persisted as a raw string under its own key so it
/// survives model-version bumps independently of the data slices.
nonisolated enum AppMode: String, Codable, Equatable {
    /// Brand-new install that hasn't seen the welcome intro yet. No
    /// data is seeded; the intro carousel is shown over the home.
    case uninitialized

    /// The pre-auth sample sandbox ("Explore a demo first") — a
    /// clearly-marked, fully local sample life the person can leave at
    /// any time. Exiting wipes every sample row and routes back into
    /// the real onboarding flow.
    case demo

    /// The user chose to start their own season from a clean slate.
    /// Nothing is seeded; they walk the real onboarding flow.
    case clean
}
