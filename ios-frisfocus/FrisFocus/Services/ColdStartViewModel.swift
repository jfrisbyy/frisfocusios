//
//  ColdStartViewModel.swift
//  FrisFocus
//
//  Drives the 60-second cold start: which directions the person picked,
//  the working task set for each direction (which band each card sits in,
//  and its rank inside that band), and the final de-duplicated, priced
//  board handed to the Store.
//
//  Placement is the whole interaction: dragging a card into a band means
//  both "this is on my board" AND "this is what it costs me". Cards left
//  in the tray are not on the board. Values are derived from band + rank,
//  never shown — the sun carries them. Pure local state; the tile path
//  never touches the network.
//

import Foundation
import SwiftUI

/// The three effort bands a card can land in. Order matters: floor is the
/// cheapest ("even on a bad day"), ideal the most demanding.
enum ColdStartBand: String, CaseIterable, Equatable, Hashable {
    case floor
    case normal
    case ideal

    var title: String {
        switch self {
        case .floor:  return "Even on a bad day"
        case .normal: return "A normal day"
        case .ideal:  return "An ideal day"
        }
    }

    /// Value range for cards in this band. Top of a band takes the most
    /// out of you and earns the high end.
    var range: (lo: Int, hi: Int) {
        switch self {
        case .floor:  return (1, 2)
        case .normal: return (3, 5)
        case .ideal:  return (6, 10)
        }
    }

    /// Weight-rail brightness (floor lightest → ideal heaviest). No numbers.
    var railWeight: Double {
        switch self {
        case .floor:  return 0.28
        case .normal: return 0.6
        case .ideal:  return 1.0
        }
    }
}

/// One task in the final board committed to the Store, fully priced.
struct ColdStartFinalTask: Equatable {
    let label: String
    let blurb: String
    let lifeArea: LibraryLifeArea
    let band: ColdStartBand
    let bandRank: Int
    let value: Int
    let isCustom: Bool
    let subDirection: String?
}

@Observable
final class ColdStartViewModel {
    /// A working card inside a direction. `band == nil` means it's still
    /// in the tray (not on the board). Identity is stable so drag / reflow
    /// animate cleanly.
    struct Item: Identifiable, Equatable, Hashable {
        let id: String
        var label: String
        var blurb: String
        var lifeArea: LibraryLifeArea
        var band: ColdStartBand?
        var isCustom: Bool
        var subDirection: String?
    }

    /// One chosen direction = one board page on Screen 2.
    struct Direction: Identifiable, Equatable {
        let id: String
        /// nil for a free-text general fallback direction.
        let area: StarterFocusArea?
        let title: String
        let tint: Color
        var items: [Item]
        /// Sub-direction chips picked on this page.
        var selectedSubs: Set<String>

        var symbol: String { area?.symbol ?? "sparkles" }
    }

    // MARK: Selection (Screen 1)

    /// Focus-area ids chosen, in tap order.
    var selectedAreaIds: [String] = []
    /// Genuinely unmapped free-text intents → each becomes a general
    /// fallback direction.
    var customIntents: [String] = []

    // MARK: Board (Screen 2)

    var directions: [Direction] = []
    var index: Int = 0
    /// Direction ids that already got the one-time "anything on a rough
    /// day?" nudge, so it never repeats.
    var floorAskedDirectionIds: Set<String> = []

    // MARK: Capstone (Screen A) — free-written milestones (north stars)

    /// The person's own words for what would make this season a win.
    /// Never pre-filled from a library. Each becomes a north-star
    /// milestone at a hidden default value on commit.
    var milestones: [String] = []

    // MARK: Season frame (Screen B)

    /// The season's name. Empty defaults to "Season One" on commit.
    var seasonName: String = ""
    /// How the season ends. Open-ended is the calm default.
    var seasonEndMode: SeasonEndMode = .openEnded
    /// The chosen end date when `seasonEndMode == .date`. Never silently
    /// rounded — it's exactly the date the person picked.
    var seasonEndDate: Date = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()

    /// True once the person has named at least one milestone — gates the
    /// "when my milestones land" end option.
    var hasMilestones: Bool { !cleanedMilestones.isEmpty }

    /// Trimmed, non-empty milestone lines in entry order.
    var cleanedMilestones: [String] {
        milestones
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The final season name, defaulting to "Season One" when left blank.
    var resolvedSeasonName: String {
        let trimmed = seasonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Season One" : trimmed
    }

    // MARK: Ghost copy (locally flavored, zero LLM)

    /// Rotating placeholder milestones that teach the SHAPE, flavored by
    /// the chosen directions. Never inserted as real content.
    var milestoneGhostExamples: [String] {
        var out: [String] = []
        for id in selectedAreaIds {
            switch id {
            case "fitness", "health": out += ["reach 180…", "run the 10K…", "deadlift 300…"]
            case "work", "career", "business": out += ["launch it…", "land the client…", "ship the app…"]
            case "school", "study": out += ["finish the certification…", "ace the finals…"]
            case "faith", "spiritual": out += ["read it cover to cover…"]
            case "money", "finance": out += ["clear the debt…", "save the first $5k…"]
            case "creative", "art": out += ["finish the record…", "fill the sketchbook…"]
            default: break
            }
        }
        if out.isEmpty {
            out = ["finish the certification…", "run the 10K…", "reach 180…", "launch it…"]
        }
        return out
    }

    /// Rotating placeholder season names, locally flavored.
    var seasonNameGhostExamples: [String] {
        var out: [String] = ["Season One"]
        for id in selectedAreaIds {
            switch id {
            case "fitness", "health": out += ["The Comeback", "Summer of Discipline"]
            case "work", "career", "business": out += ["Build Mode", "The Founder Sprint"]
            case "school", "study": out += ["Lock In", "Finals Season"]
            case "creative", "art": out += ["The Making", "Studio Season"]
            default: break
            }
        }
        if out.count == 1 { out += ["The Comeback", "Build Mode", "Summer of Discipline"] }
        return out
    }

    var selectionCount: Int { selectedAreaIds.count + customIntents.count }
    var canContinue: Bool { selectionCount > 0 }

    func isSelected(_ areaId: String) -> Bool { selectedAreaIds.contains(areaId) }

    func toggleArea(_ areaId: String) {
        if let i = selectedAreaIds.firstIndex(of: areaId) {
            selectedAreaIds.remove(at: i)
        } else {
            selectedAreaIds.append(areaId)
        }
    }

    /// Route free text locally. Returns true if it mapped to / selected
    /// an area; false means it became a general fallback direction.
    @discardableResult
    func submitFreeText(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let areaId = StarterLibrary.route(freeText: trimmed) {
            if !selectedAreaIds.contains(areaId) { selectedAreaIds.append(areaId) }
            return true
        }
        if !customIntents.contains(trimmed) { customIntents.append(trimmed) }
        return false
    }

    /// Build the per-direction working sets from the selection. Every
    /// library task starts UNPLACED in the tray — placement is the user's.
    func build() {
        var dirs: [Direction] = []
        for areaId in selectedAreaIds {
            guard let area = StarterLibrary.focusArea(areaId) else { continue }
            let items = StarterLibrary.tier1(for: areaId).map {
                Item(id: $0.id, label: $0.label, blurb: $0.blurb, lifeArea: $0.lifeArea, band: nil, isCustom: false, subDirection: nil)
            }
            dirs.append(Direction(id: areaId, area: area, title: area.title, tint: area.tint, items: items, selectedSubs: []))
        }
        for intent in customIntents {
            let items = StarterLibrary.generalBoard().map {
                Item(id: "\(intent)-\($0.id)", label: $0.label, blurb: $0.blurb, lifeArea: $0.lifeArea, band: nil, isCustom: false, subDirection: nil)
            }
            dirs.append(Direction(id: "custom-\(intent)", area: nil, title: intent.capitalized, tint: Theme.sunOuter, items: items, selectedSubs: []))
        }
        directions = dirs
        index = 0
    }

    // MARK: Current-direction access

    var current: Direction? {
        guard directions.indices.contains(index) else { return nil }
        return directions[index]
    }

    var isLastDirection: Bool { index >= directions.count - 1 }

    /// Cards still waiting in the tray for the current direction.
    var trayItems: [Item] {
        current?.items.filter { $0.band == nil } ?? []
    }

    /// Cards placed into a band, top-first (rank order).
    func items(in band: ColdStartBand) -> [Item] {
        current?.items.filter { $0.band == band } ?? []
    }

    /// How many cards are on the board (placed in any band) right now.
    var placedCountCurrent: Int {
        current?.items.filter { $0.band != nil }.count ?? 0
    }

    /// True when the floor band has no cards — used for the one gentle ask.
    var floorEmptyCurrent: Bool {
        items(in: .floor).isEmpty
    }

    func shouldAskAboutFloor() -> Bool {
        guard let id = current?.id else { return false }
        return floorEmptyCurrent && placedCountCurrent > 0 && !floorAskedDirectionIds.contains(id)
    }

    func markFloorAsked() {
        if let id = current?.id { floorAskedDirectionIds.insert(id) }
    }

    // MARK: Placement (the core gesture)

    /// Move a card into `band` (nil = back to the tray). When `beforeId`
    /// is given the card lands directly above that card (reorder / insert);
    /// otherwise it appends to the end of the destination.
    func place(_ itemId: String, into band: ColdStartBand?, before beforeId: String? = nil) {
        guard directions.indices.contains(index),
              let from = directions[index].items.firstIndex(where: { $0.id == itemId }) else { return }
        var item = directions[index].items.remove(at: from)
        item.band = band
        if let beforeId,
           beforeId != itemId,
           let target = directions[index].items.firstIndex(where: { $0.id == beforeId }) {
            directions[index].items.insert(item, at: target)
        } else {
            directions[index].items.append(item)
        }
    }

    // MARK: Sub-direction chips

    func isSubSelected(_ sub: String) -> Bool {
        current?.selectedSubs.contains(sub) ?? false
    }

    var availableSubDirections: [String] {
        guard let areaId = current?.area?.id else { return [] }
        return StarterLibrary.subDirections(for: areaId)
    }

    /// Toggle a sub-direction chip. Selecting unions its drills into the
    /// tray (de-duped by label); deselecting removes only its still-unplaced
    /// drills, never anything the user already banded.
    func toggleSub(_ sub: String) {
        guard directions.indices.contains(index),
              let areaId = directions[index].area?.id else { return }
        if directions[index].selectedSubs.contains(sub) {
            directions[index].selectedSubs.remove(sub)
            directions[index].items.removeAll {
                $0.subDirection == sub && $0.band == nil && !$0.isCustom
            }
        } else {
            directions[index].selectedSubs.insert(sub)
            let drills = StarterLibrary.tasks(for: areaId, subDirection: sub)
            for task in drills where !directions[index].items.contains(where: {
                $0.id == task.id || $0.label.lowercased() == task.label.lowercased()
            }) {
                directions[index].items.append(
                    Item(id: task.id, label: task.label, blurb: task.blurb, lifeArea: task.lifeArea, band: nil, isCustom: false, subDirection: sub)
                )
            }
        }
    }

    // MARK: Item mutations

    func remove(itemId: String) {
        guard directions.indices.contains(index) else { return }
        directions[index].items.removeAll { $0.id == itemId }
    }

    func update(itemId: String, label: String, blurb: String, lifeArea: LibraryLifeArea) {
        guard directions.indices.contains(index),
              let i = directions[index].items.firstIndex(where: { $0.id == itemId }) else { return }
        directions[index].items[i].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        directions[index].items[i].blurb = blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        directions[index].items[i].lifeArea = lifeArea
    }

    /// Add a user's own task. Lands in the tray, flagged custom.
    func addCustom(label: String, lifeArea: LibraryLifeArea) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, directions.indices.contains(index) else { return }
        let item = Item(id: UUID().uuidString, label: trimmed, blurb: "", lifeArea: lifeArea, band: nil, isCustom: true, subDirection: nil)
        directions[index].items.append(item)
    }

    /// Pull a Tier-2 bench task into the current direction's tray.
    func pullFromBench(_ task: StarterTask) {
        guard directions.indices.contains(index) else { return }
        guard !directions[index].items.contains(where: { $0.id == task.id }) else { return }
        let item = Item(id: task.id, label: task.label, blurb: task.blurb, lifeArea: task.lifeArea, band: nil, isCustom: false, subDirection: task.subDirection)
        directions[index].items.append(item)
    }

    func benchAdded(_ task: StarterTask) -> Bool {
        guard directions.indices.contains(index) else { return false }
        return directions[index].items.contains { $0.id == task.id }
    }

    // MARK: Pricing

    /// Value for a card at band-local rank `index` inside a band of `count`
    /// cards. Top of the band (index 0) earns the high end.
    static func value(band: ColdStartBand, count: Int, index: Int) -> Int {
        let (lo, hi) = band.range
        guard count > 1 else { return Int((Double(lo + hi) / 2.0).rounded()) }
        let v = Double(lo) + Double(hi - lo) * Double(count - 1 - index) / Double(count - 1)
        return Int(v.rounded())
    }

    /// Live sum of every placed card's value across all directions.
    var liveValueSum: Int {
        var total = 0
        for dir in directions {
            for band in ColdStartBand.allCases {
                let group = dir.items.filter { $0.band == band }
                for i in group.indices {
                    total += Self.value(band: band, count: group.count, index: i)
                }
            }
        }
        return total
    }

    /// Daily target = 60 % of the total value on the board. Recomputed live.
    var liveDailyTarget: Int {
        Int((0.60 * Double(liveValueSum)).rounded())
    }

    // MARK: Final board

    /// The de-duplicated, priced board: placed cards across all directions,
    /// values derived from band + rank, then GCD-normalized so the value
    /// set is coprime (e.g. {10, 6} → {5, 3}).
    func finalBoard() -> [ColdStartFinalTask] {
        var seen = Set<String>()
        var result: [ColdStartFinalTask] = []
        for direction in directions {
            for band in ColdStartBand.allCases {
                let group = direction.items.filter { $0.band == band }
                for (rank, item) in group.enumerated() {
                    let key = item.label.lowercased()
                    guard seen.insert(key).inserted else { continue }
                    let value = Self.value(band: band, count: group.count, index: rank)
                    result.append(ColdStartFinalTask(
                        label: item.label,
                        blurb: item.blurb,
                        lifeArea: item.lifeArea,
                        band: band,
                        bandRank: rank,
                        value: value,
                        isCustom: item.isCustom,
                        subDirection: item.subDirection
                    ))
                }
            }
        }

        let divisor = Self.gcd(of: result.map(\.value))
        guard divisor > 1 else { return result }
        return result.map { task in
            ColdStartFinalTask(
                label: task.label,
                blurb: task.blurb,
                lifeArea: task.lifeArea,
                band: task.band,
                bandRank: task.bandRank,
                value: max(1, task.value / divisor),
                isCustom: task.isCustom,
                subDirection: task.subDirection
            )
        }
    }

    var directionTitles: [String] { directions.map(\.title) }

    // MARK: GCD

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? abs(a) : gcd(b, a % b)
    }

    private static func gcd(of values: [Int]) -> Int {
        let positives = values.filter { $0 > 0 }
        guard let first = positives.first else { return 1 }
        return max(1, positives.dropFirst().reduce(first) { gcd($0, $1) })
    }
}
