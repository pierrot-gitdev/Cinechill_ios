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
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(model.filteredBadges) { badge in
                            cell(badge)
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                } header: {
                    filterBar
                }
            }
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(String(localized: "Mes badges", bundle: .app)) {
                PlanHeaderCount(value: "\(model.unlockedCount.formatted()) / \(model.totalCount.formatted())")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.refresh() }
        .sheet(item: $selected) { badge in
            BadgeDetailView(
                badge: badge,
                progress: model.progress(for: badge),
                // Une fois le badge affiché, on referme la galerie pour révéler
                // le profil directement — pas juste la fiche.
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

    /// Le voile de la nuit remplace `ultraThinMaterial` : la même lisibilité
    /// sous l'en-tête épinglé, sans emprunter l'esthétique du système.
    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(BadgesViewModel.Filter.allCases) { option in
                    PlanChip(title: option.label, isOn: model.filter == option) {
                        Haptics.selection()
                        model.filter = option
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 12)

            PlanEdge()
        }
        .background(Ink.ground)
    }

    private func cell(_ badge: Badge) -> some View {
        let state = model.progress(for: badge)
        return Button {
            Haptics.impact(.light)
            selected = badge
        } label: {
            VStack(spacing: 9) {
                BadgeView(badge: badge, isUnlocked: state.unlocked, size: 88)

                Text(badge.displayName(unlocked: state.unlocked))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(state.unlocked ? Ink.ink : Ink.ink2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if !state.unlocked {
                    Text(badge.isSecret
                         ? String(localized: "Secret", bundle: .app)
                         : "\(state.current.formatted()) / \(state.target.formatted())")
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
    }
}

/// La fiche d'un badge : ce qu'il représente, et ce qui manque exactement.
///
/// **Le badge est la seule couleur de l'écran.** C'est la règle que la carte de
/// signature du profil applique déjà, écrite dans son propre commentaire — si la
/// page a son identité chromatique et le badge la sienne, les deux se battent.
/// Sa fiche faisait exactement l'inverse : jauge et bouton en dégradé
/// indigo→rose, confirmation verte posée sur l'objet lui-même.
///
/// La couleur de rareté, elle, est conservée : c'est un système illustratif
/// adossé aux artworks, pas une sémantique iOS empruntée. On ne force pas
/// l'identité là où une couleur porte une information que rien d'autre ne porte.
struct BadgeDetailView: View {
    let badge: Badge
    let progress: BadgeProgress
    /// Appelé après l'animation de confirmation, uniquement quand le badge vient
    /// d'être choisi (pas quand on le retire) — c'est ce qui referme la galerie
    /// pour révéler le profil avec le nouveau badge.
    var onDisplayedOnProfile: (() -> Void)?

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false

    private var isDisplayed: Bool { libraryStore.displayedBadgeID == badge.id }

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        BadgeView(badge: badge, isUnlocked: progress.unlocked, size: 138)
                            .padding(.top, 34)

                        Text(badge.displayName(unlocked: progress.unlocked))
                            .planTitle(26)
                            .foregroundStyle(Ink.ink)
                            .multilineTextAlignment(.center)
                            .padding(.top, 26)

                        Text(badge.rarity.label)
                            .planLabel()
                            .foregroundStyle(badge.rarity.accent)
                            .padding(.top, 9)

                        Text(badge.displayCondition(unlocked: progress.unlocked))
                            .font(.system(size: 13.5))
                            .foregroundStyle(Ink.ink2)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)

                        if progress.unlocked {
                            unlockedNote
                        } else if !badge.isSecret {
                            progressBlock
                        } else if let detail = progress.detail {
                            Text(detail)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Ink.ink3)
                                .multilineTextAlignment(.center)
                                .padding(.top, 14)
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                if progress.unlocked {
                    footer
                }
            }
        }
    }

    /// La progression dit ce qui **reste**, pas seulement où l'on en est : c'est
    /// le chiffre manquant qui met en mouvement, et il n'était affiché nulle part.
    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(progress.current)")
                    .planTitle(26)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)

                Text(remainingText)
                    .planLabel()
                    .foregroundStyle(Ink.ink3)

                Spacer(minLength: 0)
            }

            PlanProgressRule(fraction: progress.fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(progress.current) sur \(progress.target)", bundle: .app))
    }

    private var remainingText: String {
        let missing = max(0, progress.target - progress.current)
        guard missing > 0 else { return String(localized: "sur \(progress.target)", bundle: .app) }
        return String(localized: "sur \(progress.target) · il en reste \(missing)", bundle: .app)
    }

    @ViewBuilder
    private var unlockedNote: some View {
        if let date = progress.unlockedAt {
            Text(String(localized: "Obtenu le \(date.formatted(date: .abbreviated, time: .omitted))", bundle: .app))
                .planLabel()
                .foregroundStyle(Ink.ink3)
                .padding(.top, 26)
        }
    }

    /// Le bouton descend au plancher : position constante, comme partout
    /// ailleurs — le pouce n'apprend qu'une seule hauteur.
    private var footer: some View {
        VStack(spacing: 0) {
            PlanEdge()

            Group {
                if isDisplayed && !isConfirming {
                    PlanSecondaryButton(title: String(localized: "Retirer de mon profil", bundle: .app), height: Metrics.control) {
                        handleTap()
                    }
                } else {
                    PlanButton(
                        title: isConfirming
                            ? String(localized: "Affiché sur votre profil", bundle: .app)
                            : String(localized: "Afficher sur mon profil", bundle: .app),
                        isEnabled: !isConfirming,
                        height: Metrics.control
                    ) {
                        handleTap()
                    }
                    .overlay(alignment: .trailing) {
                        if isConfirming {
                            PlanLight(tint: Ink.ground)
                                .padding(.trailing, 14)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .animation(Metrics.shift, value: isConfirming)
    }

    private func handleTap() {
        let willDisplay = !isDisplayed
        libraryStore.setDisplayedBadge(willDisplay ? badge.id : nil)

        // Retirer un badge n'a pas besoin de mise en scène : seule la sélection
        // d'un nouveau badge mérite la confirmation et le retour au profil.
        guard willDisplay else {
            Haptics.impact(.light)
            dismiss()
            return
        }

        Haptics.success()
        withAnimation(Metrics.shift) { isConfirming = true }

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
