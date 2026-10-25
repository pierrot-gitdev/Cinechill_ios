//
//  TasteGridSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// Ce qu'une planche de goût demande.
nonisolated enum TasteGridKind: String, Identifiable, Hashable, Sendable {
    /// « Quels films as-tu adorés ? » : l'étape Coups de cœur de la Porte.
    case loved
    /// « Lesquels n'as-tu pas aimés ? » : l'étape Déceptions.
    case disliked

    var id: Self { self }
}

/// La planche de goût : douze films de la galerie, on touche ceux qu'on a
/// adorés, ou ceux qui ont déçu, puis on enregistre.
///
/// **Une seule planche par question, où qu'on la pose.** Il y en avait trois,
/// chacune avec sa manière : celle de Découvrir où l'on touchait puis
/// validait, celle de la Porte où chaque toucher écrivait sur une grille de
/// toute la galerie, et celle des déceptions avec son « Je les ai tous
/// aimés ». La même question a désormais le même écran et le même geste :
/// - **on touche**, rien n'est coché d'avance ;
/// - **un seul bouton** : « Aucun coup de cœur ici » ou « Aucune déception
///   ici » tant que rien n'est touché, « Enregistrer » ensuite. Il attend le serveur avant de passer à la suite
///   ou de refermer, et dit l'échec s'il y en a un ;
/// - **les films ne reviennent pas** d'une planche à l'autre : un film montré
///   a reçu sa réponse, même laissé tel quel ;
/// - **« Aucun … ici » appelle une autre page** : ces douze films n'ont rien
///   appris, au plus trois pages vides d'affilée.
///
/// Le serveur compose chaque page (`getTasteGrid`) : une saga par page, plus
/// aucune saga dont un film a déjà sa réponse, un genre par case. Les coups
/// de cœur viennent des mieux notés, les déceptions des films que la carte
/// croit le plus aimés.
///
/// Ouverte depuis la Porte, la planche enchaîne les pages jusqu'à ce que
/// l'étape soit faite. Proposée par Découvrir, elle tient en une page : on y
/// est venu pour balayer.
struct TasteGridSheet: View {
    let kind: TasteGridKind
    var format: MediaFormat = .film
    /// Une seule page (Découvrir), ou jusqu'à l'étape faite (la Porte).
    var singlePage = false
    /// Appelé à la fermeture, avec le nombre de films touchés et enregistrés.
    let onClose: (Int) -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(DoorStore.self) private var doorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var items: [TasteGridItem] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var saveFailed = false
    /// Films touchés et enregistrés depuis l'ouverture.
    @State private var savedHere = 0
    /// Films passés en revue depuis l'ouverture (déceptions).
    @State private var reviewedHere = 0
    /// Le compte du serveur à l'ouverture. Ajouter `reviewedHere` à un compte
    /// déjà rafraîchi comptait deux fois la page enregistrée.
    @State private var reviewedAtOpen: Int?
    /// Pages laissées vides d'affilée depuis l'ouverture.
    @State private var emptyStreak = 0

    /// Affiches d'une page, pour les deux questions.
    static let pageSize = 12

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
        count: 3
    )

    var body: some View {
        VStack(spacing: 0) {
            header

            if isLoading {
                loadingState
            } else if loadFailed || items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 10) {
                        ForEach(items) { item in
                            tile(item)
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
                floor
            }
        }
        .background(Ink.ground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Une sélection ne part pas d'un glissement du doigt : elle
        // s'enregistre, ou se défait.
        .interactiveDismissDisabled(!selection.isEmpty || isSaving)
        .task { await load() }
    }

    // MARK: - Les mots

    private var artifactKey: DoorArtifactKey { kind == .loved ? .coeur : .deceptions }
    /// La teinte des mots et de la jauge : le halo du médaillon. Sa teinte
    /// d'émail, trop sombre sur la nuit, ne passait pas le contraste d'un texte
    /// de 10 points. L'émail reste pour le filet d'une affiche adorée.
    private var tint: Color { Color(hex: artifactKey.halo) }
    private var isSeries: Bool { kind == .loved && format == .series }

    private var title: String {
        switch kind {
        case .loved:
            isSeries
                ? String(localized: "Quelles saisons as-tu adorées ?", bundle: .app)
                : String(localized: "Quels films as-tu adorés ?", bundle: .app)
        case .disliked:
            String(localized: "Lesquels n'as-tu pas aimés ?", bundle: .app)
        }
    }

    /// La réponse quand rien n'est touché : rien n'est écrit sur ces films,
    /// la page est seulement passée en revue.
    private var emptyAnswer: String {
        switch kind {
        case .loved: String(localized: "Aucun coup de cœur ici", bundle: .app)
        case .disliked: String(localized: "Aucune déception ici", bundle: .app)
        }
    }

    private var instruction: String {
        switch kind {
        case .loved:
            String(localized: "Touche ceux que tu as adorés. On s'en sert d'abord pour te proposer des films.", bundle: .app)
        case .disliked:
            String(localized: "Touche ceux qui t'ont déçu. On ne te proposera plus de films comme eux.", bundle: .app)
        }
    }

    // MARK: - L'étape

    private var artifact: DoorArtifact? {
        doorStore.door(for: kind == .loved ? format : .film).artifact(artifactKey)
    }

    private var target: Int { artifact?.target ?? (kind == .loved ? 12 : 24) }

    /// Où en est l'étape, enregistrements de cette planche compris.
    private var current: Int {
        switch kind {
        case .loved:
            isSeries ? libraryStore.lovedSeasonCount : libraryStore.lovedCount
        case .disliked:
            max(artifact?.current ?? 0, (reviewedAtOpen ?? artifact?.current ?? 0) + reviewedHere)
        }
    }

    private var isStepDone: Bool { current >= target }

    // MARK: - L'en-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(artifactKey.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .shadow(color: Color(hex: artifactKey.halo).opacity(0.35), radius: 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(artifactKey.displayName)
                        .planLabel()
                        .foregroundStyle(tint)
                    Text(title)
                        .planTitle(24)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Text(instruction)
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            HStack(spacing: 12) {
                PlanProgressRule(fraction: target > 0 ? min(1, Double(current) / Double(target)) : 0)
                Text(String(localized: "\(min(current, target)) sur \(target)", bundle: .app))
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                    .contentTransition(.numericText())
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, Metrics.margin)
        // Sous la poignée de la feuille, que l'en-tête ne doit pas toucher.
        .padding(.top, 26)
        .padding(.bottom, 4)
        .animation(Metrics.shift, value: current)
    }

    // MARK: - Une affiche

    private func tile(_ item: TasteGridItem) -> some View {
        let isOn = selection.contains(item.id)
        return Button {
            withAnimation(Metrics.shift) {
                if isOn { selection.remove(item.id) } else { selection.insert(item.id) }
            }
            saveFailed = false
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterFrame(posterPath: item.posterPath, title: item.title)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(kind == .loved ? Color(hex: artifactKey.hue) : Ink.ink, lineWidth: isOn ? 2 : 0)
                    }
                    .overlay(alignment: .topLeading) {
                        if let season = item.season {
                            PosterPlate(text: String(localized: "Saison \(season)", bundle: .app))
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isOn, kind == .loved {
                            Image(DoorArtifactKey.coeur.assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .padding(5)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if isOn, kind == .disliked {
                            PosterPlate(text: String(localized: "Pas aimé", bundle: .app))
                                .transition(.opacity)
                        }
                    }
                    // Une déception s'éteint : elle sort de ce qu'on aime.
                    .opacity(isOn && kind == .disliked ? 0.55 : 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .planFont(11, weight: isOn ? .semibold : .regular)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: item.displayYear)
                        .planFont(10.5)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Trois colonnes d'un tiers d'écran ne tiennent plus un titre
                // au-delà.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(isSaving)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.accessibilityTitle))
        .accessibilityValue(isOn
            ? (kind == .loved ? String(localized: "Coup de cœur", bundle: .app) : String(localized: "Pas aimé", bundle: .app))
            : "")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Le plancher

    private var floor: some View {
        VStack(spacing: 0) {
            PlanEdge().padding(.bottom, 10)
            Group {
                if isStepDone {
                    Text("C'est fait, l'étape est validée.", bundle: .app)
                        .foregroundStyle(tint)
                } else {
                    Text("Encore \(target - current) pour valider l'étape.", bundle: .app)
                        .foregroundStyle(Ink.ink2)
                }
            }
            .planFont(12.5)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)

            if saveFailed {
                Text("Pas enregistré. Vérifie ta connexion et réessaie.", bundle: .app)
                    .planFont(12)
                    .foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }

            PlanButton(
                // Le bouton dit ce qu'il enregistre. « Aucun de ceux-là » se
                // lisait des deux façons pour les déceptions : « aucun ne m'a
                // déçu », ou « tous m'ont déçu ».
                title: selection.isEmpty ? emptyAnswer : String(localized: "Enregistrer", bundle: .app),
                loadingTitle: String(localized: "Enregistrement…", bundle: .app),
                isLoading: isSaving,
                height: Metrics.control
            ) {
                Task { await validate() }
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 8)
        .animation(Metrics.shift, value: saveFailed)
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

    private var emptyState: some View {
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
                action: loadFailed ? { Task { await load() } } : { onClose(savedHere) },
                secondaryTitle: loadFailed ? String(localized: "Fermer", bundle: .app) : nil,
                secondaryAction: loadFailed ? { onClose(savedHere) } : nil
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
    }

    // MARK: - Chargement et écriture

    private func load() async {
        isLoading = true
        loadFailed = false
        selection = []
        defer { isLoading = false }
        if reviewedAtOpen == nil { reviewedAtOpen = artifact?.current ?? 0 }
        let offered = kind == .loved
            ? UserDefaults.standard.stringArray(forKey: Self.lovedOfferedKey) ?? []
            : []
        do {
            let client = TasteGridClient()
            let format: MediaFormat = isSeries ? .series : .film
            var films = try await client.grid(kind: kind, format: format, excluding: offered)
            // Tous les films déjà montrés : l'étape des cœurs ne doit pas
            // rester sans planche. La liste repart de zéro, ce qui n'a pas reçu
            // de cœur peut revenir.
            if films.isEmpty, kind == .loved, !offered.isEmpty, !isStepDone {
                UserDefaults.standard.removeObject(forKey: Self.lovedOfferedKey)
                films = try await client.grid(kind: kind, format: format, excluding: [])
            }
            items = films.map(TasteGridItem.init(film:))
            // Proposée par Découvrir, une planche vide ne s'ouvre pas : elle
            // se referme sans un mot, et compte comme restée vide.
            if items.isEmpty, singlePage {
                Self.recordPage(kind, empty: true)
                onClose(savedHere)
            }
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }

    /// Écrit la page, puis enchaîne la suivante tant que l'étape n'est pas
    /// faite, ou referme.
    private func validate() async {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }

        let picked = items.filter { selection.contains($0.id) }
        let shownIDs = items.map(\.id)
        switch kind {
        case .loved:
            let changes = picked.compactMap { item in
                libraryStore.galleryItems.first { $0.id == item.id }.map { (item: $0.mediaItem, loved: true) }
            }
            if !changes.isEmpty {
                let saved = await libraryStore.saveLoves(changes)
                guard saved else {
                    saveFailed = true
                    return
                }
            }
        case .disliked:
            do {
                try await TasteGridClient().record(
                    shown: items.map(\.tmdbId),
                    disliked: picked.map(\.tmdbId)
                )
            } catch {
                saveFailed = true
                return
            }
            reviewedHere += items.count
            Task { await doorStore.refresh() }
        }

        // Montrés et répondus : ces films ne reviennent plus. Marqués au
        // chargement, une planche baissée du doigt les brûlait sans réponse.
        if kind == .loved { Self.rememberOffered(shownIDs) }
        if !picked.isEmpty { Haptics.success() }
        savedHere += picked.count
        emptyStreak = picked.isEmpty ? emptyStreak + 1 : 0
        Self.recordPage(kind, empty: picked.isEmpty)

        // Une page vide appelle une autre page, trois au plus d'affilée. Une
        // page enregistrée referme la planche de Découvrir ; depuis la Porte,
        // les pages s'enchaînent jusqu'à l'étape faite.
        let another = !isStepDone && emptyStreak < 3 && (!singlePage || picked.isEmpty)
        guard another else {
            onClose(savedHere)
            return
        }
        await load()
    }

    // MARK: - La mémoire des planches

    /// Les films déjà montrés dans une planche des coups de cœur : ils ont eu
    /// leur réponse. Une clé de compte (voir `LibraryStore.adoptAccount`).
    static let lovedOfferedKey = "swipe.loveGrid.offered"

    private static func emptyPagesKey(_ kind: TasteGridKind) -> String { "taste.emptyPages.\(kind.rawValue)" }

    /// Les clés de compte des planches, effacées quand un autre compte se
    /// connecte.
    static var accountScopedKeys: [String] {
        [lovedOfferedKey] + [TasteGridKind.loved, .disliked].map { emptyPagesKey($0) }
    }

    /// Pages laissées vides d'affilée pour cette question, toutes ouvertures
    /// confondues. Deux de suite : Découvrir la repose moins souvent.
    static func emptyPages(_ kind: TasteGridKind) -> Int {
        UserDefaults.standard.integer(forKey: emptyPagesKey(kind))
    }

    private static func recordPage(_ kind: TasteGridKind, empty: Bool) {
        UserDefaults.standard.set(empty ? emptyPages(kind) + 1 : 0, forKey: emptyPagesKey(kind))
    }

    /// La liste ne garde que les quatre cents derniers, de quoi couvrir la
    /// galerie.
    private static func rememberOffered(_ ids: [String]) {
        let offered = UserDefaults.standard.stringArray(forKey: lovedOfferedKey) ?? []
        UserDefaults.standard.set(Array((offered + ids).suffix(400)), forKey: lovedOfferedKey)
    }
}

/// Un film d'une planche de goût, d'où qu'il vienne : la galerie du
/// téléphone (coups de cœur) ou le serveur (déceptions).
struct TasteGridItem: Identifiable, Hashable {
    /// L'identifiant de bibliothèque (`movie-603`, `tv-1399-s2`).
    let id: String
    let tmdbId: Int
    let title: String
    let posterPath: String?
    let releaseDate: String?
    let season: Int?

    init(film: TasteFilm) {
        id = film.id
        tmdbId = film.tmdbId
        title = film.title
        posterPath = film.posterPath
        releaseDate = film.releaseDate
        season = film.season
    }

    var displayYear: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }

    /// L'année inconnue se tait : VoiceOver lisait « tiret ».
    var accessibilityTitle: String {
        guard let releaseDate, releaseDate.count >= 4 else { return title }
        return "\(title), \(displayYear)"
    }
}
