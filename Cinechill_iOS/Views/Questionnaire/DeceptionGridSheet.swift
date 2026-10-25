//
//  DeceptionGridSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// La planche « Lesquels n'as-tu pas aimés ? » — l'étape « Tes déceptions »
/// de la Porte.
///
/// La carte des goûts lit un « vu » comme un petit oui, et presque toute la
/// galerie vient du deck, qui ne distingue pas « vu et aimé » de « vu et
/// détesté ». Le serveur montre ici les films vus que le moteur croit le plus
/// aimés : c'est là qu'une déception cachée le trompe le plus.
///
/// Rien n'est coché d'avance. Un film touché devient « Pas aimé » ; un film
/// laissé tel quel n'est pas écrit, il dit seulement qu'il n'a pas déçu.
/// « Je les ai tous aimés » est une réponse, et l'étape compte les films
/// passés en revue, jamais les déceptions : personne n'a à en inventer.
struct DeceptionGridSheet: View {
    let onClose: () -> Void

    @Environment(DoorStore.self) private var doorStore

    @State private var films: [DeceptionFilm] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadFailed = false
    @State private var saveFailed = false
    /// Films passés en revue pendant cette ouverture, pour enchaîner la
    /// planche suivante sans attendre la remesure de la Porte.
    @State private var reviewedHere = 0

    private let client = DeceptionClient()

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
        count: 3
    )

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(
                    String(localized: "Lesquels n'as-tu pas aimés ?", bundle: .app),
                    leading: .none
                ) {
                    if let progress {
                        PlanHeaderCount(value: progress)
                    }
                }
                .padding(.top, 14)

                if isLoading {
                    loadingState
                } else if loadFailed || films.isEmpty {
                    failureState
                } else {
                    content
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private var artifact: DoorArtifact? {
        doorStore.door(for: .film).artifact(.deceptions)
    }

    /// « 12 sur 24 » : où en est l'étape, pour que la question dise pourquoi
    /// elle est posée.
    private var progress: String? {
        guard let artifact else { return nil }
        let current = min(artifact.current + reviewedHere, artifact.target)
        return String(localized: "\(current) sur \(artifact.target)", bundle: .app)
    }

    // MARK: - Contenu

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Touche ceux qui t'ont déçu. On ne te proposera plus de films comme eux.", bundle: .app)
                        .planFont(12.5)
                        .foregroundStyle(Ink.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: Self.columns, spacing: 8) {
                        ForEach(films) { film in
                            tile(film)
                        }
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.vertical, 20)
            }

            floor
        }
    }

    private func tile(_ film: DeceptionFilm) -> some View {
        let isOn = selection.contains(film.id)
        return Button {
            withAnimation(Metrics.shift) {
                if isOn {
                    selection.remove(film.id)
                } else {
                    selection.insert(film.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterFrame(posterPath: film.posterPath, title: film.title)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Ink.ink, lineWidth: isOn ? 2 : 0)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if isOn {
                            PosterPlate(text: String(localized: "Pas aimé", bundle: .app))
                                .transition(.opacity)
                        }
                    }
                    // L'affiche touchée s'éteint : elle sort de ce qu'on aime.
                    .opacity(isOn ? 0.55 : 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(film.title)
                        .planFont(11, weight: isOn ? .semibold : .regular)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: film.displayYear)
                        .planFont(10.5)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Même plafond que les autres planches : trois colonnes d'un
                // tiers d'écran ne tiennent plus un titre au-delà.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(isSaving)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityTitle(film)))
        .accessibilityValue(isOn ? String(localized: "Pas aimé", bundle: .app) : "")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
    }

    /// L'année inconnue se tait : VoiceOver lisait « tiret ».
    private func accessibilityTitle(_ film: DeceptionFilm) -> String {
        guard let date = film.releaseDate, date.count >= 4 else { return film.title }
        return "\(film.title), \(film.displayYear)"
    }

    // MARK: - Le plancher

    private var floor: some View {
        VStack(spacing: 0) {
            PlanEdge().padding(.bottom, 12)
            if saveFailed {
                Text("Pas enregistré. Vérifie ta connexion et réessaie.", bundle: .app)
                    .planFont(12)
                    .foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }
            PlanButton(
                title: primaryTitle,
                loadingTitle: String(localized: "Enregistrement…", bundle: .app),
                isLoading: isSaving,
                height: Metrics.control
            ) {
                Task { await submit() }
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 8)
    }

    /// Le libellé dit ce qui va être écrit.
    private var primaryTitle: String {
        switch selection.count {
        case 0: String(localized: "Je les ai tous aimés", bundle: .app)
        case 1: String(localized: "1 film ne m'a pas plu", bundle: .app)
        default: String(localized: "\(selection.count) films ne m'ont pas plu", bundle: .app)
        }
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

    private var failureState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlanEmptyState(
                icon: .salle,
                title: loadFailed
                    ? String(localized: "Impossible de charger les films", bundle: .app)
                    : String(localized: "Plus rien à passer en revue", bundle: .app),
                message: loadFailed
                    ? String(localized: "Vérifie ta connexion et réessaie.", bundle: .app)
                    : String(localized: "Tous les films de ta galerie ont été vus ici.", bundle: .app),
                actionTitle: loadFailed ? String(localized: "Réessayer", bundle: .app) : String(localized: "Fermer", bundle: .app),
                action: loadFailed ? { Task { await load() } } : onClose,
                secondaryTitle: loadFailed ? String(localized: "Fermer", bundle: .app) : nil,
                secondaryAction: loadFailed ? onClose : nil
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
    }

    // MARK: - Chargement et écriture

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            films = try await client.grid()
            selection = []
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }

    /// Écrit la planche, puis enchaîne la suivante tant que l'étape n'est pas
    /// faite : deux planches de douze, sans repasser par la Porte.
    private func submit() async {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }

        let shown = films.map(\.tmdbId)
        let disliked = films.filter { selection.contains($0.id) }.map(\.tmdbId)
        do {
            try await client.record(shown: shown, disliked: disliked)
        } catch {
            saveFailed = true
            return
        }
        Haptics.success()
        reviewedHere += shown.count
        let done = artifact.map { $0.current + reviewedHere >= $0.target } ?? true
        Task { await doorStore.refresh() }
        if done {
            onClose()
        } else {
            await load()
            if films.isEmpty { onClose() }
        }
    }
}
