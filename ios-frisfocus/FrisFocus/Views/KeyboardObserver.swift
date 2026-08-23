//
//  KeyboardObserver.swift
//  FrisFocus
//
//  Tiny shared helper: mirrors the software keyboard's visibility into
//  a bound Bool so chrome (like the sundial nav) can slide away while
//  the person is typing and return when the keyboard drops.
//

import SwiftUI
import UIKit

extension View {
    /// Keeps `isVisible` in sync with the software keyboard, animating
    /// the flip so dependent views transition smoothly.
    func observeKeyboard(_ isVisible: Binding<Bool>) -> some View {
        self
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in
                guard !isVisible.wrappedValue else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible.wrappedValue = true
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                guard isVisible.wrappedValue else { return }
                withAnimation(.easeIn(duration: 0.22)) {
                    isVisible.wrappedValue = false
                }
            }
    }
}
