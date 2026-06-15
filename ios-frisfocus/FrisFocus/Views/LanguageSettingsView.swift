//
//  LanguageSettingsView.swift
//  FrisFocus
//
//  Pick the language the app uses. Today this drives voice transcription
//  in season setup — your spoken answers are transcribed in this language
//  instead of your phone's system language. A checkmark marks the active
//  choice and the pick is remembered between launches.
//

import SwiftUI
import UIKit

struct LanguageSettingsView: View {
    @State private var store = AppLanguageStore.shared

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    Text("Your spoken answers in season setup are transcribed in this language. Change it anytime — voice picks it up the next time you tap the mic.")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                            if index > 0 {
                                Rectangle()
                                    .fill(Theme.textPrimary.opacity(0.06))
                                    .frame(height: 0.5)
                                    .padding(.leading, 16)
                            }
                            row(language)
                        }
                    }
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func row(_ language: AppLanguage) -> some View {
        let isSelected = store.language == language
        return Button {
            guard !isSelected else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.language = language
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.displayName)
                        .font(.sans(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if language.nativeName != language.displayName {
                        Text(language.nativeName)
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
    }
}
