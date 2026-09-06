//
//  CadenceLinkService.swift
//  FrisFocus
//
//  The read side of the Esengo seam. Talks to the shared Supabase
//  project (LINK-0): checks per-product entitlements, lists the user's
//  Cadence routines for the link picker, and consumes outcome events to
//  credit FrisFocus points — idempotently and honestly.
//
//  FrisFocus is whole without Cadence: `isEligible` is false unless the
//  account holds BOTH `frisfocus` and `cadence` entitlements, and every
//  link surface is gated on that. (DEBUG builds report eligible + seed a
//  few sample routines so the flow is reviewable in the simulator; the
//  outcome sync still runs against the real table.)
//

import Foundation
import Observation
import Supabase

@Observable
final class CadenceLinkService {
    /// Whether the signed-in account holds each product entitlement.
    var hasCadence: Bool = false
    var hasFrisFocus: Bool = false

    /// The account's Cadence routines, for the link picker.
    var routines: [CadenceRoutineSummary] = []

    var isRefreshing: Bool = false

    /// The link feature is available only when the account holds BOTH
    /// entitlements. In DEBUG we force eligible so the UI is reviewable.
    var isEligible: Bool {
        #if DEBUG
        return true
        #else
        return hasCadence && hasFrisFocus
        #endif
    }

    var routineCount: Int { routines.count }

    // MARK: - Refresh

    /// Refresh entitlements + routines for the signed-in account. Safe to
    /// call repeatedly (on sign-in, on the connect screen appearing).
    func refresh(myUserId: String?) async {
        guard let myUserId, !myUserId.isEmpty else {
            hasCadence = false
            hasFrisFocus = false
            routines = []
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshEntitlements()
        await loadRoutines()
    }

    private func refreshEntitlements() async {
        do {
            let cadence: Bool = try await supabase
                .rpc("esengo_has_product", params: ["p_product": "cadence"])
                .execute()
                .value
            let fris: Bool = try await supabase
                .rpc("esengo_has_product", params: ["p_product": "frisfocus"])
                .execute()
                .value
            hasCadence = cadence
            hasFrisFocus = fris
        } catch {
            Log.cadence.error("entitlement check failed: \(error)")
        }
    }

    func loadRoutines() async {
        do {
            let rows: [CadenceRoutineWire] = try await supabase
                .from("cadence_routines")
                .select("id, name, kind, step_count, est_minutes")
                .order("name", ascending: true)
                .execute()
                .value
            if !rows.isEmpty {
                routines = rows.map { $0.summary }
                return
            }
        } catch {
            Log.cadence.error("routine load failed: \(error)")
        }
        #if DEBUG
        if routines.isEmpty {
            routines = CadenceLinkService.debugSampleRoutines
        }
        #endif
    }

    // MARK: - Outcome sync (silent credit)

    /// Read unconsumed outcome events for the account, score each one
    /// into the Store, and mark the handled events consumed. Idempotent:
    /// a verified event is never double-scored (the backend
    /// `consumed_by_frisfocus` flag plus the Store's consumed-id set).
    /// Verified-false events are recorded (consumed) but never scored.
    func sync(into store: Store, myUserId: String?) async {
        guard let myUserId, !myUserId.isEmpty else { return }
        do {
            let rows: [CadenceOutcomeEventRow] = try await supabase
                .from("cadence_outcome_events")
                .select("id, account_id, event_type, routine_id, occurred_at, verified, metrics")
                .eq("consumed_by_frisfocus", value: false)
                .order("occurred_at", ascending: true)
                .execute()
                .value
            guard !rows.isEmpty else { return }

            var consumedIds: [String] = []
            for row in rows {
                if store.applyCadenceEvent(row) {
                    consumedIds.append(row.id.uuidString)
                }
            }
            guard !consumedIds.isEmpty else { return }

            try await supabase
                .from("cadence_outcome_events")
                .update(["consumed_by_frisfocus": true])
                .in("id", values: consumedIds)
                .execute()
        } catch {
            Log.cadence.error("outcome sync failed: \(error)")
        }
    }

    #if DEBUG
    static let debugSampleRoutines: [CadenceRoutineSummary] = [
        CadenceRoutineSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000CAD1")!,
            name: "Wind-down routine", kind: "sleep", stepCount: 5, estMinutes: 10
        ),
        CadenceRoutineSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000CAD2")!,
            name: "Morning routine", kind: "morning", stepCount: 6, estMinutes: 12
        ),
        CadenceRoutineSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000CAD3")!,
            name: "Deep focus block", kind: "focus", stepCount: 1, estMinutes: 60
        )
    ]
    #endif
}

// MARK: - Wire

/// `cadence_routines` row. `nonisolated` + `Sendable` so it decodes off
/// the main actor.
nonisolated struct CadenceRoutineWire: Decodable, Sendable {
    let id: UUID
    let name: String
    let kind: String?
    let stepCount: Int
    let estMinutes: Int

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case stepCount = "step_count"
        case estMinutes = "est_minutes"
    }

    var summary: CadenceRoutineSummary {
        CadenceRoutineSummary(id: id, name: name, kind: kind, stepCount: stepCount, estMinutes: estMinutes)
    }
}
