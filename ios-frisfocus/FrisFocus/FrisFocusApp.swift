//
//  FrisFocusApp.swift
//  FrisFocus
//

import SwiftUI

@main
struct FrisFocusApp: App {
    @State private var store = Store()
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(authManager)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}
