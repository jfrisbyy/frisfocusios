//
//  AppDelegate.swift
//  FrisFocus
//
//  A thin UIKit bridge for push notifications, wired into the SwiftUI app
//  via `@UIApplicationDelegateAdaptor`. It owns the shared
//  `NotificationManager` (injected into the environment from
//  `FrisFocusApp`) and forwards the three things only UIKit can give us:
//  the registered APNs device token, registration failures, and
//  notification taps (including a cold launch from a tapped push).
//
//  The whole class is `@MainActor` (the project's default isolation), and
//  the `UNUserNotificationCenterDelegate` callbacks use the async
//  overloads, which is the clean, compile-safe shape here — UIKit and
//  UserNotifications deliver these on the main actor.
//

import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The single source of truth for permission, token upload, and the
    /// pending deep-link route. Injected into the SwiftUI environment.
    let notifications = NotificationManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Cold launch from a tapped notification: stash the route so the
        // app shell can open it once the UI is up.
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            notifications.handleTap(userInfo: userInfo)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        notifications.didRegister(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        notifications.didFailToRegister(error)
    }

    // Show a quiet banner even when the app is foreground, so an in-app
    // user still sees a friend's proof / request land.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // A tap (foreground or background) resolves to a deep-link route.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        notifications.handleTap(userInfo: response.notification.request.content.userInfo)
    }
}
