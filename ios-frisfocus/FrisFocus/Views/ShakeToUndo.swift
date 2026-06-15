//
//  ShakeToUndo.swift
//  FrisFocus
//
//  Device-shake detection wired into SwiftUI. UIWindow already reports
//  the motion event up the responder chain; we rebroadcast it as a
//  Notification so any view can react with `.onShake { }`. Used by the
//  home page to undo the last reversible plan action.
//

import SwiftUI
import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("FFDeviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

/// Fires `onShake` whenever the device is given a quick shake.
private struct ShakeDetector: ViewModifier {
    let onShake: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            onShake()
        }
    }
}

extension View {
    /// React to a device shake — used for shake-to-undo on the home page.
    func onShake(perform: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(onShake: perform))
    }
}
