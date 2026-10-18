//
//  RecommendFilmSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// Recommander un film à quelqu'un, depuis son profil.
///
/// Le parcours inverse de `SuggestionComposerSheet` : la personne est déjà
/// choisie, on choisit le film. Seuls les films de sa galerie se proposent,
/// parce que le serveur n'accepte de recommandation que pour un film vu ; les
/// coups de cœur passent en tête, ce sont ceux qu'on a le plus envie de faire
/// voir.
///
/// Un seul film à la fois : on recommande un film à quelqu'un, pas une liste.
struct RecommendFilmSheet: View {
    let profile: PublicProfile
    /// Rapporte ce qui s'est réellement passé, pour le bandeau du profil.
    let onSent: (SuggestionOutcome) -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.dismiss) private var dismiss

    @State private var filter = ""
    @State private var selectedID: String?
    @State private var isSending = false

    /// Les coups de cœur d'abord, puis le plus récent : l'ordre dans lequel
    /// on pense à un film qu'on veut faire voir.
    private var films: [GalleryEntry] {
        libraryStore.galleryFilms
            .filter { !$0.isDisliked }
            .sorted {
                if $0.isLoved != $1.isLoved { return $0.isLoved }
                return $0.addedAt > $1.addedAt
            }
    }

    private var filtered: [GalleryEntry] {
        let needle = SocialStore.normalize(filter)
        guard !needle.isEmpty else { return films }
        return films.filter { SocialStore.normalize($0.title).contains(needle) }
    }

    private var selected: GalleryEntry? {
        films.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if films.isEmpty {
                    HallEmptyState(
                        icon: .recommander,
                        title: String(localized: "Ta galerie est vide", bundle: .app),
                        message: String(localized: "Ajoute les films que tu as vus pour pouvoir les recommander.", bundle: .app)
                    )
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.ground)
            .safeAreaInset(edge: .top) {
                PlanHeader(String(localized: "Recommander un film", bundle: .app), leading: .close)
            }
            .safeAreaInset(edge: .bottom) {
                if !films.isEmpty { sendBar }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Contenu

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if films.count > 8 {
                    HallSearchField(
                        placeholder: String(localized: "Chercher dans ta galerie", bundle: .app),
                        text: $filter
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                }

                if filtered.isEmpty {
                    Text("Aucun film de ta galerie ne correspond.", bundle: .app)
                        .planFont(13)
                        .foregroundStyle(Ink.ink2)
                        .padding(.horizontal, Metrics.margin)
                        .padding(.top, 12)
                } else {
                    ForEach(filtered) { entry in
                        row(entry)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Pour qui : l'avatar et le nom, comme sur le profil qu'on vient de
    /// quitter, pour qu'on ne se demande pas à qui part le film.
    private var header: some View {
        HStack(spacing: 12) {
            HallAvatar(seed: profile.id, initial: profile.initials, url: profile.avatarURL, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Pour \(profile.displayName)", bundle: .app))
                    .planTitle(17)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                Text("Choisis un film de ta galerie.", bundle: .app)
                    .planFont(12.5)
                    .foregroundStyle(Ink.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private func row(_ entry: GalleryEntry) -> some View {
        let isOn = selectedID == entry.id
        return Button {
            Haptics.impact(.light)
            selectedID = isOn ? nil : entry.id
        } label: {
            HStack(spacing: 12) {
                PosterTile(posterPath: entry.posterPath, title: entry.title, width: 40, cornerRadius: Metrics.radius)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .planFont(14.5, weight: .medium)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        if let year = entry.releaseDate.flatMap({ $0.count >= 4 ? String($0.prefix(4)) : nil }) {
                            Text(verbatim: year)
                                .monospacedDigit()
                        }
                        if entry.isLoved {
                            DetailHeartShape()
                                .fill(Color(hex: 0xC25562))
                                .frame(width: 10, height: 9)
                                .accessibilityHidden(true)
                        }
                    }
                    .planFont(12.5)
                    .foregroundStyle(Ink.ink2)
                }

                Spacer(minLength: 6)

                // La case retenue s'allume, comme dans la feuille qui part du
                // film : ce qui est choisi est acquis.
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Ink.ruleSet, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .fill(isOn ? Ink.light : Color.clear)
                    )
                    .frame(width: 20, height: 20)
                    .animation(Metrics.shift, value: isOn)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(entry.isLoved ? String(localized: "Coup de cœur", bundle: .app) : "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Envoi

    /// Le libellé dit exactement ce qui va partir, et à qui.
    private var sendBar: some View {
        VStack(spacing: 0) {
            PlanEdge()

            PlanButton(
                title: selected.map { String(localized: "Recommander « \($0.title) »", bundle: .app) }
                    ?? String(localized: "Choisis un film", bundle: .app),
                loadingTitle: String(localized: "Envoi…", bundle: .app),
                isLoading: isSending,
                isEnabled: selected != nil,
                height: Metrics.control
            ) {
                Haptics.impact(.medium)
                Task { await send() }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Ink.ground)
    }

    private func send() async {
        guard let entry = selected, !isSending else { return }
        isSending = true
        defer { isSending = false }

        let name = profile.displayName
        var outcome = SuggestionOutcome(film: entry.title, sent: [], alreadySeen: [], hadFailure: false)
        do {
            try await socialStore.sendSuggestion(to: profile.id, item: entry.mediaItem)
            outcome = SuggestionOutcome(film: entry.title, sent: [name], alreadySeen: [], hadFailure: false)
            Haptics.success()
            // Premier envoi : le bon moment pour proposer les notifications,
            // une fois cette feuille refermée.
            NotificationPermission.shared.offer(.firstSuggestion)
        } catch SocialError.targetAlreadySeen {
            outcome = SuggestionOutcome(film: entry.title, sent: [], alreadySeen: [name], hadFailure: false)
        } catch SocialError.alreadySuggested {
            // Déjà recommandé : le film est déjà chez la personne, ce n'est
            // pas un échec, c'est comme s'il était parti.
            outcome = SuggestionOutcome(film: entry.title, sent: [name], alreadySeen: [], hadFailure: false)
        } catch SocialError.dailyLimit {
            outcome = SuggestionOutcome(film: entry.title, sent: [], alreadySeen: [], hadFailure: false, hitDailyLimit: true)
        } catch is CancellationError {
            return
        } catch {
            outcome = SuggestionOutcome(film: entry.title, sent: [], alreadySeen: [], hadFailure: true)
        }
        onSent(outcome)
        dismiss()
    }
}
