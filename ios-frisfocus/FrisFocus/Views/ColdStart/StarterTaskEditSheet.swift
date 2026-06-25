//
//  StarterTaskEditSheet.swift
//  FrisFocus
//
//  Press-and-hold (or tap) to edit a starter task during the cold start:
//  rename, tweak the blurb, change the life-area grouping, or remove it.
//  Groupings are flexible suggestions, never locked buckets.
//

import SwiftUI

struct StarterTaskEditSheet: View {
    @Bindable var viewModel: ColdStartViewModel
    let item: ColdStartViewModel.Item

    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var blurb: String = ""
    @State private var lifeArea: LibraryLifeArea = .work

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit task")
                .font(.serif(22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Name")
                TextField("Task name", text: $label, axis: .vertical)
                    .font(.sans(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1...2)
                    .padding(13)
                    .background(field)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Note (optional)")
                TextField("A short reminder of what it means", text: $blurb, axis: .vertical)
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1...3)
                    .padding(13)
                    .background(field)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Grouping")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LibraryLifeArea.allCases) { area in
                            groupingChip(area)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    viewModel.remove(itemId: item.id)
                    dismiss()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "trash")
                        Text("Remove")
                    }
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.alertRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.alertRed.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.update(itemId: item.id, label: label, blurb: blurb, lifeArea: lifeArea)
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(label.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textPrimary.opacity(0.3) : Theme.textPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .background(Theme.paperCream)
        .onAppear {
            label = item.label
            blurb = item.blurb
            lifeArea = item.lifeArea
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        EyebrowText(text: text, opacity: 0.5)
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.warmWheat)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 1)
            )
    }

    private func groupingChip(_ area: LibraryLifeArea) -> some View {
        let selected = lifeArea == area
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { lifeArea = area }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: area.symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(area.displayName)
                    .font(.sans(13, weight: .medium))
            }
            .foregroundStyle(selected ? Theme.textCream : area.tint.darkVariant)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(selected ? area.tint : area.tint.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color helper

private extension Color {
    /// A slightly darker variant for legible chip text on a light wash.
    var darkVariant: Color { self.opacity(0.95) }
}
