//
//  SessionEntryView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'entrée de CinéMatch : le mur, avec la première question dessus.
///
/// L'écran qu'elle remplace décrivait une procédure. Il posait une icône, un
/// paragraphe, trois étapes numérotées, une ligne de durée et une ligne de
/// provenance, tous en gris voisins, puis un bouton « Commencer » qui n'ouvrait
/// qu'un formulaire. Cinq blocs pour annoncer le travail à fournir, et **pas un
/// seul film à l'écran** sur la fonctionnalité qui en recommande.
///
/// Deux décisions le remplacent.
///
/// - **Le fond est un mur d'affiches réelles**, rabattu sous un voile jusqu'à
///   redevenir une matière. Elles sortent du catalogue de l'accueil, déjà
///   préchargé pendant l'ouverture de l'app : le mur se peint donc à la première
///   image, sans requête. Quand le catalogue est vide, il ne reste que la nuit,
///   et l'écran tient quand même.
/// - **Le geste « Commencer » disparaît.** Il ne servait qu'à ouvrir un écran
///   qu'on venait de lire. La première question est ici, répondable tout de
///   suite ; `SessionFrameView` prend la suite avec les deux qui restent.
///
/// Le voile n'est pas un ornement. C'est le seul dispositif qui rende le texte
/// lisible sur une image dont on ne connaît pas les valeurs, et c'est le rôle
/// documenté de `PlanScrim` dans la direction.
///
/// **L'encart du verdict de la veille a été retiré de cet écran** : il coupait
/// l'entrée en deux et arrivait avant qu'on ait rien demandé. `VerdictPromptView`
/// existe toujours et n'attend qu'un endroit qui lui aille — la conséquence à
/// connaître est que, sans lui, plus rien ne recueille « Je l'ai adoré », le
/// signal le plus sûr du trait et l'une des sources du coup de cœur.
struct SessionEntryView: View {
    /// Le vivier où le mur puise ses affiches, tel quel : c'est `wallItems` qui
    /// y fait le tri. Décoratives de bout en bout — aucune n'est désignée, aucune
    /// n'est cliquable, et elles ne présagent en rien du trio.
    let posters: [MediaItem]
    @Binding var audience: Audience?
    let onProfileTap: () -> Void
    let onNext: () -> Void

    /// Quatre colonnes : à cette largeur une affiche fait environ 96 points, de
    /// quoi reconnaître un film sans qu'aucun ne se donne pour un choix.
    private static let columns = 4
    /// De quoi couvrir la hauteur d'un grand écran sans en demander davantage au
    /// catalogue, qui en tient une cinquantaine.
    private static let rows = 7
    private static var capacity: Int { rows * columns }

    /// Le seuil de notoriété du mur.
    ///
    /// **C'est le seul nombre à régler ici.** Trop haut, presque aucun film ne
    /// passe et le classement par note ne s'applique plus à rien ; trop bas, une
    /// sortie de la semaine notée 8,4 par trois cents personnes se retrouve au
    /// mur alors que personne ne la reconnaît. Deux mille votes est le point où
    /// un film cesse d'être confidentiel sans qu'il faille être un blockbuster.
    private static let minimumVotes = 2_000

    /// Les affiches retenues : **les mieux notées parmi celles que beaucoup de
    /// gens ont vues**.
    ///
    /// La note seule ne suffisait pas. Le vivier est celui de l'accueil, c'est-à-dire
    /// les films populaires du moment sur les plateformes de la personne : trié sur
    /// la seule note, il remonte des sorties récentes acclamées par une poignée de
    /// spectateurs, et le mur cesse d'être un mur de films qu'on reconnaît.
    ///
    /// Quand trop peu de films franchissent le seuil, on complète par les **plus
    /// vus** plutôt que de laisser des trous : un mur troué se lit comme un
    /// chargement raté, jamais comme un parti pris.
    private var wallItems: [MediaItem] {
        let known = posters
            .filter { ($0.voteCount ?? 0) >= Self.minimumVotes }
            .sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
        guard known.count < Self.capacity else {
            return Array(known.prefix(Self.capacity))
        }
        let retained = Set(known.map(\.id))
        let filler = posters
            .filter { !retained.contains($0.id) }
            .sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
        return Array((known + filler).prefix(Self.capacity))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            wall
            veil
            content
        }
        .overlay(alignment: .top) {
            AppHeaderView(
                title: String(localized: "CinéMatch", bundle: .app),
                onProfileTap: onProfileTap
            )
        }
    }

    // MARK: - Le mur

    private var wall: some View {
        // Retenu une fois pour toutes : `wallItems` filtre et trie, et l'appeler
        // dans chaque case le referait vingt-huit fois par rendu.
        let items = wallItems
        return GeometryReader { proxy in
            let side = (proxy.size.width - CGFloat(Self.columns - 1) * 3) / CGFloat(Self.columns)
            VStack(spacing: 3) {
                ForEach(0 ..< Self.rows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0 ..< Self.columns, id: \.self) { column in
                            let index = row * Self.columns + column
                            let item = index < items.count ? items[index] : nil
                            PosterFrame(posterPath: item?.posterPath, title: item?.title ?? "")
                                .frame(width: side)
                                .opacity(item == nil ? 0 : 1)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, alignment: .top)
        }
        // Le haut seulement. `MainTabView` pose la barre d'onglets en frère du
        // contenu, pas en surcouche : déborder par le bas glisserait des affiches
        // derrière elle, là où le voile a déjà tout ramené à la nuit pleine.
        .ignoresSafeArea(edges: .top)
        .clipped()
        // Décoratif de bout en bout : ni le lecteur d'écran ni le doigt n'ont
        // rien à y faire. Sans ça, VoiceOver ferait la lecture de vingt-huit
        // titres avant d'atteindre la question.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Le voile

    /// Un aplat, puis une descente vers la nuit pleine. L'aplat écarte les
    /// affiches du premier plan ; la descente donne au texte un fond franc sans
    /// jamais tracer de bord.
    private var veil: some View {
        ZStack {
            Ink.ground.opacity(0.80)
            LinearGradient(
                stops: [
                    .init(color: Ink.ground.opacity(0), location: 0),
                    .init(color: Ink.ground.opacity(0.86), location: 0.38),
                    .init(color: Ink.ground, location: 0.78),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - La question

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                PlanLight()
                Text("Trouve ton film du soir en 60 sec avant que ton plat refroidisse", bundle: .app)
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Le seul « vous » qui reste dans l'application, et il est juste :
            // il s'adresse aux personnes devant l'écran, pas à celle qui tient
            // le téléphone. Voir la règle du tutoiement dans CLAUDE.md.
            Text("Vous êtes combien ?", bundle: .app)
                .planTitle(34)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)

            FlowLayout(spacing: 7) {
                ForEach(Audience.allCases, id: \.self) { value in
                    PlanChip(title: value.label, isOn: audience == value) {
                        audience = value
                    }
                }
            }
            .padding(.top, 22)

            // La conséquence, dite au moment où elle devient vraie plutôt qu'en
            // permanence : elle ne prend de la place que si elle en dit.
            if audience == .family {
                Text("On ne proposera que des films adaptés aux enfants.", bundle: .app)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            PlanButton(
                title: String(localized: "Suivant", bundle: .app),
                isEnabled: audience != nil,
                action: onNext
            )
            .padding(.top, 26)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, Metrics.margin)
        .animation(Metrics.unfold, value: audience)
    }
}

#Preview("L'entrée") {
    struct Harness: View {
        @State private var audience: Audience?

        var body: some View {
            ZStack {
                Ink.ground.ignoresSafeArea()
                // Sans affiche : c'est le cas dégradé, celui où le catalogue de
                // l'accueil n'est pas encore revenu. L'écran doit tenir dessus.
                SessionEntryView(
                    posters: [],
                    audience: $audience,
                    onProfileTap: {},
                    onNext: {}
                )
            }
            // `AppHeaderView` les réclame ; sans elles l'aperçu tombe.
            .environmentObject(UserProfileStore())
            .environmentObject(SocialStore())
        }
    }
    return Harness()
}
