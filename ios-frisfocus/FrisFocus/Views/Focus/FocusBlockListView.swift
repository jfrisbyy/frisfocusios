//
//  FocusBlockListView.swift
//  FrisFocus
//
//  Picks which apps / categories to silence during a focus block. Wraps
//  Apple's official `FamilyActivityPicker` (the only way to choose real
//  apps — their tokens are opaque and can't be built by hand) behind the
//  app's warm paper aesthetic, with a first-run Screen Time explainer and
//  a clear "tap to allow blocking" prompt until approval is granted.
//

import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
#endif

struct FocusBlockListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FocusBlockingService.self) private var blocking

    @State private var showPicker = false
    @State private var showAuthFailure = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    statusCard
                    chooseButton
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .navigationTitle("Silence apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .onAppear { blocking.refreshAuthStatus() }
            #if canImport(FamilyControls)
            .familyActivityPicker(isPresented: $showPicker, selection: bindingSelection)
            #endif
            .alert("Screen Time approval failed", isPresented: $showAuthFailure) {
                authFailureActions
            } message: {
                Text(failureText)
            }
        }
    }

    #if canImport(FamilyControls)
    private var bindingSelection: Binding<FamilyActivitySelection> {
        Bindable(blocking).selection
    }
    #endif

    // MARK: - Sections

    @ViewBuilder
    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick the apps that pull you away. While a focus block runs, opening one shows a block screen instead — so the tree keeps its leaves.")
                .font(.serifItalic(15))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        @Bindable var b = blocking
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BLOCKING")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Spacer()
                Toggle("", isOn: $b.isEnabled)
                    .labelsHidden()
                    .tint(Theme.alertGreen)
            }
            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Image(systemName: blocking.hasSelection ? "hand.raised.fill" : "hand.raised")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(blocking.hasSelection ? Theme.alertGreen : Theme.textPrimary.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(blocking.summaryLine)
                        .font(.serif(16, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                    if !blocking.canBlockForReal {
                        Text(authNote)
                            .font(.sans(11))
                            .foregroundStyle(Color(hex: 0x9E7E40))
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.warmWheat)
        )
    }

    @ViewBuilder
    private var chooseButton: some View {
        VStack(spacing: 10) {
            Button(action: choose) {
                Text(blocking.hasSelection ? "Edit silenced apps" : "Choose apps to silence")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.warmWheat)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.textPrimary)
                    )
            }
            .buttonStyle(.plain)

            if blocking.authStatus == .denied {
                Text("Screen Time access is off. Enable it in Settings › Screen Time to silence other apps.")
                    .font(.sans(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        Text("Locking or sleeping your phone never costs a leaf. Only opening a silenced app — or leaving FrisFocus — does.")
            .font(.serifItalic(12))
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
    }

    private var authNote: String {
        switch blocking.authStatus {
        case .approved: return ""
        case .denied: return "Screen Time access is off — tap to allow blocking"
        case .notDetermined: return "Tap to allow blocking"
        case .unavailable: return "Real blocking runs on your iPhone"
        }
    }

    @ViewBuilder
    private var authFailureActions: some View {
        let failure: FocusBlockingService.AuthFailure? = blocking.lastFailure
        if failure?.canRetry ?? true {
            Button("Try Again") { choose() }
        }
        if failure?.suggestsSettings ?? false {
            Button("Open Settings") { openSettings() }
        }
        Button("Not Now", role: .cancel) {}
    }

    private var failureText: String {
        guard let failure = blocking.lastFailure else {
            return "Apple refused the Screen Time request. Please try again."
        }
        return "\(failure.message)\n\nApple's error: \(failure.rawCode)"
    }

    // MARK: - Actions

    /// The picker tap is the permission trigger: ask Apple first, and
    /// only open the real app picker once approval is held. A refusal
    /// raises a clear alert instead of failing silently.
    private func choose() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            switch blocking.authStatus {
            case .approved, .unavailable:
                // Approved — or the simulator preview, where the flow
                // stays testable even though Apple can't truly shield.
                showPicker = true
            case .notDetermined, .denied:
                let granted = await blocking.requestAuthorization()
                if granted || blocking.authStatus == .unavailable {
                    showPicker = true
                } else {
                    showAuthFailure = true
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
