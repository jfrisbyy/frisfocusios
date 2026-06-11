//
//  PactsListView.swift
//  FrisFocus
//
//  The Pacts surface — a list of the user's two-person, time-boxed
//  commitments. Distinct from circles even though plumbing is shared.
//  Each row surfaces the partner, title, days left, and miniature
//  symmetric progress bars (you + partner). A propose-a-pact CTA at
//  the top opens the compose flow. Pending invites render with
//  accept / decline affordances inline.
//

import SwiftUI
import UIKit

struct PactsListView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showPropose: Bool = false
    @State private var selectedPactId: UUID?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 14) {
                        proposeCTA

                        if store.myPacts.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.myPacts) { pact in
                                    PactRowCard(pact: pact) {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedPactId = pact.id
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 18)

                    Color.clear.frame(height: 160)
                }
            }
            .background(Theme.warmWheat)
            .ignoresSafeArea(edges: .top)

            SundialNavView(
                active: .subPage,
                onCaptureTap: {},
                onHomeTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                },
                onCirclesTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPropose) {
            ProposePactView()
                .environment(store)
        }
        .navigationDestination(item: $selectedPactId) { id in
            if let pact = store.pact(by: id) {
                PactDetailView(pact: pact)
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1830),
                    Color(hex: 0x2A2438),
                    Color(hex: 0x6B4D70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Two faint linked discs as decoration.
            decorationDiscs
                .allowsHitTesting(false)

            topBar
                .padding(.top, 56)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                Text("TWO PEOPLE · ONE WINDOW")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.72))
                Text("Pacts")
                    .font(.serif(28, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            }
            .padding(.leading, Theme.pageHorizontalPadding)
            .padding(.bottom, 22)
        }
        .frame(height: 200)
        .clipped()
    }

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.sans(15, weight: .medium))
                    Text("Friends")
                        .font(.sans(14, weight: .regular))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Friends")

            Spacer()
        }
    }

    @ViewBuilder
    private var decorationDiscs: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Circle()
                    .strokeBorder(Theme.textCream.opacity(0.10), lineWidth: 1)
                    .frame(width: 56, height: 56)
                    .position(x: w - 90, y: h * 0.36)
                Rectangle()
                    .fill(Theme.textCream.opacity(0.10))
                    .frame(width: 28, height: 1)
                    .position(x: w - 48, y: h * 0.36)
                Circle()
                    .strokeBorder(Theme.textCream.opacity(0.10), lineWidth: 1)
                    .frame(width: 56, height: 56)
                    .position(x: w - 6, y: h * 0.36)
            }
        }
    }

    // MARK: - Propose CTA

    private var proposeCTA: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPropose = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.sans(13, weight: .semibold))
                Text("Propose a pact")
                    .font(.sans(14, weight: .semibold))
                Spacer(minLength: 0)
                Text("with a friend")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.7))
            }
            .foregroundStyle(Theme.textCream)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.textPrimary)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Propose a pact with a friend")
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No pacts yet")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
            Text("Make one with a friend — same window, same commitment, no winner. You finish together.")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Row card

private struct PactRowCard: View {
    @Environment(Store.self) private var store
    let pact: Pact
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(eyebrow)
                            .font(.sans(10, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        Text(pact.title)
                            .font(.serif(17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    pairAvatars
                }

                if pact.status == .active {
                    twoBars
                } else if pact.status == .pending {
                    pendingPill
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pact: \(pact.title)")
    }

    private var partner: Friend? { store.partnerFriend(forPact: pact) }

    private var eyebrow: String {
        let partnerName = partner?.displayName ?? "friend"
        switch pact.status {
        case .pending:
            return pact.proposerId == store.currentUserId
                ? "PENDING · WAITING ON \(partnerName.uppercased())"
                : "INVITE FROM \(partnerName.uppercased())"
        case .active:
            let days = store.pactDaysLeft(pact: pact)
            let suffix = days == 1 ? "1 DAY LEFT" : "\(days) DAYS LEFT"
            return "A PACT WITH \(partnerName.uppercased()) · \(suffix)"
        case .completed:
            return "PACT KEPT · \(partnerName.uppercased())"
        case .declined:
            return "DECLINED"
        }
    }

    private var pairAvatars: some View {
        HStack(spacing: -6) {
            youDisc
            if let partner {
                partnerDisc(partner)
            }
        }
    }

    private var youDisc: some View {
        ZStack {
            Circle().fill(Theme.textPrimary)
            Text("J")
                .font(.sans(10, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 22, height: 22)
        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.2))
    }

    private func partnerDisc(_ friend: Friend) -> some View {
        ZStack {
            Circle().fill(Color(hex: friend.accentColorHex))
            Text(friend.initials)
                .font(.sans(10, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 22, height: 22)
        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.2))
    }

    private var twoBars: some View {
        let window = max(pact.durationDays, 1)
        let youKept = store.pactDaysKept(pact: pact, userId: store.currentUserId)
        let partnerKept = partner.map { store.pactDaysKept(pact: pact, userId: $0.id) } ?? 0
        return HStack(spacing: 10) {
            miniBar(label: "You", kept: youKept, window: window, tint: Theme.sunOuter)
            miniBar(
                label: partner?.displayName ?? "Partner",
                kept: partnerKept,
                window: window,
                tint: partner.map { Color(hex: $0.accentColorHex) } ?? Theme.alertGreen
            )
        }
    }

    private func miniBar(label: String, kept: Int, window: Int, tint: Color) -> some View {
        let fraction = min(1.0, max(0.0, Double(kept) / Double(window)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                Spacer()
                Text("\(kept)/\(window)")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
    }

    private var pendingPill: some View {
        Text(pact.proposerId == store.currentUserId
             ? "Sent — they accept and you both start."
             : "Tap to accept or decline.")
            .font(.serifItalic(13, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
    }
}

#Preview {
    NavigationStack {
        PactsListView()
            .environment(Store())
    }
}
