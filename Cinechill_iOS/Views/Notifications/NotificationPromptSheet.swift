//
//  NotificationPromptSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// La feuille qui précède la fenêtre d'iOS.
///
/// iOS ne montre sa fenêtre d'autorisation qu'une fois : un « Ne pas
/// autoriser » donné à froid ferme la porte pour de bon. Cette feuille la
/// précède au moment où la demande se comprend, dit ce qu'on y gagne, et
/// « Plus tard » la referme sans rien demander à iOS.
///
/// Deux textes, un par moment ; le reste est commun. Pas d'illustration : la
/// cloche de l'en-tête, en petit, suffit à dire de quoi on parle.
struct NotificationPromptSheet: View {
    let moment: NotificationPermission.Moment

    @Environment(\.dismiss) private var dismiss
    @State private var isAsking = false
    @State private var contentHeight: CGFloat = 320
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image("notification")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Ink.ink2)
                    .accessibilityHidden(true)

                Text(title)
                    .planTitle(22)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 16)

                Text(message)
                    .planFont(14)
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                PlanButton(
                    title: String(localized: "Activer les notifications", bundle: .app),
                    isLoading: isAsking
                ) {
                    Task { await enable() }
                }
                .padding(.top, 26)

                Button {
                    dismiss()
                } label: {
                    Text("Plus tard", bundle: .app)
                        .planFont(14, weight: .medium)
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Metrics.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.97))
                .disabled(isAsking)
                .padding(.top, 6)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 28)
            .padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.bottom
        } action: { inset in
            bottomInset = inset
        }
        .background(Ink.ground2.ignoresSafeArea())
        // La hauteur du contenu, plafonnée par l'écran : en texte très grand,
        // la feuille monte jusqu'en haut et son contenu défile.
        .presentationDetents([.height(contentHeight + bottomInset), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Ink.ground2)
        .onAppear { NotificationPermission.shared.markOffered(moment) }
    }

    private var title: String {
        switch moment {
        case .firstSuggestion:
            String(localized: "Sache ce que devient ta recommandation", bundle: .app)
        case .firstWatch:
            String(localized: "On te demande demain comment c'était", bundle: .app)
        }
    }

    private var message: String {
        switch moment {
        case .firstSuggestion:
            String(localized: "On te prévient quand quelqu'un l'ajoute à sa watchlist ou la regarde, et quand on te recommande un film.", bundle: .app)
        case .firstWatch:
            String(localized: "Une notification à 19 h. Ta réponse range le film dans ta galerie et compte pour tes prochains films.", bundle: .app)
        }
    }

    private func enable() async {
        isAsking = true
        await NotificationPermission.shared.requestFull()
        isAsking = false
        dismiss()
    }
}

// MARK: - L'avis du lendemain

/// Les quatre réponses, en tête de la fiche d'un film ouverte depuis la
/// question du lendemain.
///
/// Elles partent au toucher, et la ligne ne dit « rangé » qu'une fois le
/// serveur revenu. La confirmation reste le temps de se lire, puis le bloc se
/// retire : la fiche redevient une fiche.
struct FilmVerdictPrompt: View {
    let item: MediaItem
    /// Le bloc a fini son travail : la fiche le retire.
    let onFinished: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Phase: Equatable {
        case asking
        case sending(LibraryStore.FilmVerdict)
        case done(String)
        case failed
    }

    @State private var phase: Phase = .asking

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .done(let confirmation):
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    PlanLight()
                    Text(confirmation)
                        .planFont(13.5)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            default:
                question
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
        .animation(Metrics.shift, value: phase)
        .task(id: phase) {
            guard case .done = phase else { return }
            try? await Task.sleep(for: .seconds(2.6))
            onFinished()
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tu l'as regardé ?", bundle: .app)
                .planTitle(18)
                .foregroundStyle(Ink.ink)
                .accessibilityAddTraits(.isHeader)

            // Deux par deux ; en très grand texte, une colonne : « Je l'ai
            // adoré » ne tient plus sur une demi-largeur.
            if typeSize.isAccessibilitySize {
                VStack(spacing: Metrics.gutter) {
                    ForEach(LibraryStore.FilmVerdict.allCases, id: \.self) { verdict in
                        answer(verdict)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Metrics.gutter) {
                    answerRow(.loved, .liked)
                    answerRow(.disliked, .notWatched)
                }
            }

            if phase == .failed {
                Text("On n'a pas pu enregistrer ta réponse. Réessaie.", bundle: .app)
                    .planFont(12)
                    .foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    /// Deux réponses de même largeur et de même hauteur, même quand l'une
    /// passe sur deux lignes.
    private func answerRow(_ first: LibraryStore.FilmVerdict, _ second: LibraryStore.FilmVerdict) -> some View {
        HStack(spacing: Metrics.gutter) {
            answer(first)
            answer(second)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func answer(_ verdict: LibraryStore.FilmVerdict) -> some View {
        let isSending = phase == .sending(verdict)
        let isBusy: Bool = {
            if case .sending = phase { return true }
            return false
        }()

        return Button {
            Task { await send(verdict) }
        } label: {
            HStack(spacing: 8) {
                Text(label(verdict))
                    .planFont(14, weight: .medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if isSending {
                    CinechillSpinner(size: 12)
                }
            }
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: Metrics.control, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Ink.ruleSet, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        // Une seule réponse à la fois : deux écritures croisées sur le même
        // film arriveraient dans un ordre que personne ne contrôle.
        .disabled(isBusy)
        .opacity(isBusy && !isSending ? 0.5 : 1)
        .accessibilityValue(isSending ? String(localized: "Enregistrement…", bundle: .app) : "")
    }

    private func label(_ verdict: LibraryStore.FilmVerdict) -> String {
        switch verdict {
        case .loved: String(localized: "Je l'ai adoré", bundle: .app)
        case .liked: String(localized: "Il m'a plu", bundle: .app)
        case .disliked: String(localized: "Pas aimé", bundle: .app)
        case .notWatched: String(localized: "Pas regardé", bundle: .app)
        }
    }

    private func confirmation(_ verdict: LibraryStore.FilmVerdict) -> String {
        switch verdict {
        case .loved:
            String(localized: "Rangé dans ta galerie, en coup de cœur.", bundle: .app)
        case .liked:
            String(localized: "Rangé dans ta galerie.", bundle: .app)
        case .disliked:
            String(localized: "Rangé dans ta galerie. Il ne comptera pas dans tes goûts.", bundle: .app)
        case .notWatched:
            libraryStore.isInWatchlist(item)
                ? String(localized: "Il reste dans ta watchlist.", bundle: .app)
                : String(localized: "Rien ne change dans tes listes.", bundle: .app)
        }
    }

    private func send(_ verdict: LibraryStore.FilmVerdict) async {
        phase = .sending(verdict)
        do {
            try await libraryStore.setFilmVerdict(item, verdict: verdict)
            Haptics.success()
            phase = .done(confirmation(verdict))
        } catch {
            phase = .failed
        }
    }
}

// MARK: - Le profil ouvert depuis une notification

/// Le profil d'une personne dont on ne connaît que l'identifiant.
///
/// `PublicProfileView` part d'un profil déjà lu ; une notification n'apporte
/// qu'un uid. On lit donc le profil d'abord, en tenant l'attente et l'échec
/// sur place, puis on passe la main à l'écran habituel.
struct NotificationProfileView: View {
    let uid: String

    @State private var profile: PublicProfile?
    @State private var failure: String?

    var body: some View {
        Group {
            if let profile {
                PublicProfileView(profile: profile)
            } else {
                VStack(spacing: 0) {
                    PlanHeader("", leading: .close)
                    Spacer(minLength: 0)
                    if let failure {
                        HallEmptyState(
                            icon: .salle,
                            title: String(localized: "Profil indisponible", bundle: .app),
                            message: failure,
                            actionTitle: String(localized: "Réessayer", bundle: .app),
                            action: { Task { await load() } }
                        )
                    } else {
                        CinechillSpinner(size: 22)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Ink.ground)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: uid) { await load() }
    }

    private func load() async {
        failure = nil
        do {
            profile = try await SocialClient().publicProfileDetail(uid: uid).profile
        } catch is CancellationError {
            return
        } catch SocialError.targetNotFound {
            failure = String(localized: "Ce profil n'est pas accessible.", bundle: .app)
        } catch {
            failure = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "On n'a pas pu charger ce profil.", bundle: .app)
        }
    }
}
