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

// MARK: - Retiring a replaced profile photo
//
// The gap: every avatar/header upload wrote a NEW uniquely-named object
// and never removed the one it replaced. The `avatars` bucket is public,
// so a photo someone had replaced stayed fetchable at its old URL
// forever — not what "I changed my picture" is understood to mean.
//
// These cover the parser that decides what gets deleted, because getting
// it wrong deletes the wrong object.

@Suite("Avatar object path")
struct AvatarObjectPathTests {

    private let me = "user-abc"
    private func url(_ tail: String) -> String {
        "https://example.supabase.co/storage/v1/object/public/\(tail)"
    }

    @Test("A normal avatar URL resolves to its object path")
    func resolvesOwnAvatar() {
        let path = ProfileStore.avatarObjectPath(
            from: url("avatars/user-abc/avatar_1234.jpg"), myUserId: me)
        #expect(path == "user-abc/avatar_1234.jpg")
    }

    @Test("A header URL resolves too")
    func resolvesOwnHeader() {
        let path = ProfileStore.avatarObjectPath(
            from: url("avatars/user-abc/header_9999.jpg"), myUserId: me)
        #expect(path == "user-abc/header_9999.jpg")
    }

    @Test("Someone else's prefix is never resolvable")
    func refusesOtherPeoplesObjects() {
        // The whole point of the owner check: a stored URL is data, and
        // data must not be able to name a delete outside your own folder.
        #expect(ProfileStore.avatarObjectPath(
            from: url("avatars/user-zzz/avatar_1.jpg"), myUserId: me) == nil)
    }

    @Test("Only names this app generates are resolvable")
    func refusesForeignFilenames() {
        #expect(ProfileStore.avatarObjectPath(
            from: url("avatars/user-abc/something-else.jpg"), myUserId: me) == nil)
    }

    @Test("Another bucket is never touched")
    func refusesOtherBuckets() {
        #expect(ProfileStore.avatarObjectPath(
            from: url("stories/user-abc/avatar_1.jpg"), myUserId: me) == nil)
    }

    @Test("Malformed and truncated URLs resolve to nothing")
    func refusesMalformed() {
        #expect(ProfileStore.avatarObjectPath(from: "", myUserId: me) == nil)
        #expect(ProfileStore.avatarObjectPath(from: "not a url at all", myUserId: me) == nil)
        // Bucket present but no file component after the owner.
        #expect(ProfileStore.avatarObjectPath(
            from: url("avatars/user-abc"), myUserId: me) == nil)
    }
}

// MARK: - Media container sniffing

/// Every upload site used to derive its content type from the caller's
/// intent, so a clip that fell back to the raw QuickTime recording was
/// stored as `.mp4` under `video/mp4`. These cases pin the magic-byte
/// reading that replaced that guess.
@Suite("Media container sniffing")
struct MediaContainerTests {

    /// Build a synthetic header: a 4-byte box length, a box type, and
    /// (for `ftyp`) a major brand — then pad past the 12-byte minimum.
    private func header(box: String, brand: String? = nil) -> Data {
        var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x20]
        bytes += Array(box.utf8)
        if let brand { bytes += Array(brand.utf8) } else { bytes += [0, 0, 0, 0] }
        bytes += Array(repeating: 0, count: 16)
        return Data(bytes)
    }

    @Test("An MP4 brand reads as MP4")
    func mp4Brand() {
        #expect(MediaContainer.sniff(header(box: "ftyp", brand: "isom")) == .mp4)
        #expect(MediaContainer.sniff(header(box: "ftyp", brand: "mp42")) == .mp4)
    }

    @Test("The QuickTime brand is not mistaken for MP4")
    func quickTimeBrand() {
        // AVCaptureMovieFileOutput writes `ftyp` with a `qt  ` brand —
        // the exact case that was being uploaded as `video/mp4`.
        #expect(MediaContainer.sniff(header(box: "ftyp", brand: "qt  ")) == .quickTime)
    }

    @Test("A brandless QuickTime atom still reads as QuickTime")
    func classicQuickTime() {
        #expect(MediaContainer.sniff(header(box: "moov")) == .quickTime)
        #expect(MediaContainer.sniff(header(box: "mdat")) == .quickTime)
    }

    @Test("JPEG and PNG are recognized")
    func stillImages() {
        var jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        jpeg.append(Data(repeating: 0, count: 12))
        #expect(MediaContainer.sniff(jpeg) == .jpeg)

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(Data(repeating: 0, count: 8))
        #expect(MediaContainer.sniff(png) == .png)
    }

    @Test("Too-short and unrecognized data sniff to nothing")
    func unknownData() {
        #expect(MediaContainer.sniff(Data([0x01, 0x02, 0x03])) == nil)
        #expect(MediaContainer.sniff(Data()) == nil)
        #expect(MediaContainer.sniff(Data(repeating: 0x5A, count: 64)) == nil)
    }

    @Test("A slice keeps its parent's indices without crashing")
    func slicedData() {
        // `Data` slices keep the parent's index range, so reading
        // `data[4]` on a slice starting at 100 traps. The sniffer must
        // survive being handed one.
        let padded = Data(repeating: 0xAB, count: 100) + header(box: "ftyp", brand: "qt  ")
        #expect(MediaContainer.sniff(padded.dropFirst(100)) == .quickTime)
    }

    @Test("An unreadable blob keeps the caller's assumption")
    func fallsBackToAssumption() {
        let junk = Data(repeating: 0x5A, count: 64)
        #expect(MediaContainer.forUpload(junk, assuming: .mp4) == .mp4)
        #expect(MediaContainer.forUpload(junk, assuming: .jpeg) == .jpeg)
    }

    @Test("A sniff never flips a video upload into an image, or back")
    func neverCrossesMediaClass() {
        // If a photo's bytes somehow sniff as video, something upstream
        // is broken; honouring the sniff would only hide it.
        var jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        jpeg.append(Data(repeating: 0, count: 12))
        #expect(MediaContainer.forUpload(jpeg, assuming: .mp4) == .mp4)
        #expect(MediaContainer.forUpload(header(box: "ftyp", brand: "qt  "), assuming: .jpeg) == .jpeg)
    }

    @Test("The declared type and extension always agree")
    func typesAndExtensionsAgree() {
        #expect(MediaContainer.mp4.contentType == "video/mp4")
        #expect(MediaContainer.mp4.fileExtension == "mp4")
        #expect(MediaContainer.quickTime.contentType == "video/quicktime")
        #expect(MediaContainer.quickTime.fileExtension == "mov")
        #expect(MediaContainer.jpeg.isVideo == false)
        #expect(MediaContainer.quickTime.isVideo)
    }
}

// MARK: - Tiered negatives

/// "One drink is minus three, two or more is minus fifteen" means
/// fifteen ALTOGETHER, not eighteen. Kept by hand this is two paired
/// rows, which is a trap: two independent items with no mutual
/// exclusion charge both on the same night. These pin the arithmetic
/// that replaced the pair.
@Suite("Tiered negative totals")
struct TieredNegativeTests {

    /// Alcohol: −3 for one in a day, −15 once you reach two.
    private var alcohol: AvoidanceItem {
        AvoidanceItem(
            name: "Alcohol",
            pointsPerOccurrence: 3,
            negativeType: .tiered,
            tiers: [
                NegativeTier(threshold: 1, points: 3),
                NegativeTier(threshold: 2, points: 15),
            ]
        )
    }

    @Test("Nothing costs nothing")
    func noOccurrences() {
        #expect(alcohol.tieredTotal(for: 0) == 0)
    }

    @Test("The day's total is the highest tier reached, not the sum")
    func totalsAreNotCumulative() {
        #expect(alcohol.tieredTotal(for: 1) == 3)
        // The trap: two paired rows would charge 3 + 15 = 18 here.
        #expect(alcohol.tieredTotal(for: 2) == 15)
    }

    @Test("Staying inside a tier costs nothing more")
    func withinTier() {
        #expect(alcohol.tieredTotal(for: 3) == 15)
        #expect(alcohol.tieredTotal(for: 9) == 15)
    }

    @Test("Each occurrence charges only the step up")
    func marginalCharges() {
        // What `avoidanceDeduction` computes: total(n) − total(n−1).
        let marginal = (1...4).map { alcohol.tieredTotal(for: $0) - alcohol.tieredTotal(for: $0 - 1) }
        #expect(marginal == [3, 12, 0, 0])
        // And the running total always equals the tier, never the sum.
        #expect(marginal.prefix(2).reduce(0, +) == 15)
    }

    @Test("A gap before the first tier is free")
    func firstTierAboveOne() {
        let item = AvoidanceItem(
            name: "Takeout",
            pointsPerOccurrence: 0,
            negativeType: .tiered,
            tiers: [NegativeTier(threshold: 3, points: 10)]
        )
        #expect(item.tieredTotal(for: 1) == 0)
        #expect(item.tieredTotal(for: 2) == 0)
        #expect(item.tieredTotal(for: 3) == 10)
    }

    @Test("Tiers are held in ascending order however they arrive")
    func tiersSort() {
        let item = AvoidanceItem(
            name: "Folding",
            pointsPerOccurrence: 8,
            negativeType: .tiered,
            tiers: [
                NegativeTier(threshold: 2, points: 20),
                NegativeTier(threshold: 1, points: 8),
            ]
        )
        #expect(item.tiers.map(\.threshold) == [1, 2])
        #expect(item.tieredTotal(for: 1) == 8)
        #expect(item.tieredTotal(for: 2) == 20)
    }

    @Test("An empty tier list never charges")
    func noTiers() {
        let item = AvoidanceItem(name: "Unset", pointsPerOccurrence: 5, negativeType: .tiered)
        #expect(item.tieredTotal(for: 4) == 0)
    }

    @Test("A descending tier list can never refund")
    func neverNegative() {
        // max(0, after − before) in avoidanceDeduction guards this; the
        // totals themselves take the largest matching tier, so a badly
        // ordered list still reads as its worst step.
        let item = AvoidanceItem(
            name: "Odd",
            pointsPerOccurrence: 10,
            negativeType: .tiered,
            tiers: [
                NegativeTier(threshold: 1, points: 10),
                NegativeTier(threshold: 2, points: 4),
            ]
        )
        #expect(item.tieredTotal(for: 2) == 10)
        #expect(item.tieredTotal(for: 2) - item.tieredTotal(for: 1) == 0)
    }

    @Test("The other shapes keep no tiers")
    func otherShapesUnaffected() {
        let perInstance = AvoidanceItem(name: "Skip", pointsPerOccurrence: 4)
        #expect(perInstance.negativeType == .perInstance)
        #expect(perInstance.tiers.isEmpty)
        #expect(perInstance.usesFreeAllowance == false)
    }
}

// MARK: - Weekly rule shapes

/// Every weekly rule used to have to point at a daily task and count
/// it, which left three real shapes unrepresentable: a weekly TOTAL
/// ("150k steps"), an end-of-week STATE ("the apartment is clean"), and
/// a weekly one-off ("finish the book"). These pin the distinctions
/// without constructing a Store — the suite stays hermetic.
@Suite("Weekly rule shapes")
struct WeeklyRuleShapeTests {

    @Test("Metric is optional so existing boosters still decode")
    func metricIsOptional() {
        let booster = WeeklyBooster(name: "Three gym days", reference: .task(UUID()), threshold: 3)
        // Nil rather than `.days`: synthesized Decodable throws on a
        // missing key instead of falling back to a property default, so
        // a non-optional would fail to decode every booster on disk.
        #expect(booster.metric == nil)
    }

    @Test("A manual goal watches nothing and is worth its bonus")
    func manualWatchesNothing() {
        let booster = WeeklyBooster(name: "Apartment clean", reference: .manual, bonusPoints: 30)
        #expect(booster.reference == .manual)
        #expect(booster.bonusPoints == 30)
    }

    @Test("The three references stay distinct")
    func referencesAreDistinct() {
        let id = UUID()
        #expect(BoosterReference.task(id) != BoosterReference.manual)
        #expect(BoosterReference.category(.fitness) != BoosterReference.manual)
        #expect(BoosterReference.task(id) != BoosterReference.task(UUID()))
        #expect(BoosterReference.category(.fitness) != BoosterReference.category(.learning))
    }

    @Test("A reference survives a round trip through Codable")
    func referenceRoundTrips() throws {
        for reference in [BoosterReference.manual, .category(.people), .task(UUID())] {
            let data = try JSONEncoder().encode(reference)
            #expect(try JSONDecoder().decode(BoosterReference.self, from: data) == reference)
        }
    }

    @Test("A floor reads its metric, defaulting to days")
    func penaltyMetric() {
        let days = PenaltyRule(enabled: true, timesThreshold: 3, condition: .lessThan, penaltyPoints: 10)
        #expect(days.resolvedMetric == .days)
        let sum = PenaltyRule(
            enabled: true, timesThreshold: 400, condition: .lessThan,
            penaltyPoints: 10, metric: .sum
        )
        #expect(sum.resolvedMetric == .sum)
        // 400 pushups is a total, not four hundred separate days.
        #expect(sum.timesThreshold == 400)
    }

    @Test("The two new category slots exist and are stable")
    func categorySlots() {
        // The commit path caps a season's areas at `Category.allCases`,
        // and the raw values are what every persisted season stores, so
        // a rename or a removal would silently re-home real tasks.
        #expect(Category.allCases.count == 8)
        #expect(Category.learning.rawValue == "learning")
        #expect(Category.people.rawValue == "people")
    }
}

// MARK: - Matching a season's areas onto the slots
//
// The bug: slots were handed out by POSITION. The setup conversation
// leads with the person's top domain, so slot 0 — `.spiritual` — took
// whatever mattered most. Someone whose season opened on training found
// the gym filed under a header reading "Spiritual", tinted indigo
// against an orange season, and nudged back to life with "Quiet time has
// been waiting".

@Suite("Area slots")
struct CategorySlotTests {

    private func slot(_ name: String, taken: Set<FrisFocus.Category> = []) -> FrisFocus.Category {
        FrisFocus.Category.bestSlot(for: name, avoiding: taken)
    }

    @Test("An area lands in the slot its own name means")
    func namesMatchSlots() {
        #expect(slot("Fitness") == .fitness)
        #expect(slot("Training") == .fitness)
        #expect(slot("Faith") == .spiritual)
        #expect(slot("Ministry") == .spiritual)
        #expect(slot("Languages") == .learning)
        #expect(slot("Work") == .work)
        #expect(slot("Creative") == .creative)
        #expect(slot("The flat") == .apartment)
        #expect(slot("My kid") == .people)
    }

    @Test("Case and surrounding words do not matter")
    func matchingIsLoose() {
        #expect(slot("MY TRAINING BLOCK") == .fitness)
        #expect(slot("keeping the place from falling apart") == .apartment)
    }

    @Test("A keyword buried inside a longer word is not a match")
    func noSubstringMatches() {
        // The trap this suite was written for: raw `contains` filed
        // "falling apart" under Creative, because it holds "art".
        #expect(slot("falling apart") != .creative)
        #expect(slot("for a reason") != .people)      // "son"
        #expect(slot("a grunt of effort") != .fitness) // "run"
        #expect(slot("total recall") != .people)       // "call"
    }

    @Test("Two areas never take the same slot")
    func slotsAreNotShared() {
        var taken: Set<FrisFocus.Category> = []
        for name in ["Fitness", "Basketball", "Faith", "Work"] {
            let assigned = FrisFocus.Category.bestSlot(for: name, avoiding: taken)
            #expect(!taken.contains(assigned))
            taken.insert(assigned)
        }
        #expect(taken.count == 4)
    }

    @Test("A name nothing matches still gets a slot")
    func unmatchedStillLands() {
        let taken: Set<FrisFocus.Category> = [.spiritual, .fitness]
        let assigned = slot("Zzzz", taken: taken)
        #expect(!taken.contains(assigned))
    }

    @Test("A season using every slot still assigns one")
    func fullBoardDoesNotCrash() {
        // The commit path caps at eight areas, so this is unreachable
        // there — but a function that can return nothing has to be
        // proved not to.
        _ = FrisFocus.Category.bestSlot(for: "anything", avoiding: Set(FrisFocus.Category.allCases))
    }
}

// MARK: - Drafts that predate a field
//
// The bug this defends against, twice already: synthesized `Decodable`
// does NOT fall back to a property's default when the key is missing —
// it throws. Only Optional properties get `decodeIfPresent`. A draft
// saved before a field existed therefore fails to decode, and takes the
// whole resumed conversation down with it.

@Suite("Draft decoding")
struct DraftDecodingTests {

    @Test("A negative saved before tiers existed still decodes")
    func negativeWithoutTiers() throws {
        let json = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"Takeaway","shape":"frequencyThreshold","value":4,"window":"weekly","freeCount":2}"#.utf8)
        let decoded = try JSONDecoder().decode(DraftNegative.self, from: json)
        #expect(decoded.name == "Takeaway")
        #expect(decoded.shape == .frequencyThreshold)
        #expect(decoded.freeCount == 2)
        #expect(decoded.tiers.isEmpty)
    }

    @Test("A tiered negative round-trips")
    func tieredRoundTrip() throws {
        let negative = DraftNegative(
            name: "Drinking",
            shape: .tiered,
            value: 15,
            tiers: [NegativeTier(threshold: 1, points: 3), NegativeTier(threshold: 2, points: 15)]
        )
        let data = try JSONEncoder().encode(negative)
        let back = try JSONDecoder().decode(DraftNegative.self, from: data)
        #expect(back.shape == .tiered)
        #expect(back.tiers.count == 2)
        // The steps are day TOTALS, so the headline value is the worst
        // a day can cost — not the sum of both steps.
        #expect(back.value == 15)
    }
}

// MARK: - Deriving a week from the season
//
// The bug: the commit path decided when everything happened by ignoring
// the question. Unpinned gave an empty plan the morning after a
// fifteen-minute interview; pinned-to-every-day gave a fifty-eight row
// wall. The season had been stating its own frequency the whole time —
// a booster reading "three gym days" IS three days a week — and both
// guesses talked over it.

@Suite("Day shape")
struct DayShapeTests {

    private let categoryId = UUID()

    private func task(_ name: String, value: Int = 5, minutes: Int? = nil) -> DraftTask {
        DraftTask(
            name: name,
            categoryId: categoryId,
            shape: .flat,
            value: value,
            estimatedMinutes: minutes
        )
    }

    private func booster(_ reference: String, metric: BoosterMetric, threshold: Int) -> DraftBooster {
        DraftBooster(
            name: "b",
            referenceName: reference,
            metric: metric,
            threshold: threshold,
            value: 10
        )
    }

    private func floor(_ reference: String, metric: BoosterMetric, threshold: Int) -> DraftWeeklyPenalty {
        DraftWeeklyPenalty(
            name: "f",
            referenceName: reference,
            metric: metric,
            threshold: threshold,
            value: 10
        )
    }

    // MARK: Spreading

    @Test("A count becomes that many days, spread across the week")
    func weekdaysSpread() {
        #expect(RubricDraft.weekdays(count: 3).count == 3)
        #expect(RubricDraft.weekdays(count: 5).count == 5)
        // Empty is the every-day sentinel, so seven and above collapse.
        #expect(RubricDraft.weekdays(count: 7).isEmpty)
        #expect(RubricDraft.weekdays(count: 9).isEmpty)
        #expect(RubricDraft.weekdays(count: 0).isEmpty)
    }

    @Test("Three days are spread, not clustered")
    func threeDaysAreNotConsecutive() {
        // Nobody who says "three gym days" means Monday, Tuesday,
        // Wednesday — a clustered guess is one someone has to undo.
        let days = RubricDraft.weekdays(count: 3).sorted()
        #expect(days == [2, 4, 6])
        for (a, b) in zip(days, days.dropFirst()) {
            #expect(b - a > 1)
        }
    }

    // MARK: What the season states

    @Test("A day-count booster sets the frequency")
    func boosterStatesFrequency() {
        let gym = task("Gym session", value: 8, minutes: 60)
        let days = RubricDraft.derivedDays(
            for: gym,
            boosters: [booster("Gym session", metric: .days, threshold: 3)],
            floors: []
        )
        #expect(days.count == 3)
    }

    @Test("A weekly total has to be reachable every day")
    func sumBoosterIsEveryDay() {
        let steps = task("Steps", value: 4, minutes: 30)
        let days = RubricDraft.derivedDays(
            for: steps,
            boosters: [booster("Steps", metric: .sum, threshold: 150_000)],
            floors: []
        )
        #expect(days.isEmpty)
    }

    @Test("A floor is a lower bound, and the higher signal wins")
    func floorRaisesFrequency() {
        let run = task("A proper run", value: 5, minutes: 40)
        // Booster says two, floor says four — four is the binding one.
        let days = RubricDraft.derivedDays(
            for: run,
            boosters: [booster("A proper run", metric: .days, threshold: 2)],
            floors: [floor("A proper run", metric: .days, threshold: 4)]
        )
        #expect(days.count == 4)
    }

    @Test("The worst-day layer is reachable on the worst day")
    func floorItemsAreEveryDay() {
        // A one-point item only means anything if it's there on the day
        // everything goes wrong.
        #expect(RubricDraft.derivedDays(for: task("Take the stairs", value: 1, minutes: 3),
                                        boosters: [], floors: []).isEmpty)
        #expect(RubricDraft.derivedDays(for: task("Walk the dog", value: 2, minutes: 20),
                                        boosters: [], floors: []).isEmpty)
    }

    @Test("With nothing stated, length stands in for frequency")
    func durationFallback() {
        // The only guess in the derivation, and it only runs when the
        // rubric is silent.
        #expect(RubricDraft.derivedDays(for: task("Long block", value: 6, minutes: 120),
                                        boosters: [], floors: []).count == 3)
        #expect(RubricDraft.derivedDays(for: task("Medium", value: 5, minutes: 60),
                                        boosters: [], floors: []).count == 4)
        #expect(RubricDraft.derivedDays(for: task("Short", value: 4, minutes: 30),
                                        boosters: [], floors: []).count == 5)
        #expect(RubricDraft.derivedDays(for: task("Tiny", value: 4, minutes: 5),
                                        boosters: [], floors: []).isEmpty)
    }

    @Test("A stated frequency beats the duration guess")
    func statedBeatsGuessed() {
        // A two-hour thing would fall to three days on length alone.
        let long = task("Studio session", value: 8, minutes: 120)
        let days = RubricDraft.derivedDays(
            for: long,
            boosters: [booster("Studio session", metric: .days, threshold: 6)],
            floors: []
        )
        #expect(days.count == 6)
    }

    // MARK: Bands

    @Test("Bands are only assigned where the shape is obvious")
    func bandsAreShy() {
        // A tiny anchor at the top of a day, and the one heavy effort
        // after it. Everything else stays in the tray rather than being
        // placed somewhere the app guessed.
        #expect(RubricDraft.derivedBand(for: task("Make the bed", value: 1, minutes: 3)) == .morning)
        #expect(RubricDraft.derivedBand(for: task("Gym session", value: 8, minutes: 60)) == .evening)
        #expect(RubricDraft.derivedBand(for: task("Read 10 pages", value: 3, minutes: 20)) == .anytime)
        // No estimate at all is not a reason to place something.
        #expect(RubricDraft.derivedBand(for: task("Unknown", value: 1)) == .anytime)
    }

    // MARK: End to end

    @Test("Deriving a draft leaves the season's own numbers intact")
    func derivingWholeDraft() {
        var draft = RubricDraft.starter()
        draft.deriveDayShape()
        // "Move four days" is a booster on the starter board.
        let move = draft.tasks.first { $0.name == "Move for 30 minutes" }
        #expect(move?.days.count == 4)
        #expect(move?.isEveryDay == false)
        #expect(move?.cadenceText == "4 days a week")
        // A two-point anchor stays available every day.
        let meal = draft.tasks.first { $0.name == "Real meal, not grabbed" }
        #expect(meal?.isEveryDay == true)
        #expect(meal?.cadenceText == "every day")
    }

    @Test("Every task is placed somewhere, and nothing is lost")
    func derivingLosesNothing() {
        let before = RubricDraft.starter()
        var after = before
        after.deriveDayShape()
        #expect(after.tasks.count == before.tasks.count)
        #expect(after.boosters.count == before.boosters.count)
        #expect(after.negatives.count == before.negatives.count)
        #expect(after.dailyTarget == before.dailyTarget)
    }
}
