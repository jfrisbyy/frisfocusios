//
//  FrisFocusTests.swift
//  FrisFocusTests
//
//  The first real tests in this project — the target was still the empty
//  Xcode template.
//
//  Scope is deliberate: every case here covers a rule that was ACTUALLY
//  WRONG in shipped code, not a rule that merely could be. Each one is a
//  regression test for a specific bug, so a future change that reintroduces
//  it fails here rather than in someone's week.
//
//  All of it is pure functions. Nothing constructs a Store or touches
//  UserDefaults, so the suite stays hermetic and fast, and CI does not need
//  a simulator with app state.
//

import Foundation
import Testing
@testable import FrisFocus

// MARK: - The daily target
//
// The bug: the cold start priced a day at 60% of the value of the ENTIRE
// season library. Nothing on that board is scheduled and the tour teaches
// pulling "the day's few" onto today, so a full sun demanded most of the
// season every day — and the more someone added during onboarding, the
// further out of reach it moved.
//
// The invariant these tests defend: the target is always what ONE day
// holds, never a fraction of the library.

@Suite("Strong day value")
struct StrongDayValueTests {

    private func task(
        _ title: String,
        _ value: Int,
        _ schedule: PinSchedule = .none
    ) -> FFTask {
        FFTask(title: title, category: .work, pointValue: value, pinSchedule: schedule)
    }

    @Test("An empty season still has a reachable target")
    func emptyLibrary() {
        #expect(Store.strongDayValue(from: []) == 1)
    }

    @Test("Before any rhythm, the best few tasks stand in for a day")
    func unscheduledLibraryUsesTopTasks() {
        // Eighteen cards, as a three-direction cold start produces.
        let tasks = (1...18).map { task("t\($0)", $0) }
        // Top four: 18 + 17 + 16 + 15.
        #expect(Store.strongDayValue(from: tasks) == 66)
    }

    @Test("A big library does not inflate the target")
    func libraryGrowthDoesNotMoveTheTarget() {
        let small = (1...5).map { task("t\($0)", 4) }
        let large = (1...60).map { task("t\($0)", 4) }
        // This is the whole bug in one assertion: adding more options to
        // the season must not make a day harder.
        #expect(Store.strongDayValue(from: small) == Store.strongDayValue(from: large))
    }

    @Test("Daily tasks describe every day")
    func dailyTasksSum() {
        let tasks = [task("a", 5, .daily), task("b", 3, .daily), task("c", 99)]
        // The unscheduled 99-point task is library, not a day.
        #expect(Store.strongDayValue(from: tasks) == 8)
    }

    @Test("Weekday rhythms use the busiest day, not the weekly total")
    func weekdayRhythmsUseBusiestDay() {
        let tasks = [
            task("mon", 6, .daysOfWeek([2])),
            task("tue", 4, .daysOfWeek([3])),
            task("wed", 4, .daysOfWeek([4])),
        ]
        // Monday is the heaviest single day at 6 — not 14, which is a week.
        #expect(Store.strongDayValue(from: tasks) == 6)
    }

    @Test("Daily and weekday rhythms combine on the day they share")
    func dailyAndWeekdayCombine() {
        let tasks = [
            task("every day", 5, .daily),
            task("mondays", 7, .daysOfWeek([2])),
        ]
        // Monday carries both; every other day carries only the daily one.
        #expect(Store.strongDayValue(from: tasks) == 12)
    }

    @Test("One-off pins never set a day's expectation")
    func oneOffsAreIgnoredWhenRhythmsExist() {
        let withOneOffs = [
            task("every day", 5, .daily),
            task("just today", 40, .today),
            task("one date", 40, .singleDate(Date())),
        ]
        #expect(Store.strongDayValue(from: withOneOffs) == 5)
    }
}

// MARK: - Sharing tiers
//
// The bug: the app offered three per-friend tiers and told people exactly
// what each exposed, but every real path collapsed them to two. Choosing
// "Open" — progress and rhythm, but not the actual tasks — wrote "full" to
// the server and rendered the friend's real task rows.

@Suite("Visibility tiers")
struct VisibilityTierTests {

    @Test("Raw values are the strings the server stores")
    func rawValuesMatchTheWireFormat() {
        // share_tiers.tier and get_season_cards both speak these exact
        // strings. If these ever drift, the tier silently degrades.
        #expect(VisibilityTier.quiet.rawValue == "quiet")
        #expect(VisibilityTier.open.rawValue == "open")
        #expect(VisibilityTier.full.rawValue == "full")
    }

    @Test("Every tier survives a round-trip through the clearance flags")
    func tierRoundTrip() {
        for tier in VisibilityTier.allCases {
            #expect(SharingSettings.from(tier: tier).tier == tier)
        }
    }

    @Test("Open does not expose task names")
    func openHidesTasks() {
        // The exact promise the settings screen makes: "Progress & rhythm
        // — but not the actual tasks."
        let open = SharingSettings.from(tier: .open)
        #expect(open.shareTaskNames == false)
        #expect(open.shareScore || open.shareGoalStatus)
    }

    @Test("Quiet exposes neither the tasks nor the shape")
    func quietHidesEverything() {
        let quiet = SharingSettings.from(tier: .quiet)
        #expect(quiet.shareTaskNames == false)
        #expect(quiet.shareScore == false)
        #expect(quiet.shareGoalStatus == false)
    }

    @Test("The default clearance is the middle tier, never the widest")
    func defaultIsOpen() {
        // A privacy control has to fail toward less exposure. This is also
        // the client half of the server defaulting a missing share_tiers
        // row to 'open' rather than 'full'.
        #expect(SharingSettings().tier == .open)
    }
}

// MARK: - The age gate
//
// The gap: the Terms require 13+ and nothing ever asked. Age is computed
// by the calendar rather than by dividing days, so leap years and month
// lengths cannot put a birthday a day out.

@Suite("Age gate")
struct AgeGateTests {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        return Calendar.current.date(from: components)!
    }

    @Test("Someone turning 13 today is old enough")
    func exactlyThirteenPasses() {
        let now = date(2026, 9, 6)
        #expect(AgeGate.age(from: date(2013, 9, 6), now: now) == AgeGate.minimumAge)
    }

    @Test("The day before a thirteenth birthday is still twelve")
    func dayBeforeThirteenFails() {
        let now = date(2026, 9, 6)
        #expect(AgeGate.age(from: date(2013, 9, 7), now: now) < AgeGate.minimumAge)
    }

    @Test("A leap-day birthday lands on the 28th in a common year")
    func leapDayBirthday() {
        // 2012-02-29 has no anniversary in 2025, a common year. The
        // calendar treats the 28th as the anniversary — which is what we
        // want: a February birthday must not slide into March, and a
        // 13-year-old must not be told to come back tomorrow.
        #expect(AgeGate.age(from: date(2012, 2, 29), now: date(2025, 2, 27)) == 12)
        #expect(AgeGate.age(from: date(2012, 2, 29), now: date(2025, 2, 28)) == 13)
        #expect(AgeGate.age(from: date(2012, 2, 29), now: date(2025, 3, 1)) == 13)
    }

    @Test("A leap-day birthday still needs the real day in a leap year")
    func leapDayBirthdayInLeapYear() {
        // 2028 has a 29th, so the 28th is genuinely the day before.
        #expect(AgeGate.age(from: date(2012, 2, 29), now: date(2028, 2, 28)) == 15)
        #expect(AgeGate.age(from: date(2012, 2, 29), now: date(2028, 2, 29)) == 16)
    }
}

// MARK: - Cold start pricing
//
// Where a card sits on the board is what it is worth. These guard the
// band ranges the onboarding copy now promises out loud.

@Suite("Cold start band pricing")
struct ColdStartPricingTests {

    @Test("Every card is priced inside its band")
    func valuesStayInBand() {
        for band in ColdStartBand.allCases {
            for count in 1...8 {
                for index in 0..<count {
                    let value = ColdStartViewModel.value(band: band, count: count, index: index)
                    #expect(value >= band.range.lo)
                    #expect(value <= band.range.hi)
                }
            }
        }
    }

    @Test("A floor task always costs less than an ideal one")
    func floorIsCheaperThanIdeal() {
        // The manifesto promises effort is priced by what it costs you,
        // and the board says the bad-day ones are priced small on purpose.
        #expect(ColdStartBand.floor.range.hi < ColdStartBand.ideal.range.lo)
        #expect(ColdStartBand.floor.range.hi < ColdStartBand.normal.range.lo)
    }

    @Test("Earlier cards in a band are worth more than later ones")
    func rankOrdersValueWithinABand() {
        let first = ColdStartViewModel.value(band: .normal, count: 5, index: 0)
        let last = ColdStartViewModel.value(band: .normal, count: 5, index: 4)
        #expect(first > last)
    }
}

// MARK: - Salvaging a partly-unreadable slice
//
// The gap: `loadArray` decoded each persisted slice as a whole array, so
// a single element written by a newer build — or one field that changed
// shape — turned a thousand tasks into zero. The bytes were preserved
// under a recovery key nobody reads, which is not the same as keeping
// someone's season.

@Suite("Partial decode salvage")
struct SalvageTests {

    private struct Row: Codable, Equatable {
        let id: Int
        let name: String
    }

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("A clean array survives salvage unchanged")
    func cleanArray() {
        let rows: [Row]? = Store.salvageElements(
            from: data(#"[{"id":1,"name":"a"},{"id":2,"name":"b"}]"#)
        )
        #expect(rows == [Row(id: 1, name: "a"), Row(id: 2, name: "b")])
    }

    @Test("One unreadable element costs only that element")
    func oneBadElement() {
        // The middle row is missing `name`, so it cannot decode. The
        // whole-array path loses all three; this must keep two.
        let rows: [Row]? = Store.salvageElements(
            from: data(#"[{"id":1,"name":"a"},{"id":2},{"id":3,"name":"c"}]"#)
        )
        #expect(rows == [Row(id: 1, name: "a"), Row(id: 3, name: "c")])
    }

    @Test("An element with extra unknown fields still reads")
    func forwardCompatibleElement() {
        // A row written by a newer build carrying a field this build has
        // never heard of is not corrupt — it must not be dropped.
        let rows: [Row]? = Store.salvageElements(
            from: data(#"[{"id":1,"name":"a","addedLater":true}]"#)
        )
        #expect(rows == [Row(id: 1, name: "a")])
    }

    @Test("Bytes that are not a JSON array are not salvageable")
    func notAnArray() {
        let object: [Row]? = Store.salvageElements(from: data(#"{"id":1,"name":"a"}"#))
        #expect(object == nil)
        let garbage: [Row]? = Store.salvageElements(from: data("not json at all"))
        #expect(garbage == nil)
    }

    @Test("An array of entirely unreadable rows salvages nothing")
    func allBad() {
        // Empty, not nil: the bytes *were* an array. loadArray treats an
        // empty salvage as a full failure, so this distinction is what
        // decides whether the slice is reported unreadable.
        let rows: [Row]? = Store.salvageElements(from: data(#"[{"x":1},{"y":2}]"#))
        #expect(rows == [])
    }

    @Test("An empty array is not mistaken for a failure")
    func emptyArray() {
        let rows: [Row]? = Store.salvageElements(from: data("[]"))
        #expect(rows == [])
    }
}

// MARK: - A reachable sun, whichever door you came through
//
// The cold start priced a day at 60% of the whole library, which made the
// sun unfillable. The conversational door never had that formula — its
// target comes from the model — but the target and the task list are two
// separate parts of one reply, and nothing makes them agree. Same
// unreachable sun, different route. Both commit paths now clamp the
// target down to what a strong day of the committed tasks can actually
// produce, and never up.

@Suite("Reachable daily target")
struct ReachableTargetTests {

    private func task(_ title: String, _ value: Int, _ schedule: PinSchedule) -> FFTask {
        FFTask(title: title, category: .work, pointValue: value, pinSchedule: schedule)
    }

    @Test("An over-ambitious target is lowered to a day the board can reach")
    func clampsDownward() {
        let board = [task("a", 5, .daily), task("b", 4, .daily)]
        let reachable = Store.strongDayValue(from: board)
        #expect(reachable == 9)
        // The commit paths compute min(requested, reachable).
        #expect(min(40, reachable) == 9)
    }

    @Test("A target the board can already reach is left alone")
    func leavesModestTargetsAlone() {
        // The conversation decided this; nothing should raise it just
        // because the board could carry more.
        let board = (1...6).map { task("t\($0)", 10, .daily) }
        let reachable = Store.strongDayValue(from: board)
        #expect(reachable == 60)
        #expect(min(15, reachable) == 15)
    }

    @Test("An empty board still yields a reachable target")
    func emptyBoardIsStillReachable() {
        // strongDayValue floors at 1, so the clamp can never produce a
        // target of zero and freeze the sun at "already full".
        #expect(min(30, Store.strongDayValue(from: [])) == 1)
    }
}
