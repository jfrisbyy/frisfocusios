//
//  AreaGrid.swift
//  FrisFocus
//
//  The coarse "Near you" grid. A coordinate maps to a half-degree cell
//  (~50 km) so a profile only ever carries a city-scale area — never an
//  exact position. Matching considers the cell plus its 8 neighbors, so
//  people just across a cell border still find each other.
//

import Foundation

nonisolated enum AreaGrid {
    /// Cell size in degrees. 0.5° of latitude is roughly 55 km.
    static let cellSize: Double = 0.5

    /// The grid key for a coordinate, e.g. "a60:-148".
    static func key(latitude: Double, longitude: Double) -> String {
        let latIndex = Int(floor(latitude / cellSize))
        let lonIndex = Int(floor(longitude / cellSize))
        return "a\(latIndex):\(lonIndex)"
    }

    /// The cell itself plus its 8 surrounding cells — the query set for
    /// "people roughly in my area". Returns just the input when the key
    /// doesn't parse (defensive; keys are always self-produced).
    static func neighborKeys(of key: String) -> [String] {
        guard key.hasPrefix("a") else { return [key] }
        let body = key.dropFirst()
        let parts = body.split(separator: ":")
        guard parts.count == 2,
              let latIndex = Int(parts[0]),
              let lonIndex = Int(parts[1]) else { return [key] }
        var keys: [String] = []
        for dLat in -1...1 {
            for dLon in -1...1 {
                keys.append("a\(latIndex + dLat):\(lonIndex + dLon)")
            }
        }
        return keys
    }
}
