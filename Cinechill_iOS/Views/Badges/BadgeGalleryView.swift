//
//  BadgeGalleryView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La galerie de badges — la collection, obtenus et verrouillés côte à côte.
///
/// Les verrouillés gardent leur silhouette et leur composition exactes,
/// éteintes en pierre : on voit précisément ce qu'on n'a pas, c'est le moteur.
struct BadgeGalleryView: View {
    @Bindable var model: BadgesViewModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Badge?

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 130), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(model.filteredBadges) { badge in
                            cell(badge)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                } header: {
                    filterBar
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Mes badges · \(model.unlockedCount) / \(model.totalCount)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .sheet(item: $selected) { badge in
            BadgeDetailView(
                badge: badge,
                progress: model.progress(for: badge),
                // Une fois le badge affiché, on referme la galerie pour
                // révéler le profil directement — pas juste la fiche.
                onDisplayedOnProfile: {
                    selected = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        dismiss()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(BadgesViewModel.Filter.allCases) { option in
                let isOn = model.filter == option
                Button {
                    Haptics.selection()
                    model.filter = option
                } label: {
                    Text(option.label)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isOn ? Color(.systemBackground) : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isOn ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color(.secondarySystemBackground)),
                            in: Capsule()
                        )
                }
                .buttonStyle(PressableScaleStyle(scale: 0.92))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func cell(_ badge: Badge) -> some View {
        let state = model.progress(for: badge)
        return Button {
            Haptics.impact(.light)
            selected = badge
        } label: {
            VStack(spacing: 7) {
                BadgeView(badge: badge, isUnlocked: state.unlocked, size: 88)

                Text(badge.displayName(unlocked: state.unlocked))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if !state.unlocked {
                    Text(badge.isSecret ? "Secret" : "\(state.current) / \(state.target)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
    }
}

/// La fiche d'un badge : ce qu'il représente, et ce qui manque exactement.
struct BadgeDetailView: View {
    let badge: Badge
    let progress: BadgeProgress
    /// Appelé après l'animation de confirmation, uniquement quand le badge
    /// vient d'être choisi (pas quand on le retire) — c'est ce qui referme la
    /// galerie pour révéler le profil avec le nouveau badge.
    var onDisplayedOnProfile: (() -> Void)?

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false

    private var isDisplayed: Bool { libraryStore.displayedBadgeID == badge.id }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BadgeView(badge: badge, isUnlocked: progress.unlocked, size: 168)
                    .padding(.top, 28)
                    .overlay(alignment: .topTrailing) { confirmationBadge }

                VStack(spacing: 10) {
                    Text(badge.displayName(unlocked: progress.unlocked))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))

                    Text(badge.rarity.label.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .kerning(1.2)
                        .foregroundStyle(badge.rarity.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(badge.rarity.accent.opacity(0.15), in: Capsule())

                    Text(badge.displayCondition(unlocked: progress.unlocked))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // Le détail dit ce qui manque précisément, pas juste un
                    // seuil : un badge dont on sait quoi faire est un badge
                    // qu'on va chercher.
                    if let detail = progress.detail, !progress.unlocked, !badge.isSecret {
                        Text(detail)
                            .font(.system(size: 12.5))
                            .italic()
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)

                if progress.unlocked {
                    unlockedFooter
                } else if !badge.isSecret {
                    progressBar
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }

    private var progressBar: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .pink],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 6)

            Text("\(progress.current) sur \(progress.target)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }

    private var unlockedFooter: some View {
        VStack(spacing: 12) {
            if let date = progress.unlockedAt {
                Text("Obtenu le \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Button(action: handleTap) {
                HStack(spacing: 7) {
                    if isConfirming {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(buttonLabel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isDisplayed && !isConfirming ? Color.secondary : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(buttonBackground)
                }
            }
            .buttonStyle(PressableScaleStyle(scale: 0.97))
            .disabled(isConfirming)
            .padding(.horizontal, 28)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isConfirming)
        }
    }

    private var buttonLabel: String {
        isConfirming ? "Ajouté à votre profil" : (isDisplayed ? "Retirer de mon profil" : "Afficher sur mon profil")
    }

    private var buttonBackground: AnyShapeStyle {
        if isConfirming { return AnyShapeStyle(Color.green) }
        if isDisplayed { return AnyShapeStyle(Color(.tertiarySystemFill)) }
        return AnyShapeStyle(
            LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    /// Le petit pictogramme qui pulse sur le badge au moment de la confirmation.
    @ViewBuilder
    private var confirmationBadge: some View {
        if isConfirming {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .background(Circle().fill(.white))
                .offset(x: 4, y: 32)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
        }
    }

    private func handleTap() {
        let willDisplay = !isDisplayed
        libraryStore.setDisplayedBadge(willDisplay ? badge.id : nil)

        // Retirer un badge n'a pas besoin de mise en scène : seule la
        // sélection d'un nouveau badge mérite la confirmation et le retour
        // au profil.
        guard willDisplay else {
            Haptics.impact(.light)
            dismiss()
            return
        }

        Haptics.success()
        withAnimation { isConfirming = true }

        Task {
            try? await Task.sleep(for: .milliseconds(750))
            if let onDisplayedOnProfile {
                onDisplayedOnProfile()
            } else {
                dismiss()
            }
        }
    }
}
