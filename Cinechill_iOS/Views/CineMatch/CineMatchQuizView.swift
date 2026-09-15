//
//  CineMatchQuizView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le questionnaire de CinéMatch : deux questions, puis jusqu'à quatre
/// comparaisons entre des films déjà vus.
///
/// **Le questionnaire quitte la salle.** C'est une page plate, comme les écrans
/// de réglage : une ligne d'avancement, la question en toutes lettres, et des
/// réponses qui la terminent en annonçant ce qu'elles changent. Aucune ligne
/// d'aide : la question se suffit, et une phrase de plus serait une chose de
/// plus à lire avant de pouvoir répondre.
///
/// Les comparaisons portent sur la galerie, jamais sur des films inconnus :
/// comparer quatre affiches qu'on n'a pas vues revient à comparer quatre
/// affiches, la reconnaissance décide seule. Sur des films vus, on compare
/// quatre soirées qu'on connaît. Le film gardé cède sa place à un autre film
/// vu, pour que la seconde question porte sur quatre options réelles.
struct CineMatchQuizView: View {
    let viewModel: CineMatchViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La réponse touchée : elle s'allume avant qu'on passe à la suite, pour
    /// qu'elle soit vue comme prise. Sans ce temps, la page change sous le
    /// doigt et l'on ne sait plus ce qu'on a répondu.
    @State private var pressedAnswer: String?
    /// L'affiche qu'on vient d'écarter, montrée comme telle le temps que le
    /// tour suivant arrive. Le modèle enregistre le geste tout de suite : la
    /// latence est mesurée au geste, pas à la fin d'une animation.
    @State private var excludedID: Int?

    init(viewModel: CineMatchViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 480

            VStack(alignment: .leading, spacing: 0) {
                header
                progress
                    .padding(.top, 2)

                page(isCompact: isCompact)
                    .id(pageKey)
                    .transition(.opacity)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Ink.ground)
        .animation(.easeOut(duration: 0.2), value: pageKey)
        .onChange(of: viewModel.comparisonRound) { _, _ in excludedID = nil }
        .onChange(of: viewModel.step) { _, _ in
            excludedID = nil
            pressedAnswer = nil
        }
    }

    /// Ce qui fait changer de page : chaque question, et chaque tour.
    private var pageKey: String {
        switch viewModel.step {
        case .comparison: "comparison-\(viewModel.comparisonRound)"
        default: "\(viewModel.step)"
        }
    }

    // MARK: - L'en-tête

    private var header: some View {
        HStack(spacing: 12) {
            Text(stepLabel)
                .planLabel()
                .monospacedDigit()
                .foregroundStyle(Ink.ink2)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                viewModel.cancel()
            } label: {
                Text("Annuler", bundle: .app)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink2)
                    .padding(.leading, 12)
                    .frame(minHeight: Metrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.96))
        }
        .frame(minHeight: 34)
    }

    private var stepLabel: String {
        switch viewModel.step {
        case .want:
            String(localized: "Question \(1) sur 2", bundle: .app)
        case .energy:
            String(localized: "Question \(2) sur 2", bundle: .app)
        case .comparison:
            String(localized: "Comparaison \(viewModel.comparisonRound) sur \(viewModel.comparisonTotal)", bundle: .app)
        default:
            ""
        }
    }

    /// La barre de segments : un par question, un par comparaison, et un
    /// blanc entre les deux familles. Le segment en cours prend la lumière,
    /// ceux qui sont faits passent à l'encre.
    private var progress: some View {
        let total = max(2, viewModel.progressTotal)
        // Pendant l'attente des cinq, tout est fait.
        let index = viewModel.step == .loadingFive ? total + 1 : viewModel.progressIndex

        return HStack(spacing: 4) {
            ForEach(1 ... total, id: \.self) { segment in
                if segment == 3 {
                    Color.clear.frame(width: 6)
                }
                Rectangle()
                    .fill(segment < index ? Ink.ink2 : segment == index ? Ink.light : Ink.rule)
            }
        }
        .frame(height: 3)
        .animation(Metrics.shift, value: index)
        .accessibilityHidden(true)
    }

    // MARK: - Les pages

    @ViewBuilder
    private func page(isCompact: Bool) -> some View {
        if let message = viewModel.errorMessage,
           viewModel.step == .comparison || viewModel.step == .loadingFive {
            failure(message)
        } else {
            switch viewModel.step {
            case .want:
                answersPage(
                    question: String(localized: "Tu as envie de quoi ce soir ?", bundle: .app),
                    answers: viewModel.availableWants.map { want in
                        Answer(key: want.rawValue, title: title(for: want), consequence: consequence(for: want)) {
                            viewModel.chooseWant(want)
                        }
                    },
                    isCompact: isCompact
                )
            case .energy:
                answersPage(
                    question: String(localized: "Tu te sens comment ce soir ?", bundle: .app),
                    answers: CineMatchEnergy.allCases.map { energy in
                        Answer(key: energy.rawValue, title: title(for: energy), consequence: consequence(for: energy)) {
                            await viewModel.chooseEnergy(energy)
                        }
                    },
                    isCompact: isCompact
                )
            case .comparison:
                comparisonPage(isCompact: isCompact)
            case .loadingFive:
                waiting
            default:
                Color.clear
            }
        }
    }

    private func questionTitle(_ text: String, isCompact: Bool) -> some View {
        Text(text)
            .font(.system(size: isCompact ? 20 : 24, weight: .regular, design: .serif))
            .kerning(0.1)
            .lineSpacing(2)
            .foregroundStyle(Ink.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isCompact ? 14 : 24)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Les deux questions

    private struct Answer {
        let key: String
        let title: String
        let consequence: String
        let choose: () async -> Void
    }

    private func answersPage(question: String, answers: [Answer], isCompact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                questionTitle(question, isCompact: isCompact)

                VStack(spacing: isCompact ? 6 : 7) {
                    ForEach(answers, id: \.key) { answer in
                        answerRow(answer, isCompact: isCompact)
                    }
                }
                .padding(.top, isCompact ? 12 : 18)
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func answerRow(_ answer: Answer, isCompact: Bool) -> some View {
        let isOn = pressedAnswer == answer.key

        return Button {
            guard pressedAnswer == nil else { return }
            Haptics.selection()
            pressedAnswer = answer.key
            Task {
                // Le temps de voir la ligne allumée, puis on avance.
                try? await Task.sleep(for: .milliseconds(150))
                await answer.choose()
                pressedAnswer = nil
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(answer.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isOn ? Ink.ground : Ink.ink)
                    Text(answer.consequence)
                        .font(.system(size: 12))
                        .foregroundStyle(isOn ? Ink.ground.opacity(0.62) : Ink.ink2)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                QuizChevron()
                    .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(isOn ? Ink.ground : Ink.ink3)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, isCompact ? 8 : 10)
            .frame(minHeight: isCompact ? 50 : 56)
            .background {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(isOn ? Ink.ink : Ink.ground2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isOn ? Ink.ink : Ink.ruleSet, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(pressedAnswer != nil && !isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: Les comparaisons

    private func comparisonPage(isCompact: Bool) -> some View {
        let films = viewModel.displayedFilms
        let isExcluding = viewModel.comparisonStage == .exclude

        return VStack(alignment: .leading, spacing: 0) {
            questionTitle(
                isExcluding
                    ? String(localized: "Et lequel tu n'as pas du tout envie de revoir ?", bundle: .app)
                    : String(localized: "Lequel tu reverrais bien ce soir ?", bundle: .app),
                isCompact: isCompact
            )

            GeometryReader { proxy in
                if films.isEmpty {
                    CinechillSpinner(size: 26)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    posterGrid(films, in: proxy.size)
                }
            }
            .frame(minHeight: 130)
            .padding(.top, isCompact ? 10 : 14)

            Button {
                guard excludedID == nil, !viewModel.isLoadingRound else { return }
                Haptics.selection()
                Task { await viewModel.noneOfThese() }
            } label: {
                Text(noneTitle(isExcluding: isExcluding, count: films.count))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .disabled(films.isEmpty || excludedID != nil || viewModel.isLoadingRound)
        }
    }

    private func noneTitle(isExcluding: Bool, count: Int) -> String {
        guard isExcluding else {
            return String(localized: "Aucun des quatre ce soir", bundle: .app)
        }
        // Plus de film vu pour remplacer le gardé : on compare les trois qui restent.
        return count == 3
            ? String(localized: "Aucun des trois", bundle: .app)
            : String(localized: "Aucun des quatre", bundle: .app)
    }

    /// Quatre affiches, deux par deux si la hauteur le permet, sinon sur une
    /// ligne : on retient la disposition qui donne les plus grandes affiches.
    /// Sur un téléphone court, quatre en ligne sont plus grandes que deux par
    /// deux.
    private func posterGrid(_ films: [CineMatchGalleryFilm], in size: CGSize) -> some View {
        let layout = QuizPosterLayout(size: size)
        let rows: [[Int]] = layout.columns == 2 ? [[0, 1], [2, 3]] : [[0, 1, 2, 3]]

        return VStack(spacing: layout.gap) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .bottom, spacing: layout.gap) {
                    ForEach(row, id: \.self) { index in
                        if index < films.count {
                            tile(films[index], layout: layout)
                                .id(films[index].id)
                        } else {
                            Color.clear
                                .frame(width: layout.cellWidth, height: layout.cellHeight)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func tile(_ film: CineMatchGalleryFilm, layout: QuizPosterLayout) -> some View {
        let isOut = excludedID == film.id
        let isBusy = excludedID != nil || viewModel.isLoadingRound

        return Button {
            guard !isBusy else { return }
            Haptics.selection()
            switch viewModel.comparisonStage {
            case .keep:
                viewModel.keep(film)
            case .exclude:
                excludedID = film.id
                let round = viewModel.comparisonRound
                Task {
                    await viewModel.exclude(film)
                    // Le modèle a refusé le geste, ou le tour suivant n'est
                    // pas venu : l'affiche ne reste pas marquée écartée.
                    if viewModel.step == .comparison, viewModel.comparisonRound == round {
                        excludedID = nil
                    }
                }
            }
        } label: {
            QuizPosterTile(
                film: film,
                layout: layout,
                isOut: isOut,
                isFresh: film.id == viewModel.freshFilmID,
                reduceMotion: reduceMotion
            )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .accessibilityLabel(
            isOut
                ? String(localized: "\(film.title), écarté", bundle: .app)
                : film.title
        )
    }

    // MARK: L'attente et l'échec

    /// L'attente des cinq : le projecteur tourne, et une phrase dit ce qui se
    /// passe. Rien qui prétende une durée.
    private var waiting: some View {
        VStack(spacing: 14) {
            CinechillSpinner(size: 28)
            Text("On cherche tes cinq films…", bundle: .app)
                .font(.system(size: 13.5))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func failure(_ message: String) -> some View {
        PlanEmptyState(
            title: String(localized: "Impossible de charger les films", bundle: .app),
            message: message,
            actionTitle: String(localized: "Réessayer", bundle: .app),
            action: { Task { await viewModel.retry() } },
            secondaryTitle: String(localized: "Retour à l'accueil", bundle: .app),
            secondaryAction: { viewModel.backToHome() }
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Les textes des réponses

    private func title(for want: CineMatchWant) -> String {
        switch want {
        case .light: String(localized: "Quelque chose de léger", bundle: .app)
        case .soft: String(localized: "Quelque chose de doux", bundle: .app)
        case .suspense: String(localized: "Du suspense", bundle: .app)
        case .think: String(localized: "Un film qui fait réfléchir", bundle: .app)
        case .feelgood: String(localized: "Un film qui fait du bien", bundle: .app)
        case .everyone: String(localized: "Un film qui plaît à tout le monde", bundle: .app)
        }
    }

    private func consequence(for want: CineMatchWant) -> String {
        switch want {
        case .light: String(localized: "Rythmé, sans prise de tête", bundle: .app)
        case .soft: String(localized: "Tranquille, sans tension, qui finit bien", bundle: .app)
        case .suspense: String(localized: "Un film qui te tient en haleine", bundle: .app)
        case .think: String(localized: "Un film qui marque", bundle: .app)
        case .feelgood: String(localized: "Pour te remonter le moral", bundle: .app)
        case .everyone: String(localized: "Grand public, tout le monde sera d'accord", bundle: .app)
        }
    }

    private func title(for energy: CineMatchEnergy) -> String {
        switch energy {
        case .low: String(localized: "Pas trop en forme", bundle: .app)
        case .high: String(localized: "En forme", bundle: .app)
        }
    }

    private func consequence(for energy: CineMatchEnergy) -> String {
        switch energy {
        case .low: String(localized: "Des films faciles à suivre, plutôt des valeurs sûres", bundle: .app)
        case .high: String(localized: "Des films plus prenants, et des découvertes", bundle: .app)
        }
    }
}

// MARK: - La grille d'affiches

/// La maille des quatre affiches, calculée sur la place qui reste.
private struct QuizPosterLayout {
    /// Le titre sous l'affiche : deux lignes de 12 pt et l'espace qui le
    /// sépare de l'image.
    static let caption: CGFloat = 30
    static let captionSpacing: CGFloat = 6

    let columns: Int
    let gap: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let posterWidth: CGFloat
    let posterHeight: CGFloat

    init(size: CGSize) {
        let textBlock = Self.caption + Self.captionSpacing

        let squareGap: CGFloat = 10
        let squareCell = CGSize(width: max(0, (size.width - squareGap) / 2), height: max(0, (size.height - squareGap) / 2))
        let squarePoster = max(0, min(squareCell.height - textBlock, squareCell.width * 1.5))

        let rowGap: CGFloat = 8
        let rowCell = CGSize(width: max(0, (size.width - rowGap * 3) / 4), height: max(0, size.height))
        let rowPoster = max(0, min(rowCell.height - textBlock, rowCell.width * 1.5))

        if squarePoster >= rowPoster {
            columns = 2
            gap = squareGap
            cellWidth = squareCell.width
            cellHeight = squareCell.height
            posterHeight = squarePoster
        } else {
            columns = 4
            gap = rowGap
            cellWidth = rowCell.width
            cellHeight = rowCell.height
            posterHeight = rowPoster
        }
        posterWidth = posterHeight / 1.5
    }
}

/// Une affiche de la galerie et son titre. L'affiche qui vient d'arriver entre
/// en fondu : c'est ce qui dit qu'un autre film a pris la place du gardé.
private struct QuizPosterTile: View {
    let film: CineMatchGalleryFilm
    let layout: QuizPosterLayout
    let isOut: Bool
    let isFresh: Bool
    let reduceMotion: Bool

    @State private var hasArrived = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: QuizPosterLayout.captionSpacing) {
            PosterImageView(url: film.posterURL, contentMode: .fill)
                .frame(width: layout.posterWidth, height: layout.posterHeight)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Ink.ink.opacity(0.18), lineWidth: 1))
                .opacity(isOut ? 0.22 : 1)
                .overlay(alignment: .top) {
                    if isOut {
                        Text("Écarté", bundle: .app)
                            .planLabel()
                            .foregroundStyle(Ink.ink2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Ink.ground3, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .padding(.top, 6)
                            .transition(.opacity)
                    }
                }
                .opacity(isFresh && !hasArrived ? 0 : 1)
                .offset(y: isFresh && !hasArrived && !reduceMotion ? 6 : 0)

            Text(film.title)
                .font(.system(size: 12))
                .foregroundStyle(Ink.ink2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: layout.cellWidth, height: QuizPosterLayout.caption, alignment: .top)
        }
        .frame(width: layout.cellWidth, height: layout.cellHeight, alignment: .bottom)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: isOut)
        .onAppear {
            guard isFresh, !hasArrived else { return }
            withAnimation(.easeOut(duration: 0.32)) { hasArrived = true }
        }
    }
}

/// Le chevron des réponses : grille de 24, trait de 1,6, extrémités rondes.
private struct QuizChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 9 * scale, y: rect.minY + 6 * scale))
        path.addLine(to: CGPoint(x: rect.minX + 15 * scale, y: rect.minY + 12 * scale))
        path.addLine(to: CGPoint(x: rect.minX + 9 * scale, y: rect.minY + 18 * scale))
        return path
    }
}
