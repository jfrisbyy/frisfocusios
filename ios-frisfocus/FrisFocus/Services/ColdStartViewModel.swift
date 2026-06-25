//
//  ColdStartViewModel.swift
//  FrisFocus
//
//  Drives the 60-second cold start: which directions the person picked,
//  the working task list for each direction (kept state + rank order),
//  and the final de-duplicated board handed to the Store. Pure local
//  state — the tile path never touches the network.
//

import Foundation
import SwiftUI

/// One task in the final board committed to the Store.
struct ColdStartFinalTask: Equatable {
    let label: String
    let blurb: String
    let lifeArea: LibraryLifeArea
}

@Observable
final class ColdStartViewModel {
    /// A working task row inside a direction page. Identity is stable so
    /// the List's drag-to-rank and swipe-to-remove animate cleanly.
    struct Item: Identifiable, Equatable, Hashable {
        let id: String
        var label: String
        var blurb: String
        var lifeArea: LibraryLifeArea
        var kept: Bool
    }

    /// One chosen direction = one page on Screen 2.
    struct Direction: Identifiable, Equatable {
        let id: String
        /// nil for a free-text general fallback direction.
        let area: StarterFocusArea?
        let title: String
        let tint: Color
        var items: [Item]

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

    /// Build the per-direction working lists from the selection. Called
    /// when leaving Screen 1.
    func build() {
        var dirs: [Direction] = []
        for areaId in selectedAreaIds {
            guard let area = StarterLibrary.focusArea(areaId) else { continue }
            let items = StarterLibrary.tier1(for: areaId).map {
                Item(id: $0.id, label: $0.label, blurb: $0.blurb, lifeArea: $0.lifeArea, kept: true)
            }
            dirs.append(Direction(id: areaId, area: area, title: area.title, tint: area.tint, items: items))
        }
        for intent in customIntents {
            let items = StarterLibrary.generalBoard().map {
                Item(id: "\(intent)-\($0.id)", label: $0.label, blurb: $0.blurb, lifeArea: $0.lifeArea, kept: true)
            }
            dirs.append(Direction(id: "custom-\(intent)", area: nil, title: intent.capitalized, tint: Theme.sunOuter, items: items))
        }
        directions = dirs
        index = 0
    }

    // MARK: Current-direction mutations

    var current: Direction? {
        guard directions.indices.contains(index) else { return nil }
        return directions[index]
    }

    var isLastDirection: Bool { index >= directions.count - 1 }

    var keptCountCurrent: Int {
        guard let current else { return 0 }
        return current.items.filter(\.kept).count
    }

    func toggleKeep(_ itemId: String) {
        guard directions.indices.contains(index),
              let i = directions[index].items.firstIndex(where: { $0.id == itemId }) else { return }
        directions[index].items[i].kept.toggle()
    }

    func move(from source: IndexSet, to destination: Int) {
        guard directions.indices.contains(index) else { return }
        directions[index].items.move(fromOffsets: source, toOffset: destination)
    }

    func remove(at offsets: IndexSet) {
        guard directions.indices.contains(index) else { return }
        directions[index].items.remove(atOffsets: offsets)
    }

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

    func addCustom(label: String, lifeArea: LibraryLifeArea) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, directions.indices.contains(index) else { return }
        let item = Item(id: UUID().uuidString, label: trimmed, blurb: "", lifeArea: lifeArea, kept: true)
        directions[index].items.append(item)
    }

    /// Pull a Tier-2 bench task into the current direction's list.
    func pullFromBench(_ task: StarterTask) {
        guard directions.indices.contains(index) else { return }
        guard !directions[index].items.contains(where: { $0.id == task.id }) else { return }
        let item = Item(id: task.id, label: task.label, blurb: task.blurb, lifeArea: task.lifeArea, kept: true)
        directions[index].items.append(item)
    }

    /// Whether a bench task is already on the current direction's list.
    func benchAdded(_ task: StarterTask) -> Bool {
        guard directions.indices.contains(index) else { return false }
        return directions[index].items.contains { $0.id == task.id }
    }

    // MARK: Final board

    /// The de-duplicated, ordered board: kept items across all
    /// directions, in direction order then rank order. The order is the
    /// ranking prior the later season conversation can build on.
    func finalBoard() -> [ColdStartFinalTask] {
        var seen = Set<String>()
        var result: [ColdStartFinalTask] = []
        for direction in directions {
            for item in direction.items where item.kept {
                let key = item.label.lowercased()
                if seen.insert(key).inserted {
                    result.append(ColdStartFinalTask(label: item.label, blurb: item.blurb, lifeArea: item.lifeArea))
                }
            }
        }
        return result
    }

    var directionTitles: [String] { directions.map(\.title) }
}
