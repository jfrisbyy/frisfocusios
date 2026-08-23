//
//  FrisFocusWidgetBundle.swift
//  FrisFocusWidget
//
//  Bundles every extension widget: the home-screen sun widget and the
//  focus-block Live Activity.
//

import SwiftUI
import WidgetKit

@main
struct FrisFocusWidgetBundle: WidgetBundle {
    var body: some Widget {
        FrisFocusSunWidget()
        FocusLiveActivity()
    }
}
