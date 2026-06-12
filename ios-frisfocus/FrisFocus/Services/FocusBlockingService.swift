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
        /// product flow still works; real shielding takes effect on
        /// a physical iPhone.
        case unavailable
    }

    /// Why the last authorization request failed — in plain words plus
    /// Apple's raw error code, so the true cause is always visible
    /// instead of the app silently giving up.
    struct AuthFailure: Equatable {
        /// Plain-language explanation shown to the user.
        let message: String
        /// Apple's raw error code, for the small diagnostic line.
        let rawCode: String
        /// Whether retrying in-app can plausibly succeed.
        let canRetry: Bool
        /// Whether the fix lives in the Settings app (iCloud / Screen Time).
        let suggestsSettings: Bool
    }

    private(set) var authStatus: AuthStatus = .notDetermined
    /// Set whenever the most recent authorization request failed on a
    /// real device. Cleared on the next attempt or success.
    private(set) var lastFailure: AuthFailure?
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
        return "\(n) \(n == 1 ? "thing" : "things") silenced"
    }

    /// True when the user has apps to silence but hasn't yet granted the
    /// Screen Time approval needed to actually block them. Drives the
    /// "Tap to allow blocking" prompt at session start.
    var needsPermission: Bool {
        isEnabled && hasSelection && authStatus == .notDetermined
    }

    /// Ensure we hold Screen Time approval before a session begins —
    /// asks once if it's never been requested. Safe to call anytime;
    /// no-op when already approved, denied, or unavailable.
    func ensureAuthorizedForSessionStart() async {
        guard isEnabled, hasSelection else { return }
        if authStatus == .notDetermined {
            await requestAuthorization()
        }
    }

    // MARK: - Authorization

    func refreshAuthStatus() {
        #if targetEnvironment(simulator)
        // Apple physically never shows the Screen Time prompt in the
        // simulator / browser preview — detected here properly instead
        // of inferred from a thrown error.
        authStatus = .unavailable
        #elseif canImport(FamilyControls)
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

    /// Asks for Screen Time access. Safe to call repeatedly: on a real
    /// iPhone a failure never permanently disables blocking; it records
    /// a plain-language `lastFailure` and stays retryable.
    /// - Returns: `true` when approval is held after the request.
    @discardableResult
    func requestAuthorization() async -> Bool {
        #if targetEnvironment(simulator)
        authStatus = .unavailable
        return false
        #elseif canImport(FamilyControls)
        lastFailure = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuthStatus()
            return authStatus == .approved
        } catch {
            print("[FocusBlocking] authorization failed: \(error)")
            lastFailure = Self.classify(error)
            // Re-read the system status (it may now be .denied), but
            // never write .unavailable on a real device — the user can
            // always try again.
            refreshAuthStatus()
            return false
        }
        #else
        authStatus = .unavailable
        return false
        #endif
    }

    /// Translates Apple's Family Controls errors into plain words that
    /// the user can act on, keeping the raw code visible for diagnosis.
    private static func classify(_ error: Error) -> AuthFailure {
        #if canImport(FamilyControls)
        if let fcError = error as? FamilyControlsError {
            switch fcError {
            case .invalidAccountType:
                return AuthFailure(
                    message: "This iPhone isn't signed into iCloud (or the signed-in account can't use Screen Time). Sign into iCloud in Settings, then try again.",
                    rawCode: "invalidAccountType",
                    canRetry: true,
                    suggestsSettings: true
                )
            case .authorizationCanceled:
                return AuthFailure(
                    message: "The approval was dismissed before it finished. Tap Try Again and choose Allow when Apple asks.",
                    rawCode: "authorizationCanceled",
                    canRetry: true,
                    suggestsSettings: false
                )
            case .authenticationMethodUnavailable:
                return AuthFailure(
                    message: "This iPhone has no passcode set. Apple requires a device passcode (or Face ID) before Screen Time access can be granted — set one in Settings, then try again.",
                    rawCode: "authenticationMethodUnavailable",
                    canRetry: true,
                    suggestsSettings: true
                )
            case .networkError:
                return AuthFailure(
                    message: "Apple couldn't be reached to confirm Screen Time access. Check your connection and try again.",
                    rawCode: "networkError",
                    canRetry: true,
                    suggestsSettings: false
                )
            case .restricted:
                return AuthFailure(
                    message: "Screen Time restrictions on this iPhone prevent FrisFocus from blocking apps. Check Settings › Screen Time.",
                    rawCode: "restricted",
                    canRetry: false,
                    suggestsSettings: true
                )
            case .authorizationConflict:
                return AuthFailure(
                    message: "Another app or profile already controls Screen Time on this iPhone, so FrisFocus can't take it over.",
                    rawCode: "authorizationConflict",
                    canRetry: false,
                    suggestsSettings: true
                )
            case .invalidArgument, .unavailable:
                return AuthFailure(
                    message: "This build of FrisFocus doesn't carry Apple's Family Controls approval in its signing, so iOS refuses the request. That's a one-time approval on the developer account — not a bug in the app.",
                    rawCode: String(describing: fcError),
                    canRetry: true,
                    suggestsSettings: false
                )
            @unknown default:
                break
            }
        }
        #endif
        let ns = error as NSError
        return AuthFailure(
            message: "Apple refused the Screen Time request. If this keeps happening, the installed build may be missing Apple's Family Controls signing approval.",
            rawCode: "\(ns.domain) \(ns.code)",
            canRetry: true,
            suggestsSettings: false
        )
    }

    // MARK: - Shielding

    /// Apply the shield for the duration of a focus block. No-op when
    /// disabled, empty, or unauthorized (the running screen still shows
    /// the silenced-apps summary).
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
