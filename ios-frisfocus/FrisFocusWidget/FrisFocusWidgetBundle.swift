//
//  FrisFocusWidgetBundle.swift
//  FrisFocusWidget
//
//  Bundles every extension widget. F3 ships a single Live Activity
//  for active focus blocks; no home-screen widget yet.
//

import SwiftUI
import WidgetKit

@main
struct FrisFocusWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}
