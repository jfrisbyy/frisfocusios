//
//  FrisFocusApp.swift
//  FrisFocus
//

import SwiftUI

@main
struct FrisFocusApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}
