//
//  SagaSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// La feuille de saga — ce qui se passe juste après un « vu » sur un premier
/// opus.
///
/// **C'est la pièce qui fait gagner le plus de temps de toute l'application.**
/// Un balayage à droite range un film ; celui-ci peut en ranger huit. Quelqu'un
/// qui a vu le premier Harry Potter a presque toujours vu les sept autres, et
/// les lui demander un par un coûte sept cartes pour une information qu'il
/// donne en un tap.
///
/// Trois décisions tiennent le dessin :
///
/// - **Rien n'est coché d'avance.** L'app n'écrit jamais ce que personne n'a
///   dit. Le cas majoritaire — tout vu — est servi par l'action principale,
///   pas par des cases pré-remplies qu'il faudrait décocher.
/// - **Ce qui n'est pas coché est une réponse, pas un silence.** Valider dit
///   donc deux choses à la fois : ceux-là je les ai vus, les autres non. Les
///   non-cochés passent en retrait comme un « pas vu » du deck, et la saga ne
///   revient plus la poser.
/// - **Elle ne parle pas une langue à elle.** Un « vu » posé ici est le même
///   événement qu'un balayage à droite : la feuille envoie des décisions de
///   deck, et c'est tout.
struct SagaSheet: View {
    let collectionID: Int
    /// Le film qui vient d'être rangé. Il est acquis même si la bibliothèque ne
    /// le sait pas encore : le deck envoie ses décisions par paquets, et la
    /// feuille s'ouvre bien avant que Firestore ait rendu la main.
    let originTmdbID: Int
    let originTitle: String
    let onClose: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var saga: Saga?
    @State private var selection: Set<Int> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client: any SagaFetching = BackendSagaClient()
    private let recorder: any SwipeFeedFetching = BackendSwipeFeedClient()

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(headerTitle, leading: .close, onLeading: onClose)

                if isLoading {
                    loadingState
                } else if let errorMessage, saga == nil {
                    failureState(errorMessage)
                } else if selectable.isEmpty {
                    completeState
                } else {
                    content
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private var headerTitle: String {
        saga?.displayName ?? String(localized: "La saga", bundle: .app)
    }

    // MARK: - Les opus

    /// Les autres opus, celui qu'on vient de ranger retiré : il est déjà dit
    /// dans la phrase d'en-tête, et une ligne cochée d'office qu'on ne peut pas
    /// décocher n'apprend rien.
    private var others: [SagaPart] {
        (saga?.parts ?? []).filter { $0.tmdbId != originTmdbID }
    }

    /// Ce qui est déjà en galerie : montré, mais pas à cocher.
    private var ownedIDs: Set<Int> {
        Set(libraryStore.galleryItems.map(\.tmdbId))
    }

    private var selectable: [SagaPart] {
        others.filter { !ownedIDs.contains($0.tmdbId) }
    }

    // MARK: - Contenu

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "Tu as vu « \(originTitle) ». Coche ceux que tu as vus aussi, ils entrent dans ta galerie.", bundle: .app))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.margin)
                        .padding(.bottom, 18)

                    ForEach(others) { part in
                        row(part)
                        PlanEdge().padding(.horizontal, Metrics.margin)
                    }

                    if let errorMessage {
                        HStack(alignment: .top, spacing: 11) {
                            PlanLight(tint: Ink.warn).padding(.top, 6)
                            Text(errorMessage)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Ink.warn)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Metrics.margin)
                        .padding(.top, 18)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
            }

            floor
        }
    }

    private func row(_ part: SagaPart) -> some View {
        let isOwned = ownedIDs.contains(part.tmdbId)
        let isOn = selection.contains(part.tmdbId)

        return Button {
            guard !isOwned, !isSaving else { return }
            Haptics.selection()
            withAnimation(Metrics.shift) {
                if isOn {
                    selection.remove(part.tmdbId)
                } else {
                    selection.insert(part.tmdbId)
                }
            }
        } label: {
            HStack(spacing: 12) {
                PosterTile(
                    posterPath: part.posterPath,
                    title: part.title,
                    width: 34
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(part.title)
                        .font(.system(size: 13.5, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(verbatim: part.displayYear)
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                }

                Spacer(minLength: 8)

                mark(isOwned: isOwned, isOn: isOn)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 9)
            // Le fond levé double le point : à 6 pt, le signe seul ne porte pas
            // une case à cocher, et c'est le remplissage qui doit se lire d'un
            // coup d'œil sur une liste de huit lignes.
            .background(isOn ? Ink.ground2 : .clear)
            .contentShape(Rectangle())
            .opacity(isOwned ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isOwned || isSaving)
        .accessibilityLabel(Text(verbatim: "\(part.title) \(part.displayYear)"))
        .accessibilityValue(
            isOwned
                ? String(localized: "Déjà dans ta galerie", bundle: .app)
                : (isOn ? String(localized: "Coché", bundle: .app) : "")
        )
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Le vocabulaire commun : point plein pour ce qui est acquis, point creux
    /// pour ce qui est prévu, rien pour ce qui n'a pas été dit.
    @ViewBuilder
    private func mark(isOwned: Bool, isOn: Bool) -> some View {
        if isOwned || isOn {
            PlanLight()
        } else {
            Rectangle()
                .strokeBorder(Ink.ink3, lineWidth: 1)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Le plancher

    private var floor: some View {
        VStack(spacing: 4) {
            PlanEdge().padding(.bottom, 12)

            PlanButton(
                title: primaryTitle,
                loadingTitle: String(localized: "Enregistrement…", bundle: .app),
                isLoading: isSaving,
                isEnabled: !selectable.isEmpty,
                height: Metrics.control
            ) {
                let ticked = selection.isEmpty ? selectable :
                    selectable.filter { selection.contains($0.tmdbId) }
                let rest = selection.isEmpty ? [] :
                    selectable.filter { !selection.contains($0.tmdbId) }
                submit(seen: ticked, skipped: rest)
            }

            // Toujours à sa place, pour que le bas de la feuille ne bouge pas
            // pendant qu'on coche.
            Button {
                submit(seen: [], skipped: selectable)
            } label: {
                Text("Je n'en ai vu aucun", bundle: .app)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .opacity(isSaving ? 0.4 : 1)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 8)
    }

    /// Le libellé dit toujours ce qui va être écrit, et rien d'autre.
    private var primaryTitle: String {
        let ticked = selection.intersection(Set(selectable.map(\.tmdbId))).count
        if ticked == 0 {
            return selectable.count == 1
                ? String(localized: "Je l'ai vu aussi", bundle: .app)
                : String(localized: "J'ai vu les \(selectable.count)", bundle: .app)
        }
        return ticked == 1
            ? String(localized: "Ajouter 1 film", bundle: .app)
            : String(localized: "Ajouter \(ticked) films", bundle: .app)
    }

    // MARK: - États

    private var loadingState: some View {
        VStack(spacing: 14) {
            CinechillSpinner(size: 26)
            Text("Chargement…", bundle: .app)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlanEmptyState(
                icon: .salle,
                title: String(localized: "La saga n'est pas venue", bundle: .app),
                message: message,
                actionTitle: String(localized: "Fermer", bundle: .app),
                action: onClose
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
    }

    /// Toute la saga est déjà rangée. Ce n'est pas un état vide : c'est une
    /// bonne nouvelle, et la dire évite de se demander pourquoi la feuille
    /// s'est ouverte.
    private var completeState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlanEmptyState(
                icon: .hall,
                title: String(localized: "Tu as toute la saga", bundle: .app),
                message: String(localized: "Elle est entière dans ta galerie.", bundle: .app),
                actionTitle: String(localized: "Fermer", bundle: .app),
                action: onClose
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
    }

    // MARK: - Chargement et écriture

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            saga = try await client.saga(id: collectionID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Les deux issues partent dans le même appel : « j'ai vu ceux-là » et « pas
    /// les autres » sont une seule phrase, et elles doivent être écrites
    /// ensemble ou pas du tout.
    private func submit(seen: [SagaPart], skipped: [SagaPart]) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let decisions = seen.map { PendingSwipe(card: $0.swipeCard, decision: .seen) }
            + skipped.map { PendingSwipe(card: $0.swipeCard, decision: .skipped) }

        Task {
            do {
                // `recordSwipes` plafonne le nombre de décisions par appel :
                // une saga de plus de quarante opus n'existe pas, mais le
                // découpage ne coûte rien et ne mentira jamais.
                for chunk in decisions.chunked(into: 40) {
                    try await recorder.record(chunk)
                }
                if !seen.isEmpty { Haptics.success() }
                isSaving = false
                onClose()
            } catch {
                isSaving = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

/// Ce qu'il faut pour ouvrir la feuille, et qui sert de déclencheur à
/// `sheet(item:)`.
struct SagaOffer: Identifiable, Equatable {
    let collectionID: Int
    let tmdbID: Int
    let title: String

    var id: Int { collectionID }
}
