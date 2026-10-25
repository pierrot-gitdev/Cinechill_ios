//
//  LoveGridSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// La planche des coups de cœur : neuf films de la galerie, « lesquels as-tu
/// adorés ? ».
///
/// Le double tap du deck reste, mais il demande d'y penser au moment où la
/// carte passe. Quand les coups de cœur prennent du retard sur les films vus,
/// Découvrir pose la question pour la personne, sur des films qu'elle vient de
/// ranger ou que tout le monde a bien notés : il suffit de toucher.
///
/// Rien n'est coché d'avance, et seul ce qui est touché s'écrit, par le même
/// chemin que l'écran des coups de cœur de la Porte (`LibraryStore.setLove`).
/// Ce chemin ne touche pas à la date d'ajout du film en galerie, ce que ferait
/// un nouveau « vu » envoyé par le deck.
struct LoveGridSheet: View {
    let offer: LoveGridOffer
    /// Appelé à la fermeture, avec le nombre de cœurs posés.
    let onFinish: (Int) -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(DoorStore.self) private var doorStore

    @State private var selection: Set<String> = []

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
        count: 3
    )

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(
                    String(localized: "Lesquels as-tu adorés ?", bundle: .app),
                    leading: .close,
                    onLeading: { onFinish(0) }
                ) {
                    if let progress {
                        PlanHeaderCount(value: progress)
                    }
                }
                // Un pas sous le bord de la feuille, que l'en-tête touchait.
                .padding(.top, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Touche ceux que tu as adorés. On s'en sert d'abord pour te proposer des films.", bundle: .app)
                            .planFont(12.5)
                            .foregroundStyle(Ink.ink2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        LazyVGrid(columns: Self.columns, spacing: 8) {
                            ForEach(offer.entries) { entry in
                                tile(entry)
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.vertical, 20)
                }

                floor
            }
        }
        .presentationDetents([.large])
    }

    /// « 3 sur 12 » : où en est l'étape des coups de cœur de la Porte, pour
    /// que la question dise pourquoi elle est posée.
    private var progress: String? {
        guard let coeur = doorStore.door(for: .film).artifact(.coeur) else { return nil }
        let current = max(coeur.current, libraryStore.lovedCount)
        return String(localized: "\(min(current, coeur.target)) sur \(coeur.target)", bundle: .app)
    }

    /// Une affiche à toucher, marquée comme dans l'écran des coups de cœur de
    /// la Porte : un filet à la teinte du cœur et son écusson dans le coin. Le
    /// titre et l'année restent lisibles sous l'affiche.
    private func tile(_ entry: GalleryEntry) -> some View {
        let isOn = selection.contains(entry.id)
        return Button {
            withAnimation(Metrics.shift) {
                if isOn {
                    selection.remove(entry.id)
                } else {
                    selection.insert(entry.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterFrame(posterPath: entry.posterPath, title: entry.title)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Self.loveTint, lineWidth: isOn ? 2 : 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isOn {
                            Image("ArtefactCoeur")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .padding(5)
                                .transition(.opacity)
                        }
                    }
                    .opacity(isOn || selection.isEmpty ? 1 : 0.72)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .planFont(11, weight: isOn ? .semibold : .regular)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: entry.mediaItem.displayYear)
                        .planFont(10.5)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Même plafond que la mosaïque : trois colonnes d'un tiers
                // d'écran ne tiennent plus un titre au-delà.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityTitle(entry)))
        .accessibilityValue(isOn ? String(localized: "Coup de cœur", bundle: .app) : "")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
    }

    /// L'année inconnue se tait : VoiceOver lisait « tiret ».
    private func accessibilityTitle(_ entry: GalleryEntry) -> String {
        guard let date = entry.releaseDate, date.count >= 4 else { return entry.title }
        return "\(entry.title), \(entry.mediaItem.displayYear)"
    }

    // MARK: - Le plancher

    private var floor: some View {
        VStack(spacing: 0) {
            PlanEdge().padding(.bottom, 12)
            PlanButton(title: primaryTitle, height: Metrics.control) {
                submit()
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 8)
    }

    /// Le libellé dit ce qui va être écrit.
    private var primaryTitle: String {
        switch selection.count {
        case 0: String(localized: "Aucun de ceux-là", bundle: .app)
        case 1: String(localized: "Ajouter 1 coup de cœur", bundle: .app)
        default: String(localized: "Ajouter \(selection.count) coups de cœur", bundle: .app)
        }
    }

    /// Chaque cœur part par le chemin de l'écran de la Porte. L'écran ne
    /// l'affiche qu'une fois confirmé par le serveur (pas d'optimisme) : la
    /// planche se referme sans rien prétendre de plus.
    private func submit() {
        let picked = offer.entries.filter { selection.contains($0.id) }
        for entry in picked {
            libraryStore.setLove(entry.mediaItem, loved: true)
        }
        if !picked.isEmpty { Haptics.success() }
        onFinish(picked.count)
    }

    /// La teinte du cœur, celle de l'écran des coups de cœur de la Porte.
    private static var loveTint: Color { Color(hex: 0xC25562) }
}

/// Les films d'une planche des coups de cœur.
struct LoveGridOffer: Identifiable, Equatable {
    let id = UUID()
    let entries: [GalleryEntry]

    /// Affiches d'une planche.
    static let size = 9

    /// Les films à proposer, dans l'ordre : ceux rangés pendant la session
    /// d'abord, encore frais en mémoire, puis les mieux notés. Jamais un film
    /// déjà marqué, « pas aimé », ou déjà proposé dans une planche précédente.
    ///
    /// - Parameters:
    ///   - films: films de la galerie.
    ///   - offered: films déjà montrés dans une planche des coups de cœur.
    ///   - sessionStart: début de la session de Découvrir.
    static func candidates(
        from films: [GalleryEntry],
        excluding offered: Set<String>,
        sessionStart: Date
    ) -> [GalleryEntry] {
        let open = films.filter {
            !$0.isLoved && $0.dislikedAt == nil && !offered.contains($0.id)
        }
        let byRating: (GalleryEntry, GalleryEntry) -> Bool = {
            ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0)
        }
        let recent = open.filter { $0.addedAt >= sessionStart }.sorted(by: byRating)
        let older = open.filter { $0.addedAt < sessionStart }.sorted(by: byRating)
        return Array((recent + older).prefix(size))
    }
}
