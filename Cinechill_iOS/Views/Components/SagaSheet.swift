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
/// - **Ne pas cocher n'est pas répondre.** Ne pas cocher, c'est souvent ne pas
///   avoir pris le temps : les non-cochés restent comme ils sont, et la feuille
///   le dit. Seul « Je n'en ai vu aucun » écrit des « pas vu ».
/// - **La sélection se dit à l'encre, l'acquis à la lumière.** Une case cochée
///   prend l'aplat d'encre du système ; le point de lumière reste aux opus déjà
///   en galerie, et à eux seuls.
/// - **Elle ne parle pas une langue à elle.** Un « vu » posé ici est le même
///   événement qu'un balayage à droite : la feuille envoie des décisions de
///   deck, et c'est tout.
struct SagaSheet: View {
    let offer: SagaOffer
    let onClose: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var saga: Saga?
    @State private var selection: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client: any SagaFetching = BackendSagaClient()
    private let tvClient = TVClient()
    private let recorder: any SwipeFeedFetching = BackendSwipeFeedClient()

    private var isSeries: Bool {
        if case .series = offer.source { return true }
        return false
    }

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
        saga?.displayName ?? (isSeries ? offer.title : String(localized: "La saga", bundle: .app))
    }

    // MARK: - Les opus

    /// Les autres opus, celui qu'on vient de ranger retiré : il est déjà dit
    /// dans la phrase d'en-tête, et une ligne cochée d'office qu'on ne peut pas
    /// décocher n'apprend rien.
    private var others: [SagaPart] {
        (saga?.parts ?? []).filter { $0.libraryID != offer.originID }
    }

    /// Ce qui est déjà en galerie : montré, mais pas à cocher. Par identifiant
    /// de bibliothèque, jamais par `tmdbId` seul.
    private var ownedIDs: Set<String> {
        Set(libraryStore.galleryItems.map(\.id))
    }

    private var selectable: [SagaPart] {
        others.filter { !ownedIDs.contains($0.libraryID) }
    }

    // MARK: - Contenu

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(introduction)
                        .planFont(12.5)
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
                                .planFont(12.5)
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

    private var introduction: String {
        isSeries
            ? String(localized: "Tu as vu la saison 1. Coche celles que tu as vues aussi, elles entrent dans ta galerie.", bundle: .app)
            : String(localized: "Tu as vu « \(offer.title) ». Coche ceux que tu as vus aussi, ils entrent dans ta galerie.", bundle: .app)
    }

    private func row(_ part: SagaPart) -> some View {
        let isOwned = ownedIDs.contains(part.libraryID)
        let isOn = selection.contains(part.libraryID)

        return Button {
            guard !isOwned, !isSaving else { return }
            Haptics.selection()
            withAnimation(Metrics.shift) {
                if isOn {
                    selection.remove(part.libraryID)
                } else {
                    selection.insert(part.libraryID)
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
                        .planFont(13.5, weight: isOn ? .semibold : .regular)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(verbatim: part.displayYear)
                        .planFont(10.5)
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

    /// Ce qui est déjà en galerie porte le point de lumière, le seul signe
    /// d'« acquis ». Une case, elle, se coche à l'encre : le système dit qu'une
    /// sélection se dit à l'encre, et le point de lumière ne s'allume pas plus
    /// de deux fois par écran. Vide ou pleine, la case garde sa taille.
    @ViewBuilder
    private func mark(isOwned: Bool, isOn: Bool) -> some View {
        if isOwned {
            PlanLight()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isOn ? Ink.ink : .clear)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(isOn ? Ink.ink : Ink.ink3, lineWidth: 1)
                if isOn {
                    SagaCheckGlyph()
                        .stroke(Ink.ground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .padding(3)
                }
            }
            .frame(width: 14, height: 14)
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
                    selectable.filter { selection.contains($0.libraryID) }
                // Ce qui n'est pas coché n'est pas écrit : ne pas cocher n'est
                // pas répondre.
                submit(seen: ticked, skipped: [])
            }

            // Le seul effet de la validation, dit avant qu'on valide.
            if !selection.isEmpty {
                Text(isSeries
                     ? String(localized: "Celles que tu ne coches pas restent comme elles sont.", bundle: .app)
                     : String(localized: "Ceux que tu ne coches pas restent comme ils sont.", bundle: .app))
                    .planFont(11.5)
                    .foregroundStyle(Ink.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .transition(.opacity)
            }

            // Toujours à sa place, pour que le bas de la feuille ne bouge pas
            // pendant qu'on coche.
            Button {
                if isSeries {
                    onClose()
                } else {
                    submit(seen: [], skipped: selectable)
                }
            } label: {
                Text(isSeries
                     ? String(localized: "Je n'ai vu que la première", bundle: .app)
                     : String(localized: "Je n'en ai vu aucun", bundle: .app))
                    .planFont(13, weight: .medium)
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
        let ticked = selection.intersection(Set(selectable.map(\.libraryID))).count
        if ticked == 0 {
            if selectable.count == 1 {
                return isSeries
                    ? String(localized: "Je l'ai vue aussi", bundle: .app)
                    : String(localized: "Je l'ai vu aussi", bundle: .app)
            }
            return String(localized: "J'ai vu les \(selectable.count)", bundle: .app)
        }
        if isSeries {
            return ticked == 1
                ? String(localized: "Ajouter 1 saison", bundle: .app)
                : String(localized: "Ajouter \(ticked) saisons", bundle: .app)
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
                .planFont(12.5)
                .foregroundStyle(Ink.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlanEmptyState(
                icon: .salle,
                title: isSeries
                    ? String(localized: "La série n'a pas pu se charger", bundle: .app)
                    : String(localized: "La saga n'a pas pu se charger", bundle: .app),
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
                title: isSeries
                    ? String(localized: "Tu as toutes ses saisons", bundle: .app)
                    : String(localized: "Tu as toute la saga", bundle: .app),
                message: isSeries
                    ? String(localized: "Elles sont toutes dans ta galerie.", bundle: .app)
                    : String(localized: "Elle est entière dans ta galerie.", bundle: .app),
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
            switch offer.source {
            case .collection(let id):
                saga = try await client.saga(id: id)
            case .series(let id):
                saga = sagaOfSeasons(try await tvClient.series(id: id))
            }
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

    /// Une série est une saga de saisons : ses saisons sorties, chacune comme
    /// un opus.
    private func sagaOfSeasons(_ series: TVSeriesDetail) -> Saga {
        Saga(
            id: series.id,
            name: series.name,
            parts: series.seasons.filter(\.isReleased).map { season in
                SagaPart(
                    tmdbId: series.id,
                    title: String(localized: "Saison \(season.number)", bundle: .app),
                    posterPath: season.posterPath ?? series.posterPath,
                    overview: nil,
                    voteAverage: season.voteAverage,
                    voteCount: nil,
                    genreIds: series.genreIds,
                    releaseDate: season.airDate,
                    season: season.number,
                    seriesName: series.name
                )
            }
        )
    }
}

/// D'où vient la feuille : la saga d'un film, ou les saisons d'une série.
enum SagaSource: Hashable {
    case collection(Int)
    case series(Int)
}

/// Ce qu'il faut pour ouvrir la feuille, et qui sert de déclencheur à
/// `sheet(item:)`.
struct SagaOffer: Identifiable, Equatable {
    let source: SagaSource
    /// L'identifiant de bibliothèque de ce qui vient d'être rangé
    /// (`movie-671`, `tv-1399-s1`). Il est acquis même si la bibliothèque ne
    /// le sait pas encore : le deck envoie ses décisions par paquets, et la
    /// feuille s'ouvre bien avant que Firestore ait rendu la main.
    let originID: String
    /// Le titre du film rangé, ou le nom de la série.
    let title: String

    var id: String {
        switch source {
        case .collection(let id): "collection-\(id)"
        case .series(let id): "series-\(id)"
        }
    }
}


/// La coche, dans l'écriture de la famille d'icônes.
private struct SagaCheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
