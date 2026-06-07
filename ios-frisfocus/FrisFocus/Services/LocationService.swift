//
//  LocationService.swift
//  FrisFocus
//
//  Thin wrapper around CoreLocation that only exists to source a coarse
//  coordinate for sunrise/sunset math. We don't follow the user — we
//  request a single in-use authorization and then read the last known
//  fix. If permission is denied or the device can't provide a location,
//  callers fall back to fixed 6:30 / 20:30 times.
//

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject {
    /// The latest coordinate, if available. `nil` until we get a fix or
    /// permission has been denied / restricted.
    private(set) var coordinate: CLLocationCoordinate2D?

    /// The current authorization status as reported by CoreLocation.
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // Sun position math doesn't need precision — kilometre accuracy
        // keeps the battery happy.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    /// Ask for "when in use" permission if we haven't asked yet, then
    /// start listening for a single coarse location update. Safe to call
    /// repeatedly — does nothing once permission has been granted or
    /// denied.
    func requestPermissionIfNeeded() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            // Denied / restricted — silent fallback handled by callers.
            break
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = last.coordinate
        Task { @MainActor in
            self.coordinate = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — caller's fallback kicks in.
    }
}
