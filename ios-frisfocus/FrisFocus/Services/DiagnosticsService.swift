//
//  DiagnosticsService.swift
//  FrisFocus
//
//  Crash, hang and onboarding-funnel reporting, built on MetricKit
//  rather than a third-party SDK.
//
//  The plan of record was Sentry, and the seam for it is still here —
//  `record` is the only entry point and swapping its body is the whole
//  integration. But Sentry cannot report anything without a project DSN,
//  which is an account that does not exist yet, and shipping a beta
//  blind to its own crashes to wait on a signup is the wrong trade.
//  `MetricKit` is first-party, needs no account, no SPM dependency and
//  no key: iOS hands the app the previous run's crash and hang
//  diagnostics on the next launch. It is a day late by design, which is
//  fine for "which screen is killing people" and no use for live
//  alerting — that is what the Sentry swap is for later.
//
//  Nothing here is keyed to an account. Rows carry a random per-install
//  id, so this answers "how many people crash in the cold start" and
//  cannot answer "what did this person do". That is what lets the
//  privacy manifest declare crash and diagnostic data unlinked, and it
//  is why `diagnostics_events` grants insert and nothing else — not even
//  to the device that wrote the row.
//

import Foundation
import MetricKit
import UIKit
import Supabase

/// One thing worth knowing about, on its way to the server.
private nonisolated struct DiagnosticsRow: Encodable, Sendable {
    let installId: String
    let kind: String
    let name: String
    let appVersion: String?
    let osVersion: String?
    let detail: [String: String]?
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case kind, name, detail
        case installId = "install_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case occurredAt = "occurred_at"
    }
}

/// The steps of the two onboarding doors, in the order they happen.
///
/// Named rather than free-form so the funnel can't drift into a set of
/// almost-identical strings that no query can group. Adding a step here
/// is the only way to add one to the funnel.
enum FunnelStep: String, CaseIterable, Sendable {
    // Shared entry
    case ageCheckShown = "age_check.shown"
    case ageCheckPassed = "age_check.passed"
    case ageCheckBlocked = "age_check.blocked"
    case signedIn = "auth.signed_in"

    // The cold-start door (build a season from nothing). Each of these
    // is "reached the phase", emitted from the one place phases change.
    case coldStartOpened = "cold_start.opened"
    case coldStartDirectionsChosen = "cold_start.directions_chosen"
    case coldStartBoardFilled = "cold_start.board_filled"
    case coldStartCapstone = "cold_start.capstone"
    case coldStartCalibrated = "cold_start.calibrated"
    case coldStartCommitted = "cold_start.committed"

    // The conversational door (talk the season out). Coarser than the
    // cold start on purpose — it is a conversation, not a sequence of
    // screens, so there is no honest midpoint to mark.
    case seasonSetupOpened = "season_setup.opened"
    case seasonSetupCommitted = "season_setup.committed"

    // Past the door: a season was built and then actually used.
    case firstTaskCompleted = "first.task_completed"
}

// Not @Observable: nothing renders from this, and the macro on an
// NSObject subclass buys complexity for no view.
@MainActor
final class DiagnosticsService: NSObject {

    static let shared = DiagnosticsService()

    /// A random id for this installation. Not the account, not the
    /// device — reinstalling produces a new one, and it is never joined
    /// to anything that identifies a person.
    @ObservationIgnored private let installId: String
    @ObservationIgnored private var isSignedIn = false
    /// Funnel steps recorded before a session existed. The table takes
    /// authenticated writes only, so pre-sign-in steps wait here and go
    /// up together once an account appears.
    @ObservationIgnored private var buffered: [DiagnosticsRow] = []
    /// Steps already recorded this install, so a step someone reaches
    /// twice (a restarted cold start) is counted once.
    @ObservationIgnored private var recordedSteps: Set<String> = []

    private static let installIdKey = "diagnostics.installId.v1"
    private static let recordedStepsKey = "diagnostics.recordedSteps.v1"
    /// The buffer is a courtesy, not a queue with delivery guarantees.
    /// Capped so an install that never signs in cannot grow it forever.
    private static let bufferLimit = 60

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private override init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.installIdKey) {
            installId = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Self.installIdKey)
            installId = fresh
        }
        recordedSteps = Set(defaults.stringArray(forKey: Self.recordedStepsKey) ?? [])
        super.init()
    }

    // MARK: - Lifecycle

    /// Begin receiving MetricKit payloads. Safe to call more than once.
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// A session now exists (or no longer does). Flushes anything the
    /// funnel recorded while signed out.
    func setSignedIn(_ signedIn: Bool) {
        isSignedIn = signedIn
        guard signedIn, !buffered.isEmpty else { return }
        let pending = buffered
        buffered = []
        Task { await send(pending) }
    }

    // MARK: - Recording

    /// Note that someone reached a step of onboarding. Idempotent per
    /// install: the funnel counts people, not attempts.
    func record(_ step: FunnelStep) {
        guard !recordedSteps.contains(step.rawValue) else { return }
        recordedSteps.insert(step.rawValue)
        UserDefaults.standard.set(Array(recordedSteps), forKey: Self.recordedStepsKey)
        enqueue(row(kind: "funnel", name: step.rawValue, detail: nil, at: Date()))
    }

    private func enqueue(_ row: DiagnosticsRow) {
        guard isSignedIn else {
            if buffered.count < Self.bufferLimit { buffered.append(row) }
            return
        }
        Task { await send([row]) }
    }

    /// Fire-and-forget. Diagnostics must never be the reason something
    /// the person actually asked for fails or stalls, so a failure here
    /// is dropped rather than retried.
    private func send(_ rows: [DiagnosticsRow]) async {
        guard !rows.isEmpty else { return }
        do {
            try await supabase.from("diagnostics_events").insert(rows).execute()
        } catch {
            print("[Diagnostics] send failed: \(error)")
        }
    }

    private func row(
        kind: String,
        name: String,
        detail: [String: String]?,
        at date: Date
    ) -> DiagnosticsRow {
        DiagnosticsRow(
            installId: installId,
            kind: kind,
            name: name,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            osVersion: UIDevice.current.systemVersion,
            detail: detail,
            occurredAt: Self.iso.string(from: date)
        )
    }
}

// MARK: - MetricKit

extension DiagnosticsService: MXMetricManagerSubscriber {

    /// Required by the protocol. Daily performance metrics are not what
    /// this is for — battery, launch time and scroll hitches are already
    /// in App Store Connect, and sending them here would only duplicate
    /// that at our own cost.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {}

    /// iOS delivers the previous run's diagnostics on the next launch.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Reduce to plain values before hopping actors — MetricKit's
        // types are not Sendable, so nothing from `payloads` may escape
        // this call.
        var extracted: [(kind: String, name: String, detail: [String: String], at: Date)] = []

        for payload in payloads {
            let at = payload.timeStampEnd

            for crash in payload.crashDiagnostics ?? [] {
                var detail: [String: String] = [:]
                if let signal = crash.signal { detail["signal"] = signal.stringValue }
                if let reason = crash.exceptionReason?.composedMessage { detail["reason"] = reason }
                if let type = crash.exceptionType { detail["exception_type"] = type.stringValue }
                if let code = crash.exceptionCode { detail["exception_code"] = code.stringValue }
                detail["termination_reason"] = crash.terminationReason ?? "unknown"
                detail["frames"] = Self.topFrames(of: crash.callStackTree)
                extracted.append(("crash", crash.terminationReason ?? "crash", detail, at))
            }

            for hang in payload.hangDiagnostics ?? [] {
                extracted.append((
                    "hang",
                    "hang",
                    [
                        "duration_s": String(format: "%.1f", hang.hangDuration.value),
                        "frames": Self.topFrames(of: hang.callStackTree),
                    ],
                    at
                ))
            }

            for write in payload.diskWriteExceptionDiagnostics ?? [] {
                extracted.append((
                    "disk_write",
                    "excessive_disk_write",
                    [
                        "written_kb": String(format: "%.0f", write.writesCaused.value),
                        "frames": Self.topFrames(of: write.callStackTree),
                    ],
                    at
                ))
            }
        }

        guard !extracted.isEmpty else { return }
        let payloadsToSend = extracted
        Task { @MainActor [weak self] in
            guard let self else { return }
            for item in payloadsToSend {
                self.enqueue(self.row(kind: item.kind, name: item.name, detail: item.detail, at: item.at))
            }
        }
    }

    /// The call stack as JSON, truncated hard.
    ///
    /// A full MetricKit stack tree is tens of kilobytes and every row
    /// here is inserted over the same connection the app uses for real
    /// work. The top of the stack is what names the bug; the rest is
    /// weight. Symbolication happens in Xcode's Organizer against the
    /// same crash — this row exists to say *how often* and *where*, not
    /// to replace that.
    private static func topFrames(of tree: MXCallStackTree) -> String {
        let data = tree.jsonRepresentation()
        let limit = 4_000
        guard data.count > limit else {
            return String(decoding: data, as: UTF8.self)
        }
        return String(decoding: data.prefix(limit), as: UTF8.self) + "…[truncated]"
    }
}
