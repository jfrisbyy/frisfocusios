//
//  SocialSyncService+Events.swift
//  FrisFocus
//
//  Circle events, RSVPs, and check-ins — mirrored from Supabase into
//  the Store and written through on every local mutation, exactly like
//  circles and pacts. The server owns the rows; RLS scopes everything
//  to circle membership, so every member sees the same event, the same
//  RSVP tally, and the same "who's here" — true multi-person events.
//
//  Locally-created events follow the pending-create retry contract: a
//  refresh never drops an event the server hasn't confirmed yet — it
//  retries the write instead.
//

import Foundation
import Supabase

// MARK: - Wire rows

private nonisolated struct CircleEventRowS: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let seriesId: UUID
    let creatorId: String
    let title: String
    let details: String?
    let location: String?
    let startAt: String
    let endAt: String?
    let linkedCircleTaskId: UUID?
    let repeatFrequency: String
    let repeatWeekdays: [Int]
    let repeatEndDate: String?
    let repeatEndCount: Int?
    let reminderMinutes: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, details, location
        case circleId = "circle_id"
        case seriesId = "series_id"
        case creatorId = "creator_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case linkedCircleTaskId = "linked_circle_task_id"
        case repeatFrequency = "repeat_frequency"
        case repeatWeekdays = "repeat_weekdays"
        case repeatEndDate = "repeat_end_date"
        case repeatEndCount = "repeat_end_count"
        case reminderMinutes = "reminder_minutes"
        case createdAt = "created_at"
    }
}

private nonisolated struct EventRSVPRowS: Codable, Sendable {
    let id: UUID
    let eventId: UUID
    let userId: String
    let status: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case eventId = "event_id"
        case userId = "user_id"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct EventCheckInRowS: Codable, Sendable {
    let id: UUID
    let eventId: UUID
    let userId: String
    let at: String

    enum CodingKeys: String, CodingKey {
        case id, at
        case eventId = "event_id"
        case userId = "user_id"
    }
}

// MARK: - Write payloads

private nonisolated struct CircleEventUpsertS: Encodable, Sendable {
    let id: String
    let circleId: String
    let seriesId: String
    let creatorId: String
    let title: String
    let details: String?
    let location: String?
    let startAt: String
    let endAt: String?
    let linkedCircleTaskId: String?
    let repeatFrequency: String
    let repeatWeekdays: [Int]
    let repeatEndDate: String?
    let repeatEndCount: Int?
    let reminderMinutes: Int

    enum CodingKeys: String, CodingKey {
        case id, title, details, location
        case circleId = "circle_id"
        case seriesId = "series_id"
        case creatorId = "creator_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case linkedCircleTaskId = "linked_circle_task_id"
        case repeatFrequency = "repeat_frequency"
        case repeatWeekdays = "repeat_weekdays"
        case repeatEndDate = "repeat_end_date"
        case repeatEndCount = "repeat_end_count"
        case reminderMinutes = "reminder_minutes"
    }
}

private nonisolated struct EventRSVPUpsertS: Encodable, Sendable {
    let eventId: String
    let userId: String
    let status: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case eventId = "event_id"
        case userId = "user_id"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct EventCheckInInsertS: Encodable, Sendable {
    let id: String
    let eventId: String
    let userId: String
    let at: String

    enum CodingKeys: String, CodingKey {
        case id, at
        case eventId = "event_id"
        case userId = "user_id"
    }
}

// MARK: - Events sync

extension SocialSyncService {
    private static let eventSelect =
        "id, circle_id, series_id, creator_id, title, details, location, start_at, end_at, linked_circle_task_id, repeat_frequency, repeat_weekdays, repeat_end_date, repeat_end_count, reminder_minutes, created_at"

    /// Pull every event (RLS scopes to my circles) plus RSVPs and
    /// check-ins, and mirror them into the Store.
    func refreshEvents() async {
        guard let store, myUserId != nil else { return }
        do {
            let eventRows: [CircleEventRowS] = try await supabase
                .from("circle_events")
                .select(Self.eventSelect)
                .order("start_at", ascending: true)
                .limit(500)
                .execute()
                .value

            let eventIds = eventRows.map { $0.id.uuidString }
            var rsvpRows: [EventRSVPRowS] = []
            var checkInRows: [EventCheckInRowS] = []
            if !eventIds.isEmpty {
                async let r: [EventRSVPRowS] = supabase
                    .from("circle_event_rsvps")
                    .select("id, event_id, user_id, status, updated_at")
                    .in("event_id", values: eventIds)
                    .execute().value
                async let c: [EventCheckInRowS] = supabase
                    .from("circle_event_checkins")
                    .select("id, event_id, user_id, at")
                    .in("event_id", values: eventIds)
                    .execute().value
                (rsvpRows, checkInRows) = try await (r, c)
            }

            await ensureProfiles(
                remoteIds: eventRows.map { $0.creatorId }
                    + rsvpRows.map { $0.userId }
                    + checkInRows.map { $0.userId }
            )

            let mapped: [CircleEvent] = eventRows.map { row in
                CircleEvent(
                    id: row.id,
                    circleId: row.circleId,
                    seriesId: row.seriesId,
                    creatorId: localId(forRemote: row.creatorId),
                    title: row.title,
                    details: row.details,
                    location: row.location,
                    startAt: SyncDates.parse(row.startAt),
                    endAt: row.endAt.map { SyncDates.parse($0) },
                    linkedCircleTaskId: row.linkedCircleTaskId,
                    repeatRule: EventRepeat(
                        frequency: EventRepeatFrequency(rawValue: row.repeatFrequency) ?? .none,
                        weekdays: Set(row.repeatWeekdays),
                        endDate: row.repeatEndDate.map { SyncDates.parse($0) },
                        endAfterCount: row.repeatEndCount
                    ),
                    reminderMinutes: row.reminderMinutes,
                    createdAt: SyncDates.parse(row.createdAt)
                )
            }

            // Reconcile locally-created events with the server mirror:
            // confirmed ones clear their pending flag; unconfirmed ones
            // are kept and their up-sync retried — a created event must
            // never vanish on refresh.
            let mappedIds = Set(mapped.map(\.id))
            let pendingIds = store.pendingEventCreateIds
            for id in pendingIds where mappedIds.contains(id) {
                store.clearEventCreatePending(id)
            }
            let unsynced = store.circleEvents.filter {
                pendingIds.contains($0.id) && !mappedIds.contains($0.id)
            }
            for event in unsynced { eventCreated(event, myRSVP: nil, notifyMembers: false) }
            let unsyncedIds = Set(unsynced.map(\.id))

            // Cancel local reminders for events that no longer exist
            // (deleted by another member).
            let previousIds = Set(store.circleEvents.map(\.id))
            for id in previousIds.subtracting(mappedIds).subtracting(unsyncedIds) {
                store.cancelReminder(eventId: id)
            }

            store.circleEvents = mapped + unsynced
            store.eventRSVPs = rsvpRows.map { row in
                EventRSVP(
                    id: row.id,
                    eventId: row.eventId,
                    memberId: localId(forRemote: row.userId),
                    status: EventRSVPStatus(rawValue: row.status) ?? .going,
                    updatedAt: SyncDates.parse(row.updatedAt)
                )
            } + store.eventRSVPs.filter { unsyncedIds.contains($0.eventId) }
            store.eventCheckIns = checkInRows.map { row in
                EventCheckIn(
                    id: row.id,
                    eventId: row.eventId,
                    memberId: localId(forRemote: row.userId),
                    at: SyncDates.parse(row.at)
                )
            } + store.eventCheckIns.filter { unsyncedIds.contains($0.eventId) }
            store.persistAll()

            // Members who didn't create the event still get the local
            // pre-event reminder (the creator armed theirs at create).
            let now = Date()
            for event in store.circleEvents where event.startAt > now {
                store.scheduleReminder(for: event, now: now)
            }
        } catch {
            print("[SocialSync] events refresh failed: \(error)")
        }
    }

    /// Write a new (or retried) event through to Supabase, then the
    /// creator's own RSVP, then notify the other circle members.
    nonisolated func eventCreated(_ event: CircleEvent, myRSVP: EventRSVPStatus?, notifyMembers: Bool) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                let creatorRemote = self.remoteId(forLocal: event.creatorId) ?? myUserId
                var endDateISO: String?
                if let end = event.repeatRule.endDate { endDateISO = SyncDates.iso(end) }
                try await supabase.from("circle_events").upsert(CircleEventUpsertS(
                    id: event.id.uuidString,
                    circleId: event.circleId.uuidString,
                    seriesId: event.seriesId.uuidString,
                    creatorId: creatorRemote,
                    title: event.title,
                    details: event.details,
                    location: event.location,
                    startAt: SyncDates.iso(event.startAt),
                    endAt: event.endAt.map { SyncDates.iso($0) },
                    linkedCircleTaskId: event.linkedCircleTaskId?.uuidString,
                    repeatFrequency: event.repeatRule.frequency.rawValue,
                    repeatWeekdays: Array(event.repeatRule.weekdays).sorted(),
                    repeatEndDate: endDateISO,
                    repeatEndCount: event.repeatRule.endAfterCount,
                    reminderMinutes: event.reminderMinutes
                ), onConflict: "id").execute()

                if let myRSVP {
                    try await supabase.from("circle_event_rsvps").upsert(EventRSVPUpsertS(
                        eventId: event.id.uuidString,
                        userId: myUserId,
                        status: myRSVP.rawValue,
                        updatedAt: SyncDates.iso(Date())
                    ), onConflict: "event_id,user_id").execute()
                }

                self.store?.clearEventCreatePending(event.id)

                if notifyMembers, let circle = self.store?.circle(by: event.circleId) {
                    for member in circle.memberIds where member != self.store?.currentUserId {
                        if let remote = self.remoteId(forLocal: member) {
                            PushService.send(
                                to: remote,
                                kind: .circleEvent,
                                circleId: event.circleId.uuidString,
                                preview: event.title
                            )
                        }
                    }
                }
            } catch {
                print("[SocialSync] event create failed (will retry on next refresh): \(error)")
            }
        }
    }

    /// Remove an event server-side; cascades take the RSVPs and
    /// check-ins with it.
    nonisolated func eventDeleted(_ eventId: UUID) {
        Task { @MainActor in
            do {
                try await supabase.from("circle_events")
                    .delete()
                    .eq("id", value: eventId.uuidString)
                    .execute()
            } catch {
                print("[SocialSync] event delete failed: \(error)")
            }
        }
    }

    /// Up-sync the signed-in user's RSVP — upsert on answer, delete on
    /// a cleared (toggled-off) answer.
    nonisolated func eventRSVPChanged(eventId: UUID, status: EventRSVPStatus?) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                if let status {
                    try await supabase.from("circle_event_rsvps").upsert(EventRSVPUpsertS(
                        eventId: eventId.uuidString,
                        userId: myUserId,
                        status: status.rawValue,
                        updatedAt: SyncDates.iso(Date())
                    ), onConflict: "event_id,user_id").execute()
                } else {
                    try await supabase.from("circle_event_rsvps")
                        .delete()
                        .eq("event_id", value: eventId.uuidString)
                        .eq("user_id", value: myUserId)
                        .execute()
                }
            } catch {
                print("[SocialSync] event RSVP sync failed: \(error)")
            }
        }
    }

    /// Stamp the signed-in user present at an event for everyone.
    nonisolated func eventCheckedIn(_ checkIn: EventCheckIn) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                try await supabase.from("circle_event_checkins").upsert(EventCheckInInsertS(
                    id: checkIn.id.uuidString,
                    eventId: checkIn.eventId.uuidString,
                    userId: myUserId,
                    at: SyncDates.iso(checkIn.at)
                ), onConflict: "id").execute()
            } catch {
                print("[SocialSync] event check-in sync failed: \(error)")
            }
        }
    }
}
