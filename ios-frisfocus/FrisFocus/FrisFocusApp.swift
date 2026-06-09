//
//  FrisFocusApp.swift
//  FrisFocus
//

import SwiftUI

@main
struct FrisFocusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()
    @State private var authManager = AuthManager()
    @State private var profileStore = ProfileStore()
    @State private var moderationService = ModerationService()
    @State private var cadenceLink = CadenceLinkService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(authManager)
                .environment(profileStore)
                .environment(moderationService)
                .environment(cadenceLink)
                .environment(appDelegate.notifications)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}
