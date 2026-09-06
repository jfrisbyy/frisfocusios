//
//  GoldenHourService.swift
//  FrisFocus
//
//  The backend brain of the Golden Hour module. Owns:
//
//   • Per-circle settings (enabled + scheduling mode) from
//     `golden_hour_settings`, readable by every member.
//   • The deterministic daily fire instant — every member's device
//     computes the same moment with no server cron, which is what
//     keeps the synchronized local notifications aligned.
//   • Turns-mode picks (`golden_hour_picks`): the rotating picker's
//     secret time for today.
//   • Posts (`golden_hour_posts`): uploads into the private
//     `golden-hour` bucket, the post-to-see rule, attendance, streaks.
//   • Local notification scheduling (the fire alert + the "disappears
//     in 10 minutes" reminder) and the real-deletion sweep.
//
//  Deliberately separate from stories and proofs — Golden Hour media
//  never touches `direct_messages`, the story row, or the proofs cache
//  namespace it doesn't own. RLS enforces circle membership server-side.
//

import Foundation
import Supabase
import UserNotifications

// MARK: - Wire rows

private nonisolated struct GoldenSettingsRow: Codable, Sendable {
    let circleId: UUID
    let enabled: Bool
    let mode: String
    let fireMinute: Int
    let timeZone: String

    enum CodingKeys: String, CodingKey {
        case enabled, mode
        case circleId = "circle_id"
        case fireMinute = "fire_minute"
        case timeZone = "time_zone"
    }
}

private nonisolated struct GoldenSettingsUpsert: Encodable, Sendable {
    let circleId: String
    let enabled: Bool
    let mode: String
    let fireMinute: Int
    let timeZone: String
    let updatedBy: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case enabled, mode
        case circleId = "circle_id"
        case fireMinute = "fire_minute"
        case timeZone = "time_zone"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct GoldenPickRow: Codable, Sendable {
    let circleId: UUID
    let day: String
    let pickerId: String
    let fireMinute: Int

    enum CodingKeys: String, CodingKey {
        case day
        case circleId = "circle_id"
        case pickerId = "picker_id"
        case fireMinute = "fire_minute"
    }
}

private nonisolated struct GoldenPickUpsert: Encodable, Sendable {
    let circleId: String
    let day: String
    let pickerId: String
    let fireMinute: Int

    enum CodingKeys: String, CodingKey {
        case day
        case circleId = "circle_id"
        case pickerId = "picker_id"
        case fireMinute = "fire_minute"
    }
}

private nonisolated struct GoldenPostRow: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let day: String
    let userId: String
    let mediaPath: String?
    let mediaKind: String
    let mediaDuration: Double?
    let firedAt: String
    let postedAt: String
    let secondsToSpare: Int?

    enum CodingKeys: String, CodingKey {
        case id, day
        case circleId = "circle_id"
        case userId = "user_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case mediaDuration = "media_duration"
        case firedAt = "fired_at"
        case postedAt = "posted_at"
        case secondsToSpare = "seconds_to_spare"
    }
}

private nonisolated struct GoldenPostInsert: Encodable, Sendable {
    let circleId: String
    let day: String
    let userId: String
    let mediaPath: String
    let mediaKind: String
    let mediaDuration: Double?
    let firedAt: String
    let secondsToSpare: Int

    enum CodingKeys: String, CodingKey {
        case day
        case circleId = "circle_id"
        case userId = "user_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case mediaDuration = "media_duration"
        case firedAt = "fired_at"
        case secondsToSpare = "seconds_to_spare"
    }
}

private nonisolated struct CircleNameRow: Codable, Sendable {
    let id: UUID
    let name: String
}

private nonisolated struct MembershipRow: Codable, Sendable {
    let circleId: UUID
    let userId: String

    enum CodingKeys: String, CodingKey {
        case circleId = "circle_id"
        case userId = "user_id"
    }
}

/// Lenient decode of the sweep function's response.
private nonisolated struct SweepResponse: Decodable, Sendable {
    let ok: Bool?
    let deleted: Int?
}

// MARK: - Assembled circle

/// A circle as Golden Hour sees it: just enough to render the wall and
/// rotate the turns picker — never the full goal/task machinery.
struct GoldenCircle: Identifiable {
    let id: UUID
    let name: String
    let members: [RemoteProfile]
    var settings: GoldenHourSettings

    func profile(_ userId: String) -> RemoteProfile? { members.first { $0.id == userId } }
}

// MARK: - Service

@Observable
@MainActor
final class GoldenHourService {
    /// Circles with Golden Hour enabled, members resolved.
    var circles: [GoldenCircle] = []
    /// Settings for every circle the user belongs to (enabled or not),
    /// so the settings sheet always has the current state.
    var settingsByCircle: [UUID: GoldenHourSettings] = [:]
    /// Recent posts (≈45 days) for enabled circles — today's wall plus
    /// the attendance/streak residue.
    var posts: [GoldenHourPost] = []
    var isLoading = false
    var isWorking = false
    /// Byte-level progress of an in-flight capture upload (0...1).
    var uploadProgress: Double?
    var errorMessage: String?
    var showError = false

    /// Turns-mode picks keyed by "circleId#day".
    @ObservationIgnored private var picks: [String: GoldenHourPick] = [:]
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var signedURLCache: [String: (url: URL, expires: Date)] = [:]
    @ObservationIgnored private var didSweepThisSession = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func isoString(_ date: Date) -> String { isoFormatter.string(from: date) }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let d = isoFormatter.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: raw) { return d }
        if !raw.hasSuffix("Z"), !raw.contains("+") {
            let zulu = raw + "Z"
            if let d = isoFormatter.date(from: zulu) { return d }
            return plain.date(from: zulu)
        }
        return nil
    }

    // MARK: Load

    /// Pull settings for every circle the user belongs to, then resolve
    /// members + picks + recent posts for the enabled ones.
    func load(myUserId: String) async {
        guard !myUserId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let myMemberships: [MembershipRow] = try await supabase
                .from("circle_members")
                .select("circle_id, user_id")
                .eq("user_id", value: myUserId)
                .execute()
                .value
            let circleIds = Array(Set(myMemberships.map { $0.circleId.uuidString }))
            guard !circleIds.isEmpty else {
                circles = []; settingsByCircle = [:]; posts = []
                return
            }

            let settingsRows: [GoldenSettingsRow] = try await supabase
                .from("golden_hour_settings")
                .select("circle_id, enabled, mode, fire_minute, time_zone")
                .in("circle_id", values: circleIds)
                .execute()
                .value

            var byCircle: [UUID: GoldenHourSettings] = [:]
            for row in settingsRows {
                byCircle[row.circleId] = GoldenHourSettings(
                    circleId: row.circleId,
                    enabled: row.enabled,
                    mode: GoldenHourMode(rawValue: row.mode) ?? .surprise,
                    fireMinute: row.fireMinute,
                    timeZone: row.timeZone
                )
            }
            settingsByCircle = byCircle

            let enabledIds = byCircle.values.filter(\.enabled).map { $0.circleId.uuidString }
            guard !enabledIds.isEmpty else {
                circles = []; posts = []; picks = [:]
                rescheduleFireNotifications()
                return
            }

            let sinceDay = Self.dayString(daysAgo: 45)
            async let circleRowsReq: [CircleNameRow] = supabase
                .from("circles")
                .select("id, name")
                .in("id", values: enabledIds)
                .execute().value
            async let memberRowsReq: [MembershipRow] = supabase
                .from("circle_members")
                .select("circle_id, user_id")
                .in("circle_id", values: enabledIds)
                .execute().value
            async let pickRowsReq: [GoldenPickRow] = supabase
                .from("golden_hour_picks")
                .select("circle_id, day, picker_id, fire_minute")
                .in("circle_id", values: enabledIds)
                .gte("day", value: Self.dayString(daysAgo: 1))
                .execute().value
            async let postRowsReq: [GoldenPostRow] = supabase
                .from("golden_hour_posts")
                .select("id, circle_id, day, user_id, media_path, media_kind, media_duration, fired_at, posted_at, seconds_to_spare")
                .in("circle_id", values: enabledIds)
                .gte("day", value: sinceDay)
                .execute().value

            let circleRows = try await circleRowsReq
            let memberRows = try await memberRowsReq
            let pickRows = try await pickRowsReq
            let postRows = try await postRowsReq

            let profilesById = try await fetchProfiles(ids: Array(Set(memberRows.map(\.userId))))

            circles = circleRows.compactMap { row in
                guard let settings = byCircle[row.id] else { return nil }
                let members = memberRows
                    .filter { $0.circleId == row.id }
                    .compactMap { profilesById[$0.userId] }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                return GoldenCircle(id: row.id, name: row.name, members: members, settings: settings)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            var pickMap: [String: GoldenHourPick] = [:]
            for row in pickRows {
                let pick = GoldenHourPick(circleId: row.circleId, day: row.day, pickerId: row.pickerId, fireMinute: row.fireMinute)
                pickMap["\(row.circleId.uuidString)#\(row.day)"] = pick
            }
            picks = pickMap

            posts = postRows.compactMap(Self.mapPost)

            rescheduleFireNotifications()
            sweepIfNeeded()
            prefetchTodayMedia()
        } catch {
            fail("Couldn't load Golden Hour.", error)
        }
    }

    private static func mapPost(_ r: GoldenPostRow) -> GoldenHourPost? {
        guard let fired = parseDate(r.firedAt), let posted = parseDate(r.postedAt) else { return nil }
        return GoldenHourPost(
            id: r.id,
            circleId: r.circleId,
            day: r.day,
            userId: r.userId,
            mediaPath: r.mediaPath,
            mediaKind: ProofMediaKind(rawValue: r.mediaKind) ?? .photo,
            mediaDuration: r.mediaDuration,
            firedAt: fired,
            postedAt: posted,
            secondsToSpare: r.secondsToSpare
        )
    }

    private static func dayString(daysAgo: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)))
    }

    // MARK: Moments & phases

    func circle(_ id: UUID) -> GoldenCircle? { circles.first { $0.id == id } }

    /// Resolve the fire minute for a circle on a given day, honoring the
    /// scheduling mode (turns-mode pick > deterministic fallback).
    private func resolvedMinute(_ settings: GoldenHourSettings, day: String) -> Int {
        switch settings.mode {
        case .fixed:
            return settings.fireMinute
        case .surprise:
            return GoldenHourSchedule.surpriseMinute(circleId: settings.circleId, day: day)
        case .turns:
            if let pick = picks["\(settings.circleId.uuidString)#\(day)"] {
                return pick.fireMinute
            }
            return GoldenHourSchedule.surpriseMinute(circleId: settings.circleId, day: day)
        }
    }

    /// The moment for a circle on the day containing `reference`.
    private func moment(for settings: GoldenHourSettings, onDayOf reference: Date) -> GoldenHourMoment? {
        let tz = TimeZone(identifier: settings.timeZone) ?? .current
        let day = GoldenHourSchedule.dayKey(for: reference, timeZone: tz)
        let minute = resolvedMinute(settings, day: day)
        guard let fire = GoldenHourSchedule.fireDate(day: day, minute: minute, timeZone: tz) else { return nil }
        return GoldenHourMoment(circleId: settings.circleId, day: day, fireAt: fire)
    }

    /// The relevant moment for a circle right now: today's, unless
    /// yesterday's window is still draining (a near-midnight fire).
    /// Returns nil when Golden Hour is off for the circle.
    func currentMoment(for circleId: UUID, now: Date = Date()) -> GoldenHourMoment? {
        guard let settings = settingsByCircle[circleId], settings.enabled else { return nil }
        if let yesterday = moment(for: settings, onDayOf: now.addingTimeInterval(-86_400)),
           yesterday.phase(at: now) == .live || yesterday.phase(at: now) == .viewing {
            return yesterday
        }
        return moment(for: settings, onDayOf: now)
    }

    /// Today's turns-mode picker for a circle (nil for other modes).
    func todaysPicker(for circleId: UUID, now: Date = Date()) -> RemoteProfile? {
        guard let circle = circle(circleId), circle.settings.mode == .turns else { return nil }
        let tz = TimeZone(identifier: circle.settings.timeZone) ?? .current
        let day = GoldenHourSchedule.dayKey(for: now, timeZone: tz)
        let ids = circle.members.map(\.id).sorted()
        guard let index = GoldenHourSchedule.pickerIndex(day: day, timeZone: tz, memberCount: ids.count) else { return nil }
        return circle.profile(ids[index])
    }

    /// Whether today's pick has already been locked in (turns mode).
    func hasPickToday(for circleId: UUID, now: Date = Date()) -> Bool {
        guard let settings = settingsByCircle[circleId] else { return false }
        let tz = TimeZone(identifier: settings.timeZone) ?? .current
        let day = GoldenHourSchedule.dayKey(for: now, timeZone: tz)
        return picks["\(circleId.uuidString)#\(day)"] != nil
    }

    /// The single most urgent active moment across all circles — live
    /// beats viewing, earlier deadline beats later. Drives the orb.
    func mostUrgentActive(now: Date = Date()) -> (moment: GoldenHourMoment, phase: GoldenHourPhase)? {
        var live: [GoldenHourMoment] = []
        var viewing: [GoldenHourMoment] = []
        for circle in circles {
            guard let m = currentMoment(for: circle.id, now: now) else { continue }
            switch m.phase(at: now) {
            case .live: live.append(m)
            case .viewing: viewing.append(m)
            default: break
            }
        }
        if let m = live.min(by: { $0.captureClosesAt < $1.captureClosesAt }) { return (m, .live) }
        if let m = viewing.min(by: { $0.wallClosesAt < $1.wallClosesAt }) { return (m, .viewing) }
        return nil
    }

    // MARK: Posts (derived)

    func post(circleId: UUID, day: String, userId: String) -> GoldenHourPost? {
        posts.first { $0.circleId == circleId && $0.day == day && $0.userId == userId }
    }

    func posts(circleId: UUID, day: String) -> [GoldenHourPost] {
        posts.filter { $0.circleId == circleId && $0.day == day }
            .sorted { $0.postedAt < $1.postedAt }
    }

    /// (made, total) attendance for a circle's day.
    func attendance(circleId: UUID, day: String) -> (made: Int, total: Int) {
        let made = Set(posts(circleId: circleId, day: day).map(\.userId)).count
        let total = circle(circleId)?.members.count ?? made
        return (made, max(made, total))
    }

    /// Consecutive days (ending today or yesterday) the user made
    /// Golden Hour in this circle. Today only breaks the streak once
    /// its moment is fully over without a post.
    func streak(circleId: UUID, userId: String, now: Date = Date()) -> Int {
        guard let settings = settingsByCircle[circleId] else { return 0 }
        let tz = TimeZone(identifier: settings.timeZone) ?? .current
        let myDays = Set(posts.filter { $0.circleId == circleId && $0.userId == userId }.map(\.day))
        var count = 0
        var offset = 0
        let today = GoldenHourSchedule.dayKey(for: now, timeZone: tz)
        if !myDays.contains(today) {
            // Today is still in play (or pending) — start counting from yesterday.
            offset = 1
        }
        while true {
            let day = GoldenHourSchedule.dayKey(for: now.addingTimeInterval(TimeInterval(-offset * 86_400)), timeZone: tz)
            if myDays.contains(day) {
                count += 1
                offset += 1
            } else {
                break
            }
        }
        return count
    }

    // MARK: Settings writes

    /// Upsert a circle's Golden Hour configuration (owner/admin only —
    /// RLS enforces it). Re-anchors the schedule to the editor's timezone.
    func updateSettings(
        circleId: UUID,
        enabled: Bool,
        mode: GoldenHourMode,
        fireMinute: Int,
        myUserId: String
    ) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabase
                .from("golden_hour_settings")
                .upsert(GoldenSettingsUpsert(
                    circleId: circleId.uuidString,
                    enabled: enabled,
                    mode: mode.rawValue,
                    fireMinute: fireMinute,
                    timeZone: settingsByCircle[circleId]?.timeZone ?? TimeZone.current.identifier,
                    updatedBy: myUserId,
                    updatedAt: Self.isoString(Date())
                ), onConflict: "circle_id")
                .execute()
            await load(myUserId: myUserId)
            return true
        } catch {
            fail("Couldn't update Golden Hour for this circle.", error)
            return false
        }
    }

    /// Lock in today's secret time (turns mode, today's picker only).
    func submitPick(circleId: UUID, fireMinute: Int, myUserId: String) async -> Bool {
        guard let settings = settingsByCircle[circleId] else { return false }
        let tz = TimeZone(identifier: settings.timeZone) ?? .current
        let day = GoldenHourSchedule.dayKey(for: Date(), timeZone: tz)
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabase
                .from("golden_hour_picks")
                .upsert(GoldenPickUpsert(
                    circleId: circleId.uuidString,
                    day: day,
                    pickerId: myUserId,
                    fireMinute: fireMinute
                ), onConflict: "circle_id,day")
                .execute()
            picks["\(circleId.uuidString)#\(day)"] = GoldenHourPick(
                circleId: circleId, day: day, pickerId: myUserId, fireMinute: fireMinute
            )
            rescheduleFireNotifications()
            return true
        } catch {
            fail("Couldn't set today's time.", error)
            return false
        }
    }

    // MARK: Posting

    /// Upload a capture and write the post row. Refuses once the strict
    /// 5-minute window has closed — no late posts, client *and* server
    /// side (the row's fired_at anchors the sweep).
    func postCapture(
        circleId: UUID,
        data: Data,
        mediaKind: ProofMediaKind,
        durationSeconds: Double?,
        myUserId: String
    ) async -> Bool {
        let now = Date()
        guard let moment = currentMoment(for: circleId, now: now), moment.phase(at: now) == .live else {
            fail("The 5-minute window has closed.", URLError(.cancelled))
            return false
        }
        guard data.count <= VideoTranscoder.maxUploadBytes else {
            fail("That clip is too large to post. Try a shorter one.", StorageUploadError.badResponse(status: 413))
            return false
        }

        isWorking = true
        defer { isWorking = false }

        let ext = mediaKind == .video ? "mp4" : "jpg"
        let contentType = mediaKind == .video ? "video/mp4" : "image/jpeg"
        let path = "\(circleId.uuidString.lowercased())/\(moment.day)/\(myUserId)-\(UUID().uuidString).\(ext)"
        let secondsToSpare = max(0, Int(moment.captureClosesAt.timeIntervalSince(now)))

        do {
            uploadProgress = 0
            try await StorageUploadClient.upload(
                data: data,
                bucket: "golden-hour",
                path: path,
                contentType: contentType
            ) { [weak self] progress in
                Task { @MainActor in self?.uploadProgress = progress }
            }
            uploadProgress = nil

            ProofMediaCache.store(data, forMediaPath: path, kind: mediaKind)

            let created: GoldenPostRow = try await supabase
                .from("golden_hour_posts")
                .insert(GoldenPostInsert(
                    circleId: circleId.uuidString,
                    day: moment.day,
                    userId: myUserId,
                    mediaPath: path,
                    mediaKind: mediaKind.rawValue,
                    mediaDuration: durationSeconds,
                    firedAt: Self.isoString(moment.fireAt),
                    secondsToSpare: secondsToSpare
                ))
                .select("id, circle_id, day, user_id, media_path, media_kind, media_duration, fired_at, posted_at, seconds_to_spare")
                .single()
                .execute()
                .value

            if let post = Self.mapPost(created), !posts.contains(where: { $0.id == post.id }) {
                posts.append(post)
            }

            // "Maya made Golden Hour — 3:12 left" to everyone else.
            let remaining = GoldenHourSchedule.countdownString(until: moment.captureClosesAt, from: Date())
            if let circle = circle(circleId) {
                for member in circle.members where member.id != myUserId {
                    PushService.send(to: member.id, kind: .goldenPost, circleId: circleId.uuidString, preview: "\(remaining) left")
                }
            }

            scheduleClosingReminder(for: moment)
            return true
        } catch {
            uploadProgress = nil
            fail("Couldn't post your Golden Hour capture.", error)
            return false
        }
    }

    // MARK: Media

    /// A signed URL for a capture's private media (golden-hour bucket),
    /// cached per path for the session.
    func signedURL(forMediaPath path: String, expiresIn seconds: Int = 3600) async -> URL? {
        if let hit = signedURLCache[path], hit.expires > Date().addingTimeInterval(120) {
            return hit.url
        }
        do {
            let url = try await supabase.storage
                .from("golden-hour")
                .createSignedURL(path: path, expiresIn: seconds)
            signedURLCache[path] = (url, Date().addingTimeInterval(TimeInterval(seconds)))
            return url
        } catch {
            Log.goldenHour.error("Signed URL failed for \(path): \(error)")
            return nil
        }
    }

    /// Quietly warm caches for today's viewable walls so tiles render
    /// instantly when the user opens one.
    private func prefetchTodayMedia() {
        let now = Date()
        var targets: [(path: String, kind: ProofMediaKind)] = []
        for circle in circles {
            guard let m = currentMoment(for: circle.id, now: now),
                  m.phase(at: now) == .live || m.phase(at: now) == .viewing else { continue }
            for post in posts(circleId: circle.id, day: m.day) {
                if let path = post.mediaPath { targets.append((path, post.mediaKind)) }
            }
        }
        guard !targets.isEmpty else { return }
        Task { [weak self] in
            for target in targets {
                guard let self else { return }
                if ProofMediaCache.cachedFileURL(forMediaPath: target.path, kind: target.kind) != nil { continue }
                guard let url = await self.signedURL(forMediaPath: target.path) else { continue }
                await ProofMediaCache.download(from: url, forMediaPath: target.path, kind: target.kind)
            }
        }
    }

    // MARK: Local notifications

    /// (Re)schedule the synchronized fire alerts for the next three days
    /// across every enabled circle. Deterministic times mean every
    /// member's device schedules the exact same instants.
    func rescheduleFireNotifications() {
        struct Plan {
            let id: String
            let circleName: String
            let fireAt: Date
            let circleId: UUID
            /// A heads-up before the window opens, where one is honest.
            let headsUpAt: Date?
        }

        let plans: [Plan] = {
            var out: [Plan] = []
            let now = Date()
            for circle in circles where circle.settings.enabled {
                for dayOffset in 0..<3 {
                    let reference = now.addingTimeInterval(TimeInterval(dayOffset * 86_400))
                    guard let m = moment(for: circle.settings, onDayOf: reference), m.fireAt > now else { continue }
                    let headsUp = m.fireAt.addingTimeInterval(-Self.headsUpLead)
                    out.append(Plan(
                        id: "golden-fire-\(circle.id.uuidString)-\(m.day)",
                        circleName: circle.name,
                        fireAt: m.fireAt,
                        circleId: circle.id,
                        headsUpAt: Self.deservesHeadsUp(circle.settings) && headsUp > now ? headsUp : nil
                    ))
                }
            }
            return out
        }()

        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter {
                $0.hasPrefix("golden-fire-") || $0.hasPrefix("golden-soon-")
            }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = "Golden Hour — \(plan.circleName)"
                content.body = "5 minutes to show what you're working on. Everyone's being pinged right now."
                content.sound = .default
                content.userInfo = ["route": "golden", "circleId": plan.circleId.uuidString]
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: plan.fireAt
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
                do {
                    try await center.add(request)
                } catch {
                    Log.goldenHour.error("Failed to schedule fire alert: \(error)")
                }

                guard let headsUpAt = plan.headsUpAt else { continue }
                let soon = UNMutableNotificationContent()
                soon.title = "Golden Hour — \(plan.circleName)"
                soon.body = "In 10 minutes. The window is only five, so be somewhere you can show something."
                soon.sound = .default
                soon.userInfo = ["route": "golden", "circleId": plan.circleId.uuidString]
                let soonTrigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second],
                        from: headsUpAt
                    ),
                    repeats: false
                )
                do {
                    try await center.add(UNNotificationRequest(
                        identifier: "golden-soon-\(plan.circleId.uuidString)-\(plan.fireAt.timeIntervalSince1970)",
                        content: soon,
                        trigger: soonTrigger
                    ))
                } catch {
                    Log.goldenHour.error("Failed to schedule heads-up: \(error)")
                }
            }
        }
    }

    /// How long before the window opens the heads-up lands.
    static let headsUpLead: TimeInterval = 10 * 60

    /// Whether a circle's Golden Hour should be pre-announced.
    ///
    /// Only in `.fixed` mode. A five-minute window with one alert at the
    /// instant it opens is unforgiving — a phone in a pocket costs you
    /// the day — and where the circle has agreed on a time out loud, a
    /// heads-up gives nothing away.
    ///
    /// `.surprise` and `.turns` deliberately get none. Not knowing when
    /// it lands is the entire premise of those modes; a warning would
    /// announce the surprise ten minutes early and quietly convert them
    /// into `.fixed`. The fix for a missed surprise is a better alert,
    /// not a spoiled one.
    private static func deservesHeadsUp(_ settings: GoldenHourSettings) -> Bool {
        settings.mode == .fixed
    }

    /// "Golden Hour disappears in 10 minutes" — scheduled when the user
    /// posts, canceled the moment they open the wall.
    private func scheduleClosingReminder(for moment: GoldenHourMoment) {
        let reminderAt = moment.wallClosesAt.addingTimeInterval(-10 * 60)
        guard reminderAt > Date() else { return }
        let circleName = circle(moment.circleId)?.name ?? "your circle"
        let content = UNMutableNotificationContent()
        content.title = "Golden Hour — \(circleName)"
        content.body = "The wall disappears in 10 minutes."
        content.sound = .default
        content.userInfo = ["route": "golden", "circleId": moment.circleId.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, reminderAt.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "golden-close-\(moment.circleId.uuidString)-\(moment.day)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.goldenHour.error("Failed to schedule closing reminder: \(error)") }
        }
    }

    /// The user has seen the wall — the closing reminder is moot.
    func cancelClosingReminder(circleId: UUID, day: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["golden-close-\(circleId.uuidString)-\(day)"]
        )
    }

    // MARK: Sweep (real deletion)

    /// Ask the backend to actually delete expired media. Fire-and-forget,
    /// once per session plus whenever an expired wall is encountered.
    func sweepIfNeeded(force: Bool = false) {
        let now = Date()
        let hasExpiredMedia = posts.contains {
            $0.mediaPath != nil && now.timeIntervalSince($0.firedAt) > GoldenHourSchedule.viewingWindow + 5 * 60
        }
        guard force || (!didSweepThisSession && hasExpiredMedia) else { return }
        didSweepThisSession = true
        Task {
            do {
                let _: SweepResponse = try await supabase.functions.invoke("golden-hour-sweep")
                // Reflect the deletion locally without a full reload.
                let cutoff = Date().addingTimeInterval(-(GoldenHourSchedule.viewingWindow + 5 * 60))
                posts = posts.map { post in
                    guard post.mediaPath != nil, post.firedAt < cutoff else { return post }
                    return GoldenHourPost(
                        id: post.id, circleId: post.circleId, day: post.day, userId: post.userId,
                        mediaPath: nil, mediaKind: post.mediaKind, mediaDuration: post.mediaDuration,
                        firedAt: post.firedAt, postedAt: post.postedAt, secondsToSpare: post.secondsToSpare
                    )
                }
            } catch {
                Log.goldenHour.error("Sweep failed: \(error)")
            }
        }
    }

    // MARK: Realtime

    /// Live updates for posts and picks — a friend's capture pops onto
    /// the wall the moment it lands. Idempotent.
    func startRealtime(myUserId: String) {
        guard channel == nil else { return }
        let ch = supabase.channel("golden-hour-\(myUserId)")
        let tables = ["golden_hour_posts", "golden_hour_picks", "golden_hour_settings"]
        let streams = tables.map { ch.postgresChange(AnyAction.self, schema: "public", table: $0) }
        channel = ch
        realtimeTask = Task { [weak self] in
            await supabase.realtimeV2.setAuth()
            await ch.subscribe()
            await withTaskGroup(of: Void.self) { group in
                for stream in streams {
                    group.addTask { [weak self] in
                        for await _ in stream {
                            if Task.isCancelled { break }
                            await self?.load(myUserId: myUserId)
                        }
                    }
                }
            }
        }
    }

    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = channel {
            Task { await supabase.removeChannel(ch) }
        }
        channel = nil
    }

    func clear() {
        stopRealtime()
        circles = []
        settingsByCircle = [:]
        posts = []
        picks = [:]
        signedURLCache = [:]
    }

    // MARK: Helpers

    private func fetchProfiles(ids: [String]) async throws -> [String: RemoteProfile] {
        guard !ids.isEmpty else { return [:] }
        let rows: [RemoteProfile] = try await supabase
            .from("profiles")
            .select("id, name, username, avatar_url, header_url")
            .in("id", values: ids)
            .execute()
            .value
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func fail(_ message: String, _ error: Error) {
        Log.goldenHour.error("\(message) \(error)")
        errorMessage = message
        showError = true
    }
}
