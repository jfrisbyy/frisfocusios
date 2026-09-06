//
//  AgeCheckView.swift
//  FrisFocus
//
//  The age gate, and the reason it sits where it does.
//
//  The Terms require a person to be at least 13 (or their country's
//  minimum), but nothing in the flow ever asked. For an app with public
//  profiles, private messaging, photo and video sharing between members,
//  that is both an App Review exposure and a real COPPA one.
//
//  It runs BEFORE sign-in on purpose. Asking after would mean creating an
//  account — and a profile row, and an email address on our servers — for
//  someone we are about to turn away, which is exactly the data we should
//  never have collected.
//
//  A date is asked for rather than a yes/no box. A box invites a shrug; a
//  date makes the answer a deliberate one, and it is the form regulators
//  treat as a neutral gate.
//
//  The date itself is never stored or transmitted. Only the outcome is
//  kept, on this device: passed, or turned away. That keeps the answer out
//  of the privacy manifest entirely — there is no birth date to declare
//  because there is no birth date anywhere.
//

import SwiftUI

/// Remembers the outcome so the question is asked once. Deliberately local
/// only: a reinstall asking again is a smaller cost than holding a birth
/// date on a server.
enum AgeGate {
    private static let passedKey = "ageGate.passed.v1"
    private static let blockedKey = "ageGate.blocked.v1"

    /// The minimum age the Terms of Use state.
    static let minimumAge = 13

    static var hasPassed: Bool { UserDefaults.standard.bool(forKey: passedKey) }

    /// True once someone has answered under the minimum. Persisted so the
    /// answer cannot be retried by relaunching, which is the whole point
    /// of a gate.
    static var isBlocked: Bool { UserDefaults.standard.bool(forKey: blockedKey) }

    static func recordPass() {
        UserDefaults.standard.set(true, forKey: passedKey)
    }

    static func recordBlock() {
        UserDefaults.standard.set(true, forKey: blockedKey)
    }

    /// Whole years between `date` and now, by the calendar rather than by
    /// arithmetic on days — leap years and month lengths otherwise put
    /// birthdays a day out.
    static func age(from date: Date, now: Date = Date()) -> Int {
        Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
    }
}

struct AgeCheckView: View {
    /// Old enough — carry on into the account step.
    let onPass: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var birthDate: Date = AgeCheckView.defaultDate
    @State private var didTouch: Bool = false
    @State private var turnedAway: Bool = AgeGate.isBlocked
    @State private var shown: Bool = false

    /// Opens on a plausible adult date so the wheel is not parked on today,
    /// which would read as a suggestion.
    private static var defaultDate: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    }

    private var age: Int { AgeGate.age(from: birthDate) }
    private var isOldEnough: Bool { age >= AgeGate.minimumAge }

    var body: some View {
        Group {
            if turnedAway {
                turnedAwayPanel
            } else {
                askPanel
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { shown = true }
        }
    }

    // MARK: Asking

    private var askPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.85))

                Text("When were you born?")
                    .font(.serif(30, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("FrisFocus is for people \(AgeGate.minimumAge) and over. We don't keep this date — it only decides whether to let you in.")
                    .font(.serifItalic(15.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 28)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)

            DatePicker(
                "Date of birth",
                selection: $birthDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .onChange(of: birthDate) { _, _ in didTouch = true }
            .padding(.vertical, 8)
            .accessibilityLabel("Date of birth")

            Spacer(minLength: 16)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if isOldEnough {
                    AgeGate.recordPass()
                    onPass()
                } else {
                    AgeGate.recordBlock()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        turnedAway = true
                    }
                }
            } label: {
                Text("Continue")
                    .font(.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.textCream.opacity(didTouch ? 1 : 0.55))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            // Until the wheel is touched the value is our suggestion, not
            // their answer, and a gate must not pass on an untouched default.
            .disabled(!didTouch)
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
            .opacity(shown ? 1 : 0)
        }
    }

    // MARK: Turned away

    /// No retry, and no back. A gate that can be re-answered is not a gate,
    /// and the tone stays kind — this is a rule, not a judgement.
    private var turnedAwayPanel: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "sun.and.horizon")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.8))

            Text("Not just yet.")
                .font(.serif(30, weight: .semibold))
                .foregroundStyle(Theme.textCream)

            Text("FrisFocus is built for people \(AgeGate.minimumAge) and over. Come back when you are — the sun will still be here.")
                .font(.serifItalic(16, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 34)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        DawnBackdrop(progress: 0.2).ignoresSafeArea()
        AgeCheckView(onPass: {})
    }
}
