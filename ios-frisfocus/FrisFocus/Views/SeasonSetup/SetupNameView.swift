//
//  SetupNameView.swift
//  FrisFocus
//
//  Screen 4 — name & frame it, AFTER the board has been seen. The orb
//  sits high on the arc, the AI-suggested name arrives prefilled in a
//  serif field ("tap to make it yours"), length is confirmed here, and
//  an optional intention line closes the ritual. No numbers on this
//  screen — the targets live back on review, next to the tasks.
//

import SwiftUI
import UIKit

struct SetupNameView: View {
    @Bindable var viewModel: SeasonSetupViewModel
    let onLockIn: (String, SeasonEndMode, Date?) -> Void

    @State private var name: String = ""
    @State private var endMode: SeasonEndMode = .openEnded
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
    @State private var intention: String = ""
    @FocusState private var nameFocused: Bool

    private let endOptions: [(mode: SeasonEndMode, label: String)] = [
        (.openEnded, "Open — until I end it"),
        (.milestones, "Until the milestones land"),
        (.date, "Ends on a date"),
    ]

    var body: some View {
        ZStack {
            SetupSky.dawn(lift: 1).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        viewModel.backToReview()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .medium))
                            Text("Review")
                                .font(.sans(14, weight: .regular))
                        }
                        .foregroundStyle(Theme.textCream.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    EyebrowText(text: "Name your season", opacity: 0.7, color: Theme.textCream)

                    Spacer()

                    // Balance the back button.
                    Color.clear.frame(width: 64, height: 1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)

                ScrollView {
                    VStack(spacing: 0) {
                        SetupHeroSun(diameter: 72, haloOpacity: 0.3)
                            .padding(.top, 26)
                            .padding(.bottom, 26)

                        Text("From what you told me, this\nfelt like the name of it —")
                            .font(.serifItalic(14, weight: .regular))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textCream.opacity(0.75))
                            .padding(.bottom, 16)

                        TextField("Name your season", text: $name, axis: .vertical)
                            .font(.serif(28, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textCream)
                            .focused($nameFocused)
                            .lineLimit(1...3)
                            .padding(.horizontal, 32)

                        Rectangle()
                            .fill(Theme.textCream.opacity(0.3))
                            .frame(width: 180, height: 0.7)
                            .padding(.top, 10)

                        if viewModel.suggestedName != nil {
                            Text("\(Image(systemName: "sparkle")) suggested · tap to make it yours")
                                .font(.sans(11, weight: .regular))
                                .tracking(0.6)
                                .foregroundStyle(Theme.textCream.opacity(0.55))
                                .padding(.top, 10)
                        }

                        VStack(spacing: 1) {
                            // How it ends — confirm or adjust what was discussed.
                            Menu {
                                ForEach(endOptions, id: \.mode) { option in
                                    Button(option.label) {
                                        endMode = option.mode
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("How it ends")
                                        .font(.sans(14, weight: .regular))
                                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                                    Spacer()
                                    Text(endModeLabel)
                                        .font(.sans(14, weight: .medium))
                                        .foregroundStyle(Theme.sunShadow)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.92))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // A real end date — only when "ends on a date".
                            if endMode == .date {
                                HStack {
                                    Text("End date")
                                        .font(.sans(14, weight: .regular))
                                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                                    Spacer()
                                    DatePicker(
                                        "",
                                        selection: $endDate,
                                        in: tomorrow...,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                    .tint(Theme.sunShadow)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.92))
                            }

                            // Optional intention line — identity, not numbers.
                            HStack {
                                Text("The intention")
                                    .font(.sans(14, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                                Spacer()
                                TextField("optional", text: $intention)
                                    .font(.serifItalic(14, weight: .regular))
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                                    .frame(maxWidth: 170)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.92))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 22)
                        .padding(.top, 40)

                        Color.clear.frame(height: 30)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onLockIn(
                        finalName.isEmpty ? "New Season" : finalName,
                        endMode,
                        endMode == .date ? endDate : nil
                    )
                } label: {
                    Text("Lock it in & start →")
                        .font(.sans(16, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.textPrimary.opacity(0.92))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            }
        }
        .onAppear {
            if name.isEmpty {
                name = viewModel.suggestedName ?? ""
            }
            applySuggestedEnd()
            if viewModel.suggestedName == nil {
                nameFocused = true
            }
        }
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var endModeLabel: String {
        endOptions.first { $0.mode == endMode }?.label ?? "Open"
    }

    /// Pre-select the end mode from what the setup guide heard: a named
    /// date → date-ending with that date; an explicit open-ended intent or
    /// nothing → open-ended (the calm default).
    private func applySuggestedEnd() {
        if let date = viewModel.suggestedEndDate {
            endMode = .date
            endDate = date
        } else {
            endMode = .openEnded
            if let days = viewModel.suggestedLengthDays {
                endDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? endDate
            }
        }
    }
}
