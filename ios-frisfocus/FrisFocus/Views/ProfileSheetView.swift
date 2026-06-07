//
//  ProfileSheetView.swift
//  FrisFocus
//
//  Placeholder for the eventual "You" experience — profile, settings,
//  season management, history, account. Shown when the user taps the
//  top-right avatar on the homepage. Real content is a follow-up
//  prompt; this stub reserves the destination so the avatar has
//  somewhere to land.
//

import SwiftUI

struct ProfileSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer().frame(height: 24)

                    ZStack {
                        Circle()
                            .fill(Theme.textPrimary)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Circle()
                                    .stroke(Theme.sunWarm, lineWidth: 2)
                            )
                        Text("J")
                            .font(.serif(28, weight: .medium))
                            .foregroundStyle(Theme.textCream)
                    }

                    VStack(spacing: 6) {
                        Text("You")
                            .font(.serif(26, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)

                        Text("Profile, settings, season management, history.")
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Spacer()
                }
                .padding(.top, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .toolbarBackground(Theme.warmWheat, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    Color.gray.opacity(0.3)
        .sheet(isPresented: .constant(true)) {
            ProfileSheetView()
        }
}
