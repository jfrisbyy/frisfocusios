//
//  CaptureSheetView.swift
//  FrisFocus
//
//  The partial-height sheet that pops up when the user taps the center
//  "+" button in the bottom nav. Offers three picker options: a new
//  repeatable Task, a one-time To-do, or a free-form Note. Each option
//  opens a corresponding full-height form sheet on top of this one.
//
//  Saving inside a form calls back here so the whole capture flow
//  collapses — the form dismisses itself, then this sheet dismisses too.
//

import SwiftUI

struct CaptureSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @State private var activeForm: CaptureFormType?
    @State private var showPhotoCapture: Bool = false

    enum CaptureFormType: Identifiable {
        case task
        case todo
        case note
        case voiceMemo

        var id: Self { self }
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 12) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        CaptureOptionButton(
                            title: "Photo / Video",
                            subtitle: "share a moment · tag a task",
                            iconName: "camera",
                            accent: Color(hex: 0xD87D44)
                        ) {
                            showPhotoCapture = true
                        }

                        CaptureOptionButton(
                            title: "New Task",
                            subtitle: "repeatable, point-bearing",
                            iconName: "repeat",
                            accent: Theme.categoryWork
                        ) {
                            activeForm = .task
                        }

                        CaptureOptionButton(
                            title: "New To-do",
                            subtitle: "one-time item, optional date",
                            iconName: "square.dashed",
                            accent: Theme.textTertiary
                        ) {
                            activeForm = .todo
                        }

                        CaptureOptionButton(
                            title: "New Note",
                            subtitle: "thought, verse, evening reflection",
                            iconName: "pencil.line",
                            accent: Theme.categoryCreative
                        ) {
                            activeForm = .note
                        }

                        CaptureOptionButton(
                            title: "Voice Memo",
                            subtitle: "record, play back, save",
                            iconName: "waveform",
                            accent: Theme.categorySpiritual
                        ) {
                            activeForm = .voiceMemo
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
        }
        .sheet(item: $activeForm) { type in
            switch type {
            case .task:
                NewTaskFormView { dismiss() }
            case .todo:
                NewTodoFormView { dismiss() }
            case .note:
                NewNoteFormView { dismiss() }
            case .voiceMemo:
                NewVoiceMemoFormView { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showPhotoCapture) {
            CaptureView(mode: .generalPost)
                .environment(store)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 6) {
            EyebrowText(text: "Capture", opacity: 0.55)
            Text("What wants to be written down?")
                .font(.serif(19, weight: .medium))
                .italic()
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Option button

private struct CaptureOptionButton: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accent: Color
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 44, height: 44)

                    Image(systemName: iconName)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sans(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Text(subtitle)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    Color.black.opacity(0.2)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            CaptureSheetView()
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .environment(Store())
        }
}
