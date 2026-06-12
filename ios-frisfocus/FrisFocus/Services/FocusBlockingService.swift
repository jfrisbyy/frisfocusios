//
//  FocusBlockingService.swift
//  FrisFocus
//
//  Real iPhone app-blocking for focus sessions, built on Apple's Screen
//  Time stack (FamilyControls + ManagedSettings). While a focus block —
//  solo or grove — is running, the apps/categories the user hand-picked
//  through Apple's official picker are shielded: opening one shows the
//  system block screen instead. When the block ends (timer, early quit,
//  or unexpected teardown) the shield is always lifted.
//
//  Apple gates real blocking behind the Family Controls entitlement, so
//  OS-level shielding only takes effect on a real device with the
//  approved entitlement. In the simulator the same flow runs but Apple
//  can't actually shield other apps — the UI labels that honestly while
//  staying fully testable.
//

import Foundation
import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

/// App-wide service that owns the focus blocklist + applies/removes the
/// OS shield around a focus session. Injected via the environment.
@Observable
@MainActor
final class FocusBlockingService {
    static let shared = FocusBlockingService()

    /// Where authorization currently stands. Drives the explainer /
    /// permission prompt and whether real shielding can take effect.
    enum AuthStatus: Equatable {
        /// Never asked.
        case notDetermined
        /// Approved — real shielding works on device.
        case approved
        /// User declined Screen Time access.
        case denied
        /// Family Controls can't run here (e.g. the simulator). The
        /// product flow still works; blocking is demo-only.
        case unavailable
    }

    private(set) var authStatus: AuthStatus = .notDetermined
    /// True while a shield is actively applied to the chosen apps.
    private(set) var isShielding = false
    /// Whether the user wants blocking on for their sessions. Persisted.
    var isEnabled: Bool = true {
        didSet { defaults.set(isEnabled, forKey: enabledKey) }
    }

    private let defaults = UserDefaults.standard
    private let selectionKey = "focusBlock.selection.v1"
    private let enabledKey = "focusBlock.enabled.v1"

    #if canImport(FamilyControls)
    /// The user's chosen apps / categories / web domains to silence.
    /// Codable, persisted between launches.
    var selection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }
    /// A private named store so our shield never collides with another
    /// app's Screen Time configuration.
    private let managedStore = ManagedSettingsStore(named: .init("frisfocusFocus"))
    #endif

    init() {
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        loadSelection()
        refreshAuthStatus()
    }

    // MARK: - Selection summary

    /// How many distinct things are currently in the blocklist.
    var blockedItemCount: Int {
        #if canImport(FamilyControls)
        return selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
        #else
        return 0
        #endif
    }

    var hasSelection: Bool { blockedItemCount > 0 }

    /// Whether real OS-level shielding can actually take effect here.
    var canBlockForReal: Bool { authStatus == .approved }

    /// Short line for the focus setup / running screens.
    var summaryLine: String {
        guard isEnabled, hasSelection else { return "No apps silenced" }
        let n = blockedItemCount
        let base = "\(n) \(n == 1 ? "thing" : "things") silenced"
        return canBlockForReal ? base : "\(base) · demo"
    }

    // MARK: - Authorization

    func refreshAuthStatus() {
        #if canImport(FamilyControls)
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: authStatus = .approved
        case .denied: authStatus = .denied
        case .notDetermined: authStatus = .notDetermined
        @unknown default: authStatus = .notDetermined
        }
        #else
        authStatus = .unavailable
        #endif
    }

    /// Ask for Screen Time access. Safe to call repeatedly.
    func requestAuthorization() async {
        #if canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuthStatus()
        } catch {
            // On the simulator (and when the entitlement isn't present)
            // this throws — fall back to demo mode rather than blocking
            // the user from continuing.
            print("[FocusBlocking] authorization failed: \(error)")
            authStatus = .unavailable
        }
        #else
        authStatus = .unavailable
        #endif
    }

    // MARK: - Shielding

    /// Apply the shield for the duration of a focus block. No-op when
    /// disabled, empty, or unauthorized (the running screen still shows
    /// the demo summary).
    func beginShielding() {
        guard isEnabled, hasSelection else { return }
        #if canImport(FamilyControls)
        guard canBlockForReal else { return }
        managedStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        managedStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil : selection.webDomainTokens
        isShielding = true
        #endif
    }

    /// Always-safe teardown — lifts every shield this app set. Called on
    /// session end, early quit, and as a guard on app launch so nothing
    /// is ever left locked by accident.
    func endShielding() {
        #if canImport(FamilyControls)
        managedStore.shield.applications = nil
        managedStore.shield.applicationCategories = nil
        managedStore.shield.webDomains = nil
        managedStore.clearAllSettings()
        #endif
        isShielding = false
    }

    // MARK: - Persistence

    private func loadSelection() {
        #if canImport(FamilyControls)
        guard let data = defaults.data(forKey: selectionKey) else { return }
        if let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = decoded
        }
        #endif
    }

    private func saveSelection() {
        #if canImport(FamilyControls)
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: selectionKey)
        }
        #endif
    }
}
